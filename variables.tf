#Region
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

#Availability zone 1 
variable "availability_zone" {
  description = "Availability zone"
  type        = string
  default     = "us-west-2a"
}

#Instance type for EC2
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.medium"
}

#Allowed SSH CIDR Ingress
variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed for SSH (use your IP!)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

#Availability zone 2 
variable "availability_zone2" {
  description = "Second Availability zone"
  type        = string
  default     = "us-west-2b"
}

#CIDR for the second public subnet
variable "public_subnet_cidr2" {
  description = "CIDR for the second public subnet"
  type        = string
  default     = "10.0.2.0/24"
}

#ASG minimum capacity
variable "asg_min_size" {
  description = "ASG minimum capacity"
  type        = number
  default     = 1
}

#ASG desired capacity
variable "asg_desired_capacity" {
  description = "ASG desired capacity"
  type        = number
  default     = 2
}

#ASG maximum capacity
variable "asg_max_size" {
  description = "ASG maximum capacity"
  type        = number
  default     = 3
}

#Health check path for ALB target group
variable "alb_health_check_path" {
  description = "Health check path for ALB target group"
  type        = string
  default     = "/health"
}

#CIDR for the private subnet Mongo
variable "private_subnet_cidr_Mongo" {
  description = "CIDR for the private subnet for Mongo"
  type        = string
  default     = "10.0.10.0/24"
}

#CIDR for the private subnet Mongo 2
variable "private_subnet_cidr_Mongo_2" {
  description = "CIDR for the private subnet for Mongo"
  type        = string
  default     = "10.0.11.0/24"
}

#CIDR for the private subnet Mongo 3
variable "mongo_subnet_cidr_3" {
  description = "CIDR for the third private subnet for Mongo"     
  type        = string
  default     = "10.0.12.0/24"
}

#CIDR for the private subnet EC2
variable "private_subnet_cidr_EC2" {
  description = "CIDR for the private subnet for EC2"
  type        = string
  default     = "10.0.9.0/24"
}

#CIDR for the private subnet EC2 2
variable "private_subnet_cidr_EC2_2" {
  description = "CIDR for the private subnet for EC2"
  type        = string
  default     = "10.0.8.0/24"
}

#Whether to create a NAT Gateway for private subnet egress
variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway for private subnet egress"
  type        = bool
  default     = true
}
#Service port
variable "service_port" {
  description = "Application service port exposed on instances and checked by ALB"
  type        = number
  default     = 8080
}
# Listener HTTPS
variable "enable_https" {
  description = "Enable HTTPS listener on ALB and redirect HTTP to HTTPS"
  type        = bool
  default     = false
}
# ACM certificate ARN
variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS on ALB (required if enable_https=true)"
  type        = string
  default     = ""
} 

# Cron schedule for EBS backups
variable "backup_schedule" {
  description = "Cron schedule for EBS backups"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC
}
