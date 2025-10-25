#!/bin/bash
#
# migrate-gcp-to-aws.sh
# Migrate n8n from Google Cloud Run to AWS EC2
#
# Usage: ./scripts/migrate-gcp-to-aws.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GCP_PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project-id}"
GCP_REGION="${GCP_REGION:-us-central1}"
GCP_SERVICE_NAME="n8n-app"
BACKUP_DIR="./migration-backup-$(date +%Y%m%d-%H%M%S)"

echo -e "${GREEN}=== n8n GCP to AWS Migration ===${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "Checking prerequisites..."
if ! command_exists gcloud; then
    echo -e "${RED}ERROR: gcloud CLI not found. Install: https://cloud.google.com/sdk/install${NC}"
    exit 1
fi

if ! command_exists aws; then
    echo -e "${RED}ERROR: AWS CLI not found. Install: https://aws.amazon.com/cli/${NC}"
    exit 1
fi

if ! command_exists terraform; then
    echo -e "${RED}ERROR: Terraform not found. Install: https://www.terraform.io/downloads${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} All prerequisites met"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo -e "${GREEN}Created backup directory: $BACKUP_DIR${NC}"
echo ""

# Step 1: Export n8n workflows
echo -e "${YELLOW}Step 1: Exporting n8n workflows from GCP...${NC}"

# Try to get Cloud Run service URL
GCP_URL=$(gcloud run services describe $GCP_SERVICE_NAME \
    --region=$GCP_REGION \
    --format='value(status.url)' 2>/dev/null || echo "")

if [ -z "$GCP_URL" ]; then
    echo -e "${YELLOW}Could not auto-detect Cloud Run URL${NC}"
    read -p "Enter your n8n URL (e.g., https://n8n.yourdomain.com): " GCP_URL
fi

echo "n8n URL: $GCP_URL"

# Get API key
read -p "Enter your n8n API key: " -s N8N_API_KEY
echo ""

# Export workflows
echo "Exporting workflows..."
curl -X GET "$GCP_URL/api/v1/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -o "$BACKUP_DIR/workflows.json" 2>/dev/null

if [ -f "$BACKUP_DIR/workflows.json" ]; then
    WORKFLOW_COUNT=$(jq '.data | length' "$BACKUP_DIR/workflows.json" 2>/dev/null || echo "0")
    echo -e "${GREEN}✓${NC} Exported $WORKFLOW_COUNT workflows"
else
    echo -e "${RED}WARNING: Could not export workflows${NC}"
fi

# Export credentials (encrypted)
echo "Exporting credentials..."
curl -X GET "$GCP_URL/api/v1/credentials" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -o "$BACKUP_DIR/credentials.json" 2>/dev/null || true

echo ""

# Step 2: Export database
echo -e "${YELLOW}Step 2: Exporting PostgreSQL database from Cloud SQL...${NC}"

# Get Cloud SQL instance name
read -p "Enter Cloud SQL instance name (or press Enter to skip): " CLOUDSQL_INSTANCE

