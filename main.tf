provider "aws" {
  region = "us-west-2"
}

# --- VPC ---
resource "aws_vpc" "vpc1" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "vpc1" }
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc1.id
  tags = { Name = "vpc1-igw" }
}

# --- Subnet ---
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc1.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet" }
}

# --- Route Table ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc1.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-route-table" }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# --- Security Group ---
resource "aws_security_group" "sg1" {
  name        = "sg1"
  description = "In/out traffic on ports 22, 80, 27017"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM Role per EC2 con accesso S3 ---
resource "aws_iam_role" "ec2_s3_role" {
  name = "ec2_s3_access_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "ec2_s3_policy" {
  name   = "ec2_s3_access_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject","s3:GetObject","s3:ListBucket"]
      Resource = ["arn:aws:s3:::cloning-app-storage","arn:aws:s3:::cloning-app-storage/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

# --- IAM Instance Profile ---
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "ec2_s3_profile"
  role = aws_iam_role.ec2_s3_role.name
}

# --- Key Pair ---
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("chiave.pub")
}

# --- AMI Amazon Linux 2 ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter { name = "name"; values = ["amzn2-ami-hvm-*-x86_64-gp2"] }
}

# --- Volume persistente per MongoDB (EBS) ---
resource "aws_ebs_volume" "mongo_data" {
  availability_zone = "us-west-2a"
  size              = 10
  tags = { Name = "mongo_data_volume" }
}

# --- EC2 Instance ---
resource "aws_instance" "base" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.medium"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.sg1.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3_profile.name
  key_name               = aws_key_pair.deployer.key_name
  availability_zone      = "us-west-2a"

  tags = { Name = "notaboringname_ec2" }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    service docker start
    usermod -a -G docker ec2-user
    curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    mkfs -t ext4 /dev/xvdf
    mkdir -p /mnt/mongo_data
    mount /dev/xvdf /mnt/mongo_data
    chown ec2-user:ec2-user /mnt/mongo_data
  EOF
}

# --- Attach EBS volume all'EC2 ---
resource "aws_volume_attachment" "mongo_data_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.mongo_data.id
  instance_id = aws_instance.base.id
}

# --- S3 bucket ---
resource "aws_s3_bucket" "storage" {
  bucket = "cloning-app-storage"
  tags = { Name = "CloningAppStorage"; Environment = "Dev" }
}

resource "aws_s3_bucket_public_access_block" "storage_pab" {
  bucket = aws_s3_bucket.storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "storage_versioning" {
  bucket = aws_s3_bucket.storage.id
  versioning_configuration { status = "Enabled" }
}

# --- Outputs ---
output "instance_public_ip" {
  value = aws_instance.base.public_ip
}

output "s3_bucket_name" {
  value = aws_s3_bucket.storage.bucket
}
