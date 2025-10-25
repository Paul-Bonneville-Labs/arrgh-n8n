# AWS n8n Hosting - Cost Optimization Plan (REVISED)

## Executive Summary

After validating n8n's actual resource requirements, **EC2 + RDS is the most cost-effective AWS solution** at ~$17/month (66% savings vs current $50/month GCP setup).

## Critical Finding: Lightsail is Insufficient

Initial analysis recommended Lightsail, but n8n's actual requirements make this unviable:

**n8n Production Requirements**:
- Minimum: 2 vCPU, 4 GB RAM (n8n + PostgreSQL combined)
- Recommended: 4 vCPU, 8 GB RAM

**Lightsail Container Limitation**:
- Cheap tiers ($7-20/mo): 0.25-0.5 vCPU, 512MB-2GB ❌ Insufficient
- Viable tier: Medium ($40/mo) - 1 vCPU, 4 GB ✅ But not cost-effective
- **Lightsail Medium at $40/month only saves $10/month vs current GCP**

## Current GCP Setup (Baseline)

**Google Cloud Run Deployment**:
- Service: Cloud Run (0.5 CPU, 512Mi RAM) - **n8n only**
- Database: Cloud SQL PostgreSQL (separate, shared instance)
- Cost: ~$50/month
- Features: Auto-scaling (0-10 instances), managed SSL, monitoring

**Why GCP config is misleading**: Cloud Run shows 512 MB RAM, but that's just the n8n container. The database runs separately on Cloud SQL with its own resources.

---

## Recommended Solution: EC2 t4g.small + RDS PostgreSQL

### Cost: $17/month (year 1), $32/month (year 2+)

**Components**:
- **EC2 t4g.small** (ARM): $13/month
  - 2 vCPU, 2 GB RAM dedicated for n8n
- **RDS PostgreSQL db.t4g.micro**: $0-15/month
  - 1 vCPU, 1 GB RAM dedicated for database
  - FREE first 12 months
- **Storage & IP**: $1/month

**Savings**:
- Year 1: $50 → $17/month (66% reduction, $396/year saved)
- Year 2+: $50 → $32/month (36% reduction, $216/year saved)

### Why This Wins

1. **Best cost-to-performance ratio**
2. **More resources** than current GCP (2 vCPU vs 0.5 vCPU, 3 GB vs varies)
3. **Matches GCP pattern** (separate compute and database)
4. **Production-ready** (meets n8n requirements)
5. **Free tier benefits** (first year especially cheap)

### Architecture

```
┌─────────────────────────────────────────┐
│ AWS Account                             │
│                                         │
│  ┌──────────────────┐                  │
│  │ EC2 t4g.small    │                  │
│  │ 2 vCPU, 2 GB RAM │                  │
│  │                  │                  │
│  │ - Ubuntu 24.04   │                  │
│  │ - Docker         │                  │
│  │ - n8n container  │                  │
│  │ - Caddy (SSL)    │                  │
│  └────────┬─────────┘                  │
│           │                             │
│           │ PostgreSQL connection       │
│           ↓                             │
│  ┌──────────────────┐                  │
│  │ RDS PostgreSQL   │                  │
│  │ db.t4g.micro     │                  │
│  │ 1 vCPU, 1 GB RAM │                  │
│  │ 20 GB SSD        │                  │
│  └──────────────────┘                  │
│                                         │
│  Elastic IP → Custom Domain            │
│  Caddy → Auto SSL (Let's Encrypt)      │
└─────────────────────────────────────────┘
```

---

## Alternative Options (For Comparison)

### Option 2: EC2 t4g.medium (All-in-One)
**Cost: $29/month (constant)**

- Single EC2 instance runs both n8n and PostgreSQL
- 2 vCPU, 4 GB RAM
- Simpler deployment, no network latency
- Manual database backups required
- Can't scale compute/database independently

### Option 3: ECS Fargate + RDS
**Cost: $32/month (year 1), $47/month (year 2+)**

- Managed containers (no server management)
- Higher long-term cost
- Complex setup
- Only saves $3/month vs current GCP after year 1

### Option 4: Lightsail Medium
**Cost: $55/month**

- More expensive than current GCP ❌
- Not recommended

---

## Quick Start Deployment

### 1. Launch EC2 Instance