if [ ! -z "$CLOUDSQL_INSTANCE" ]; then
    BUCKET_NAME="gs://${GCP_PROJECT_ID}-n8n-migration"

    # Create bucket if needed
    gsutil mb -p $GCP_PROJECT_ID $BUCKET_NAME 2>/dev/null || true

    # Export database
    echo "Exporting database to Cloud Storage..."
    gcloud sql export sql $CLOUDSQL_INSTANCE \
        $BUCKET_NAME/n8n-database-$(date +%Y%m%d-%H%M%S).sql \
        --database=n8n \
        --offload 2>/dev/null || true

    # Download export
    echo "Downloading database export..."
    gsutil cp "$BUCKET_NAME/n8n-database-*.sql" "$BACKUP_DIR/" 2>/dev/null || true

    if ls $BACKUP_DIR/*.sql 1> /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Database exported"
    else
        echo -e "${YELLOW}WARNING: Could not export database${NC}"
    fi
else
    echo -e "${YELLOW}Skipping database export${NC}"
fi

echo ""

# Step 3: Deploy AWS infrastructure
echo -e "${YELLOW}Step 3: Deploying AWS infrastructure with Terraform...${NC}"

cd terraform/aws-n8n

if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}terraform.tfvars not found. Creating from example...${NC}"
    cp terraform.tfvars.example terraform.tfvars
    echo -e "${RED}IMPORTANT: Edit terraform.tfvars with your settings before continuing${NC}"
    read -p "Press Enter after editing terraform.tfvars..."
fi

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Plan deployment
echo "Planning deployment..."
terraform plan -out=tfplan

echo ""
echo -e "${YELLOW}Review the Terraform plan above.${NC}"
read -p "Continue with deployment? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

# Apply Terraform
echo "Deploying infrastructure..."
terraform apply tfplan

# Get outputs
AWS_PUBLIC_IP=$(terraform output -raw ec2_public_ip)
AWS_RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
AWS_ENCRYPTION_KEY=$(terraform output -raw encryption_key)

echo ""
echo -e "${GREEN}✓${NC} AWS infrastructure deployed"
echo "   Public IP: $AWS_PUBLIC_IP"
echo ""

cd ../..

# Step 4: Wait for EC2 to be ready
echo -e "${YELLOW}Step 4: Waiting for EC2 instance to complete initialization...${NC}"

echo "This may take 5-10 minutes for Docker and n8n to start..."
echo "Monitoring EC2 initialization..."

MAX_WAIT=600 # 10 minutes
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if ssh -i ~/.ssh/*.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        ubuntu@$AWS_PUBLIC_IP "docker ps | grep -q n8n" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} n8n is running on AWS"
        break
    fi

    echo -n "."
    sleep 10
    WAITED=$((WAITED + 10))
done

echo ""

if [ $WAITED -ge $MAX_WAIT ]; then
    echo -e "${YELLOW}WARNING: Timed out waiting for n8n. Check manually:${NC}"
    echo "   ssh ubuntu@$AWS_PUBLIC_IP 'docker ps'"
fi

echo ""

# Step 5: Import database
echo -e "${YELLOW}Step 5: Importing database to AWS RDS...${NC}"

if ls $BACKUP_DIR/*.sql 1> /dev/null 2>&1; then
    DB_FILE=$(ls $BACKUP_DIR/*.sql | head -1)

    # Get database password
    read -p "Enter database password from terraform.tfvars: " -s DB_PASSWORD
    echo ""

    # Copy SQL file to EC2
    echo "Uploading database backup to EC2..."
    scp -i ~/.ssh/*.pem -o StrictHostKeyChecking=no \
        "$DB_FILE" ubuntu@$AWS_PUBLIC_IP:/tmp/n8n-backup.sql

    # Import database
    echo "Importing database..."
    ssh -i ~/.ssh/*.pem -o StrictHostKeyChecking=no ubuntu@$AWS_PUBLIC_IP << EOSSH
export PGPASSWORD="$DB_PASSWORD"
psql -h $AWS_RDS_ENDPOINT -U n8n -d n8n < /tmp/n8n-backup.sql
rm /tmp/n8n-backup.sql
EOSSH

    echo -e "${GREEN}✓${NC} Database imported"
else
    echo -e "${YELLOW}No database backup found, skipping import${NC}"
fi

echo ""

# Step 6: Import workflows
echo -e "${YELLOW}Step 6: Importing workflows to AWS n8n...${NC}"

# Get AWS n8n domain from terraform
cd terraform/aws-n8n
AWS_DOMAIN=$(terraform output -raw n8n_url | sed 's|https://||')
cd ../..

echo "Waiting for n8n to be accessible at https://$AWS_DOMAIN..."
sleep 30

if [ -f "$BACKUP_DIR/workflows.json" ]; then
    # Import workflows using API
    echo "Importing workflows..."

    # Note: Individual workflow import may be needed
    echo -e "${YELLOW}Manual step required:${NC}"
    echo "1. Access https://$AWS_DOMAIN"
    echo "2. Go to Settings > Import from File"
    echo "3. Upload: $BACKUP_DIR/workflows.json"
    echo ""
    echo "Or use the n8n API to import programmatically"
fi

echo ""

# Step 7: Configure DNS
echo -e "${YELLOW}Step 7: DNS Configuration${NC}"

echo ""
echo "Add the following DNS A record:"
echo "   Hostname: $AWS_DOMAIN"
echo "   Type: A"
echo "   Value: $AWS_PUBLIC_IP"
echo "   TTL: 300"
echo ""

read -p "Press Enter after updating DNS..."

echo ""

# Step 8: Test AWS deployment
echo -e "${YELLOW}Step 8: Testing AWS deployment...${NC}"

echo "Testing n8n accessibility..."
if curl -I -k "https://$AWS_DOMAIN" 2>/dev/null | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✓${NC} n8n is accessible at https://$AWS_DOMAIN"
else
    echo -e "${YELLOW}WARNING: n8n not yet accessible (DNS may still be propagating)${NC}"
fi

echo ""

# Step 9: Monitor parallel running
echo -e "${YELLOW}Step 9: Parallel Monitoring Period${NC}"

echo ""
echo "Both GCP and AWS deployments are now running."
echo "Monitor AWS deployment for 48 hours before decommissioning GCP:"
echo ""
echo "AWS n8n: https://$AWS_DOMAIN"
echo "GCP n8n: $GCP_URL"
echo ""
echo "Verify:"
echo "- All workflows execute correctly"
echo "- All integrations work"
echo "- Webhooks receive requests"
echo "- Performance is acceptable"
echo ""

read -p "Mark migration as successful? (yes/no): " SUCCESS

if [ "$SUCCESS" = "yes" ]; then
    echo ""
    echo -e "${YELLOW}Step 10: Decommissioning GCP (Optional)${NC}"
    echo ""
    echo "Once you've verified AWS is working correctly, you can decommission GCP:"
    echo ""
    echo "1. Stop Cloud Run service:"
    echo "   gcloud run services delete $GCP_SERVICE_NAME --region=$GCP_REGION"
    echo ""
    echo "2. Delete Cloud SQL instance (after final backup):"
    echo "   gcloud sql instances delete $CLOUDSQL_INSTANCE"
    echo ""
    echo "3. Clean up Cloud Storage:"
    echo "   gsutil rm -r $BUCKET_NAME"
    echo ""

    read -p "Decommission GCP now? (yes/no): " DECOMMISSION

    if [ "$DECOMMISSION" = "yes" ]; then
        echo "Decommissioning GCP..."

        # Delete Cloud Run service
        gcloud run services delete $GCP_SERVICE_NAME \
            --region=$GCP_REGION \
            --quiet || true

        echo -e "${GREEN}✓${NC} GCP Cloud Run service deleted"
    fi
fi

echo ""
echo -e "${GREEN}=== Migration Complete ===${NC}"
echo ""
echo "Summary:"
echo "- Backup location: $BACKUP_DIR"
echo "- AWS n8n URL: https://$AWS_DOMAIN"
echo "- AWS Public IP: $AWS_PUBLIC_IP"
echo "- AWS SSH: ssh ubuntu@$AWS_PUBLIC_IP"
echo ""
echo "Next steps:"
echo "1. Test all workflows on AWS"
echo "2. Update any external webhooks to new URL"
echo "3. Monitor costs in AWS Console"
echo "4. Keep GCP backup for 30 days"
echo ""
echo "Estimated monthly cost:"
echo "- Year 1: \$17/month"
echo "- Year 2+: \$32/month"
echo "- Savings: \$18-33/month vs GCP"
echo ""
