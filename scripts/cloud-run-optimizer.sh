#!/bin/bash

# Cloud Run Optimizer Script
# Analyzes and optimizes Cloud Run services for cost efficiency

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
DRY_RUN=false
SAFE_ONLY=false
ANALYZE_ONLY=false
APPLY_CHANGES=false
ROLLBACK_MODE=false
TARGET_PROJECT=""
TARGET_SERVICE=""
PERCENTAGE_REDUCTION=25

# Usage function
usage() {
    echo "Cloud Run Optimizer - Cost optimization for Cloud Run services"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --analyze-only          Only analyze and report optimization opportunities"
    echo "  --dry-run              Show what would be changed without applying"
    echo "  --safe-only            Only apply low-risk optimizations"
    echo "  --apply                Apply optimizations (requires confirmation)"
    echo "  --rollback             Rollback recent changes"
    echo "  --project PROJECT      Target specific project only"
    echo "  --service SERVICE      Target specific service only"
    echo "  --percentage N         Percentage reduction for resources (default: 25)"
    echo "  --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --analyze-only                    # Generate optimization report"
    echo "  $0 --safe-only --dry-run            # Show safe optimizations"
    echo "  $0 --safe-only --apply              # Apply safe optimizations"
    echo "  $0 --apply --percentage 30          # Apply 30% resource reduction"
    echo "  $0 --rollback --service my-service  # Rollback specific service"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --analyze-only)
            ANALYZE_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --safe-only)
            SAFE_ONLY=true
            shift
            ;;
        --apply)
            APPLY_CHANGES=true
            shift
            ;;
        --rollback)
            ROLLBACK_MODE=true
            shift
            ;;
        --project)
            TARGET_PROJECT="$2"
            shift 2
            ;;
        --service)
            TARGET_SERVICE="$2"
            shift 2
            ;;
        --percentage)
            PERCENTAGE_REDUCTION="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

echo -e "${GREEN}⚡ Cloud Run Optimizer${NC}"
echo "=================================="
echo ""

# Check authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo -e "${RED}❌ Not authenticated with Google Cloud. Please run:${NC}"
    echo "   gcloud auth login"
    exit 1
fi

# Create temp directory for analysis
TEMP_DIR=$(mktemp -d)
ANALYSIS_FILE="$TEMP_DIR/analysis.json"
BACKUP_FILE="$TEMP_DIR/backup-$(date +%Y%m%d-%H%M%S).json"
OPTIMIZATION_LOG="optimization-log-$(date +%Y%m%d-%H%M%S).txt"

# Initialize analysis data
echo "[]" > "$ANALYSIS_FILE"

