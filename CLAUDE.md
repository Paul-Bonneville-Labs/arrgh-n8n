# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is an n8n self-hosting setup supporting two deployment environments:
- **Local development**: Docker Compose with PostgreSQL
- **Production (AWS)**: AWS EC2 with RDS PostgreSQL (~$29/month optimized hosting)

The project uses AWS as the production platform for its cost efficiency, dedicated resources, and Infrastructure as Code management via Terraform.

## Architecture

### Dual Environment Design
- **Local**: `docker-compose.yml` provides isolated development with bundled PostgreSQL
- **Production (AWS)**: Terraform configuration in `terraform/aws-n8n/` deploys EC2 + RDS infrastructure

### Configuration Strategy
- Local uses hardcoded credentials in docker-compose.yml
- AWS production uses Terraform for infrastructure management
- EC2 instance configured via user-data script with Docker Compose
- Credentials managed via AWS Secrets Manager
- Both environments use the same n8n image (`n8nio/n8n:latest`)

### Database Architecture
- **Local**: PostgreSQL 14 container with persistent volumes
- **Production (AWS)**: RDS PostgreSQL 14.13 (db.t4g.micro) with private VPC connection
- Infrastructure defined in Terraform, deployed via `terraform apply`

## Common Commands

### Local Development
```bash
# Start n8n with database
docker-compose up -d

# View logs
docker-compose logs -f n8n

# Stop and preserve data
docker-compose down

# Stop and remove all data
docker-compose down -v

# Restart n8n service only
docker-compose restart n8n
```

### AWS Production
```bash
# Deploy infrastructure with Terraform
cd terraform/aws-n8n
terraform init
terraform plan
terraform apply

# SSH to EC2 instance
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@<ec2-ip>

# View n8n logs
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@<ec2-ip> "docker logs n8n"

# Restart n8n
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@<ec2-ip> "docker restart n8n"

# Check RDS status
aws rds describe-db-instances --region us-west-2 --db-instance-identifier n8n-db
```

## Key Configuration Points

### AWS Production Configuration
AWS deployment configured for cost optimization (~$29/month):
- **Compute**: EC2 t4g.small instance (ARM-based, 2 vCPU, 2GB RAM)
- **Database**: RDS PostgreSQL 14.13 (db.t4g.micro)
- **Region**: us-west-2 (Oregon)
- **Reverse Proxy**: Caddy for automatic HTTPS
- **Secrets**: AWS Secrets Manager for database credentials
- **Custom domain**: n8n.paulbonneville.com (DNS A record to EC2 Elastic IP)
- **SSL**: Automatically provisioned by Caddy

## Environment Access

### Local Access
- URL: http://localhost:5678
- Username: `admin`
- Password: `password`

### Production Access (AWS)
- URL: https://n8n.paulbonneville.com
- Username: `admin`
- Password: Configured in `/home/ubuntu/n8n/docker-compose.yml` on EC2 instance
- SSH Access: `ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204`

## Troubleshooting Context

### Common Local Issues
- Port 5678 conflicts: Modify `docker-compose.yml` ports section
- Database connectivity: Ensure PostgreSQL container is healthy

### Common AWS Production Issues
- n8n not accessible: Check EC2 instance status and security group rules
- Database connection errors: Verify RDS connectivity and credentials in docker-compose.yml
- SSH access issues: Ensure using correct key (`~/.ssh/n8n-deploy-key.pem`) and security groups allow port 22
- SSL certificate issues: Check Caddy logs with `ssh ubuntu@<ip> "sudo journalctl -u caddy"`

## Cost Considerations

**AWS deployment** cost-optimized hosting solution:
- Estimated $29/month for production workload
  - EC2 t4g.small: ~$13/month
  - RDS db.t4g.micro: ~$16/month
- Single-cloud architecture (no cross-cloud egress charges)
- ARM-based instances for better price/performance
- 7-day automated RDS backups included
- CloudWatch monitoring and logging included

## GitHub Actions & PR Standards

This repository uses shared GitHub Actions workflows from `arrgh-hub` for PR validation and automation:

### Workflow Architecture
- **Shared workflows**: Hosted in `pbonneville/arrgh-hub/.github/workflows/`
- **Local wrappers**: Minimal `.github/workflows/` files that call the shared ones
- **PR template**: Standardized `.github/pull_request_template.md`

### Features
- **PR Validation**: Size limits (200 lines for infra changes), conventional commits
- **Auto-labeling**: Based on PR type (feat, fix, docs, etc.)
- **Auto-merge**: Enabled for docs and chore PRs only
- **Release notes**: Automatic generation for features/fixes
- **Security scanning**: Detects security-related file changes

See `docs/github-actions-shared-workflows.md` for complete documentation.

## Inbound Email Processing

AWS SES inbound email processing is configured to forward emails to n8n for automated processing:

### Quick Deployment
```bash
# Deploy complete inbound email infrastructure
./deploy-inbound-email.sh
```

### Manual Setup
1. **Deploy AWS Infrastructure**: `cd terraform && terraform apply`
2. **Configure DNS**: Add MX record (see `docs/dns-mx-setup.md`)
3. **Import n8n Workflow**: Upload `workflows/inbound-email-processor.json`
4. **Test**: Send email to your domain

### Architecture
- **Email Reception**: AWS SES receives emails via MX record
- **Storage**: Emails stored in S3 bucket with 30-day lifecycle
- **Notification**: SNS triggers n8n webhook in real-time
- **Processing**: n8n downloads, parses, and processes email content
- **Custom Logic**: Add business logic in the "Process Email Logic" node

### Cost Impact
- SES: $0.10 per 1,000 emails received
- S3: Minimal storage costs (emails auto-deleted after 30 days)
- SNS: $0.50 per 1 million notifications

See `docs/inbound-email-deployment.md` for complete setup instructions.