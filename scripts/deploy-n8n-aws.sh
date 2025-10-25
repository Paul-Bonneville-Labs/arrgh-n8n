#!/bin/bash
#
# deploy-n8n-aws.sh
# Deploy n8n on AWS using AWS CLI (no Terraform required)
#
# Usage: ./scripts/deploy-n8n-aws.sh [--env-file path/to/.env]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== n8n AWS Deployment ===${NC}"
echo "This script will deploy n8n on AWS using AWS CLI"
echo ""

# Parse arguments
ENV_FILE=".env"
while [[ $# -gt 0 ]]; do
    case $1 in
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI not installed${NC}"
    echo "Install: https://aws.amazon.com/cli/"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}ERROR: jq not installed${NC}"
    echo "Install: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}ERROR: AWS credentials not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites met"
echo ""

# Load environment from .env file if it exists
if [ -f "$ENV_FILE" ]; then
    echo -e "${GREEN}Loading configuration from $ENV_FILE${NC}"
    set -a
    source "$ENV_FILE"
    set +a

    AWS_REGION=${AWS_REGION:-us-east-1}
    PROJECT_NAME=${PROJECT_NAME:-n8n}
    EC2_TYPE=${EC2_INSTANCE_TYPE:-t4g.small}
    RDS_TYPE=${RDS_INSTANCE_CLASS:-db.t4g.micro}
    SSH_KEY_NAME=${SSH_KEY_NAME}
    N8N_DOMAIN=${N8N_DOMAIN}
    N8N_PASSWORD=${N8N_PASSWORD}
    DB_PASSWORD=${DB_PASSWORD}
    ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

    echo -e "${BLUE}Using configuration from .env:${NC}"
    echo "  Region: $AWS_REGION"
    echo "  Project: $PROJECT_NAME"
    echo "  Domain: $N8N_DOMAIN"
    echo ""
else
    echo -e "${YELLOW}No .env file found. Using interactive mode.${NC}"
    echo ""

    # Configuration
    echo -e "${YELLOW}=== Configuration ===${NC}"
    echo ""

    read -p "AWS Region [us-east-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}

    read -p "Project name [n8n]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-n8n}

    read -p "EC2 instance type [t4g.small]: " EC2_TYPE
    EC2_TYPE=${EC2_TYPE:-t4g.small}

    read -p "RDS instance type [db.t4g.micro]: " RDS_TYPE
    RDS_TYPE=${RDS_TYPE:-db.t4g.micro}

    read -p "SSH key pair name (must exist in AWS): " SSH_KEY_NAME
    if [ -z "$SSH_KEY_NAME" ]; then
        echo -e "${RED}ERROR: SSH key name required${NC}"
        exit 1
    fi

    read -p "n8n domain (e.g., n8n.yourdomain.com): " N8N_DOMAIN
    if [ -z "$N8N_DOMAIN" ]; then
        echo -e "${RED}ERROR: Domain required for SSL${NC}"
        exit 1
    fi

    read -p "n8n admin password: " -s N8N_PASSWORD
    echo ""
    if [ ${#N8N_PASSWORD} -lt 8 ]; then
        echo -e "${RED}ERROR: Password must be at least 8 characters${NC}"
        exit 1
    fi

    read -p "Database password: " -s DB_PASSWORD
    echo ""
    if [ ${#DB_PASSWORD} -lt 8 ]; then
        echo -e "${RED}ERROR: Database password must be at least 8 characters${NC}"
        exit 1
    fi

    ENCRYPTION_KEY=$(openssl rand -hex 32)
fi

# Validate required variables
if [ -z "$SSH_KEY_NAME" ] || [ -z "$N8N_DOMAIN" ] || [ -z "$N8N_PASSWORD" ] || [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}ERROR: Missing required configuration${NC}"
    echo "Required: SSH_KEY_NAME, N8N_DOMAIN, N8N_PASSWORD, DB_PASSWORD"
    exit 1
fi

read -p "Your IP address for SSH (leave empty for auto-detect): " SSH_IP
if [ -z "$SSH_IP" ]; then
    SSH_IP=$(curl -s ifconfig.me)
    echo "Detected IP: $SSH_IP"
fi

echo ""
echo -e "${BLUE}Configuration Summary:${NC}"
echo "  Region: $AWS_REGION"
echo "  Project: $PROJECT_NAME"
echo "  EC2 Type: $EC2_TYPE"
echo "  RDS Type: $RDS_TYPE"
echo "  Domain: $N8N_DOMAIN"
echo "  SSH IP: $SSH_IP/32"
echo ""

read -p "Proceed with deployment? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo -e "${YELLOW}=== Starting Deployment ===${NC}"
echo ""

# Get latest Ubuntu 24.04 ARM AMI
echo "Finding latest Ubuntu 24.04 ARM AMI..."
AMI_ID=$(aws ec2 describe-images \
    --region $AWS_REGION \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-arm64-server-*" \
              "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

echo -e "${GREEN}✓${NC} AMI: $AMI_ID"

# Create security group for EC2
echo "Creating EC2 security group..."
EC2_SG_ID=$(aws ec2 create-security-group \
    --region $AWS_REGION \
    --group-name "${PROJECT_NAME}-ec2-sg" \
    --description "Security group for n8n EC2 instance" \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
        --region $AWS_REGION \
        --group-names "${PROJECT_NAME}-ec2-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

echo -e "${GREEN}✓${NC} EC2 Security Group: $EC2_SG_ID"

# Add security group rules
echo "Configuring EC2 security group..."
aws ec2 authorize-security-group-ingress \
    --region $AWS_REGION \
    --group-id $EC2_SG_ID \
    --ip-permissions \
        IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges="[{CidrIp=${SSH_IP}/32,Description='SSH'}]" \
        IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges="[{CidrIp=0.0.0.0/0,Description='HTTP'}]" \
        IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges="[{CidrIp=0.0.0.0/0,Description='HTTPS'}]" \
    2>/dev/null || echo "Security group rules already exist"

# Create security group for RDS
echo "Creating RDS security group..."
RDS_SG_ID=$(aws ec2 create-security-group \
    --region $AWS_REGION \
    --group-name "${PROJECT_NAME}-rds-sg" \
    --description "Security group for n8n RDS database" \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
        --region $AWS_REGION \
        --group-names "${PROJECT_NAME}-rds-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

echo -e "${GREEN}✓${NC} RDS Security Group: $RDS_SG_ID"

# Add RDS security group rule
aws ec2 authorize-security-group-ingress \
    --region $AWS_REGION \
    --group-id $RDS_SG_ID \
    --protocol tcp \
    --port 5432 \
    --source-group $EC2_SG_ID \
    2>/dev/null || echo "RDS security group rule already exists"

# Create RDS instance
echo "Creating RDS PostgreSQL instance (this takes 5-10 minutes)..."
RDS_ENDPOINT=$(aws rds describe-db-instances \
    --region $AWS_REGION \
    --db-instance-identifier "${PROJECT_NAME}-db" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text 2>/dev/null || echo "")

if [ -z "$RDS_ENDPOINT" ] || [ "$RDS_ENDPOINT" = "None" ]; then
    aws rds create-db-instance \
        --region $AWS_REGION \
        --db-instance-identifier "${PROJECT_NAME}-db" \
        --db-instance-class $RDS_TYPE \
        --engine postgres \
        --engine-version 14.13 \
        --master-username n8n \
        --master-user-password "$DB_PASSWORD" \
        --allocated-storage 20 \
        --max-allocated-storage 100 \
        --storage-type gp3 \
        --storage-encrypted \
        --vpc-security-group-ids $RDS_SG_ID \
        --backup-retention-period 7 \
        --preferred-backup-window "03:00-04:00" \
        --no-publicly-accessible \
        --tags "Key=Name,Value=${PROJECT_NAME}-database" \
        > /dev/null

    echo "Waiting for RDS to become available (this takes 5-10 minutes)..."
    aws rds wait db-instance-available \
        --region $AWS_REGION \
        --db-instance-identifier "${PROJECT_NAME}-db"

    RDS_ENDPOINT=$(aws rds describe-db-instances \
        --region $AWS_REGION \
        --db-instance-identifier "${PROJECT_NAME}-db" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
fi

echo -e "${GREEN}✓${NC} RDS Endpoint: $RDS_ENDPOINT"

# Create user data script
cat > /tmp/n8n-user-data.sh << USERDATA
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting n8n installation at \$(date)"

# Update system
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Install Docker Compose
apt-get install -y docker-compose-plugin

# Install Caddy
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

# Configure Caddy
cat > /etc/caddy/Caddyfile << 'EOF'
${N8N_DOMAIN} {
    reverse_proxy localhost:5678
    encode gzip
}
EOF

systemctl enable caddy
systemctl start caddy

# Create n8n directory
mkdir -p /home/ubuntu/n8n
cd /home/ubuntu/n8n

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - N8N_HOST=${N8N_DOMAIN}
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - WEBHOOK_URL=https://${N8N_DOMAIN}/
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${RDS_ENDPOINT}
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - EXECUTIONS_MODE=regular
      - N8N_METRICS=true
    volumes:
      - n8n_data:/home/node/.n8n
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:5678/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s
volumes:
  n8n_data:
EOF

chown -R ubuntu:ubuntu /home/ubuntu/n8n

# Wait for RDS
echo "Waiting for database..."
DB_HOST=\$(echo "${RDS_ENDPOINT}" | cut -d: -f1)
MAX_TRIES=30
TRIES=0
while ! nc -z \$DB_HOST 5432; do
  TRIES=\$((TRIES + 1))
  if [ \$TRIES -ge \$MAX_TRIES ]; then
    echo "ERROR: Database not available"
    exit 1
  fi
  echo "Waiting... attempt \$TRIES/\$MAX_TRIES"
  sleep 10
done

echo "Starting n8n..."
cd /home/ubuntu/n8n
docker compose up -d

echo "n8n installation completed at \$(date)"
USERDATA

# Launch EC2 instance
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --region $AWS_REGION \
    --image-id $AMI_ID \
    --instance-type $EC2_TYPE \
    --key-name $SSH_KEY_NAME \
    --security-group-ids $EC2_SG_ID \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=8,VolumeType=gp3,Encrypted=true}" \
    --user-data file:///tmp/n8n-user-data.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-server}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✓${NC} Instance ID: $INSTANCE_ID"

# Wait for instance to be running
echo "Waiting for instance to start..."
aws ec2 wait instance-running \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID

# Allocate and associate Elastic IP
echo "Allocating Elastic IP..."
ALLOCATION_ID=$(aws ec2 allocate-address \
    --region $AWS_REGION \
    --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${PROJECT_NAME}-eip}]" \
    --query 'AllocationId' \
    --output text)

PUBLIC_IP=$(aws ec2 describe-addresses \
    --region $AWS_REGION \
    --allocation-ids $ALLOCATION_ID \
    --query 'Addresses[0].PublicIp' \
    --output text)

aws ec2 associate-address \
    --region $AWS_REGION \
    --instance-id $INSTANCE_ID \
    --allocation-id $ALLOCATION_ID \
    > /dev/null

echo -e "${GREEN}✓${NC} Elastic IP: $PUBLIC_IP"

# Clean up
rm /tmp/n8n-user-data.sh

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo -e "${BLUE}Instance Information:${NC}"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP: $PUBLIC_IP"
echo "  RDS Endpoint: $RDS_ENDPOINT"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Add DNS A record:"
echo "   Hostname: $N8N_DOMAIN"
echo "   Type: A"
echo "   Value: $PUBLIC_IP"
echo "   TTL: 300"
echo ""
echo "2. Wait 5-10 minutes for:"
echo "   - Instance initialization"
echo "   - Docker and n8n installation"
echo "   - DNS propagation"
echo "   - SSL certificate generation"
echo ""
echo "3. Check installation progress:"
echo "   ssh -i ~/.ssh/${SSH_KEY_NAME}.pem ubuntu@${PUBLIC_IP}"
echo "   tail -f /var/log/user-data.log"
echo ""
echo "4. Access n8n:"
echo "   https://${N8N_DOMAIN}"
echo "   Username: admin"
echo "   Password: <your-n8n-password>"
echo ""
echo -e "${BLUE}Management Commands:${NC}"
echo "  SSH: ssh -i ~/.ssh/${SSH_KEY_NAME}.pem ubuntu@${PUBLIC_IP}"
echo "  Status: docker ps"
echo "  Logs: docker logs n8n"
echo ""
echo -e "${BLUE}Monthly Cost Estimate:${NC}"
echo "  Year 1: ~\$17/month (RDS free tier)"
echo "  Year 2+: ~\$32/month"
echo ""
echo "Deployment information saved to: deployment-info.txt"

# Save deployment info
cat > deployment-info.txt << INFO
n8n AWS Deployment
==================

Deployed: $(date)

Resources:
  Instance ID: $INSTANCE_ID
  Public IP: $PUBLIC_IP
  RDS Endpoint: $RDS_ENDPOINT
  Security Groups: $EC2_SG_ID, $RDS_SG_ID

Access:
  URL: https://${N8N_DOMAIN}
  SSH: ssh -i ~/.ssh/${SSH_KEY_NAME}.pem ubuntu@${PUBLIC_IP}

Credentials:
  All credentials stored in .env file
  (n8n password, database password, and encryption key)

AWS Region: $AWS_REGION
SSH Key: $SSH_KEY_NAME
INFO

echo -e "${GREEN}✓${NC} Deployment complete!"