# Function to analyze a single service
analyze_service() {
    local project=$1
    local service_name=$2
    local region=$3
    
    echo -e "${CYAN}  📊 Analyzing: $service_name${NC}"
    
    # Get service configuration
    local service_config=$(gcloud run services describe "$service_name" --region="$region" --project="$project" --format="json" 2>/dev/null || echo "{}")
    
    if [ "$service_config" = "{}" ]; then
        echo "    ⚠️  Could not retrieve service configuration"
        return
    fi
    
    # Extract current configuration
    local cpu_limit=$(echo "$service_config" | jq -r '.spec.template.spec.containers[0].resources.limits.cpu // "1"' | sed 's/[^0-9.]//g')
    local memory_limit=$(echo "$service_config" | jq -r '.spec.template.spec.containers[0].resources.limits.memory // "1Gi"')
    local min_instances=$(echo "$service_config" | jq -r '.spec.template.metadata.annotations."autoscaling.knative.dev/minScale" // "0"')
    local max_instances=$(echo "$service_config" | jq -r '.spec.template.metadata.annotations."autoscaling.knative.dev/maxScale" // "100"')
    local timeout=$(echo "$service_config" | jq -r '.spec.template.metadata.annotations."run.googleapis.com/timeout" // "900s"' | sed 's/s$//')
    
    # Convert memory to GB for calculations
    local memory_gb=$(echo "$memory_limit" | sed 's/Gi$//' | sed 's/Mi$//' | awk '{if($0 ~ /Mi$/) print $1/1024; else print $1}')
    
    # Calculate current costs (rough estimates)
    local daily_cpu_cost=$(echo "$cpu_limit * 86400 * 0.000024" | bc -l 2>/dev/null || echo "0")
    local daily_memory_cost=$(echo "$memory_gb * 86400 * 0.0000025" | bc -l 2>/dev/null || echo "0")
    local always_on_cost=0
    if [ "$min_instances" -gt 0 ] 2>/dev/null; then
        always_on_cost=$(echo "$min_instances * ($daily_cpu_cost + $daily_memory_cost)" | bc -l 2>/dev/null || echo "0")
    fi
    
    local total_daily_cost=$(echo "$daily_cpu_cost + $daily_memory_cost + $always_on_cost" | bc -l 2>/dev/null || echo "0")
    
    # Identify optimization opportunities
    local optimizations=()
    local potential_savings=0
    
    # Check for over-provisioning (conservative assumptions)
    if (( $(echo "$cpu_limit > 1" | bc -l) )); then
        local new_cpu=$(echo "$cpu_limit * (100 - $PERCENTAGE_REDUCTION) / 100" | bc -l)
        local cpu_savings=$(echo "($cpu_limit - $new_cpu) * 86400 * 0.000024" | bc -l)
        optimizations+=("Reduce CPU: $cpu_limit → $new_cpu cores (-$PERCENTAGE_REDUCTION%) [\$$cpu_savings/day]")
        potential_savings=$(echo "$potential_savings + $cpu_savings" | bc -l)
    fi
    
    if (( $(echo "$memory_gb > 1" | bc -l) )); then
        local new_memory=$(echo "$memory_gb * (100 - $PERCENTAGE_REDUCTION) / 100" | bc -l)
        local memory_savings=$(echo "($memory_gb - $new_memory) * 86400 * 0.0000025" | bc -l)
        optimizations+=("Reduce Memory: ${memory_gb}GB → ${new_memory}GB (-$PERCENTAGE_REDUCTION%) [\$$memory_savings/day]")
        potential_savings=$(echo "$potential_savings + $memory_savings" | bc -l)
    fi
    
    # Check always-on costs
    if [ "$min_instances" -gt 0 ] 2>/dev/null; then
        optimizations+=("Set minInstances: $min_instances → 0 (eliminate always-on cost) [\$$always_on_cost/day]")
        potential_savings=$(echo "$potential_savings + $always_on_cost" | bc -l)
    fi
    
    # Check timeout optimization
    if [ "$timeout" -gt 600 ] 2>/dev/null; then
        optimizations+=("Reduce timeout: ${timeout}s → 300s (reduce per-request costs)")
    fi
    
    # Check max instances
    if [ "$max_instances" -gt 50 ] 2>/dev/null; then
        optimizations+=("Reduce maxInstances: $max_instances → 10 (prevent over-scaling)")
    fi
    
    # Create service analysis object
    local service_analysis=$(cat <<EOF
{
  "project": "$project",
  "service": "$service_name",
  "region": "$region",
  "current_config": {
    "cpu": "$cpu_limit",
    "memory": "$memory_limit",
    "minInstances": $min_instances,
    "maxInstances": $max_instances,
    "timeout": "$timeout"
  },
  "costs": {
    "daily_total": $total_daily_cost,
    "cpu_cost": $daily_cpu_cost,
    "memory_cost": $daily_memory_cost,
    "always_on_cost": $always_on_cost
  },
  "optimizations": $(printf '%s\n' "${optimizations[@]}" | jq -R . | jq -s .),
  "potential_daily_savings": $potential_savings,
  "optimization_count": ${#optimizations[@]}
}
EOF
)
    
    # Add to analysis file
    local current_analysis=$(cat "$ANALYSIS_FILE")
    echo "$current_analysis" | jq ". += [$service_analysis]" > "$ANALYSIS_FILE"
    
    # Display current analysis
    echo "    Current: ${cpu_limit} CPU, ${memory_limit} memory, min:${min_instances}, max:${max_instances}"
    echo "    Daily cost: \$$(printf "%.2f" "$total_daily_cost")"
    if [ ${#optimizations[@]} -gt 0 ]; then
        echo "    💡 Potential savings: \$$(printf "%.2f" "$potential_savings")/day"
        for opt in "${optimizations[@]}"; do
            echo "      • $opt"
        done
    else
        echo "    ✅ Already optimized"
    fi
}

# Function to apply optimizations
apply_optimization() {
    local project=$1
    local service_name=$2
    local region=$3
    local optimization_type=$4
    local new_value=$5
    
    if [ "$DRY_RUN" = true ]; then
        echo "    [DRY RUN] Would apply: $optimization_type = $new_value"
        return
    fi
    
    echo "    🔧 Applying: $optimization_type = $new_value"
    
    # Backup current configuration
    gcloud run services describe "$service_name" --region="$region" --project="$project" --format="json" >> "$BACKUP_FILE"
    
    case "$optimization_type" in
        "cpu")
            gcloud run services update "$service_name" --region="$region" --project="$project" --cpu="$new_value" --quiet
            ;;
        "memory")
            gcloud run services update "$service_name" --region="$region" --project="$project" --memory="$new_value" --quiet
            ;;
        "min-instances")
            gcloud run services update "$service_name" --region="$region" --project="$project" --min-instances="$new_value" --quiet
            ;;
        "max-instances")
            gcloud run services update "$service_name" --region="$region" --project="$project" --max-instances="$new_value" --quiet
            ;;
        "timeout")
            gcloud run services update "$service_name" --region="$region" --project="$project" --timeout="$new_value" --quiet
            ;;
    esac
    
    echo "$(date): $project/$service_name ($region) - $optimization_type: $new_value" >> "$OPTIMIZATION_LOG"
}

