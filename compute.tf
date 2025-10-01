# compute.tf

# -------------------------
# IAM Role for EC2 instances
# -------------------------
resource "aws_iam_role" "k8s_node_role" {
  name = "paas-k8s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "k8s_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.k8s_node_role.name
}

resource "aws_iam_role_policy" "k8s_ssm_policy" {
  name = "paas-k8s-ssm-policy"
  role = aws_iam_role.k8s_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/paas/*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "k8s_node_profile" {
  name = "paas-k8s-node-profile"
  role = aws_iam_role.k8s_node_role.name
}

# -------------------------
# Launch Template for Master Node (On-Demand ARM)
# -------------------------
resource "aws_launch_template" "master_lt" {
  name_prefix   = "paas-master-"
  image_id      = var.master_ami_id != "" ? var.master_ami_id : data.aws_ami.amazon_linux_arm64.id
  instance_type = var.master_instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.k8s_node_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/master_user_data.sh", {
    region = var.aws_region
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
      delete_on_termination = false
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "paas-master"
      Role = "kubernetes-master"
    }
  }
}

# -------------------------
# Auto Scaling Group for Master (min=max=1)
# -------------------------
resource "aws_autoscaling_group" "master_asg" {
  name                = "paas-master-asg"
  vpc_zone_identifier = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id
  ]
  target_group_arns   = []
  health_check_type   = "EC2"
  health_check_grace_period = 300

  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.master_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "paas-master-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "kubernetes.io/cluster/paas-cluster"
    value               = "owned"
    propagate_at_launch = true
  }
}

# -------------------------
# Launch Template for Worker Nodes (Spot ARM)
# -------------------------
resource "aws_launch_template" "worker_lt" {
  name_prefix   = "paas-worker-"
  image_id      = var.worker_ami_id != "" ? var.worker_ami_id : data.aws_ami.amazon_linux_arm64.id
  instance_type = var.worker_instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.k8s_node_profile.name
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  user_data = base64encode(templatefile("${path.module}/worker_user_data.sh", {
    region = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "paas-worker"
      Role = "kubernetes-worker"
    }
  }
}

# -------------------------
# Auto Scaling Group for Workers (Spot)
# -------------------------
resource "aws_autoscaling_group" "worker_asg" {
  name                = "paas-worker-asg"
  vpc_zone_identifier = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id,
    aws_subnet.private_subnet_3.id
  ]
  target_group_arns   = []
  health_check_type   = "EC2"
  health_check_grace_period = 300

  min_size         = var.worker_min_size
  max_size         = var.worker_max_size
  desired_capacity = var.worker_desired_capacity

  launch_template {
    id      = aws_launch_template.worker_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "paas-worker-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "kubernetes.io/cluster/paas-cluster"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/paas-cluster"
    value               = "owned"
    propagate_at_launch = true
  }
}

# -------------------------
# Application Load Balancer
# -------------------------
resource "aws_lb" "paas_alb" {
  name               = "paas-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [
    aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id,
    aws_subnet.public_subnet_3.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "paas-alb"
  }
}

# -------------------------
# ACM Certificate for SSL
# -------------------------
resource "aws_acm_certificate" "paas_cert" {
  domain_name       = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method = "DNS"

  tags = {
    Name = "paas-ssl-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -------------------------
# ALB Target Group
# -------------------------
resource "aws_lb_target_group" "paas_tg" {
  name     = "paas-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.paas_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "paas-tg"
  }
}

# -------------------------
# ALB Listeners (HTTP + HTTPS)
# -------------------------
resource "aws_lb_listener" "paas_listener_http" {
  load_balancer_arn = aws_lb.paas_alb.arn
  port              = "80"
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

resource "aws_lb_listener" "paas_listener_https" {
  load_balancer_arn = aws_lb.paas_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.paas_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.paas_tg.arn
  }
}
