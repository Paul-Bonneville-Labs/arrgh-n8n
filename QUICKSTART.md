# n8n AWS Deployment - Quick Start

Deploy n8n on AWS for **$17/month** in 15 minutes.

## Prerequisites (5 minutes)

1. **AWS Account** with billing enabled
2. **Install tools**:
   ```bash
   # AWS CLI
   brew install awscli  # macOS
   # or: https://aws.amazon.com/cli/

   # Terraform
   brew install terraform  # macOS
   # or: https://www.terraform.io/downloads

   # Configure AWS
   aws configure
   ```

3. **Create SSH key** in AWS Console:
   - EC2 → Key Pairs → Create Key Pair
   - Save `.pem` file securely

4. **Domain ready** (e.g., n8n.yourdomain.com)

## Deploy (10 minutes)

### 1. Configure (2 minutes)

```bash
cd terraform/aws-n8n
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
ssh_key_name    = "your-aws-key-name"
n8n_domain      = "n8n.yourdomain.com"
n8n_password    = "ChangeMe123!"
db_password     = "ChangeMe456!"
ssh_allowed_ips = ["YOUR_IP/32"]  # Get from: curl ifconfig.me
```

### 2. Deploy (8 minutes)

```bash
terraform init
terraform apply
```

Type `yes` when prompted.

### 3. Get IP Address

```bash
terraform output ec2_public_ip
```

Copy the IP address.

### 4. Update DNS

Add A record to your DNS:
```
Hostname: n8n.yourdomain.com
Type: A
Value: <elastic-ip-from-above>
TTL: 300
```

### 5. Access n8n

Wait 5-10 minutes for:
- DNS propagation
- SSL certificate generation

Then visit: `https://n8n.yourdomain.com`

**Login**:
- Username: `admin`
- Password: (your `n8n_password`)

## Done! 🎉

You now have n8n running on AWS for **$17/month** (year 1) or **$32/month** (year 2+).

### Next Steps

- Create your first workflow
- Configure integrations (APIs, databases, etc.)
- Set up webhooks for automation
- Enable 2FA in settings

### Need Help?

- Check logs: `ssh ubuntu@<ip> 'docker logs n8n'`
- Full guide: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- Terraform docs: [terraform/aws-n8n/README.md](terraform/aws-n8n/README.md)

## Cost Summary

| Period | Monthly Cost | Yearly Cost |
|--------|-------------|-------------|
| Year 1 | $17 | $204 |
| Year 2+ | $32 | $384 |
