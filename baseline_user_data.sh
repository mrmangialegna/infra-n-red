#!/bin/bash
set -e

# Variables
REDIS_ENDPOINT="${redis_endpoint}"
S3_BUCKET="${s3_bucket}"
SQS_QUEUE_URL="${sqs_queue_url}"
REGION="${region}"

echo "Setting up BASELINE instance (Green Stage - Immediate Deployment)..."

# System setup
yum update -y
yum install -y git curl wget unzip jq vim htop tree nginx redis-tools rsync

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip

# Docker + Docker Compose
amazon-linux-extras install docker -y
systemctl enable docker && systemctl start docker
usermod -a -G docker ec2-user
curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Full software stack (acts as repository)
echo "Installing full software stack..."

# Node.js + PM2
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs
npm install -g pm2 pm2-logrotate

# Python
yum install -y python3 python3-pip python3-devel
pip3 install --upgrade pip virtualenv flask django

# Additional tools
yum install -y golang java-11-openjdk-devel

# Create software repository
mkdir -p /opt/software-repo/{nodejs,python,docker,golang,java}
echo "Creating software repository..."

# Package Node.js
tar -czf /opt/software-repo/nodejs/binaries.tar.gz -C /usr/bin node npm npx
tar -czf /opt/software-repo/nodejs/modules.tar.gz -C /usr/local/lib/node_modules .

# Package Python
tar -czf /opt/software-repo/python/binaries.tar.gz -C /usr/bin python3 pip3
pip3 freeze > /opt/software-repo/python/requirements.txt

# Package Docker
tar -czf /opt/software-repo/docker/binaries.tar.gz -C /usr/bin docker
cp /usr/local/bin/docker-compose /opt/software-repo/docker/

# Set permissions
chown -R ec2-user:ec2-user /opt/software-repo

# Application structure
mkdir -p /opt/heroku-clone/{apps,logs,scripts}
chown -R ec2-user:ec2-user /opt/heroku-clone

# Copy code analyzer to baseline instance
cat > /opt/heroku-clone/scripts/code_analyzer.py << 'CODE_ANALYZER'
#!/usr/bin/env python3
"""
Code Analyzer for Heroku Clone
Analyzes uploaded code and determines required packages for spot instances
"""

import os
import json
import boto3
from pathlib import Path

class CodeAnalyzer:
    def __init__(self, sqs_queue_url, region='${region}'):
        self.sqs = boto3.client('sqs', region_name=region)
        self.queue_url = sqs_queue_url
        
    def analyze_code(self, code_path, app_name):
        """Analyze code and return required packages"""
        requirements = {
            'runtime': None,
            'packages': [],
            'services': [],
            'memory': '512M',
            'cpu': 'low'
        }
        
        code_path = Path(code_path)
        
        # Analyze Node.js
        if (code_path / 'package.json').exists():
            requirements.update(self._analyze_nodejs(code_path))
            
        # Analyze Python
        elif (code_path / 'requirements.txt').exists() or (code_path / 'app.py').exists():
            requirements.update(self._analyze_python(code_path))
            
        # Analyze Docker
        elif (code_path / 'Dockerfile').exists():
            requirements.update(self._analyze_docker(code_path))
            
        # Analyze Go
        elif (code_path / 'go.mod').exists():
            requirements.update(self._analyze_go(code_path))
            
        # Analyze Java
        elif (code_path / 'pom.xml').exists() or (code_path / 'build.gradle').exists():
            requirements.update(self._analyze_java(code_path))
            
        else:
            requirements['runtime'] = 'static'
            requirements['packages'] = ['nginx']
            
        return requirements
    
    def _analyze_nodejs(self, code_path):
        """Analyze Node.js application"""
        req = {
            'runtime': 'nodejs',
            'packages': ['nodejs', 'npm', 'pm2'],
            'services': [],
            'memory': '512M',
            'cpu': 'medium'
        }
        
        try:
            with open(code_path / 'package.json') as f:
                package_json = json.load(f)
                
            dependencies = package_json.get('dependencies', {})
            
            # Check for specific frameworks/libraries
            if 'express' in dependencies:
                req['services'].append('express')
            if 'react' in dependencies or 'next' in dependencies:
                req['memory'] = '1G'
                req['cpu'] = 'high'
            if 'mongoose' in dependencies:
                req['services'].append('mongodb')
            if 'redis' in dependencies:
                req['services'].append('redis')
            if 'pg' in dependencies or 'mysql' in dependencies:
                req['services'].append('database')
                
        except Exception:
            pass
            
        return req
    
    def _analyze_python(self, code_path):
        """Analyze Python application"""
        req = {
            'runtime': 'python',
            'packages': ['python3', 'pip3'],
            'services': [],
            'memory': '512M',
            'cpu': 'medium'
        }
        
        # Check requirements.txt
        req_file = code_path / 'requirements.txt'
        if req_file.exists():
            try:
                with open(req_file) as f:
                    requirements = f.read().lower()
                    
                if 'django' in requirements:
                    req['packages'].append('django')
                    req['memory'] = '1G'
                if 'flask' in requirements:
                    req['packages'].append('flask')
                if 'fastapi' in requirements:
                    req['packages'].append('fastapi')
                    req['cpu'] = 'high'
                if 'redis' in requirements:
                    req['services'].append('redis')
                if 'psycopg2' in requirements or 'pymongo' in requirements:
                    req['services'].append('database')
                    
            except Exception:
                pass
                
        return req
    
    def _analyze_docker(self, code_path):
        """Analyze Docker application"""
        req = {
            'runtime': 'docker',
            'packages': ['docker', 'docker-compose'],
            'services': [],
            'memory': '1G',
            'cpu': 'high'
        }
        
        try:
            with open(code_path / 'Dockerfile') as f:
                dockerfile = f.read().lower()
                
            if 'node' in dockerfile:
                req['packages'].append('nodejs')
            if 'python' in dockerfile:
                req['packages'].append('python3')
            if 'nginx' in dockerfile:
                req['services'].append('nginx')
            if 'redis' in dockerfile:
                req['services'].append('redis')
                
        except Exception:
            pass
            
        return req
    
    def _analyze_go(self, code_path):
        """Analyze Go application"""
        return {
            'runtime': 'go',
            'packages': ['golang'],
            'services': [],
            'memory': '256M',
            'cpu': 'low'
        }
    
    def _analyze_java(self, code_path):
        """Analyze Java application"""
        req = {
            'runtime': 'java',
            'packages': ['java-11-openjdk-devel'],
            'services': [],
            'memory': '1G',
            'cpu': 'high'
        }
        
        # Check for Spring Boot
        if (code_path / 'pom.xml').exists():
            try:
                with open(code_path / 'pom.xml') as f:
                    pom = f.read().lower()
                if 'spring-boot' in pom:
                    req['packages'].append('maven')
                    req['memory'] = '2G'
            except Exception:
                pass
                
        return req
    
    def signal_spot_instances(self, app_name, requirements):
        """Send requirements to spot instances via SQS"""
        message = {
            'action': 'prepare-packages',
            'app_name': app_name,
            'requirements': requirements,
            'timestamp': int(__import__('time').time())
        }
        
        try:
            response = self.sqs.send_message(
                QueueUrl=self.queue_url,
                MessageBody=json.dumps(message)
            )
            print(f"Sent package requirements for {app_name} to spot instances")
            return response['MessageId']
        except Exception as e:
            print(f"Failed to send message: {e}")
            return None
    
    def analyze_and_signal(self, code_path, app_name):
        """Complete workflow: analyze code and signal spot instances"""
        print(f"🔍 Analyzing code for {app_name}...")
        
        requirements = self.analyze_code(code_path, app_name)
        
        print(f" Analysis results:")
        print(f"  Runtime: {requirements['runtime']}")
        print(f"  Packages: {', '.join(requirements['packages'])}")
        print(f"  Services: {', '.join(requirements['services'])}")
        print(f"  Memory: {requirements['memory']}")
        print(f"  CPU: {requirements['cpu']}")
        
        message_id = self.signal_spot_instances(app_name, requirements)
        
        return requirements, message_id

