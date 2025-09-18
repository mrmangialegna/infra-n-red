#Region
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

#Availability zone 1 for public subnet
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

#Availability zone 2 for public subnet
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

#CIDR for the private subnet
variable "private_subnet_cidr" {
  description = "CIDR for the private subnet"
  type        = string
  default     = "10.0.10.0/24"
}

#Whether to create a NAT Gateway for private subnet egress
variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway for private subnet egress"
  type        = bool
  default     = true
}

variable "service_port" {
  description = "Application service port exposed on instances and checked by ALB"
  type        = number
  default     = 8080
}

variable "enable_https" {
  description = "Enable HTTPS listener on ALB and redirect HTTP to HTTPS"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS on ALB (required if enable_https=true)"
  type        = string
  default     = ""
} 