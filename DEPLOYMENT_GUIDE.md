# AWS n8n Deployment Guide

Complete guide to deploy n8n on AWS for **$17/month** (66% savings vs GCP).

## Quick Start (5 Steps)

### 1. Prerequisites

- AWS account with billing enabled
- AWS CLI configured (`aws configure`)
- Terraform >= 1.0 installed
- SSH key pair in AWS
- Domain name

### 2. Configure

```bash
cd terraform/aws-n8n
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
ssh_key_name = "your-aws-key"
n8n_domain   = "n8n.yourdomain.com"
n8n_password = "strong-password"
db_password  = "strong-db-password"
ssh_allowed_ips = ["YOUR_IP/32"]  # Your IP only
```

### 3. Deploy

```bash
terraform init
terraform apply
```

Wait 10-15 minutes for deployment.

### 4. Configure DNS

Get IP address:
```bash
terraform output ec2_public_ip
```

Add DNS A record:
```
n8n.yourdomain.com → <elastic-ip>
```

### 5. Access n8n

Visit `https://n8n.yourdomain.com`
- Username: `admin`
- Password: (your `n8n_password`)

---

## Migration from GCP

### Automated Migration

```bash
./scripts/migrate-gcp-to-aws.sh
```

This script:
1. Exports workflows from GCP
2. Exports database from Cloud SQL
3. Deploys AWS infrastructure
4. Imports data to AWS
5. Guides DNS cutover

### Manual Migration

#### 1. Export from GCP

**Workflows**:
```bash
# Via API
curl -X GET https://n8n.paulbonneville.com/api/v1/workflows \
  -H "X-N8N-API-KEY: your-key" > workflows.json

# Or via UI: Settings > Export
```

**Database**:
```bash
# Export Cloud SQL
gcloud sql export sql your-instance-name \
  gs://your-bucket/n8n-backup.sql \
  --database=n8n

# Download
gsutil cp gs://your-bucket/n8n-backup.sql .
```

#### 2. Deploy AWS

```bash
cd terraform/aws-n8n
terraform apply
```

#### 3. Import to AWS

**Database**:
```bash
# Get RDS endpoint
terraform output rds_endpoint

# SSH to EC2
ssh ubuntu@<elastic-ip>

# Import
export PGPASSWORD="your-db-password"
psql -h <rds-endpoint> -U n8n -d n8n < n8n-backup.sql
```

**Workflows**:
- Access https://n8n.yourdomain.com
- Settings > Import from File
- Upload workflows.json

#### 4. Update DNS

Point `n8n.yourdomain.com` to AWS Elastic IP

#### 5. Decommission GCP

After 48 hours of AWS monitoring:

```bash
# Delete Cloud Run
gcloud run services delete n8n-app --region=us-central1

# Delete Cloud SQL (after final backup)
gcloud sql instances delete your-instance
```

---

## Architecture

```
┌─────────────────────────────────────┐
│ DNS: n8n.yourdomain.com             │
│           ↓                         │
│  ┌──────────────────┐               │
│  │ Elastic IP       │               │
│  │ (Static Public)  │               │
│  └────────┬─────────┘               │
│           ↓                         │
│  ┌──────────────────┐               │
│  │ EC2 t4g.small    │               │
│  │ 2 vCPU, 2 GB RAM │               │
│  │                  │               │
│  │ - Caddy (SSL)    │               │
│  │ - Docker         │               │
│  │ - n8n container  │               │
│  └────────┬─────────┘               │
│           │                         │
│           ↓ PostgreSQL              │
│  ┌──────────────────┐               │
│  │ RDS PostgreSQL   │               │
│  │ db.t4g.micro     │               │
│  │ 1 vCPU, 1 GB RAM │               │
│  │ Private subnet   │               │
│  └──────────────────┘               │
│                                     │
│  ┌──────────────────┐               │
│  │ S3 Backups       │               │
│  │ (Optional)       │               │
│  └──────────────────┘               │
└─────────────────────────────────────┘
```

---

## Cost Breakdown

### Monthly Costs

**Year 1** (with RDS Free Tier):
- EC2 t4g.small: $13.00
- RDS db.t4g.micro: $0.00 (free tier)
- EBS 8GB: $0.80
- Elastic IP: $0.00
- Data transfer: $1.00
- S3 backups: $0.50
- **Total: ~$15-17/month**

**Year 2+**:
- EC2 t4g.small: $13.00
- RDS db.t4g.micro: $15.00
- EBS 8GB: $0.80
- Elastic IP: $0.00
- Data transfer: $1.00
- S3 backups: $0.50
- **Total: ~$30-32/month**

