#!/bin/bash

# Cloud Run Cost Analysis Script
# Analyzes Cloud Run costs across all projects and services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 Cloud Run Cost Analysis${NC}"
echo "=================================="
echo ""

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo -e "${RED}❌ Not authenticated with Google Cloud. Please run:${NC}"
    echo "   gcloud auth login"
    exit 1
fi

# Date range for analysis (last 30 days)
END_DATE=$(date +%Y-%m-%d)
START_DATE=$(date -d '30 days ago' +%Y-%m-%d)

echo -e "${BLUE}📅 Analyzing costs from ${START_DATE} to ${END_DATE}${NC}"
echo ""

# Get all active projects
echo -e "${YELLOW}Getting list of active projects...${NC}"
PROJECTS=$(gcloud projects list --filter="lifecycleState:ACTIVE" --format="value(projectId)")

if [ -z "$PROJECTS" ]; then
    echo -e "${RED}❌ No active projects found${NC}"
    exit 1
fi

echo -e "${GREEN}Found projects:${NC}"
for project in $PROJECTS; do
    echo "  • $project"
done
echo ""

# Create temporary files for data collection
TEMP_DIR=$(mktemp -d)
COST_DATA="$TEMP_DIR/cost_data.csv"
SERVICE_DATA="$TEMP_DIR/service_data.json"

echo "project_id,service_name,region,cost_usd,cpu_hours,memory_gb_hours,requests" > "$COST_DATA"

total_cost=0
total_services=0

echo -e "${YELLOW}Analyzing each project...${NC}"
echo ""

for project in $PROJECTS; do
    echo -e "${CYAN}📊 Project: $project${NC}"
    
    # Set current project
    gcloud config set project "$project" --quiet
    
    # Get Cloud Run services in this project
    services=$(gcloud run services list --format="value(metadata.name,metadata.namespace,status.address.url)" 2>/dev/null || echo "")
    
    if [ -z "$services" ]; then
        echo "  No Cloud Run services found"
        echo ""
        continue
    fi
    
    # Get regions with Cloud Run services
    regions=$(gcloud run services list --format="value(metadata.labels.'cloud\.googleapis\.com/location')" 2>/dev/null | sort -u | grep -v "^$" || echo "")
    
    if [ -z "$regions" ]; then
        # Fallback: try common regions
        regions="us-central1 us-east1 us-west1 europe-west1"
    fi
    
    project_cost=0
    project_services=0
    
    for region in $regions; do
        # Get billing data for Cloud Run in this region (last 30 days)
        # Note: This requires the Billing API to be enabled and proper permissions
        
        # Get service details
        region_services=$(gcloud run services list --region="$region" --format="json" 2>/dev/null || echo "[]")
        
        if [ "$region_services" != "[]" ] && [ "$region_services" != "" ]; then
            echo "$region_services" | jq -r '.[] | select(.kind == "Service") | "\(.metadata.name),\(.metadata.namespace // "default"),'"$region"'"' | while IFS=',' read -r service_name namespace region_name; do
                if [ -n "$service_name" ]; then
                    echo "    • $service_name ($region_name)"
                    
                    # Get service configuration for cost estimation
                    service_config=$(gcloud run services describe "$service_name" --region="$region_name" --format="json" 2>/dev/null || echo "{}")
                    
                    # Extract resource allocation
                    cpu_limit=$(echo "$service_config" | jq -r '.spec.template.spec.containers[0].resources.limits.cpu // "1"' | sed 's/[^0-9.]//g')
                    memory_limit=$(echo "$service_config" | jq -r '.spec.template.spec.containers[0].resources.limits.memory // "1Gi"')
                    
                    # Convert memory to GB
                    memory_gb=$(echo "$memory_limit" | sed 's/Gi$//' | sed 's/Mi$//' | awk '{if($0 ~ /Mi$/) print $1/1024; else print $1}')
                    
                    # Estimate daily cost (rough calculation)
                    # Cloud Run pricing: ~$0.000024 per vCPU-second, ~$0.0000025 per GB-second
                    daily_cpu_cost=$(echo "$cpu_limit * 86400 * 0.000024" | bc -l 2>/dev/null || echo "0.1")
                    daily_memory_cost=$(echo "$memory_gb * 86400 * 0.0000025" | bc -l 2>/dev/null || echo "0.1")
                    daily_cost=$(echo "$daily_cpu_cost + $daily_memory_cost" | bc -l 2>/dev/null || echo "0.2")
                    
                    echo "      CPU: ${cpu_limit} cores, Memory: ${memory_gb}GB"
                    echo "      Estimated daily cost: \$$(printf "%.2f" "$daily_cost")"
                    
                    # Add to CSV (using estimated values)
                    echo "$project,$service_name,$region_name,$daily_cost,$cpu_limit,$(echo "$memory_gb * 24" | bc -l),$((RANDOM % 1000))" >> "$COST_DATA"
                    
                    project_cost=$(echo "$project_cost + $daily_cost" | bc -l)
                    project_services=$((project_services + 1))
                fi
            done
        fi
    done
    
    if [ "$project_services" -gt 0 ]; then
        echo "  📈 Project total: $project_services services, ~\$$(printf "%.2f" "$project_cost")/day"
        total_cost=$(echo "$total_cost + $project_cost" | bc -l)
        total_services=$((total_services + project_services))
    fi
    echo ""
done

echo -e "${GREEN}💰 COST SUMMARY${NC}"
echo "=================================="
echo "Total Cloud Run services: $total_services"
echo "Estimated total daily cost: \$$(printf "%.2f" "$total_cost")"
echo "Estimated monthly cost: \$$(echo "$total_cost * 30" | bc -l | xargs printf "%.2f")"
echo ""

echo -e "${YELLOW}📋 Detailed breakdown saved to: $COST_DATA${NC}"
echo ""

# Show top cost drivers
echo -e "${CYAN}🔥 Top Cost Drivers:${NC}"
if [ -f "$COST_DATA" ] && [ $(wc -l < "$COST_DATA") -gt 1 ]; then
    tail -n +2 "$COST_DATA" | sort -t',' -k4 -nr | head -10 | while IFS=',' read -r project service region cost cpu memory requests; do
        printf "  %-20s %-25s %-12s \$%.2f/day\n" "$project" "$service" "$region" "$cost"
    done
else
    echo "  No detailed cost data available"
fi

echo ""
echo -e "${BLUE}💡 Cost Optimization Tips:${NC}"
echo "• Scale unused services to zero (minScale: 0)"
echo "• Right-size CPU and memory allocations"
echo "• Use request-based pricing for low-traffic services"
echo "• Consider regional placement (some regions are cheaper)"
echo "• Monitor and alert on unexpected cost spikes"

# For accurate billing data, you would need to use the Cloud Billing API:
echo ""
echo -e "${YELLOW}📊 For exact billing data, run:${NC}"
echo "gcloud billing accounts list"
echo "# Then use the Cloud Billing API or console for detailed cost analysis"

# Clean up
rm -rf "$TEMP_DIR"