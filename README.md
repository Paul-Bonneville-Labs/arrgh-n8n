# n8n Self-Hosted Setup

This repository provides configurations for running n8n both locally (for development) and on AWS (for production).

## Overview

n8n is a workflow automation tool that allows you to connect various services and automate tasks. This setup includes:
- Local development environment with Docker Compose
- Production deployment on AWS EC2 with AWS RDS PostgreSQL database
- Persistent storage for workflows and credentials
- Infrastructure as Code with Terraform

## Prerequisites

### Local Development
- Docker Desktop installed
- Docker Compose
- 4GB RAM available

### Production (AWS)
- AWS account with billing enabled
- AWS CLI installed and configured
- Terraform installed
- SSH key pair for EC2 access

## Local Development

### Quick Start

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd arrgh-n8n
   ```

2. **Start n8n locally**
   ```bash
   docker-compose up -d
   ```

3. **Access n8n**
   - URL: http://localhost:5678
   - Username: `admin`
   - Password: `password`

   **Security Warning**: These are development-only credentials. Change them before exposing to any network.

### Local Features
- PostgreSQL database included
- Data persists between restarts
- Suitable for development and testing
- No cloud costs

### Stopping Local Instance
```bash
docker-compose down
```

To remove all data:
```bash
docker-compose down -v
```

## Production Deployment (AWS)

### Cost Estimate
- **Monthly cost**: ~$29 (optimized setup)
- Includes: EC2 t4g.small instance, RDS db.t4g.micro PostgreSQL, backups
- Features: Caddy reverse proxy with auto-SSL, CloudWatch monitoring

### 🚀 Quick Deployment with Terraform

See the complete Terraform configuration in `terraform/aws-n8n/`

#### Prerequisites
1. **Set up AWS credentials**
   ```bash
   aws configure
   ```

2. **Create Terraform variables**
   ```bash
   cd .conductor/semarang/terraform/aws-n8n
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

#### Deploy Infrastructure
```bash
cd .conductor/semarang/terraform/aws-n8n

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply
```

### Production Features
- **EC2 Instance**: ARM-based t4g.small for cost efficiency
- **RDS Database**: PostgreSQL 14.13 with automated backups
- **SSL/TLS**: Automatic HTTPS via Caddy reverse proxy
- **Monitoring**: CloudWatch logs and metrics
- **Backups**: Daily automated backups to S3 (optional)
- **Security**: AWS Secrets Manager for credentials, IAM roles

### Custom Domain Setup
The domain is configured automatically via Caddy. Update DNS to point to the EC2 instance Elastic IP.

## Project Structure

```
arrgh-n8n/
├── docker-compose.yml                 # Local development setup
├── .env.example                       # Environment variables template
├── .conductor/
│   └── semarang/
│       └── terraform/
│           └── aws-n8n/               # AWS infrastructure as code
│               ├── main.tf            # Main Terraform configuration
│               ├── variables.tf       # Input variables
│               ├── outputs.tf         # Output values
│               ├── secrets.tf         # AWS Secrets Manager config
│               ├── user-data.sh       # EC2 bootstrap script
│               └── terraform.tfvars.example
├── docs/
│   ├── guides/                        # Setup guides
│   └── audit/                         # Infrastructure documentation
├── workflows/                         # n8n workflow backups
└── README.md                          # This file
```

## Infrastructure as Code

This deployment uses **Terraform** for infrastructure management:

- **Terraform modules** define all AWS resources (EC2, RDS, security groups, IAM roles)
- **Variable files** (`terraform.tfvars`) contain environment-specific values
- **State management** tracks infrastructure changes
- **User-data scripts** automate EC2 configuration with Docker Compose

This approach ensures:
✅ **No hardcoded credentials** in source control
✅ **Reproducible infrastructure** across environments
✅ **Secure secret management** via AWS Secrets Manager
✅ **Version-controlled infrastructure** changes

See the Terraform configuration in `.conductor/semarang/terraform/aws-n8n/` for details.

