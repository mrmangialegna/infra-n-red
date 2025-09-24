#!/bin/bash
set -e

# Variables
BASELINE_IP="${baseline_ip}"
REDIS_ENDPOINT="${redis_endpoint}"
S3_BUCKET="${s3_bucket}"
SQS_QUEUE_URL="${sqs_queue_url}"
REGION="${region}"

echo "Setting up SPOT instance (Blue Stage - Production Migration Target)..."

# Basic system setup
yum update -y
yum install -y git curl wget unzip jq vim htop redis-tools rsync python3

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip

# Create software repository directory
mkdir -p /opt/software-repo

# Application structure
mkdir -p /opt/heroku-clone/{apps,logs,scripts}
chown -R ec2-user:ec2-user /opt/heroku-clone

# Copy package installer script
cat > /opt/heroku-clone/scripts/package_installer.sh << 'PACKAGE_INSTALLER'
#!/bin/bash
# Package Installer for Spot Instances
# Receives package requirements and installs them dynamically

set -e

REDIS_ENDPOINT="${redis_endpoint}"
S3_BUCKET="${s3_bucket}"
SQS_QUEUE_URL="${sqs_queue_url}"
REGION="${region}"
BASELINE_IP="${baseline_ip}"

echo "📦 Package Installer ready on spot instance..."

# Function to install packages based on requirements
install_packages() {
    local runtime=$1
    local packages=$2
    local services=$3
    local memory=$4
    local cpu=$5
    
    echo "Installing packages for runtime: $runtime"
    echo "Packages: $packages"
    echo "Services: $services"
    echo "Memory: $memory | CPU: $cpu"
    
    case $runtime in
        "nodejs")
            install_nodejs_stack "$packages"
            ;;
        "python")
            install_python_stack "$packages"
            ;;
        "docker")
            install_docker_stack "$packages"
            ;;
        "go")
            install_go_stack "$packages"
            ;;
        "java")
            install_java_stack "$packages"
            ;;
        "static")
            install_static_stack "$packages"
            ;;
        *)
            echo "Unknown runtime: $runtime"
            ;;
    esac
    
    # Install additional services
    if [[ $services == *"redis"* ]]; then
        install_redis_client
    fi
    
    if [[ $services == *"mongodb"* ]]; then
        install_mongodb_client
    fi
    
    if [[ $services == *"nginx"* ]]; then
        install_nginx
    fi
}

install_nodejs_stack() {
    local packages=$1
    echo "Installing Node.js stack..."
    
    # Try to get from baseline cache first
    if sync_from_baseline "nodejs"; then
        echo "Node.js installed from baseline cache"
    else
        echo "Installing Node.js directly..."
        curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
        yum install -y nodejs
        npm install -g pm2 pm2-logrotate
    fi
}

install_python_stack() {
    local packages=$1
    echo "Installing Python stack..."
    
    # Try to get from baseline cache first
    if sync_from_baseline "python"; then
        echo "Python installed from baseline cache"
    else
        echo "Installing Python directly..."
        yum install -y python3 python3-pip python3-devel
        pip3 install --upgrade pip virtualenv
        
        if [[ $packages == *"django"* ]]; then
            pip3 install django
        fi
        if [[ $packages == *"flask"* ]]; then
            pip3 install flask
        fi
        if [[ $packages == *"fastapi"* ]]; then
            pip3 install fastapi uvicorn
        fi
    fi
}

