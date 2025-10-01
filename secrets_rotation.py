import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Lambda function for rotating secrets in AWS Secrets Manager
    """
    try:
        secrets_client = boto3.client('secretsmanager')
        
        secret_arn = event['SecretId']
        token = event['ClientRequestToken']
        step = event['Step']
        
        logger.info(f"Rotating secret {secret_arn}, step: {step}")
        
        if step == "createSecret":
            # Generate new secret value
            new_secret = {
                "DATABASE_PASSWORD": generate_password(),
                "API_KEY": generate_api_key()
            }
            
            secrets_client.put_secret_value(
                SecretId=secret_arn,
                ClientRequestToken=token,
                SecretString=json.dumps(new_secret),
                VersionStage="AWSPENDING"
            )
            
        elif step == "setSecret":
            # Update the database/service with new credentials
            logger.info("Setting new secret in target service")
            
        elif step == "testSecret":
            # Test the new credentials
            logger.info("Testing new secret")
            
        elif step == "finishSecret":
            # Finalize the rotation
            secrets_client.update_secret_version_stage(
                SecretId=secret_arn,
                VersionStage="AWSCURRENT",
                ClientRequestToken=token,
                RemoveFromVersionId=get_previous_version(secrets_client, secret_arn)
            )
            
        return {"statusCode": 200}
        
    except Exception as e:
        logger.error(f"Error rotating secret: {str(e)}")
        raise e

def generate_password():
    import secrets
    import string
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(16))

def generate_api_key():
    import secrets
    return secrets.token_urlsafe(32)

def get_previous_version(client, secret_arn):
    response = client.describe_secret(SecretId=secret_arn)
    versions = response.get('VersionIdsToStages', {})
    for version_id, stages in versions.items():
        if 'AWSCURRENT' in stages:
            return version_id
    return None