## Database Configuration

This setup supports flexible database options:
- **Local**: PostgreSQL container (development)
- **Production**: AWS RDS PostgreSQL 14.13
- **Connection**: Private VPC connection for security
- **Security**: IAM authentication support, Secrets Manager for credentials
- **Backups**: Automated daily backups with 7-day retention

## Security Considerations

1. **Credentials**: All stored in AWS Secrets Manager
2. **Network**: Private VPC connection to RDS database
3. **Access**: Basic auth with strong passwords, SSH key-based EC2 access
4. **Updates**: Latest n8n version via Docker
5. **Monitoring**: CloudWatch logs and metrics enabled
6. **Encryption**: RDS encryption at rest (configurable)

## Deployment Architecture

### Current Production Setup
- **Platform**: AWS (us-west-2)
- **Compute**: EC2 t4g.small instance (ARM-based)
- **Database**: RDS PostgreSQL 14.13 (db.t4g.micro)
- **Reverse Proxy**: Caddy (automatic HTTPS)
- **Domain**: n8n.paulbonneville.com

### Benefits
- **Cost efficiency**: ~$29/month total infrastructure cost
- **Performance**: Dedicated ARM-based instances
- **Monitoring**: CloudWatch integration
- **SSL/TLS**: Automatic certificate management via Caddy
- **Backups**: Automated RDS backups with point-in-time recovery

## Troubleshooting

### Local Issues
- **Port 5678 in use**: Change port in docker-compose.yml
- **Database connection failed**: Ensure PostgreSQL container is running

### AWS Issues
- **Service not starting**: Check logs with `ssh ubuntu@<ip> "docker logs n8n"`
- **Database connection failed**: Verify RDS credentials in AWS Secrets Manager
- **EC2 access issues**: Ensure SSH key is configured and security groups allow access

### Common Commands

```bash
# Local
docker-compose logs -f n8n           # View logs
docker-compose restart n8n           # Restart n8n

# AWS Production
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@<ec2-ip> "docker logs n8n"    # View logs
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@<ec2-ip> "docker restart n8n" # Restart n8n
aws rds describe-db-instances --region us-west-2                       # Check RDS status
```

## Cost Optimization

This setup is optimized for cost efficiency:

1. **ARM-based instances**: t4g instances offer better price/performance
2. **Right-sized resources**: t4g.small EC2, db.t4g.micro RDS
3. **Single-cloud architecture**: All resources in AWS (no cross-cloud egress)
4. **Automated backups**: 7-day RDS backup retention included

## Monitoring & Maintenance

### Performance Monitoring
```bash
# Check service health
curl https://n8n.paulbonneville.com/healthz

# Monitor resource usage via AWS CloudWatch
aws cloudwatch get-metric-statistics --namespace N8N --region us-west-2

# View EC2 metrics in AWS Console
```

### Updates
```bash
# SSH to EC2 instance
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@<ec2-ip>

# Pull latest n8n image and restart
cd /home/ubuntu/n8n
docker-compose pull
docker-compose up -d
```

## Next Steps

1. **Deploy**: Use Terraform in `.conductor/semarang/terraform/aws-n8n/` directory
2. **Custom Domain**: Update DNS A record to point to EC2 Elastic IP
3. **Import Workflows**: Use the n8n API or web interface
4. **Set up Monitoring**: Configure CloudWatch alarms
5. **Cost Monitoring**: Set up AWS billing alerts

## Resources

- [n8n Documentation](https://docs.n8n.io/)
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS RDS Documentation](https://docs.aws.amazon.com/rds/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues with:
- **n8n**: Visit [n8n Community](https://community.n8n.io/)
- **AWS**: Check [AWS Support](https://aws.amazon.com/support/)
- **Terraform**: See [Terraform Documentation](https://www.terraform.io/docs)

---

**Current Status**: ✅ Production ready on AWS (us-west-2)
**Last Updated**: October 2025
**Platform**: AWS EC2 + RDS