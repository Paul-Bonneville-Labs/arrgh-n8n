#!/bin/bash

# Complete deployment script for n8n to Google Cloud Run
# This script builds, pushes, and deploys n8n to Cloud Run

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying n8n to Google Cloud Run${NC}"
echo "====================================="

# Load environment variables
if [ -f ".env" ]; then
    echo "Loading environment variables from .env..."
    export $(grep -v '^#' .env | xargs)
else
    echo -e "${YELLOW}⚠️  No .env file found. Using defaults or gcloud config.${NC}"
fi

# Get configuration (environment variables take precedence)
PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
REGION=${REGION:-us-central1}
REPO_NAME=${REPO_NAME:-n8n-repo}
SERVICE_NAME=${SERVICE_NAME:-n8n-app}

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}❌ No Google Cloud project set. Please run the setup script first.${NC}"
    exit 1
fi

echo -e "${GREEN}📦 Project: ${PROJECT_ID}${NC}"
echo -e "${GREEN}🌍 Region: ${REGION}${NC}"
echo -e "${GREEN}📋 Service: ${SERVICE_NAME}${NC}"
echo ""

# Build image tag
IMAGE_TAG="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/n8n:latest"

echo -e "${YELLOW}Step 1: Building Docker image...${NC}"

# Build the Docker image for Cloud Run
docker build -f Dockerfile.cloudrun -t "$IMAGE_TAG" .

echo -e "${GREEN}✅ Docker image built: $IMAGE_TAG${NC}"
echo ""

echo -e "${YELLOW}Step 2: Pushing to Artifact Registry...${NC}"

# Push to Artifact Registry
docker push "$IMAGE_TAG"

echo -e "${GREEN}✅ Image pushed to Artifact Registry${NC}"
echo ""

echo -e "${YELLOW}Step 3: Updating deployment configuration...${NC}"

# Generate deployment configuration from template
./scripts/generate-configs.sh

echo -e "${GREEN}✅ Deployment configuration ready${NC}"
echo ""

echo -e "${YELLOW}Step 4: Creating missing secrets...${NC}"

# Create basic auth password secret if it doesn't exist
if ! gcloud secrets describe "n8n-basic-auth-password" --project="$PROJECT_ID" &>/dev/null; then
    echo "Creating n8n-basic-auth-password secret..."
    
    # Generate a secure password or use the one from .env
    if [ -f ".env" ] && grep -q "N8N_BASIC_AUTH_PASSWORD=" .env; then
        AUTH_PASSWORD=$(grep "^N8N_BASIC_AUTH_PASSWORD=" .env | cut -d'=' -f2 | sed 's/^"//' | sed 's/"$//')
    else
        AUTH_PASSWORD="admin123!"  # Default password - change this!
        echo -e "${YELLOW}⚠️  Using default password. Change this after deployment!${NC}"
    fi
    
    echo -n "$AUTH_PASSWORD" | gcloud secrets create "n8n-basic-auth-password" --data-file=- --project="$PROJECT_ID"
    echo -e "${GREEN}✅ Basic auth password secret created${NC}"
else
    echo -e "${GREEN}ℹ️  Basic auth password secret already exists${NC}"
fi

echo ""
echo -e "${YELLOW}Step 5: Deploying to Cloud Run...${NC}"

# Deploy to Cloud Run using gcloud
gcloud run services replace cloud-run-deployment-final.yaml \
    --region="$REGION" \
    --project="$PROJECT_ID"

echo -e "${GREEN}✅ Service deployed to Cloud Run${NC}"
echo ""

echo -e "${YELLOW}Step 6: Configuring traffic and access...${NC}"

# Allocate 100% traffic to latest revision
gcloud run services update-traffic "$SERVICE_NAME" \
    --to-latest \
    --region="$REGION" \
    --project="$PROJECT_ID"

# Allow unauthenticated requests (can be changed later)
echo "Allowing unauthenticated access..."
gcloud run services add-iam-policy-binding "$SERVICE_NAME" \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --region="$REGION" \
    --project="$PROJECT_ID"

echo -e "${GREEN}✅ Traffic and access configured${NC}"
echo ""

echo -e "${YELLOW}Step 7: Getting service information...${NC}"

# Get service URL
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status.url)")

echo ""
echo -e "${GREEN}🎉 Deployment complete!${NC}"
echo ""
echo -e "${BLUE}Service Information:${NC}"
echo "─────────────────────"
echo "Service Name: $SERVICE_NAME"
echo "Service URL:  $SERVICE_URL"
echo "Region:       $REGION"
echo "Project:      $PROJECT_ID"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Visit your n8n instance: $SERVICE_URL"
echo "2. Login with username: admin"
echo "3. Update your webhook URLs in existing workflows"
echo "4. Test your workflows and integrations"
echo ""
echo -e "${YELLOW}Webhook URL for n8n:${NC}"
echo "$SERVICE_URL/webhook/"
echo ""
echo -e "${YELLOW}To update webhook URL in workflows:${NC}"
echo "Set WEBHOOK_URL environment variable to: $SERVICE_URL/"

# Save deployment info
cat > deployment-info.txt << EOF
n8n Cloud Run Deployment Information
===================================

Service Name: $SERVICE_NAME
Service URL:  $SERVICE_URL
Region:       $REGION
Project:      $PROJECT_ID
Image:        $IMAGE_TAG

Login Credentials:
- Username: admin
- Password: Check Google Secret Manager 'n8n-basic-auth-password'

Webhook URL: $SERVICE_URL/webhook/

Deployed on: $(date)
EOF

echo ""
echo -e "${GREEN}📄 Deployment info saved to: deployment-info.txt${NC}"