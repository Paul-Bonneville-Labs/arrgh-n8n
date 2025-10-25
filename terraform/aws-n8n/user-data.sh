#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting n8n installation at $(date)"

# Update system
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install AWS CLI and jq for secrets retrieval
echo "Installing AWS CLI and jq..."
apt-get install -y awscli jq

# Fetch secrets from AWS Secrets Manager
echo "Retrieving secrets from AWS Secrets Manager..."
N8N_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${n8n_password_secret_arn} --region ${aws_region} --query SecretString --output text)
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${db_password_secret_arn} --region ${aws_region} --query SecretString --output text)
ENCRYPTION_KEY=$(aws secretsmanager get-secret-value --secret-id ${encryption_key_secret_arn} --region ${aws_region} --query SecretString --output text)

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Install Docker Compose
apt-get install -y docker-compose-plugin

# Install Caddy for SSL
echo "Installing Caddy..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

# Configure Caddy
echo "Configuring Caddy..."
cat > /etc/caddy/Caddyfile <<'EOF'
${n8n_domain} {
    reverse_proxy localhost:5678
    encode gzip
}
EOF

# Enable and start Caddy
systemctl enable caddy
systemctl start caddy

# Create n8n directory
mkdir -p /home/ubuntu/n8n
cd /home/ubuntu/n8n

# Create docker-compose.yml
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      # Basic Auth
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD

      # Host Configuration
      - N8N_HOST=${n8n_domain}
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - WEBHOOK_URL=https://${n8n_domain}/

      # Database Configuration
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${db_host}
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${db_name}
      - DB_POSTGRESDB_USER=${db_user}
      - DB_POSTGRESDB_PASSWORD=$DB_PASSWORD

      # Encryption
      - N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY

      # Execution
      - EXECUTIONS_MODE=regular
      - N8N_METRICS=true

      # Timezone
      - GENERIC_TIMEZONE=America/New_York

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
    driver: local
EOF

# Set ownership
chown -R ubuntu:ubuntu /home/ubuntu/n8n

# Wait for RDS to be ready
echo "Waiting for RDS to be available..."
DB_HOST="${db_host%%:*}"
MAX_TRIES=30
TRIES=0
while ! nc -z $DB_HOST 5432; do
  TRIES=$((TRIES + 1))
  if [ $TRIES -ge $MAX_TRIES ]; then
    echo "ERROR: Database not available after $MAX_TRIES attempts"
    exit 1
  fi
  echo "Waiting for database... attempt $TRIES/$MAX_TRIES"
  sleep 10
done

echo "Database is available!"

# Start n8n
echo "Starting n8n..."
cd /home/ubuntu/n8n
docker compose up -d

# Install CloudWatch agent (optional)
echo "Installing CloudWatch agent..."
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'EOF'
{
  "metrics": {
    "namespace": "N8N",
    "metrics_collected": {
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MemoryUtilization",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DiskUtilization",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/aws/ec2/n8n",
            "log_stream_name": "{instance_id}/user-data"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Create backup script
cat > /home/ubuntu/backup-n8n.sh <<'BACKUPEOF'
#!/bin/bash
# Daily n8n workflow backup script

BACKUP_DIR="/home/ubuntu/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/n8n-workflows-$TIMESTAMP.json"

mkdir -p $BACKUP_DIR

# Export workflows using n8n CLI
docker exec n8n n8n export:workflow --all --output=/tmp/workflows.json 2>/dev/null || true

# Copy from container
docker cp n8n:/tmp/workflows.json $BACKUP_FILE 2>/dev/null || true

# Upload to S3 if bucket exists
if command -v aws &> /dev/null; then
  S3_BUCKET=$(aws s3 ls | grep n8n-backups | awk '{print $3}' | head -1)
  if [ ! -z "$S3_BUCKET" ]; then
    aws s3 cp $BACKUP_FILE s3://$S3_BUCKET/workflows/
    echo "Backup uploaded to S3: $S3_BUCKET"
  fi
fi

# Keep only last 7 days of local backups
find $BACKUP_DIR -name "n8n-workflows-*.json" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
BACKUPEOF

chmod +x /home/ubuntu/backup-n8n.sh
chown ubuntu:ubuntu /home/ubuntu/backup-n8n.sh

# Add cron job for daily backups at 2 AM
(crontab -u ubuntu -l 2>/dev/null; echo "0 2 * * * /home/ubuntu/backup-n8n.sh >> /home/ubuntu/backup.log 2>&1") | crontab -u ubuntu -

# Create update script
cat > /home/ubuntu/update-n8n.sh <<'UPDATEEOF'
#!/bin/bash
# Update n8n to latest version

cd /home/ubuntu/n8n

echo "Pulling latest n8n image..."
docker compose pull

echo "Restarting n8n..."
docker compose up -d

echo "Cleaning up old images..."
docker image prune -f

echo "n8n updated successfully!"
docker ps | grep n8n
UPDATEEOF

chmod +x /home/ubuntu/update-n8n.sh
chown ubuntu:ubuntu /home/ubuntu/update-n8n.sh

echo "n8n installation completed successfully at $(date)"
echo "n8n should be accessible at https://${n8n_domain} once DNS propagates"
echo "Check status with: docker ps"
echo "View logs with: docker logs n8n"
