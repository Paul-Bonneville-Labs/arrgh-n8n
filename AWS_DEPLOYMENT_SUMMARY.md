# n8n AWS Deployment Summary

## ✅ Deployment Status: COMPLETE

n8n has been successfully deployed to AWS using EC2 and RDS PostgreSQL.

---

## 🌐 Access Information

### Current Access (HTTP Only)
- **URL**: http://44.253.69.204:5678
- **Username**: `admin`
- **Password**: See `.env` file (`N8N_PASSWORD`)

### After DNS Configuration (HTTPS with SSL)
- **URL**: https://n8n.paulbonneville.com
- **Username**: `admin`
- **Password**: See `.env` file (`N8N_PASSWORD`)

---

## 📋 Deployed Resources

### EC2 Instance
- **Instance ID**: `i-047f72d9608c24757`
- **Instance Type**: `t4g.small` (2 vCPU, 2 GB RAM, ARM64)
- **Elastic IP**: `44.253.69.204` (Allocation ID: `eipalloc-0afd0e41e94d90a23`)
- **Security Group**: `sg-0254c708af20d1403`
- **SSH Key**: `n8n-deploy-key` (stored at `~/.ssh/n8n-deploy-key.pem`)
- **Region**: `us-west-2`
- **AMI**: Ubuntu 24.04 LTS ARM64

### RDS PostgreSQL Database
- **Instance ID**: `n8n-db`
- **Instance Class**: `db.t4g.micro` (1 vCPU, 1 GB RAM, ARM64)
- **Engine**: PostgreSQL 14.13
- **Endpoint**: `n8n-db.cfi06m00c5cr.us-west-2.rds.amazonaws.com:5432`
- **Database Name**: `n8n`
- **Username**: `n8n`
- **Password**: See `.env` file (`DB_PASSWORD`)
- **Storage**: 20 GB gp3
- **Security Group**: `sg-06875316bdd268f28`
- **Backup Retention**: 7 days
- **Backup Window**: 12:41-13:11 UTC
- **Maintenance Window**: Wednesday 10:14-10:44 UTC

### Security Groups

#### EC2 Security Group (`sg-0254c708af20d1403`)
- **SSH (22)**: Your IP only (73.14.44.180/32)
- **HTTP (80)**: 0.0.0.0/0
- **HTTPS (443)**: 0.0.0.0/0
- **n8n (5678)**: 0.0.0.0/0 (temporary, for testing)

#### RDS Security Group (`sg-06875316bdd268f28`)
- **PostgreSQL (5432)**: EC2 security group only

---

## 🚀 Next Steps

### 1. Configure DNS (Required for HTTPS)

Add an A record to your DNS configuration:

```
Type: A
Name: n8n (or @, depending on your DNS provider)
Value: 44.253.69.204
TTL: 300 (or your default)
```

**Note**: DNS propagation can take 5-60 minutes.

### 2. Wait for SSL Certificate

After DNS is configured, Caddy will automatically obtain an SSL certificate from Let's Encrypt. This process takes 1-5 minutes after DNS propagates.

You can monitor the Caddy logs:
```bash
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204 'sudo journalctl -u caddy -f'
```

### 3. Test HTTPS Access

Once DNS propagates and the certificate is issued:
```bash
curl -I https://n8n.paulbonneville.com
```

### 4. Remove HTTP Testing Access (Optional)

After HTTPS is working, you can remove the temporary port 5678 rule from the EC2 security group:
```bash
aws ec2 revoke-security-group-ingress \
  --group-id sg-0254c708af20d1403 \
  --protocol tcp \
  --port 5678 \
  --cidr 0.0.0.0/0 \
  --region us-west-2
```

---

## 💰 Monthly Cost Estimate

