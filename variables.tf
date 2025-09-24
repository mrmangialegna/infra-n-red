# =============================================================================
# HEROKU CLONE - WORKLOAD MIGRATION VARIABLES
# =============================================================================
# Variables for the workload migration architecture

# =============================================================================
# PROJECT CONFIGURATION
# =============================================================================

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

# =============================================================================
# INSTANCE CONFIGURATION
# =============================================================================

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
  description = "Name of the EC2 Key Pair"
  type        = string
  default     = ""
}

# =============================================================================
# SPOT INSTANCES CONFIGURATION
# =============================================================================

variable "spot_max_size" {
  description = "Maximum number of spot instances"
  type        = number
  default     = 5
}

variable "spot_desired_capacity" {
  description = "Desired number of spot instances (starts at 0)"
  type        = number
  default     = 0
}

# =============================================================================
# LOAD BALANCER WEIGHTS (Blue-Green)
# =============================================================================

variable "green_weight" {
  description = "Weight for green target group (baseline)"
  type        = number
  default     = 100
}

variable "blue_weight" {
  description = "Weight for blue target group (spot)"
  type        = number
  default     = 0
}

# =============================================================================
# TAGS
# =============================================================================

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project      = "Heroku Clone"
    Architecture = "Workload Migration"
    ManagedBy    = "Terraform"
  }
}
