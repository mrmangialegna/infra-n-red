# services.tf

# -------------------------
# S3 bucket for user code uploads (with cross-region replication)
# -------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "code_bucket" {
  bucket = var.s3_code_bucket_name != "" ? var.s3_code_bucket_name : "paas-user-code-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "paas-code-bucket"
  }
}

resource "aws_s3_bucket_versioning" "code_bucket_versioning" {
  bucket = aws_s3_bucket.code_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Backup bucket in different region
resource "aws_s3_bucket" "code_bucket_backup" {
  provider = aws.backup_region
  bucket   = "${aws_s3_bucket.code_bucket.bucket}-backup"

  tags = {
    Name = "paas-code-bucket-backup"
  }
}

resource "aws_s3_bucket_versioning" "code_bucket_backup_versioning" {
  provider = aws.backup_region
  bucket   = aws_s3_bucket.code_bucket_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Cross-region replication
resource "aws_s3_bucket_replication_configuration" "replication" {
  role   = aws_iam_role.s3_replication_role.arn
  bucket = aws_s3_bucket.code_bucket.id

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.code_bucket_backup.arn
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [aws_s3_bucket_versioning.code_bucket_versioning]
}

# IAM role for S3 replication
resource "aws_iam_role" "s3_replication_role" {
  name = "paas-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_replication_policy" {
  name = "paas-s3-replication-policy"
  role = aws_iam_role.s3_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.code_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.code_bucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = "${aws_s3_bucket.code_bucket_backup.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "code_bucket_notification" {
  bucket      = aws_s3_bucket.code_bucket.id
  eventbridge = true
}

resource "aws_s3_bucket_acl" "code_bucket_acl" {
  bucket = aws_s3_bucket.code_bucket.id
  acl    = "private"
}


# -------------------------
# RDS PostgreSQL (Unified: Platform + App Data)
# -------------------------
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "paas-rds-subnet-group"
  subnet_ids = [
    aws_subnet.private_subnet_1.id, 
    aws_subnet.private_subnet_2.id,
    aws_subnet.private_subnet_3.id
  ]

  tags = {
    Name = "paas-rds-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "paas-postgres"
  engine                 = "postgres"
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  max_allocated_storage  = 100
  db_name                = "paasdb"
  username               = var.rds_username
  password               = var.rds_password
  multi_az               = false
  storage_type           = "gp3"
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  # Enable automated backups
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  tags = {
    Name = "paas-postgres-unified"
  }
}

# -------------------------
# Redis in-pod 
# -------------------------
# Redis will be deployed as a Kubernetes pod with persistent volume
# This saves ~$12/month compared to ElastiCache

# -------------------------
# VPC Endpoints (saves NAT Gateway costs ~$45/month)
# -------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.paas_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [
    aws_route_table.private_rt.id
  ]

  tags = {
    Name = "paas-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.paas_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet_1.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "paas-ecr-dkr-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.paas_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet_1.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "paas-ecr-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = aws_vpc.paas_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet_1.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "paas-secrets-manager-endpoint"
  }
}

# -------------------------
# Secrets Manager with automatic rotation
# -------------------------
resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "paas-app-secrets"
  description = "Secrets for PaaS applications"

  tags = {
    Name = "paas-app-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets_version" {
  secret_id     = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    DATABASE_PASSWORD = var.rds_password
    API_KEY          = "SuperSecretKey"
  })
}

# Lambda for secrets rotation
resource "aws_lambda_function" "secrets_rotation" {
  filename         = "secrets_rotation.zip"
  function_name    = "paas-secrets-rotation"
  role            = aws_iam_role.secrets_rotation_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 30

  tags = {
    Name = "paas-secrets-rotation"
  }
}

resource "aws_iam_role" "secrets_rotation_role" {
  name = "paas-secrets-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_rotation_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.secrets_rotation_role.name
}

resource "aws_iam_role_policy" "secrets_rotation_policy" {
  name = "paas-secrets-rotation-policy"
  role = aws_iam_role.secrets_rotation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.app_secrets.arn
      }
    ]
  })
}
