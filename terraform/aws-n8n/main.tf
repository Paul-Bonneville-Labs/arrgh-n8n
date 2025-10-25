terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configure after creating S3 bucket:
    # bucket = "your-terraform-state-bucket"
    # key    = "n8n/terraform.tfstate"
    # region = "us-east-1"
    # dynamodb_table = "terraform-state-lock"
    # encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "n8n"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Data source for latest Ubuntu 24.04 ARM AMI
data "aws_ami" "ubuntu_arm" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for EC2 instance
resource "aws_security_group" "n8n" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for n8n EC2 instance"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_ips
    description = "SSH access"
  }

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

# Security Group for RDS instance
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for n8n RDS database"

  # PostgreSQL access from EC2 security group only
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.n8n.id]
    description     = "PostgreSQL from EC2"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# EC2 Instance
resource "aws_instance" "n8n" {
  ami           = data.aws_ami.ubuntu_arm.id
  instance_type = var.ec2_instance_type
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.n8n.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = var.ebs_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    n8n_domain               = var.n8n_domain
    db_host                  = aws_db_instance.n8n.endpoint
    db_name                  = var.db_name
    db_user                  = var.db_username
    aws_region               = var.aws_region
    n8n_password_secret_arn  = aws_secretsmanager_secret.n8n_password.arn
    db_password_secret_arn   = aws_secretsmanager_secret.db_password.arn
    encryption_key_secret_arn = aws_secretsmanager_secret.encryption_key.arn
  })

  # Wait for RDS to be available
  depends_on = [aws_db_instance.n8n]

  tags = {
    Name = "${var.project_name}-server"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Elastic IP
resource "aws_eip" "n8n" {
  instance = aws_instance.n8n.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }

  depends_on = [aws_instance.n8n]
}

# Random encryption key for n8n
resource "random_password" "encryption_key" {
  length  = 32
  special = false
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "n8n" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "14.13"
  instance_class = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]

  # Backup configuration
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # Snapshot configuration
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Performance Insights (optional, adds cost)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Multi-AZ for production (adds cost)
  multi_az = var.multi_az

  # Disable public access
  publicly_accessible = false

  tags = {
    Name = "${var.project_name}-database"
  }
}

# CloudWatch Log Group for n8n logs
resource "aws_cloudwatch_log_group" "n8n" {
  name              = "/aws/ec2/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# CloudWatch Metric Alarm for High CPU
resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name          = "${var.project_name}-ec2-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions       = var.alarm_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    InstanceId = aws_instance.n8n.id
  }
}

# CloudWatch Metric Alarm for RDS CPU
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = var.alarm_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.n8n.id
  }
}

# SNS Topic for CloudWatch Alarms (optional)
resource "aws_sns_topic" "alerts" {
  count = var.alarm_email != "" ? 1 : 0
  name  = "${var.project_name}-alerts"

  tags = {
    Name = "${var.project_name}-alerts"
  }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# S3 Bucket for backups (optional)
resource "aws_s3_bucket" "backups" {
  count  = var.enable_s3_backups ? 1 : 0
  bucket = "${var.project_name}-backups-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-backups"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  count  = var.enable_s3_backups ? 1 : 0
  bucket = aws_s3_bucket.backups[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  count  = var.enable_s3_backups ? 1 : 0
  bucket = aws_s3_bucket.backups[0].id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  count  = var.enable_s3_backups ? 1 : 0
  bucket = aws_s3_bucket.backups[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for EC2 (for CloudWatch and S3 access)
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "s3_backup_access" {
  count = var.enable_s3_backups ? 1 : 0
  name  = "${var.project_name}-s3-backup-access"
  role  = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.backups[0].arn,
          "${aws_s3_bucket.backups[0].arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}
