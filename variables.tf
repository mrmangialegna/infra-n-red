# variables.tf

# -------------------------
# AWS region
# -------------------------
variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

# -------------------------
# VPC and Networking
# -------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

# -------------------------
# EC2 Master and Worker
# -------------------------
variable "master_instance_type" {
  description = "EC2 instance type for master node"
  type        = string
  default     = "t4g.small"
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes (ARM Spot)"
  type        = string
  default     = "t4g.micro"
}

variable "master_ami_id" {
  description = "AMI ID for master node (on-demand)"
  type        = string
  default     = ""
}

variable "worker_ami_id" {
  description = "AMI ID for worker node (ARM Spot, Kubernetes optimized)"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
}

# -------------------------
# Auto Scaling
# -------------------------
variable "worker_desired_capacity" {
  description = "Initial desired number of worker nodes"
  type        = number
  default     = 2
}

variable "worker_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "worker_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

# -------------------------
# RDS PostgreSQL
# -------------------------
variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Initial allocated storage for RDS (GB)"
  type        = number
  default     = 20
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "rds_username" {
  description = "Master username for RDS"
  type        = string
  default     = "paasadmin"
}

variable "rds_password" {
  description = "Master password for RDS"
  type        = string
  sensitive   = true
}

# -------------------------
# S3 Bucket for Code Upload
# -------------------------
variable "s3_code_bucket_name" {
  description = "S3 bucket name for user code uploads"
  type        = string
  default     = ""
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for second private subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "domain_name" {
  description = "Domain name for the PaaS platform"
  type        = string
  default     = "paas.example.com"
}

# -------------------------
# Redis in-pod 
# -------------------------
# Redis will be deployed as Kubernetes pod with persistent volume

# -------------------------
# Step Functions and CodeBuild
# -------------------------
variable "codebuild_compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
}

variable "codebuild_image" {
  description = "CodeBuild environment image"
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

# -------------------------
# Monitoring
# -------------------------
variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for CloudWatch alarms"
  type        = number
  default     = 80
}

variable "memory_alarm_threshold" {
  description = "Memory utilization threshold for CloudWatch alarms"
  type        = number
  default     = 80
}
