# automation.tf

# -------------------------
# IAM Role for CodeBuild
# -------------------------
resource "aws_iam_role" "codebuild_role" {
  name = "paas-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_ecr_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "codebuild_logs_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy" "codebuild_k8s_policy" {
  name = "paas-codebuild-k8s-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "ssm:GetParameter"
        ]
        Resource = "*"
      }
    ]
  })
}

# -------------------------
# CodeBuild project
# -------------------------
resource "aws_codebuild_project" "build_project" {
  name          = "paas-build-project"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = var.codebuild_compute_type
    image           = var.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    
    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.paas_apps.repository_url
    }
    
    environment_variable {
      name  = "APP_NAME"
      value = "#{codebuild.resolved-source-version}"
    }
    
    environment_variable {
      name  = "RDS_ENDPOINT"
      value = aws_db_instance.postgres.endpoint
    }
    
    environment_variable {
      name  = "RDS_USERNAME"
      value = var.rds_username
    }
    
    environment_variable {
      name  = "RDS_PASSWORD"
      value = var.rds_password
    }
    
    environment_variable {
      name  = "REDIS_ENDPOINT"
      value = aws_elasticache_replication_group.redis_cluster.primary_endpoint_address
    }
  }

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.code_bucket.bucket}/source.zip"
    buildspec = file("${path.module}/buildspec.yml")
  }
}

# -------------------------
# IAM Role for Step Functions
# -------------------------
resource "aws_iam_role" "sf_role" {
  name = "paas-stepfunctions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sf_policy" {
  name   = "paas-stepfunctions-policy"
  role   = aws_iam_role.sf_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = aws_codebuild_project.build_project.arn
      }
    ]
  })
}

# -------------------------
# Step Functions state machine
# -------------------------
resource "aws_sfn_state_machine" "build_state_machine" {
  name     = "paas-build-state-machine"
  role_arn = aws_iam_role.sf_role.arn

  definition = jsonencode({
    Comment = "State machine to build user code"
    StartAt = "BuildCode"
    States = {
      BuildCode = {
        Type = "Task"
        Resource = "arn:aws:states:::codebuild:startBuild.sync"
        Parameters = {
          ProjectName = aws_codebuild_project.build_project.name
        }
        End = true
      }
    }
  })
}

# -------------------------
# EventBridge rule for S3 uploads
# -------------------------
resource "aws_cloudwatch_event_rule" "s3_upload_rule" {
  name        = "paas-s3-upload-rule"
  description = "Trigger Step Function when user uploads code"
  event_pattern = jsonencode({
    source = ["aws.s3"]
    detail-type = ["Object Created"]
    resources = [aws_s3_bucket.code_bucket.arn]
  })
}

# -------------------------
# EventBridge target (Step Functions)
# -------------------------
resource "aws_cloudwatch_event_target" "s3_upload_target" {
  rule      = aws_cloudwatch_event_rule.s3_upload_rule.name
  target_id = "StepFunction"
  arn       = aws_sfn_state_machine.build_state_machine.arn
}

# -------------------------
# Permission for EventBridge to invoke Step Functions
# -------------------------
resource "aws_sfn_state_machine_permission" "allow_eventbridge" {
  state_machine_arn = aws_sfn_state_machine.build_state_machine.arn
  principal         = "events.amazonaws.com"
  action            = "states:StartExecution"
}