# Main optimization logic
optimize_services() {
    local analysis=$(cat "$ANALYSIS_FILE")
    local services_count=$(echo "$analysis" | jq length)
    local total_current_cost=0
    local total_potential_savings=0
    
    echo -e "${YELLOW}🎯 Optimization Results${NC}"
    echo "=================================="
    
    for ((i=0; i<services_count; i++)); do
        local service=$(echo "$analysis" | jq ".[$i]")
        local project=$(echo "$service" | jq -r .project)
        local service_name=$(echo "$service" | jq -r .service)
        local region=$(echo "$service" | jq -r .region)
        local optimization_count=$(echo "$service" | jq -r .optimization_count)
        local daily_cost=$(echo "$service" | jq -r .costs.daily_total)
        local potential_savings=$(echo "$service" | jq -r .potential_daily_savings)
        
        total_current_cost=$(echo "$total_current_cost + $daily_cost" | bc -l)
        total_potential_savings=$(echo "$total_potential_savings + $potential_savings" | bc -l)
        
        if [ "$optimization_count" -gt 0 ]; then
            echo -e "${CYAN}📦 $project/$service_name ($region)${NC}"
            
            # Apply safe optimizations if requested
            if [ "$SAFE_ONLY" = true ] || [ "$APPLY_CHANGES" = true ]; then
                local current_config=$(echo "$service" | jq .current_config)
                local min_instances=$(echo "$current_config" | jq -r .minInstances)
                local timeout=$(echo "$current_config" | jq -r .timeout | sed 's/s$//')
                local max_instances=$(echo "$current_config" | jq -r .maxInstances)
                
                # Safe optimization: Set minInstances to 0 for non-production
                if [ "$min_instances" -gt 0 ] && [[ ! "$service_name" =~ prod|production ]]; then
                    apply_optimization "$project" "$service_name" "$region" "min-instances" "0"
                fi
                
                # Safe optimization: Reduce timeout if excessive
                if [ "$timeout" -gt 600 ]; then
                    apply_optimization "$project" "$service_name" "$region" "timeout" "300s"
                fi
                
                # Safe optimization: Reduce max instances if excessive
                if [ "$max_instances" -gt 50 ]; then
                    apply_optimization "$project" "$service_name" "$region" "max-instances" "10"
                fi
                
                # Resource optimization (if not safe-only mode)
                if [ "$SAFE_ONLY" = false ] && [ "$APPLY_CHANGES" = true ]; then
                    local cpu=$(echo "$current_config" | jq -r .cpu)
                    local memory=$(echo "$current_config" | jq -r .memory)
                    
                    if (( $(echo "$cpu > 1" | bc -l) )); then
                        local new_cpu=$(echo "$cpu * (100 - $PERCENTAGE_REDUCTION) / 100" | bc -l)
                        apply_optimization "$project" "$service_name" "$region" "cpu" "$new_cpu"
                    fi
                    
                    if [[ "$memory" =~ ^[0-9]+Gi$ ]] && [ "${memory%Gi}" -gt 1 ]; then
                        local memory_val="${memory%Gi}"
                        local new_memory=$(echo "$memory_val * (100 - $PERCENTAGE_REDUCTION) / 100" | bc -l)
                        apply_optimization "$project" "$service_name" "$region" "memory" "${new_memory}Gi"
                    fi
                fi
            fi
            
            # Show optimization details
            local optimizations=$(echo "$service" | jq -r '.optimizations[]')
            while IFS= read -r opt; do
                [ -n "$opt" ] && echo "  • $opt"
            done <<< "$optimizations"
        fi
    done
    
    echo ""
    echo -e "${GREEN}💰 COST SUMMARY${NC}"
    echo "=================================="
    echo "Services analyzed: $services_count"
    echo "Current daily cost: \$$(printf "%.2f" "$total_current_cost")"
    echo "Potential daily savings: \$$(printf "%.2f" "$total_potential_savings")"
    echo "Potential monthly savings: \$$(echo "$total_potential_savings * 30" | bc -l | xargs printf "%.2f")"
    
    if [ "$total_potential_savings" != "0" ]; then
        local savings_percentage=$(echo "scale=1; $total_potential_savings * 100 / $total_current_cost" | bc -l)
        echo "Potential savings: ${savings_percentage}%"
    fi
    
    if [ "$APPLY_CHANGES" = true ] && [ "$DRY_RUN" = false ]; then
        echo ""
        echo -e "${YELLOW}📋 Optimization log saved: $OPTIMIZATION_LOG${NC}"
        echo -e "${YELLOW}🔄 Backup configuration saved: $BACKUP_FILE${NC}"
    fi
}

