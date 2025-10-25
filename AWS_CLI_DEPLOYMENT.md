# Deploy n8n on AWS with AWS CLI

Deploy n8n using **only AWS CLI** (no Terraform required) for **$17/month**.

## Quick Deploy

### Prerequisites

```bash
# Install AWS CLI
brew install awscli  # macOS
# or: https://aws.amazon.com/cli/

# Install jq (JSON parser)
brew install jq  # macOS

# Configure AWS
aws configure
```

Create SSH key in AWS Console:
- EC2 → Key Pairs → Create Key Pair
- Save `.pem` file

### Deploy

```bash
./scripts/deploy-n8n-aws.sh
```

The script will ask for:
- AWS region (default: us-east-1)
- SSH key name (from AWS)
- Domain name (e.g., n8n.yourdomain.com)
- n8n password
- Database password

Then it automatically:
1. Creates security groups
2. Launches RDS PostgreSQL
3. Launches EC2 instance
4. Configures Docker + n8n
5. Sets up SSL with Caddy
6. Allocates Elastic IP

Takes ~15 minutes total.

## What Gets Created

**EC2 Instance**:
- Type: t4g.small (2 vCPU, 2 GB RAM)
- OS: Ubuntu 24.04 ARM
- Cost: $13/month

**RDS Database**:
- Type: db.t4g.micro (1 vCPU, 1 GB RAM)
- Engine: PostgreSQL 14.13
- Cost: $0 (year 1), $15/month (year 2+)

**Networking**:
- Elastic IP (static)
- Security groups (SSH, HTTP, HTTPS)

**Software**:
- Docker + Docker Compose
- n8n (latest)
- Caddy (automatic SSL)

## After Deployment

### 1. Add DNS Record

```
Hostname: n8n.yourdomain.com
Type: A
Value: <elastic-ip-from-script>
TTL: 300
```

### 2. Wait 5-10 Minutes

For:
- Instance initialization
- Docker installation
- n8n startup
- DNS propagation
- SSL certificate

### 3. Check Progress

```bash
# SSH to instance
ssh -i ~/.ssh/your-key.pem ubuntu@<elastic-ip>

# Watch installation
tail -f /var/log/user-data.log

# Check n8n
docker ps
docker logs n8n
```

### 4. Access n8n

Visit: `https://n8n.yourdomain.com`

**Login**:
- Username: `admin`
- Password: (your n8n password)

## Management

### Check Status

```bash
ssh ubuntu@<elastic-ip>
docker ps
docker logs n8n -f
```

### Update n8n

```bash
ssh ubuntu@<elastic-ip>
cd ~/n8n
docker compose pull
docker compose up -d
```

### Backup Workflows

Automated daily backups run at 2 AM.

Manual backup:
```bash
ssh ubuntu@<elastic-ip>
docker exec n8n n8n export:workflow --all --output=/tmp/workflows.json
docker cp n8n:/tmp/workflows.json ./backup-$(date +%Y%m%d).json
```

### View Logs

```bash
# n8n logs
docker logs n8n -f

# Installation log
tail -f /var/log/user-data.log

# Caddy (SSL)
sudo journalctl -u caddy -f
```

## Cost

| Period | Monthly | Yearly |
|--------|---------|--------|
| Year 1 | $17 | $204 |
| Year 2+ | $32 | $384 |

**Breakdown**:
- EC2 t4g.small: $13/month
- RDS db.t4g.micro: $0 (year 1), $15/month (year 2+)
- Storage: $1/month
- Data transfer: ~$1/month

## Cleanup

To delete everything:

```bash
# Get instance ID and RDS identifier from deployment-info.txt

# Terminate EC2
aws ec2 terminate-instances --instance-ids <instance-id>

# Delete RDS (creates final snapshot)
aws rds delete-db-instance \
  --db-instance-identifier n8n-db \
  --final-db-snapshot-identifier n8n-final-snapshot

# Release Elastic IP
aws ec2 release-address --allocation-id <allocation-id>

# Delete security groups (after instances terminate)
aws ec2 delete-security-group --group-id <ec2-sg-id>
aws ec2 delete-security-group --group-id <rds-sg-id>
```

## Troubleshooting

### n8n not starting

```bash
ssh ubuntu@<elastic-ip>

# Check Docker
docker ps -a

# Check logs
docker logs n8n

# Restart
cd ~/n8n
docker compose restart
```

### SSL not working

```bash
# Check Caddy
sudo systemctl status caddy

# Check DNS
dig n8n.yourdomain.com +short

# Should return your Elastic IP
```

### Database connection failed

```bash
# Test from EC2
nc -zv <rds-endpoint> 5432

# Should show: Connection succeeded
```

## Alternative: Use Terraform

If you prefer infrastructure-as-code:

```bash
cd terraform/aws-n8n
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform apply
```

See: [terraform/aws-n8n/README.md](terraform/aws-n8n/README.md)

## Support

- n8n: https://community.n8n.io/
- AWS: https://aws.amazon.com/support/
- Script issues: Check deployment-info.txt for resource IDs
