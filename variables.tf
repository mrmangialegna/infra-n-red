
# PROJECT CONFIGURATION

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "heroku-clone"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

# INSTANCE CONFIGURATION

variable "baseline_instance_type" {
  description = "Instance type for baseline (immediate deployment) instance"
  type        = string
  default     = "t3.medium"
}

variable "spot_instance_type" {
  description = "Instance type for spot instances"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Name of the EC2 Key Pair for SSH access"
  type        = string
  default     = ""
}
# AUTO SCALING CONFIGURATION

variable "spot_min_size" {
  description = "Minimum number of spot instances in ASG"
  type        = number
  default     = 0
}

variable "spot_max_size" {
  description = "Maximum number of spot instances in ASG"
  type        = number
  default     = 5
}

variable "spot_desired_capacity" {
  description = "Desired number of spot instances (starts at 0)"
  type        = number
  default     = 0
}

# MIXED INSTANCES POLICY

variable "on_demand_base_capacity" {
  description = "Base capacity for on-demand instances in spot ASG"
  type        = number
  default     = 0
}

variable "on_demand_percentage_above_base_capacity" {
  description = "Percentage of on-demand instances above base capacity"
  type        = number
  default     = 10
}

variable "spot_allocation_strategy" {
  description = "Strategy for spot instance allocation"
  type        = string
  default     = "diversified"
}

variable "spot_instance_pools" {
  description = "Number of spot instance pools to use"
  type        = number
  default     = 4
}

variable "spot_max_price" {
  description = "Maximum price for spot instances (per hour)"
  type        = string
  default     = "0.05"
}

# LOAD BALANCER WEIGHTS (Blue-Green)

variable "green_weight" {
  description = "Weight for green target group (baseline) - start at 100"
  type        = number
  default     = 100
}

variable "blue_weight" {
  description = "Weight for blue target group (spot) - start at 0, migrate to 100"
  type        = number
  default     = 0
}

# HEALTH CHECK CONFIGURATION

variable "health_check_path" {
  description = "Health check path for ALB target groups"
  type        = string
  default     = "/health"
}

variable "health_check_port" {
  description = "Health check port for ALB target groups"
  type        = number
  default     = 8080
}

variable "health_check_interval_green" {
  description = "Health check interval for green (baseline) target group"
  type        = number
  default     = 15
}

variable "health_check_interval_blue" {
  description = "Health check interval for blue (spot) target group"
  type        = number
  default     = 30
}

variable "health_check_timeout_green" {
  description = "Health check timeout for green (baseline) target group"
  type        = number
  default     = 5
}

variable "health_check_timeout_blue" {
  description = "Health check timeout for blue (spot) target group"
  type        = number
  default     = 10
}

variable "healthy_threshold" {
  description = "Number of consecutive health checks for healthy status"
  type        = number
  default     = 2
}

variable "unhealthy_threshold_green" {
  description = "Number of consecutive failed health checks for unhealthy status (green)"
  type        = number
  default     = 2
}

variable "unhealthy_threshold_blue" {
  description = "Number of consecutive failed health checks for unhealthy status (blue)"
  type        = number
  default     = 3
}

# REDIS CONFIGURATION

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_clusters" {
  description = "Number of cache clusters in Redis replication group"
  type        = number
  default     = 2
}

variable "redis_port" {
  description = "Port for Redis cluster"
  type        = number
  default     = 6379
}

variable "redis_parameter_group" {
  description = "Parameter group for Redis"
  type        = string
  default     = "default.redis7"
}

# S3 CONFIGURATION

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (will be suffixed with random string)"
  type        = string
  default     = "heroku-clone-apps"
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 bucket"
  type        = bool
  default     = true
}

# SQS CONFIGURATION

variable "sqs_queue_name" {
  description = "Name of SQS queue for migration coordination"
  type        = string
  default     = "heroku-clone-migration"
}

variable "sqs_message_retention_seconds" {
  description = "Message retention period in SQS queue"
  type        = number
  default     = 1209600  # 14 days
}

variable "sqs_receive_wait_time_seconds" {
  description = "Long polling wait time for SQS"
  type        = number
  default     = 10
}

# NETWORKING CONFIGURATION

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "enable_ssh_access" {
  description = "Enable SSH access between instances"
  type        = bool
  default     = true
}

# MIGRATION CONFIGURATION

variable "migration_timeout_seconds" {
  description = "Timeout for migration operations"
  type        = number
  default     = 600  # 10 minutes
}

variable "software_sync_timeout_seconds" {
  description = "Timeout for software sync from baseline to spot"
  type        = number
  default     = 120  # 2 minutes
}

variable "baseline_ready_wait_seconds" {
  description = "Time to wait for baseline instance to be ready"
  type        = number
  default     = 60
}

# TAGS

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project      = "Heroku Clone"
    Architecture = "Workload Migration"
    ManagedBy    = "Terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
