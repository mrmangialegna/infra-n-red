# lambda.tf

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_ebs_snapshot.zip"
  
  source_file  = "${path.module}/lambda_function.py"
}

resource "aws_lambda_function" "ebs_snapshot" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "ebs_snapshot_function"
  role             = aws_iam_role.lambda_ebs_snapshot_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)
  timeout          = 60
  
  depends_on = [data.archive_file.lambda_zip]
}

resource "aws_iam_role" "lambda_ebs_snapshot_role" {
  name = "lambda_ebs_snapshot_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_snapshot_policy" {
  name = "lambda_snapshot_policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateTags", 
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_snapshot_policy" {
  role       = aws_iam_role.lambda_ebs_snapshot_role.name
  policy_arn = aws_iam_policy.lambda_snapshot_policy.arn
}

# CloudWatch scheduling
resource "aws_cloudwatch_event_rule" "daily_snapshot" {
  name                = "daily-snapshot-rule"
  schedule_expression = var.backup_schedule
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_snapshot.name
  target_id = "lambda-ebs-snapshot"
  arn       = aws_lambda_function.ebs_snapshot.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ebs_snapshot.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_snapshot.arn
}

# variables.tf
variable "backup_schedule" {
  description = "Cron expression for the backup schedule"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Daily at 2 AM
}

### terraform.tfvars


