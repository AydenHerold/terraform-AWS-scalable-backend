variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "APPNAME-ENV"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to use for the subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "ami_id" {
  description = "AMI ID for web servers"
  type        = string
  default     = "ami-0230bd60aa48260c6" # Amazon Linux 2023 - update for your region
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "asg_desired_capacity" {
  description = "Desired capacity for ASG"
  type        = number
  default     = 2
}

variable "asg_min_size" {
  description = "Minimum size for ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum size for ASG"
  type        = number
  default     = 10
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "webapp"
}

variable "APP_DB_USER" {
  description = "Database username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "YOUR-APP-ENV-assets" {
  description = "Name of S3 bucket for static assets"
  type        = string
}

variable "assets_bucket_name" {
  description = "Name of the S3 bucket for static assets"
  type        = string
}

variable "yourdomain_example_com" {
  description = "Domain name for the application"
  type        = string
  default     = "example.com"
}

variable "create_route53_zone" {
  description = "Whether to create a Route53 zone"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "ENV_PLACEHOLDER"
    Project     = "PROJECT_NAME_PLACEHOLDER"
    Terraform   = "true"
  }
}