### Savings

| Period | GCP Cost | AWS Cost | Savings |
|--------|----------|----------|---------|
| Year 1 | $600 | $204 | **$396 (66%)** |
| Year 2+ | $600 | $384 | **$216 (36%)** |

---

## Management

### Access Server

```bash
# SSH
ssh ubuntu@<elastic-ip>

# Or get command from Terraform
terraform output ssh_command
```

### Check Status

```bash
# n8n container
docker ps
docker logs n8n

# Caddy (SSL)
sudo systemctl status caddy

# System resources
htop
df -h
```

### Update n8n

```bash
ssh ubuntu@<elastic-ip>
~/update-n8n.sh
```

### Backup Workflows

```bash
# Manual backup
ssh ubuntu@<elastic-ip>
~/backup-n8n.sh

# Check backups
ls -lh ~/backups/
```

Backups run automatically daily at 2 AM.

### View Logs

```bash
# n8n application logs
docker logs n8n -f

# System startup logs
tail -f /var/log/user-data.log

# Caddy logs
sudo journalctl -u caddy -f
```

---

## Monitoring

### CloudWatch Metrics

View in AWS Console:
- EC2 CPU utilization
- RDS CPU utilization
- Memory usage (requires CloudWatch agent)
- Disk usage

### Alarms

Set `alarm_email` in `terraform.tfvars` to receive:
- High CPU alerts (>80%)
- Database issues
- Instance state changes

### Cost Monitoring

```bash
# View current month estimate
aws ce get-cost-and-usage \
  --time-period Start=2025-10-01,End=2025-10-31 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

---

## Scaling

### Upgrade EC2

When needed (high CPU, memory pressure):

```hcl
# Edit terraform.tfvars
ec2_instance_type = "t4g.medium"  # 2 vCPU, 4 GB RAM - $27/month
```

```bash
terraform apply
```

### Upgrade RDS

When needed (database slow, high CPU):

```hcl
# Edit terraform.tfvars
rds_instance_class = "db.t4g.small"  # 2 vCPU, 2 GB RAM - $30/month
```

```bash
terraform apply
```

### Scaling Path

| Workload | EC2 | RDS | Cost/Month |
|----------|-----|-----|------------|
| Light | t4g.small | db.t4g.micro | $32 |
| Medium | t4g.medium | db.t4g.small | $57 |
| Heavy | t4g.large | db.t4g.medium | $110 |

---

## Troubleshooting

### n8n not accessible

```bash
# Check DNS
dig n8n.yourdomain.com

# Check n8n running
ssh ubuntu@<elastic-ip>
docker ps | grep n8n

# Check Caddy
sudo systemctl status caddy

# Check logs
docker logs n8n
```

### Database connection failed

```bash
# Test from EC2
nc -zv <rds-endpoint> 5432

# Check security group
aws ec2 describe-security-groups \
  --group-names rds-n8n-sg

# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier n8n-db
```

### SSL certificate issues

```bash
# Check Caddy logs
sudo journalctl -u caddy -n 100

# Restart Caddy
sudo systemctl restart caddy

# Verify domain resolves
dig n8n.yourdomain.com +short
```

### High costs

1. Check Cost Explorer in AWS Console
2. Verify instance types:
   ```bash
   terraform show | grep instance_type
   ```
3. Check for stopped instances still incurring charges
4. Review data transfer costs

---

## Security

### Best Practices

1. **Change default passwords** in terraform.tfvars
2. **Restrict SSH**: Set `ssh_allowed_ips = ["YOUR_IP/32"]`
3. **Enable MFA** on AWS account
4. **Use AWS Secrets Manager** for production
5. **Keep n8n updated** regularly
6. **Enable CloudTrail** for audit logs
7. **Regular backups** - verify backup restoration

### Rotate Credentials

```bash
# Update n8n password
ssh ubuntu@<elastic-ip>
cd ~/n8n
# Edit docker-compose.yml
docker compose restart
```

---

## Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
- [AWS RDS Pricing](https://aws.amazon.com/rds/postgresql/pricing/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

## Support

- **n8n Issues**: [n8n Community](https://community.n8n.io/)
- **AWS Issues**: AWS Support Console
- **Infrastructure**: Check terraform/aws-n8n/README.md

---

## Cleanup

To completely remove AWS infrastructure:

```bash
cd terraform/aws-n8n
terraform destroy
```

**Warning**: This deletes everything including:
- EC2 instance
- RDS database (creates snapshot unless disabled)
- All workflows and data
- Backups in S3
