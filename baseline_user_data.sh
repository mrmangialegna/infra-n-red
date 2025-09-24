#!/bin/bash
set -e

# Variables
REDIS_ENDPOINT="${redis_endpoint}"
S3_BUCKET="${s3_bucket}"
SQS_QUEUE_URL="${sqs_queue_url}"
REGION="${region}"

echo "🟢 Setting up BASELINE instance (Green Stage - Immediate Deployment)..."

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
echo "📦 Installing full software stack..."

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
echo "📦 Creating software repository..."

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

# Immediate deployment script
cat > /opt/heroku-clone/scripts/deploy.sh << 'DEPLOY_SCRIPT'
#!/bin/bash
APP_NAME=$1
APP_PATH=$2
PORT=${3:-8080}

echo "🚀 IMMEDIATE deployment of $APP_NAME on BASELINE instance..."

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

echo "✅ $APP_NAME running IMMEDIATELY on baseline! Preparing spot instances..."
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

echo "✅ BASELINE instance ready for IMMEDIATE deployments!"
