variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment (prod, staging)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "Environment must be prod or staging."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_username" {
  description = "Master username for RDS PostgreSQL"
  type        = string
  default     = "contoso_app"
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS ALB listener. Leave empty to skip HTTPS listener (HTTP only)."
  type        = string
  default     = ""
}