if __name__ == '__main__':
    import sys
    
    if len(sys.argv) != 4:
        print("Usage: python3 code_analyzer.py <code_path> <app_name> <sqs_queue_url>")
        sys.exit(1)
    
    code_path = sys.argv[1]
    app_name = sys.argv[2]
    queue_url = sys.argv[3]
    
    analyzer = CodeAnalyzer(queue_url)
    requirements, message_id = analyzer.analyze_and_signal(code_path, app_name)
    
    print(f"Analysis complete! Message ID: {message_id}")
CODE_ANALYZER
chmod +x /opt/heroku-clone/scripts/code_analyzer.py
cat > /opt/heroku-clone/scripts/deploy.sh << 'DEPLOY_SCRIPT'
#!/bin/bash
APP_NAME=$1
APP_PATH=$2
PORT=${3:-8080}

echo "IMMEDIATE deployment of $APP_NAME on BASELINE instance..."

mkdir -p /opt/heroku-clone/apps/$APP_NAME
cd /opt/heroku-clone/apps/$APP_NAME
cp -r $APP_PATH/* ./

# Deploy immediately
if [ -f "Dockerfile" ]; then
    docker build -t $APP_NAME .
    docker stop $APP_NAME 2>/dev/null || true
    docker rm $APP_NAME 2>/dev/null || true
    docker run -d --name $APP_NAME --restart unless-stopped -p $PORT:8080 $APP_NAME
elif [ -f "package.json" ]; then
    npm install
    pm2 stop $APP_NAME 2>/dev/null || true
    pm2 delete $APP_NAME 2>/dev/null || true
    PORT=$PORT pm2 start app.js --name $APP_NAME
    pm2 save
elif [ -f "requirements.txt" ]; then
    python3 -m venv venv && source venv/bin/activate
    pip install -r requirements.txt
    pm2 stop $APP_NAME 2>/dev/null || true
    pm2 delete $APP_NAME 2>/dev/null || true
    PORT=$PORT pm2 start "python app.py" --name $APP_NAME
    pm2 save
fi

# Store in Redis
redis-cli -h $REDIS_ENDPOINT set "app:$APP_NAME:status" "running-baseline"
redis-cli -h $REDIS_ENDPOINT set "app:$APP_NAME:port" $PORT

# Trigger spot instance preparation
aws sqs send-message --queue-url $SQS_QUEUE_URL --message-body "prepare-spot:$APP_NAME:$PORT" --region $REGION

echo "$APP_NAME running IMMEDIATELY on baseline! Preparing spot instances..."
DEPLOY_SCRIPT
chmod +x /opt/heroku-clone/scripts/deploy.sh

# Health check endpoint
cat > /opt/heroku-clone/health.py << 'HEALTH_SCRIPT'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {"status": "healthy", "stage": "green-baseline", "role": "immediate-deployment"}
            self.wfile.write(json.dumps(response).encode())

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), HealthHandler)
    server.serve_forever()
HEALTH_SCRIPT
chmod +x /opt/heroku-clone/health.py

# Start health check
nohup python3 /opt/heroku-clone/health.py &

systemctl enable nginx && systemctl start nginx

echo "BASELINE instance ready for IMMEDIATE deployments!"