```bash
# Create and configure security group
aws ec2 create-security-group \
  --group-name n8n-sg \
  --description "Security group for n8n"

# Allow SSH, HTTP, HTTPS
aws ec2 authorize-security-group-ingress --group-name n8n-sg \
  --ip-permissions \
  IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0}]' \
  IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0}]' \
  IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=0.0.0.0/0}]'

# Launch instance
aws ec2 run-instances \
  --image-id ami-0c2b0d3fb02824d92 \
  --instance-type t4g.small \
  --key-name your-key-name \
  --security-groups n8n-sg \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=n8n-server}]'
```

### 2. Create RDS Database

```bash
# Create RDS security group
aws ec2 create-security-group \
  --group-name rds-n8n-sg \
  --description "RDS for n8n"

# Allow PostgreSQL from EC2
aws ec2 authorize-security-group-ingress \
  --group-name rds-n8n-sg \
  --protocol tcp --port 5432 \
  --source-group n8n-sg

# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier n8n-db \
  --db-instance-class db.t4g.micro \
  --engine postgres \
  --engine-version 14.13 \
  --master-username n8n \
  --master-user-password STRONG_PASSWORD_HERE \
  --allocated-storage 20 \
  --vpc-security-group-ids sg-xxxxx \
  --backup-retention-period 7 \
  --storage-encrypted
```

### 3. Install Docker & Deploy n8n

```bash
# SSH into EC2
ssh -i your-key.pem ubuntu@<instance-ip>

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker ubuntu

# Create docker-compose.yml
mkdir n8n && cd n8n
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - N8N_HOST=${N8N_DOMAIN}
      - N8N_PROTOCOL=https
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${DB_HOST}
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
    volumes:
      - n8n_data:/home/node/.n8n
volumes:
  n8n_data:
EOF

# Create .env file
cat > .env << EOF
N8N_PASSWORD=your-password
N8N_DOMAIN=n8n.yourdomain.com
DB_HOST=n8n-db.xxxxx.rds.amazonaws.com
DB_PASSWORD=your-db-password
EOF

# Start n8n
docker compose up -d
```

### 4. Configure SSL (Caddy)

```bash
# Install Caddy
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install caddy

# Configure Caddy
sudo tee /etc/caddy/Caddyfile << EOF
n8n.yourdomain.com {
    reverse_proxy localhost:5678
}
EOF

# Start Caddy
sudo systemctl enable --now caddy
```

### 5. Point DNS to Elastic IP

Update your DNS A record to point to the EC2 Elastic IP.

---

## Terraform Configuration

See full Terraform code in the complete plan above (variables.tf, main.tf with EC2, RDS, security groups, etc.)

---

## Migration from GCP

1. **Export workflows** from current n8n instance
2. **Export database** from Cloud SQL
3. **Deploy AWS infrastructure**
4. **Import database** to RDS
5. **Import workflows** to new n8n
6. **Test thoroughly**
7. **Update DNS** to AWS
8. **Decommission GCP** after 48 hours

---

## Cost Breakdown

### Year 1 (with Free Tier)
- EC2 t4g.small: $13/month
- RDS db.t4g.micro: $0/month (free tier)
- EBS storage: $1/month
- Elastic IP: $0
- Data transfer: ~$1/month
- **Total: ~$15-17/month**

### Year 2+ (after Free Tier)
- EC2 t4g.small: $13/month
- RDS db.t4g.micro: $15/month
- EBS storage: $1/month
- Elastic IP: $0
- Data transfer: ~$1/month
- **Total: ~$30-32/month**

### Comparison
| Platform | Cost | Savings |
|----------|------|---------|
| Current GCP | $50/mo | - |
| AWS Year 1 | $17/mo | $33/mo (66%) |
| AWS Year 2+ | $32/mo | $18/mo (36%) |

---

## Next Steps

1. ✅ Approve EC2 + RDS approach
2. 📋 Set up AWS account (if needed)
3. 🔑 Generate SSH key pair
4. 🌐 Decide on domain name
5. 💾 Export n8n data from GCP
6. 🚀 Deploy using Terraform or manual steps
7. 🧪 Test all workflows
8. 🔄 Update DNS
9. 💰 Save $216-396/year

Ready to proceed with deployment?
