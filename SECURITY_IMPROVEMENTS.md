# Security Improvements - Credential Management

## Overview

All hardcoded credentials have been removed from the codebase and replaced with secure credential management practices.

## Changes Made

### 1. AWS_DEPLOYMENT_SUMMARY.md ✅
**Issue**: Exposed credentials in plain text
- n8n password
- Database password
- Encryption key

**Fix**: Replaced with references to `.env` file
- All passwords now show: "See `.env` file (`VARIABLE_NAME`)"
- Added security warning about never committing `.env` to version control
- Database commands updated to use `.pgpass` file on EC2

### 2. scripts/deploy-n8n-aws.sh ✅
**Issue**: Hardcoded credentials in user-data script and deployment info

**Fix**:
- Added `.env` file support with `--env-file` flag
- Script now sources configuration from `.env` if available
- Falls back to interactive prompts if `.env` doesn't exist
- Deployment info file no longer exposes credentials
- Usage: `./scripts/deploy-n8n-aws.sh --env-file .env`

### 3. terraform/aws-n8n/ ✅
**Issue**: Credentials passed directly to user-data script

**Fix**: Added AWS Secrets Manager integration
- Created new `secrets.tf` file with:
  - `aws_secretsmanager_secret.n8n_password`
  - `aws_secretsmanager_secret.db_password`
  - `aws_secretsmanager_secret.encryption_key`
  - IAM policy for EC2 to read secrets
- Updated `main.tf` to pass secret ARNs instead of plaintext
- Updated `user-data.sh` to fetch secrets from Secrets Manager at runtime
- EC2 instance now retrieves credentials securely during boot

### 4. .gitignore ✅
**Added entries**:
```
# Environment files with credentials
.env
.env.*
!.env.example
```

### 5. .env.example ✅
**Created template file** with:
- All required configuration variables
- Placeholder values (CHANGE_ME_*)
- Clear instructions to never commit `.env`
- Documentation of all environment variables

## Security Best Practices

### For AWS CLI Deployments
1. Copy `.env.example` to `.env`
2. Fill in actual values in `.env`
3. Run: `./scripts/deploy-n8n-aws.sh --env-file .env`
4. Never commit `.env` to git

### For Terraform Deployments
1. Store credentials in `terraform.tfvars` (gitignored)
2. Credentials are automatically stored in AWS Secrets Manager
3. EC2 instance retrieves secrets at runtime via IAM role
4. No plaintext credentials in Terraform state or user-data

### Access Patterns
**Development/Management**:
- Use `.env` file (never committed)
- Source: `source .env` or pass to scripts

**Production (Terraform)**:
- Use AWS Secrets Manager
- EC2 retrieves via IAM role
- Automatic rotation possible
- Audit trail in CloudTrail

## Files with Credentials

### ✅ Safe (not in git)
- `.env` - Local development credentials (gitignored)
- `~/.ssh/n8n-deploy-key.pem` - SSH private key (local only)
- `~/.pgpass` - PostgreSQL password file on EC2 (server only)

### ✅ Safe (references only)
- `AWS_DEPLOYMENT_SUMMARY.md` - References `.env`
- `scripts/deploy-n8n-aws.sh` - Sources from `.env`
- `terraform/aws-n8n/*.tf` - Uses Secrets Manager ARNs

### ✅ Safe (templates only)
- `.env.example` - Template with placeholder values

## Cost Impact

**AWS Secrets Manager**:
- $0.40/month per secret
- $0.05 per 10,000 API calls
- **Total**: ~$1.50/month for 3 secrets with minimal API calls

## Verification Checklist

- [x] No plaintext credentials in `.md` files
- [x] No plaintext credentials in `.sh` files
- [x] No plaintext credentials in `.tf` files
- [x] `.env` added to `.gitignore`
- [x] `.env.example` created as template
- [x] Terraform uses AWS Secrets Manager
- [x] Deploy script sources from `.env`
- [x] EC2 retrieves secrets via IAM role

## Migration Guide

If you have an existing deployment with hardcoded credentials:

1. **Update local files**:
   ```bash
   cp .env.example .env
   # Fill in your actual values in .env
   ```

2. **For Terraform deployments**:
   ```bash
   cd terraform/aws-n8n
   terraform plan  # Review changes
   terraform apply # Updates secrets and IAM
   ```

3. **For existing EC2 instances**:
   - Secrets Manager integration requires re-creating the instance
   - Or manually update docker-compose on EC2 to source from Secrets Manager

## Additional Recommendations

1. **Enable AWS Secrets Rotation**:
   ```bash
   aws secretsmanager rotate-secret \
     --secret-id n8n-db-password \
     --rotation-lambda-arn <lambda-arn> \
     --rotation-rules AutomaticallyAfterDays=90
   ```

2. **Use AWS SSM Parameter Store** (free alternative to Secrets Manager):
   - No cost for standard parameters
   - Similar security model
   - Consider for non-critical credentials

3. **Enable CloudTrail** for credential access auditing:
   - Track who accessed which secrets
   - Monitor for unauthorized access
   - Set up alerts for suspicious activity

## References

- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [Terraform AWS Provider - Secrets Manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret)
- [n8n Security Best Practices](https://docs.n8n.io/hosting/security/)

---

**Last Updated**: October 25, 2025
**Status**: ✅ All credential exposure issues resolved
