provider "aws" {
  region = var.region
}

# VPC and Networking (simplified)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(var.default_tags, var.additional_tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "heroku-clone-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = merge(var.default_tags, { Name = "${var.project_name}-public-subnet-${count.index + 1}" })
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = merge(var.default_tags, { Name = "${var.project_name}-private-subnet-${count.index + 1}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "heroku-clone-alb-"
  vpc_id      = aws_vpc.main.id

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

resource "aws_security_group" "instances" {
  name_prefix = "heroku-clone-instances-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8090
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    self      = true  # Instances can SSH to each other
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Redis for session/state management
resource "aws_elasticache_subnet_group" "main" {
  name       = "heroku-clone-cache"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${var.project_name}-redis"
  description                = "Redis for workload migration"
  node_type                  = var.redis_node_type
  port                       = var.redis_port
  num_cache_clusters         = var.redis_num_cache_clusters
  automatic_failover_enabled = true
  multi_az_enabled          = true
  subnet_group_name         = aws_elasticache_subnet_group.main.name
  security_group_ids        = [aws_security_group.instances.id]
  
  tags = var.default_tags
}

# S3 for app storage
resource "aws_s3_bucket" "apps" {
  bucket = "${var.s3_bucket_prefix}-${random_string.suffix.result}"
  tags = var.default_tags
}

resource "aws_s3_bucket_versioning" "apps" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.apps.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# SQS for migration coordination
resource "aws_sqs_queue" "migration" {
  name                      = var.sqs_queue_name
  message_retention_seconds = var.sqs_message_retention_seconds
  receive_wait_time_seconds = var.sqs_receive_wait_time_seconds
  tags = var.default_tags
}

# IAM for instances
resource "aws_iam_role" "instance" {
  name = "heroku-clone-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "instance" {
  name = "heroku-clone-instance-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:ListBucket",
          "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
          "ec2:DescribeInstances", "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "instance" {
  role       = aws_iam_role.instance.name
  policy_arn = aws_iam_policy.instance.arn
}

resource "aws_iam_instance_profile" "instance" {
  name = "heroku-clone-instance-profile"
  role = aws_iam_role.instance.name
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "heroku-clone-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

# Target Groups for Green (baseline) and Blue (spot)
resource "aws_lb_target_group" "green" {
  name     = "heroku-clone-green"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
  }

  tags = { Stage = "green-baseline" }
}

resource "aws_lb_target_group" "blue" {
  name     = "heroku-clone-blue"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
  }

  tags = { Stage = "blue-production" }
}

# ALB Listener with weighted routing (starts 100% green, migrates to blue)
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = var.green_weight  # Start at 100, migrate to 0
      }
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = var.blue_weight   # Start at 0, migrate to 100
      }
    }
  }
}

# Baseline EC2 Instance (Green Stage - Immediate Deployment)
resource "aws_instance" "baseline" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.baseline_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.instances.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  key_name              = var.key_name
/*/
  user_data = base64encode(templatefile("baseline_user_data.sh", {
    redis_endpoint = aws_elasticache_replication_group.main.primary_endpoint_address
    s3_bucket      = aws_s3_bucket.apps.bucket
    sqs_queue_url  = aws_sqs_queue.migration.url
    region         = var.region
  }))

  tags = {
    Name  = "heroku-clone-baseline"
    Stage = "green-baseline"
    Role  = "immediate-deployment"
  }
}
/**/
# Call to baseline_user_data.sh with replacements
user_data = base64encode(
  replace(
    replace(
      replace(
        replace(
          file("${path.module}/baseline_user_data.sh"),
          "$${redis_endpoint}",
          aws_elasticache_replication_group.main.primary_endpoint_address
        ),
        "$${s3_bucket}",
        aws_s3_bucket.apps.bucket
      ),
      "$${sqs_queue_url}",
      aws_sqs_queue.migration.url
    ),
    "$${region}",
    var.region
  )
)
}

# Auto Scaling Group for Spot Instances (Blue Stage - Production)
resource "aws_launch_template" "spot" {
  name_prefix   = "heroku-clone-spot-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.spot_instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.instances.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }

  user_data = base64encode(templatefile("${path.module}/spot_user_data.sh", {
    baseline_ip    = aws_instance.baseline.private_ip
    redis_endpoint = aws_elasticache_replication_group.main.primary_endpoint_address
    s3_bucket      = aws_s3_bucket.apps.bucket
    sqs_queue_url  = aws_sqs_queue.migration.url
    region         = var.region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name  = "heroku-clone-spot"
      Stage = "blue-production"
      Role  = "cost-optimized-production"
    }
  }
}

resource "aws_autoscaling_group" "spot" {
  name                = "heroku-clone-spot-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.blue.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = 0  # Start with 0, scale up when migration begins
  max_size         = var.spot_max_size
  desired_capacity = 0

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.spot.id
        version           = "$Latest"
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 10
      spot_allocation_strategy                 = "diversified"
      spot_instance_pools                      = 4
    }
  }

  tag {
    key                 = "Name"
    value               = "heroku-clone-spot-asg"
    propagate_at_launch = false
  }
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "baseline" {
  target_group_arn = aws_lb_target_group.green.arn
  target_id        = aws_instance.baseline.id
  port             = 8080
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Outputs
output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "baseline_ip" {
  value = aws_instance.baseline.public_ip
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "migration_command" {
  value = "aws sqs send-message --queue-url ${aws_sqs_queue.migration.url} --message-body 'start-migration' --region ${var.region}"
}


# Private subnet for MongoDB
resource "aws_subnet" "mongodb" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.mongodb_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = merge(var.default_tags, { Name = "${var.project_name}-mongodb-subnet" })
}

# Route table for MongoDB subnet
resource "aws_route_table" "mongodb" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "mongodb-rt" }
}

resource "aws_route_table_association" "mongodb" {
  subnet_id      = aws_subnet.mongodb.id
  route_table_id = aws_route_table.mongodb.id
}

# Security group for MongoDB
resource "aws_security_group" "mongodb" {
  name_prefix = "heroku-clone-mongodb-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.instances.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EBS volume for MongoDB
resource "aws_ebs_volume" "mongodb" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = var.mongodb_volume_size
  type              = "gp3"
  encrypted         = true

  tags = merge(var.default_tags, {
    Name   = "${var.project_name}-mongodb-volume"
    Backup = "MongoDB"
  })
}

# MongoDB instance
resource "aws_instance" "mongodb" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.mongodb_instance_type
  subnet_id              = aws_subnet.mongodb.id
  vpc_security_group_ids = [aws_security_group.mongodb.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  availability_zone      = data.aws_availability_zones.available.names[0]

  user_data_base64 = base64encode(file("${path.module}/mongodb_user_data.sh")) 

  tags = merge(var.default_tags, {
    Name = "${var.project_name}-mongodb"
    Role = "database"
  })
}

# Volume attachment
resource "aws_volume_attachment" "mongodb" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.mongodb.id
  instance_id = aws_instance.mongodb.id
}