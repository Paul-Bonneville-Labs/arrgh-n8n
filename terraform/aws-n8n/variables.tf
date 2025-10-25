variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "n8n"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}

# EC2 Configuration
variable "ec2_instance_type" {
  description = "EC2 instance type (ARM-based t4g recommended for cost)"
  type        = string
  default     = "t4g.small" # 2 vCPU, 2 GB RAM - $13/month
}

variable "ebs_volume_size" {
  description = "EBS root volume size in GB"
  type        = number
  default     = 8
}

variable "ssh_key_name" {
  description = "Name of existing SSH key pair for EC2 access"
  type        = string
}

variable "ssh_allowed_ips" {
  description = "List of IP addresses allowed to SSH into EC2 instance"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Change this to your IP for security
}

# RDS Configuration
variable "rds_instance_class" {
  description = "RDS instance class (ARM-based db.t4g recommended for cost)"
  type        = string
  default     = "db.t4g.micro" # 1 vCPU, 1 GB RAM - Free tier eligible, then $15/month
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage size in GB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum RDS storage size in GB for autoscaling"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "n8n"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "n8n"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long"
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain automated RDS backups"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final RDS snapshot on destroy (not recommended for production)"
  type        = bool
  default     = false
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for RDS (adds cost but improves availability)"
  type        = bool
  default     = false
}

# n8n Configuration
variable "n8n_domain" {
  description = "Domain name for n8n (e.g., n8n.yourdomain.com)"
  type        = string
}

variable "n8n_password" {
  description = "n8n basic auth password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.n8n_password) >= 8
    error_message = "n8n password must be at least 8 characters long"
  }
}

# Monitoring Configuration
variable "alarm_email" {
  description = "Email address for CloudWatch alarms (leave empty to disable)"
  type        = string
  default     = ""
}

# Backup Configuration
variable "enable_s3_backups" {
  description = "Enable S3 bucket for workflow backups"
  type        = bool
  default     = true
}