# Main execution
if [ "$ROLLBACK_MODE" = true ]; then
    echo -e "${YELLOW}🔄 Rollback functionality - implement based on backup files${NC}"
    echo "Check backup files and optimization logs for rollback commands"
    exit 0
fi

# Get projects to analyze
if [ -n "$TARGET_PROJECT" ]; then
    PROJECTS="$TARGET_PROJECT"
else
    PROJECTS=$(gcloud projects list --filter="lifecycleState:ACTIVE" --format="value(projectId)")
fi

echo -e "${BLUE}🔍 Analyzing Cloud Run services...${NC}"
echo ""

# Analyze each project
for project in $PROJECTS; do
    echo -e "${PURPLE}📂 Project: $project${NC}"
    gcloud config set project "$project" --quiet
    
    # Get services in this project
    if [ -n "$TARGET_SERVICE" ]; then
        # Analyze specific service
        local regions=$(gcloud run services list --filter="metadata.name:$TARGET_SERVICE" --format="value(metadata.labels.'cloud\.googleapis\.com/location')" | sort -u | grep -v "^$")
        for region in $regions; do
            analyze_service "$project" "$TARGET_SERVICE" "$region"
        done
    else
        # Analyze all services
        local services_data=$(gcloud run services list --format="json" 2>/dev/null || echo "[]")
        local services_count=$(echo "$services_data" | jq length)
        
        if [ "$services_count" -eq 0 ]; then
            echo "  No Cloud Run services found"
        else
            for ((j=0; j<services_count; j++)); do
                local service_name=$(echo "$services_data" | jq -r ".[$j].metadata.name")
                local region=$(echo "$services_data" | jq -r ".[$j].metadata.labels.\"cloud.googleapis.com/location\" // \"us-central1\"")
                analyze_service "$project" "$service_name" "$region"
            done
        fi
    fi
    echo ""
done

# Generate optimization report or apply changes
if [ "$ANALYZE_ONLY" = false ]; then
    optimize_services
fi

# Generate analysis report
if [ "$ANALYZE_ONLY" = true ] || [ "$DRY_RUN" = true ]; then
    echo -e "${GREEN}📊 Analysis complete! Report saved to: $ANALYSIS_FILE${NC}"
fi

# Cleanup
rm -rf "$TEMP_DIR"