### Year 1 (with Free Tier)
- **EC2 t4g.small**: ~$12/month (no free tier)
- **RDS db.t4g.micro**: FREE (750 hours/month free tier)
- **RDS storage (20 GB)**: FREE (20 GB/month free tier)
- **RDS backups**: FREE (backup storage = DB size within free tier)
- **Elastic IP**: FREE (when associated with running instance)
- **Data transfer**: ~$1-2/month (first 100 GB free)

**Total Year 1**: ~$13-14/month

### Year 2+ (after Free Tier expires)
- **EC2 t4g.small**: ~$12/month
- **RDS db.t4g.micro**: ~$11/month
- **RDS storage (20 GB gp3)**: ~$2.50/month
- **RDS backups (7 days)**: ~$2-3/month
- **Elastic IP**: FREE
- **Data transfer**: ~$1-2/month

**Total Year 2+**: ~$28-30/month

---

## 🔧 Management Commands

### SSH Access
```bash
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204
```

### View n8n Logs
```bash
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204 'docker logs n8n -f'
```

### Restart n8n
```bash
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204 'docker restart n8n'
```

### View Caddy Logs
```bash
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204 'sudo journalctl -u caddy -f'
```

### Check EC2 Instance
```bash
aws ec2 describe-instances --instance-ids i-047f72d9608c24757 --region us-west-2
```

### Check RDS Database
```bash
aws rds describe-db-instances --db-instance-identifier n8n-db --region us-west-2
```

### Connect to PostgreSQL
```bash
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204
# Then on EC2:
# Password is stored in ~/.pgpass on the EC2 instance
psql -h n8n-db.cfi06m00c5cr.us-west-2.rds.amazonaws.com -U n8n -d n8n
```

---

## 🔐 Security Notes

1. **SSH Key**: The private key is stored at `~/.ssh/n8n-deploy-key.pem` - keep this secure
2. **Passwords**: All credentials are stored in `.env` file (not committed to git)
3. **Encryption Key**: Stored in `.env` file (`N8N_ENCRYPTION_KEY`) - required for n8n data encryption
4. **Database**: Only accessible from EC2 instance (not publicly accessible)
5. **n8n**: Protected with basic authentication
6. **SSL/TLS**: Automatic HTTPS via Caddy and Let's Encrypt

**Important**: The `.env` file contains sensitive credentials. Never commit it to version control.

---

## 📝 Configuration Files

All configuration is stored on the EC2 instance:
- **docker-compose.yml**: `/home/ubuntu/n8n/docker-compose.yml`
- **Caddyfile**: `/etc/caddy/Caddyfile`
- **n8n data**: Docker volume `n8n_data`
- **PostgreSQL credentials**: `~/.pgpass` on EC2

---

## ⚠️ Troubleshooting

### n8n not accessible
```bash
# Check if n8n is running
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204 'docker ps'

# Check n8n logs
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204 'docker logs n8n'

# Restart n8n
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204 'docker restart n8n'
```

### Database connection issues
```bash
# Test database connectivity from EC2
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204
# Password is stored in ~/.pgpass on the EC2 instance
psql -h n8n-db.cfi06m00c5cr.us-west-2.rds.amazonaws.com -U n8n -d n8n -c '\l'
```

### HTTPS not working
```bash
# Check DNS resolution
dig n8n.paulbonneville.com +short
# Should return: 44.253.69.204

# Check Caddy status
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204 'sudo systemctl status caddy'

# Check Caddy logs
ssh -i ~/.ssh/n8n-deploy-key.pem ubuntu@44.253.69.204 'sudo journalctl -u caddy -n 50'
```

---

## 📚 Additional Resources

- **n8n Documentation**: https://docs.n8n.io/
- **AWS EC2 Documentation**: https://docs.aws.amazon.com/ec2/
- **AWS RDS Documentation**: https://docs.aws.amazon.com/rds/
- **Caddy Documentation**: https://caddyserver.com/docs/

---

**Deployment Date**: October 25, 2025
**Deployed By**: AWS CLI
**Region**: us-west-2 (Oregon)
