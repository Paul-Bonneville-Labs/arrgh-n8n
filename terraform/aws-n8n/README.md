# n8n AWS Deployment with Terraform

Deploy n8n on AWS EC2 + RDS for **$17/month** (year 1) or **$32/month** (year 2+).

## Architecture

- **EC2 t4g.small**: 2 vCPU, 2 GB RAM running n8n in Docker
- **RDS PostgreSQL db.t4g.micro**: 1 vCPU, 1 GB RAM database
- **Elastic IP**: Static IP address
- **Caddy**: Automatic HTTPS/SSL certificates
- **CloudWatch**: Monitoring and logging
- **S3**: Optional workflow backups

## Prerequisites

1. **AWS Account** with billing enabled
2. **AWS CLI** configured with credentials
3. **Terraform** >= 1.0 installed
4. **SSH Key Pair** created in AWS
5. **Domain name** for n8n (e.g., n8n.yourdomain.com)

## Quick Start

### 1. Configure Variables

```bash
cd terraform/aws-n8n
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:
- `ssh_key_name`: Your AWS SSH key name
- `n8n_domain`: Your domain (e.g., n8n.yourdomain.com)
- `n8n_password`: Strong password for n8n login
- `db_password`: Strong password for PostgreSQL
- `ssh_allowed_ips`: Your IP address for SSH access (security)

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review Plan

```bash
terraform plan
```

Review the resources that will be created.

### 4. Deploy

```bash
terraform apply
```

Type `yes` to confirm. Deployment takes ~10-15 minutes.

### 5. Configure DNS

Add an A record pointing your domain to the Elastic IP:

```bash
# Get the Elastic IP from Terraform output
terraform output ec2_public_ip

# Add DNS A record
# n8n.yourdomain.com → <elastic-ip>
```

Wait 5-30 minutes for DNS propagation.

### 6. Access n8n

Once DNS propagates, visit:
```
https://n8n.yourdomain.com
```

**Login**:
- Username: `admin`
- Password: (your `n8n_password` from terraform.tfvars)

## Post-Deployment

### SSH into Server

```bash
# Get SSH command from Terraform
terraform output ssh_command

# Or manually
ssh -i ~/.ssh/your-key.pem ubuntu@<elastic-ip>
```

### Check n8n Status

```bash
docker ps
docker logs n8n
```

### View Service URLs

```bash
terraform output n8n_url
```

### Get Encryption Key (for backup/restore)

```bash
terraform output encryption_key
```

## Cost Breakdown

### Year 1 (with RDS Free Tier)
- EC2 t4g.small: $13/month
- RDS db.t4g.micro: $0/month (free tier)
- EBS storage: $1/month
- Data transfer: $1-2/month
- **Total: ~$15-17/month**

### Year 2+ (after Free Tier)
- EC2 t4g.small: $13/month
- RDS db.t4g.micro: $15/month
- EBS storage: $1/month
- Data transfer: $1-2/month
- **Total: ~$30-32/month**

## Monitoring

CloudWatch alarms are configured for:
- EC2 high CPU (>80%)
- RDS high CPU (>80%)

Set `alarm_email` in `terraform.tfvars` to receive alerts.

## Backups

### Automated RDS Backups
- Daily snapshots (7-day retention)
- Configured automatically

### Workflow Backups
A cron job backs up workflows daily at 2 AM:
```bash
# Check backups on EC2
ssh ubuntu@<elastic-ip>
ls -lh ~/backups/

# Manual backup
~/backup-n8n.sh
```

Backups are stored:
- Locally: `/home/ubuntu/backups/` (7-day retention)
- S3: `s3://n8n-backups-<account-id>/workflows/` (30-day retention)

## Maintenance

### Update n8n

```bash
# SSH into server
ssh ubuntu@<elastic-ip>

# Run update script
~/update-n8n.sh
```

### Update System Packages

```bash
ssh ubuntu@<elastic-ip>
sudo apt update && sudo apt upgrade -y
sudo reboot # If kernel updated
```

### View Logs

```bash
# n8n logs
docker logs n8n -f

# System logs
tail -f /var/log/user-data.log
```

## Scaling

### Upgrade EC2 Instance

```bash
# Edit terraform.tfvars
ec2_instance_type = "t4g.medium" # 2 vCPU, 4 GB RAM - $27/month

# Apply changes
terraform apply
```

### Upgrade RDS Instance

```bash
# Edit terraform.tfvars
rds_instance_class = "db.t4g.small" # 2 vCPU, 2 GB RAM - $30/month

# Apply changes
terraform apply
```

## Migration from GCP

See `../MIGRATION_GUIDE.md` for detailed steps to migrate from Google Cloud Run.

## Troubleshooting

### n8n not accessible

1. Check DNS propagation: `dig n8n.yourdomain.com`
2. Check n8n is running: `docker ps`
3. Check Caddy: `sudo systemctl status caddy`
4. Check logs: `docker logs n8n`

### Database connection failed

1. Check RDS is running: `terraform show | grep rds`
2. Check security group: EC2 can access RDS on port 5432
3. Test connection from EC2:
   ```bash
   nc -zv <rds-endpoint> 5432
   ```

### High costs

1. Check AWS Cost Explorer
2. Verify instance types match expected
3. Check for unexpected data transfer
4. Review CloudWatch metrics for over-provisioning

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete:
- EC2 instance
- RDS database (creates final snapshot unless `skip_final_snapshot = true`)
- All data and workflows

## Security Best Practices

1. **Change default passwords** in `terraform.tfvars`
2. **Restrict SSH access**: Set `ssh_allowed_ips` to your IP only
3. **Enable MFA** on AWS account
4. **Rotate passwords** regularly
5. **Review IAM permissions** periodically
6. **Enable CloudTrail** for audit logging
7. **Use AWS Secrets Manager** for production (instead of tfvars)

## Support

For issues:
- n8n: [n8n Community](https://community.n8n.io/)
- AWS: [AWS Support](https://aws.amazon.com/support/)
- Terraform: [Terraform Docs](https://www.terraform.io/docs)

## Files

- `main.tf`: Main infrastructure configuration
- `variables.tf`: Input variables
- `outputs.tf`: Output values
- `user-data.sh`: EC2 initialization script
- `terraform.tfvars.example`: Example configuration
- `.gitignore`: Excluded files from version control

## Next Steps

1. ✅ Deploy infrastructure
2. ✅ Configure DNS
3. ✅ Access n8n
4. 📦 Import workflows from GCP
5. 🧪 Test all workflows
6. 🔄 Update DNS to point to AWS
7. 💰 Monitor costs
8. 🗑️ Decommission GCP resources
