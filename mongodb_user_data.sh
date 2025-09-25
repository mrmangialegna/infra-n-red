#!/bin/bash
set -e

# Variables
REGION="${region}"
S3_BUCKET="${s3_bucket}"
MONGODB_INSTANCE_TYPE="${mongodb_instance_type}"
MONGODB_VOLUME_SIZE="${mongodb_volume_size}"
MONGODB_SUBNET_CIDR="${mongodb_subnet_cidr}"

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Update system packages..."
yum update -y

log "Install AWS CLI..."
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
fi

log "Configure MongoDB repository..."
cat <<EOF >/etc/yum.repos.d/mongodb-org-7.repo
[mongodb-org-7]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/7/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
EOF

log "Install MongoDB..."
yum install -y mongodb-org

log "Create data folder /data/db..."
mkdir -p /data/db
chown -R mongod:mongod /data/db

log "Start and enable MongoDB service..."
systemctl enable mongod
systemctl start mongod

# Download data from S3 if bucket is specified
if [[ -n "$S3_BUCKET" ]]; then
    log "Download initial data from S3 bucket $S3_BUCKET..."
    aws s3 cp s3://$S3_BUCKET/mongodb-init/ /data/db/ --recursive --region $REGION
    chown -R mongod:mongod /data/db
fi

log "MongoDB configured successfully in the region $REGION"
