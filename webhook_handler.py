import json
import boto3
import urllib.request
import tempfile
import os
import psycopg2

s3 = boto3.client('s3')

def handler(event, context):
    try:
        # Parse webhook payload
        body = json.loads(event['body'])
        app_name = event['pathParameters']['app_name']
        
        # GitHub webhook
        if 'repository' in body and 'head_commit' in body:
            repo_url = body['repository']['clone_url']
            commit_sha = body['head_commit']['id']
            
            # Download repository as zip
            zip_url = f"{repo_url.replace('.git', '')}/archive/{commit_sha}.zip"
            
            with tempfile.NamedTemporaryFile() as tmp_file:
                urllib.request.urlretrieve(zip_url, tmp_file.name)
                
                # Upload to S3
                bucket_name = os.environ['CODE_BUCKET']
                s3_key = f"{app_name}/{commit_sha}.zip"
                
                s3.upload_file(tmp_file.name, bucket_name, s3_key)
                
                # Update app metadata in PostgreSQL
                conn = psycopg2.connect(
                    host=os.environ['POSTGRES_HOST'],
                    database=os.environ['POSTGRES_DB'],
                    user=os.environ['POSTGRES_USER'],
                    password=os.environ['POSTGRES_PASS']
                )
                
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO platform.deployments (app_name, repo_url, commit_sha, status, created_at)
                        VALUES (%s, %s, %s, 'building', NOW())
                        ON CONFLICT (app_name) DO UPDATE SET
                        commit_sha = EXCLUDED.commit_sha,
                        status = 'building',
                        updated_at = NOW()
                    """, (app_name, repo_url, commit_sha))
                    
                conn.commit()
                conn.close()
                
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': f'Deployment triggered for {app_name}',
                        'commit': commit_sha
                    })
                }
        
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid webhook payload'})
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
