# AWS Secrets Manager for n8n credentials

# n8n Admin Password Secret
resource "aws_secretsmanager_secret" "n8n_password" {
  name        = "${var.project_name}-n8n-password"
  description = "n8n admin password"

  tags = {
    Name = "${var.project_name}-n8n-password"
  }
}

resource "aws_secretsmanager_secret_version" "n8n_password" {
  secret_id     = aws_secretsmanager_secret.n8n_password.id
  secret_string = var.n8n_password
}

# Database Password Secret
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.project_name}-db-password"
  description = "PostgreSQL database password"

  tags = {
    Name = "${var.project_name}-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

# n8n Encryption Key Secret
resource "aws_secretsmanager_secret" "encryption_key" {
  name        = "${var.project_name}-encryption-key"
  description = "n8n encryption key for securing sensitive data"

  tags = {
    Name = "${var.project_name}-encryption-key"
  }
}

resource "aws_secretsmanager_secret_version" "encryption_key" {
  secret_id     = aws_secretsmanager_secret.encryption_key.id
  secret_string = random_password.encryption_key.result
}

# IAM Policy for EC2 to read secrets
resource "aws_iam_role_policy" "secrets_access" {
  name = "${var.project_name}-secrets-access"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.n8n_password.arn,
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.encryption_key.arn
        ]
      }
    ]
  })
}
