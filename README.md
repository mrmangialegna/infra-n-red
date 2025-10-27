# PaaS Infrastructure - Manual Deployment

Manual PaaS architecture with EC2 + Kubernetes + Spot instances for a PaaS clone.

- Master Node: EC2 on-demand ARM (t4g.small) with Kubernetes control plane + persistent EBS for etcd
- Worker Nodes: EC2 spot ARM (t4g.micro) managed by Karpenter (faster scaling)
- Database: RDS PostgreSQL Single-AZ (db.t4g.micro) - Multi-AZ only when needed
- Cache: Redis in-pod with persistent volume (savings ~$12/month vs. ElastiCache)
- Storage: S3 for user code uploads
- CI/CD: Step Functions + CodeBuild for automatic builds
- Monitoring: CloudWatch with 7-day retention + only essential metrics for scaling
- Networking: VPC with VPC Endpoints (savings ~$45/month vs. NAT Gateway) + ALB
- Security: External Secrets Operator for secure management secrets

Prerequisites

1. AWS CLI configured
2. Terraform >= 1.0
3. Existing EC2 key pair
4. Kubernetes-optimized ARM64 AMIs

## Pre-deployment Steps

Before applying Terraform, create the Lambda zip files:

```bash
# Install dependencies
pip install -r requirements.txt -t .

# Create webhook handler zip (includes dependencies)
zip -r webhook_handler.zip webhook_handler.py index.py boto3 psycopg2_binary-*.dist-info urllib3

# Create secrets rotation zip (optional)
zip secrets_rotation.zip secrets_rotation.py
```

## Deploy

1. Configure Variables:
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

2. Initialize Terraform:
```bash
terraform init
```

3. Plan Deployment:
```bash
terraform plan
```

4. Apply Infrastructure:
```bash
terraform apply -var="domain_name=yourdomain.com" -var="rds_password=YourSecurePassword123!" -var="master_ami_id=ami-12345678" -var="worker_ami_id=ami-87654321" -var="key_pair_name=your-key-pair"
```

   Or create a `terraform.tfvars` file:
   ```hcl
   domain_name = "yourdomain.com"
   rds_password = "YourSecurePassword123!"
   master_ami_id = "ami-12345678"
   worker_ami_id = "ami-87654321"
   key_pair_name = "your-key-pair"
   aws_region = "us-east-1"
   ```

## Key Variables

| Variable 

`aws_region` us-east-1
`master_instance_type`  t4g.small 
`worker_instance_type` t4g.micro 
`master_ami_id` required 
`worker_ami_id` AMI ID for workers, required 
`key_pair_name` SSH key pair name, required 
`rds_password` Required 

## Output

After deployment, you will get:
- VPC and subnet IDs
- ALB DNS name
- RDS endpoint
- S3 bucket name
- Step Functions ARN
- VPC Endpoints for S3/ECR/Secrets Manager

## Post-deployment Configuration

**1. Initialize Database Schema**

Connect to the RDS instance and run the init_db.sql script:

```bash
# Get RDS endpoint from terraform output
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)

# Connect and run init script
psql -h $RDS_ENDPOINT -U paasadmin -d paasdb -f init_db.sql
```

**2. Configure kubectl access for CodeBuild:**

1. Retrieve your cluster kubeconfig from the master node
2. Store it in AWS Secrets Manager or SSM Parameter Store
3. Update the buildspec.yml to retrieve and use the kubeconfig

Example:
```bash
ssh -i your-key.pem ubuntu@master-node-ip 'kubectl config view --flatten' > kubeconfig.yaml
```

Then store it in Secrets Manager:
```bash
aws secretsmanager create-secret --name paas/kubeconfig --secret-string file://kubeconfig.yaml
```

Update CodeBuild IAM role to allow reading from Secrets Manager.

**3. Configure GitHub Webhook**

After deployment, get the API Gateway webhook URL from Terraform outputs:

```bash
WEBHOOK_URL=$(terraform output -raw webhook_url)
```

Configure this URL in your GitHub repository:
1. Go to Settings → Webhooks
2. Add webhook URL: `https://${WEBHOOK_URL}/webhook/{app_name}`
3. Set content type to `application/json`
4. Enable "Just the push event"

**4. Deploy Your First App**

1. Push code to your GitHub repository
2. The webhook triggers the Lambda function
3. Lambda downloads the code, uploads to S3
4. Step Functions triggers CodeBuild
5. CodeBuild builds Docker image and pushes to ECR
6. CodeBuild deploys to Kubernetes
7. Your app is live!

## Cleanup

```bash
terraform destroy
```
