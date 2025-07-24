# GCP Cloud Run Commands Usage Guide

This guide covers the GCP slash commands for Cloud Run cost analysis and optimization.

## Available Commands

### `/gcp-cost-analysis`
Analyzes Cloud Run costs across all projects and provides detailed breakdown.

### `/gcp-optimize` 
Optimizes Cloud Run services for cost efficiency with safety controls.

## Prerequisites

Before using these commands, ensure you have:

1. **Google Cloud CLI installed and authenticated**:
   ```bash
   gcloud auth login
   ```

2. **Required permissions**:
   - Cloud Run Viewer (for analysis)
   - Cloud Run Admin (for optimization)
   - Billing Account Viewer (for accurate cost data)

3. **APIs enabled**:
   - Cloud Run API
   - Cloud Billing API (optional, for precise costs)

## Command Usage

### Cost Analysis

#### Basic Analysis
```bash
/gcp-cost-analysis
```
This will:
- Scan all active projects
- List all Cloud Run services
- Estimate daily/monthly costs
- Identify top cost drivers
- Suggest optimization opportunities

#### Expected Output
```
🔍 CLOUD RUN COST ANALYSIS
================================

📊 SUMMARY
- Total Projects: 3
- Total Services: 12
- Estimated Monthly Cost: $247.50
- Potential Savings: $89.25 (36%)

📈 TOP COST DRIVERS
1. prod-app/api-service (us-central1) - $8.45/day
2. staging-env/worker-service (us-west1) - $6.22/day
3. dev-project/test-api (europe-west1) - $4.18/day

💡 OPTIMIZATION OPPORTUNITIES
- api-service: Over-provisioned (reduce CPU 2→1)
- worker-service: Always-on cost (set minInstances: 0)
- test-api: Expensive region (move to us-central1)
```

### Service Optimization

#### Safe Optimizations Only
```bash
/gcp-optimize --safe-only
```
Applies only low-risk optimizations:
- Remove always-on costs for dev/staging services
- Reduce excessive timeouts
- Optimize max instance limits

#### Full Analysis
```bash
/gcp-optimize --analyze-only
```
Generates comprehensive optimization report without making changes.

#### Gradual Optimization
```bash
# Start with 25% resource reduction
/gcp-optimize --apply --percentage 25

# Monitor for 24-48 hours, then increase if stable
/gcp-optimize --apply --percentage 40
```

#### Target Specific Services
```bash
# Specific project
/gcp-optimize --project my-project --safe-only

# Specific service
/gcp-optimize --service my-api --analyze-only
```

## Safety Features

### Dry Run Mode
Always test changes first:
```bash
/gcp-optimize --apply --dry-run
```

### Backup and Rollback
Automatic backup of configurations:
```bash
# Rollback recent changes
/gcp-optimize --rollback --service my-service

# View backup files
ls optimization-backup-*.json
```

### Risk Levels

**LOW RISK (Safe Mode)**:
- Set minInstances: 0 for dev/staging
- Reduce timeout from 900s to 300s
- Lower maxInstances for predictable traffic

**MEDIUM RISK**:
- 25-50% CPU/memory reduction
- Regional migration
- Scaling policy changes

**HIGH RISK (Manual Approval)**:
- >50% resource reduction
- Production service changes during business hours
- Multi-region consolidation

## Cost Optimization Strategies

### 1. Right-Size Resources
```bash
# Analyze current usage patterns
/gcp-cost-analysis

# Apply conservative 25% reduction
/gcp-optimize --apply --percentage 25

# Monitor and adjust
```

### 2. Eliminate Always-On Costs
```bash
# Find services with minInstances > 0
/gcp-optimize --analyze-only | grep "minInstances"

# Set to 0 for non-latency-critical services
/gcp-optimize --safe-only --apply
```

### 3. Regional Optimization
Most cost-effective regions (in order):
1. `us-central1` (Iowa) - Cheapest
2. `us-east1` (South Carolina)
3. `us-west1` (Oregon)
4. Europe/Asia regions - 20-50% more expensive

### 4. Monitoring and Alerts
After optimization:
```bash
# Set up cost alerts in Cloud Console
# Monitor CPU/Memory utilization
# Watch for error rate increases
# Schedule monthly optimization reviews
```

## Best Practices

### Before Optimization
1. **Backup configurations** - Done automatically
2. **Identify production services** - Avoid during business hours
3. **Set monitoring alerts** - Watch for issues
4. **Plan rollback strategy** - Test rollback procedures

### During Optimization
1. **Start with safe optimizations** - Low risk first
2. **Apply changes gradually** - 25% → 40% → 50% reductions
3. **Monitor service health** - Check error rates and latency
4. **Test functionality** - Verify services work correctly

### After Optimization
1. **Monitor for 48 hours** - Watch for issues
2. **Document changes** - Keep optimization log
3. **Schedule follow-up** - Monthly optimization reviews
4. **Share learnings** - Help other teams optimize

## Troubleshooting

### Authentication Issues
```bash
# Re-authenticate
gcloud auth login

# Check current account
gcloud auth list

# Set active account
gcloud config set account your-email@domain.com
```

### Permission Errors
```bash
# Check current project
gcloud config get-value project

# List accessible projects
gcloud projects list

# Set correct project
gcloud config set project your-project-id
```

### Service Health Issues Post-Optimization
```bash
# Check service status
gcloud run services list --filter="metadata.name:SERVICE_NAME"

# View service logs
gcloud logs read --filter="resource.type=cloud_run_revision"

# Rollback if needed
/gcp-optimize --rollback --service SERVICE_NAME
```

### Cost Tracking
```bash
# View billing in Cloud Console
# Go to Billing → Reports
# Filter by Service: Cloud Run
# Group by Project/Service

# Set up budget alerts
# Billing → Budgets & Alerts
# Create budget for Cloud Run services
```

## Expected Savings

Typical optimization results:
- **Development services**: 60-80% cost reduction
- **Staging services**: 40-60% cost reduction  
- **Production services**: 20-40% cost reduction
- **Overall average**: 30-50% total cost reduction

## Follow-up Actions

After running optimization:
1. **Set up monitoring dashboards**
2. **Create cost alerts**
3. **Schedule monthly reviews**
4. **Document optimization decisions**
5. **Plan next optimization cycle**

## Getting Help

For issues or questions:
1. Check logs in `optimization-log-*.txt`
2. Review backup files for rollback
3. Monitor service health in Cloud Console
4. Consult Cloud Run documentation for resource guidelines