# outputs.tf

# -------------------------
# VPC and Subnets
# -------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.paas_vpc.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public_subnet_1.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private_subnet_1.id
}

output "private_subnet_2_id" {
  description = "ID of the second private subnet"
  value       = aws_subnet.private_subnet_2.id
}

output "private_subnet_3_id" {
  description = "ID of the third private subnet"
  value       = aws_subnet.private_subnet_3.id
}

output "public_subnet_2_id" {
  description = "ID of the second public subnet"
  value       = aws_subnet.public_subnet_2.id
}

output "public_subnet_3_id" {
  description = "ID of the third public subnet"
  value       = aws_subnet.public_subnet_3.id
}

output "ssl_certificate_arn" {
  description = "ARN of the SSL certificate"
  value       = aws_acm_certificate.paas_cert.arn
}

# -------------------------
# EC2 Master and Worker
# -------------------------
output "master_asg_id" {
  description = "Auto Scaling Group ID of the master node"
  value       = aws_autoscaling_group.master_asg.id
}

output "worker_asg_id" {
  description = "Auto Scaling Group ID of the worker nodes"
  value       = aws_autoscaling_group.worker_asg.id
}

# -------------------------
# RDS PostgreSQL
# -------------------------
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.postgres.port
}

# -------------------------
# Redis in-pod
# -------------------------

output "s3_backup_bucket" {
  description = "S3 backup bucket name"
  value       = aws_s3_bucket.code_bucket_backup.bucket
}

# -------------------------
# S3 Bucket
# -------------------------
output "s3_code_bucket_name" {
  description = "S3 bucket name for user code uploads"
  value       = aws_s3_bucket.code_bucket.bucket
}

# -------------------------
# ALB
# -------------------------
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.paas_alb.dns_name
}

# -------------------------
# Step Functions and CodeBuild
# -------------------------
output "step_function_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.build_state_machine.arn
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.build_project.name
}

# -------------------------
# S3 VPC Endpoint
# -------------------------
output "s3_vpc_endpoint_id" {
  description = "S3 VPC Endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

# -------------------------
# CloudFront
# -------------------------
output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.paas_cdn.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.paas_cdn.id
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID for Route53"
  value       = aws_cloudfront_distribution.paas_cdn.hosted_zone_id
}

output "webhook_url" {
  description = "Webhook URL for Git integration"
  value       = "${aws_api_gateway_rest_api.git_webhooks.execution_arn}/prod/webhook/{app_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL for container images"
  value       = aws_ecr_repository.paas_apps.repository_url
}