install_docker_stack() {
    local packages=$1
    echo "🐳 Installing Docker stack..."
    
    # Try to get from baseline cache first
    if sync_from_baseline "docker"; then
        echo "Docker installed from baseline cache"
    else
        echo "Installing Docker directly..."
        amazon-linux-extras install docker -y
        systemctl enable docker && systemctl start docker
        usermod -a -G docker ec2-user
        
        # Docker Compose
        curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

install_go_stack() {
    local packages=$1
    echo "Installing Go stack..."
    
    if sync_from_baseline "golang"; then
        echo "Go installed from baseline cache"
    else
        echo "Installing Go directly..."
        yum install -y golang
    fi
}

install_java_stack() {
    local packages=$1
    echo "☕ Installing Java stack..."
    
    if sync_from_baseline "java"; then
        echo "Java installed from baseline cache"
    else
        echo "Installing Java directly..."
        yum install -y java-11-openjdk-devel
        
        if [[ $packages == *"maven"* ]]; then
            yum install -y maven
        fi
    fi
}

install_static_stack() {
    local packages=$1
    echo "Installing static file server..."
    install_nginx
}

install_redis_client() {
    echo "Installing Redis client..."
    yum install -y redis-tools
}

install_mongodb_client() {
    echo "Installing MongoDB client..."
    yum install -y mongodb-org-shell
}

install_nginx() {
    echo "Installing Nginx..."
    yum install -y nginx
    systemctl enable nginx
}

sync_from_baseline() {
    local software=$1
    echo "⚡ Trying to sync $software from baseline ($BASELINE_IP)..."
    
    if [ -z "$BASELINE_IP" ]; then
        return 1
    fi
    
    # Try to sync from baseline
    timeout 60 rsync -av --timeout=30 ec2-user@$BASELINE_IP:/opt/software-repo/$software/ /opt/software-repo/$software/ 2>/dev/null || {
        echo "Sync from baseline failed for $software"
        return 1
    }
    
    # Install from cache
    case $software in
        "nodejs")
            if [ -f /opt/software-repo/nodejs/binaries.tar.gz ]; then
                tar -xzf /opt/software-repo/nodejs/binaries.tar.gz -C /usr/bin/
                mkdir -p /usr/local/lib/node_modules
                tar -xzf /opt/software-repo/nodejs/modules.tar.gz -C /usr/local/lib/node_modules/
                chmod +x /usr/bin/{node,npm,npx}
                return 0
            fi
            ;;
        "python")
            if [ -f /opt/software-repo/python/binaries.tar.gz ]; then
                tar -xzf /opt/software-repo/python/binaries.tar.gz -C /usr/bin/
                chmod +x /usr/bin/{python3,pip3}
                if [ -f /opt/software-repo/python/requirements.txt ]; then
                    pip3 install -r /opt/software-repo/python/requirements.txt
                fi
                return 0
            fi
            ;;
        "docker")
            if [ -f /opt/software-repo/docker/binaries.tar.gz ]; then
                tar -xzf /opt/software-repo/docker/binaries.tar.gz -C /usr/bin/
                cp /opt/software-repo/docker/docker-compose /usr/local/bin/
                chmod +x /usr/bin/docker /usr/local/bin/docker-compose
                amazon-linux-extras install docker -y
                systemctl enable docker && systemctl start docker
                usermod -a -G docker ec2-user
                return 0
            fi
            ;;
    esac
    
    return 1
}

# Process SQS messages for package installation
process_package_messages() {
    echo "Listening for package installation messages..."
    
    while true; do
        # Poll SQS for messages
        MESSAGE=$(aws sqs receive-message --queue-url $SQS_QUEUE_URL --region $REGION --output json 2>/dev/null)
        
        if [ "$MESSAGE" != "null" ] && [ -n "$MESSAGE" ]; then
            BODY=$(echo $MESSAGE | jq -r '.Messages[0].Body' 2>/dev/null)
            RECEIPT_HANDLE=$(echo $MESSAGE | jq -r '.Messages[0].ReceiptHandle' 2>/dev/null)
            
            if [ "$BODY" != "null" ]; then
                ACTION=$(echo $BODY | jq -r '.action' 2>/dev/null)
                
                if [ "$ACTION" = "prepare-packages" ]; then
                    APP_NAME=$(echo $BODY | jq -r '.app_name' 2>/dev/null)
                    RUNTIME=$(echo $BODY | jq -r '.requirements.runtime' 2>/dev/null)
                    PACKAGES=$(echo $BODY | jq -r '.requirements.packages | join(" ")' 2>/dev/null)
                    SERVICES=$(echo $BODY | jq -r '.requirements.services | join(" ")' 2>/dev/null)
                    MEMORY=$(echo $BODY | jq -r '.requirements.memory' 2>/dev/null)
                    CPU=$(echo $BODY | jq -r '.requirements.cpu' 2>/dev/null)
                    
                    echo "Preparing packages for $APP_NAME..."
                    
                    # Install required packages
                    install_packages "$RUNTIME" "$PACKAGES" "$SERVICES" "$MEMORY" "$CPU"
                    
                    # Signal readiness in Redis
                    redis-cli -h $REDIS_ENDPOINT set "app:$APP_NAME:packages-ready" "true" >/dev/null 2>&1 || true
                    redis-cli -h $REDIS_ENDPOINT set "app:$APP_NAME:runtime" "$RUNTIME" >/dev/null 2>&1 || true
                    
                    echo "Packages ready for $APP_NAME ($RUNTIME)"
                fi
            fi
            
            # Delete processed message
            if [ "$RECEIPT_HANDLE" != "null" ]; then
                aws sqs delete-message --queue-url $SQS_QUEUE_URL --receipt-handle "$RECEIPT_HANDLE" --region $REGION >/dev/null 2>&1
            fi
        fi
        
        sleep 5
    done
}

# Start the package message processor
process_package_messages
PACKAGE_INSTALLER
chmod +x /opt/heroku-clone/scripts/package_installer.sh

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
nohup /opt/heroku-clone/scripts/package_installer.sh &

echo "SPOT instance ready with intelligent package installation!"
