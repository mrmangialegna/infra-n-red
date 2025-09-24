#!/bin/bash
set -e

# Variables
BASELINE_IP="${baseline_ip}"
REDIS_ENDPOINT="${redis_endpoint}"
S3_BUCKET="${s3_bucket}"
SQS_QUEUE_URL="${sqs_queue_url}"
REGION="${region}"

echo "🔵 Setting up SPOT instance (Blue Stage - Production Migration Target)..."

# Basic system setup
yum update -y
yum install -y git curl wget unzip jq vim htop redis-tools rsync

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip

# Fast software sync from baseline
echo "⚡ Syncing software from baseline ($BASELINE_IP)..."
mkdir -p /opt/software-repo

# Wait for baseline to be ready
sleep 60

# Sync software repository from baseline
rsync -av --timeout=120 ec2-user@$BASELINE_IP:/opt/software-repo/ /opt/software-repo/ || {
    echo "⚠️ Software sync failed, will install on-demand"
    SYNC_FAILED=true
}

if [ "$SYNC_FAILED" != "true" ]; then
    echo "📦 Installing software from local cache..."
    
    # Install Node.js from cache
    if [ -f /opt/software-repo/nodejs/binaries.tar.gz ]; then
        tar -xzf /opt/software-repo/nodejs/binaries.tar.gz -C /usr/bin/
        mkdir -p /usr/local/lib/node_modules
        tar -xzf /opt/software-repo/nodejs/modules.tar.gz -C /usr/local/lib/node_modules/
        chmod +x /usr/bin/{node,npm,npx}
    fi
    
    # Install Python from cache
    if [ -f /opt/software-repo/python/binaries.tar.gz ]; then
        tar -xzf /opt/software-repo/python/binaries.tar.gz -C /usr/bin/
        chmod +x /usr/bin/{python3,pip3}
        if [ -f /opt/software-repo/python/requirements.txt ]; then
            pip3 install -r /opt/software-repo/python/requirements.txt
        fi
    fi
    
    # Install Docker from cache
    if [ -f /opt/software-repo/docker/binaries.tar.gz ]; then
        tar -xzf /opt/software-repo/docker/binaries.tar.gz -C /usr/bin/
        cp /opt/software-repo/docker/docker-compose /usr/local/bin/
        chmod +x /usr/bin/docker /usr/local/bin/docker-compose
        amazon-linux-extras install docker -y
        systemctl enable docker && systemctl start docker
        usermod -a -G docker ec2-user
    fi
    
    echo "✅ Software installed from cache in ~30 seconds!"
else
    echo "📦 Fallback: Installing software directly..."
    amazon-linux-extras install docker -y
    systemctl enable docker && systemctl start docker
    curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
    yum install -y nodejs python3 python3-pip
    npm install -g pm2
fi

# Application structure
mkdir -p /opt/heroku-clone/{apps,logs,scripts}
chown -R ec2-user:ec2-user /opt/heroku-clone

# SQS message processor
cat > /opt/heroku-clone/scripts/process_messages.sh << 'PROCESS_SCRIPT'
#!/bin/bash

echo "👂 Listening for migration messages..."

while true; do
    # Poll SQS for messages
    MESSAGE=$(aws sqs receive-message --queue-url $SQS_QUEUE_URL --region $REGION --output json 2>/dev/null)
    
    if [ "$MESSAGE" != "null" ] && [ -n "$MESSAGE" ]; then
        BODY=$(echo $MESSAGE | jq -r '.Messages[0].Body' 2>/dev/null)
        RECEIPT_HANDLE=$(echo $MESSAGE | jq -r '.Messages[0].ReceiptHandle' 2>/dev/null)
        
        if [[ $BODY == prepare-spot:* ]]; then
            APP_NAME=$(echo $BODY | cut -d: -f2)
            echo "🔄 Preparing for $APP_NAME migration..."
            
            # Signal ready for migration
            redis-cli -h $REDIS_ENDPOINT set "app:$APP_NAME:spot-ready" "true"
        fi
        
        # Delete processed message
        if [ "$RECEIPT_HANDLE" != "null" ]; then
            aws sqs delete-message --queue-url $SQS_QUEUE_URL --receipt-handle "$RECEIPT_HANDLE" --region $REGION
        fi
    fi
    
    sleep 5
done
PROCESS_SCRIPT
chmod +x /opt/heroku-clone/scripts/process_messages.sh

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
            response = {"status": "healthy", "stage": "blue-production", "role": "cost-optimized-production"}
            self.wfile.write(json.dumps(response).encode())

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), HealthHandler)
    server.serve_forever()
HEALTH_SCRIPT
chmod +x /opt/heroku-clone/health.py

# Start services
nohup python3 /opt/heroku-clone/health.py &
nohup /opt/heroku-clone/scripts/process_messages.sh &

echo "✅ SPOT instance ready to receive workload migrations!"
