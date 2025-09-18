provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "vpc1" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc1"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc1.id

  tags = {
    Name = "vpc1-igw"
  }
}

# First Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc1.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

# Second public subnet for multi-AZ
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.vpc1.id
  cidr_block              = var.public_subnet_cidr2
  availability_zone       = var.availability_zone2
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-2"
  }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate RT to first public subnet
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Associate RT to second public subnet as well
resource "aws_route_table_association" "public_rta_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for App EC2
resource "aws_security_group" "sg1" {
  name        = "sg1"
  description = "App instances security group"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
  }

  ingress {
    from_port       = var.service_port
    to_port         = var.service_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for EC2 with S3 access
resource "aws_iam_role" "ec2_s3_role" {
  name = "ec2_s3_access_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Policy - What EC2 can do with S3
resource "aws_iam_policy" "ec2_s3_policy" {
  name = "ec2_s3_access_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::cloning-app-storage",
        "arn:aws:s3:::cloning-app-storage/*"
      ]
    }]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

# IAM Instance Profile to attach the role to the EC2
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "ec2_s3_profile"
  role = aws_iam_role.ec2_s3_role.name
}

# AMI Amazon Linux 2 system image
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Persistent Volume for MongoDB (EBS)
resource "aws_ebs_volume" "mongo_data" {
  availability_zone = var.availability_zone
  size              = 10

  tags = {
    Name = "mongo_data_volume"
  }
}

# S3 bucket
resource "aws_s3_bucket" "storage" {
  bucket = "cloning-app-storage"

  tags = {
    Name        = "CloningAppStorage"
    Environment = "Dev"
  }
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

  versioning_configuration {
    status = "Enabled"
  }
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP to ALB"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# Application Load Balancer
resource "aws_lb" "app_alb" {
  name               = "notaboringname-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]
  idle_timeout       = 60
  enable_deletion_protection = false

  tags = {
    Name = "notaboringname-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name     = "notaboringname-tg"
  port     = var.service_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc1.id

  health_check {
    enabled             = true
    path                = var.alb_health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200-399"
  }
}

# HTTP listener forwarding (enabled when enable_https=false)
resource "aws_lb_listener" "http_forward" {
  count             = var.enable_https ? 0 : 1
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# HTTP listener redirect (enabled when enable_https=true)
resource "aws_lb_listener" "http_redirect" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener (enabled when enable_https=true)
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Launch Template
resource "aws_launch_template" "app_lt" {
  name_prefix   = "notaboringname-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.sg1.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_s3_profile.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    service docker start
    usermod -a -G docker ec2-user
    curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    mkfs -t ext4 /dev/xvdf || true
    mkdir -p /mnt/mongo_data
    mount /dev/xvdf /mnt/mongo_data || true
    chown ec2-user:ec2-user /mnt/mongo_data
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "notaboringname_asg_ec2"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  name                = "notaboringname-asg"
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_size
  min_size            = var.asg_min_size
  vpc_zone_identifier = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app_tg.arn]

  health_check_type         = "EC2"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "notaboringname_asg_ec2"
    propagate_at_launch = true
  }
}

# Outputs
output "s3_bucket_name" {
  value = aws_s3_bucket.storage.bucket
}

# Private Subnet and NAT for Mongo
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc1.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-mongo"
  }
}

# Elastic IP for NAT
resource "aws_eip" "nat_eip" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "nat-eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = var.enable_nat_gateway ? aws_eip.nat_eip[0].id : null
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "vpc1-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vpc1.id

  tags = {
    Name = "private-route-table"
  }
}

# Route to internet via NAT
resource "aws_route" "private_to_internet_via_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[0].id
}

# Associate private route table to private subnet
resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# MongoDB Security Group (private)
resource "aws_security_group" "mongo_sg" {
  name        = "mongo-sg"
  description = "Allow MongoDB only from app SG"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.sg1.id]
    description     = "App SG to Mongo"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# MongoDB EC2 in private subnet
resource "aws_instance" "mongo" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private_subnet.id
  vpc_security_group_ids      = [aws_security_group.mongo_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_s3_profile.name
  associate_public_ip_address = false
  availability_zone           = var.availability_zone

  tags = {
    Name = "mongo_private_ec2"
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install epel -y || true
    yum install -y mongodb-org || true
    mkdir -p /data/db
    chown -R mongod:mongod /data/db || true
    systemctl enable mongod || true
    systemctl start mongod || true
  EOF
}

# Attach the EBS to the private Mongo instance
resource "aws_volume_attachment" "mongo_data_attach_private" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.mongo_data.id
  instance_id = aws_instance.mongo.id
}
