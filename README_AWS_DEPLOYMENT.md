# Deploy n8n on AWS - Fresh Installation

Deploy n8n OSS on AWS for **$17/month** (year 1) or **$32/month** (year 2+).

## Quick Deploy (15 minutes)

### Prerequisites

- AWS account
- AWS CLI configured (`aws configure`)
- Terraform installed
- SSH key pair in AWS
- Domain name

### Deploy

```bash
# 1. Configure
cd terraform/aws-n8n
cp terraform.tfvars.example terraform.tfvars

# 2. Edit terraform.tfvars with your settings
# - ssh_key_name: Your AWS SSH key name
# - n8n_domain: Your domain (e.g., n8n.yourdomain.com)
# - n8n_password: Login password
# - db_password: Database password
# - ssh_allowed_ips: Your IP for SSH access

# 3. Deploy
terraform init
terraform apply

# 4. Get IP address
terraform output ec2_public_ip

# 5. Add DNS A record
# n8n.yourdomain.com → <elastic-ip>

# 6. Access (after DNS propagates)
# https://n8n.yourdomain.com
# Username: admin
# Password: <your-n8n-password>
```

## What Gets Deployed

- **EC2 t4g.small**: 2 vCPU, 2 GB RAM ($13/month)
- **RDS PostgreSQL**: 1 vCPU, 1 GB RAM ($0 first year, $15/month after)
- **Automatic SSL**: via Caddy
- **Daily backups**: to S3
- **CloudWatch monitoring**: CPU/memory alerts

## Cost

| Period | Monthly | Yearly | Breakdown |
|--------|---------|--------|-----------|
| Year 1 | $17 | $204 | EC2 + storage (RDS free tier) |
| Year 2+ | $32 | $384 | EC2 + RDS + storage |

## Management

```bash
# SSH to server
ssh ubuntu@<elastic-ip>

# Check status
docker ps
docker logs n8n

# Update n8n
~/update-n8n.sh

# Backup workflows
~/backup-n8n.sh
```

## Scaling

To upgrade resources, edit `terraform.tfvars`:

```hcl
# More CPU/RAM
ec2_instance_type = "t4g.medium"  # $27/month
rds_instance_class = "db.t4g.small" # $30/month
```

Then: `terraform apply`

## Files

- `QUICKSTART.md` - 15-minute deployment guide
- `DEPLOYMENT_GUIDE.md` - Complete documentation
- `AWS_N8N_HOSTING_PLAN.md` - Cost analysis and architecture
- `terraform/aws-n8n/` - Infrastructure code
- `terraform/aws-n8n/README.md` - Terraform documentation

## Support

- n8n: https://community.n8n.io/
- AWS: https://aws.amazon.com/support/
- Infrastructure issues: Check terraform/aws-n8n/README.md
