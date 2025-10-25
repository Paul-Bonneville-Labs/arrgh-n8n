output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.n8n.id
}

output "ec2_public_ip" {
  description = "Elastic IP address for n8n server"
  value       = aws_eip.n8n.public_ip
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.n8n.endpoint
  sensitive   = true
}

output "rds_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.n8n.id
}

output "n8n_url" {
  description = "n8n access URL"
  value       = "https://${var.n8n_domain}"
}

output "ssh_command" {
  description = "SSH command to connect to EC2 instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_eip.n8n.public_ip}"
}

output "s3_backup_bucket" {
  description = "S3 bucket name for backups"
  value       = var.enable_s3_backups ? aws_s3_bucket.backups[0].id : null
}

output "encryption_key" {
  description = "Generated n8n encryption key"
  value       = random_password.encryption_key.result
  sensitive   = true
}

output "dns_configuration" {
  description = "DNS A record configuration"
  value = {
    hostname = var.n8n_domain
    type     = "A"
    value    = aws_eip.n8n.public_ip
    ttl      = 300
  }
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    ec2 = aws_security_group.n8n.id
    rds = aws_security_group.rds.id
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT

  🎉 n8n Infrastructure Deployed Successfully!

  Next Steps:

  1. Update DNS:
     - Add A record: ${var.n8n_domain} → ${aws_eip.n8n.public_ip}
     - Wait for DNS propagation (5-30 minutes)

  2. SSH into server:
     ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_eip.n8n.public_ip}

  3. Check n8n status:
     docker ps
     docker logs n8n

  4. Access n8n:
     https://${var.n8n_domain}
     Username: admin
     Password: <your-n8n-password>

  5. Import workflows from GCP

  6. Monitor costs in AWS Console

  EOT
}
