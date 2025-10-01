# PaaS Infrastructure - Manual Deployment

Manual PaaS architecture with EC2 + Kubernetes + Spot instances for a Heroku clone.

- **Master Node**: EC2 on-demand ARM (t4g.small) with Kubernetes control plane + persistent EBS for etcd
- **Worker Nodes**: EC2 spot ARM (t4g.micro) managed by Karpenter (faster scaling)
- **Database**: RDS PostgreSQL Single-AZ (db.t4g.micro) - Multi-AZ only when needed
- **Cache**: Redis in-pod with persistent volume (savings ~$12/month vs. ElastiCache)
- **Storage**: S3 for user code uploads
- **CI/CD**: Step Functions + CodeBuild for automatic builds
- **Monitoring**: CloudWatch with 7-day retention + only essential metrics for scaling
- **Networking**: VPC with VPC Endpoints (savings ~$45/month vs. NAT Gateway) + ALB
- **Security**: External Secrets Operator for secure management secrets

## Prerequisites

1. AWS CLI configured
2. Terraform >= 1.0
3. Existing EC2 key pair
4. Kubernetes-optimized ARM64 AMIs

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

| Variable | Description | Default |
|-----------|-------------|---------|
| `aws_region` | AWS Region | us-east-1 |
| `master_instance_type` | Master Instance Type | t4g.small |
| `worker_instance_type` | Worker Instance Type | t4g.micro |
| `master_ami_id` | AMI ID for master | Required |
| `worker_ami_id` | AMI ID for workers | Required |
| `key_pair_name` | SSH key pair name | Required |
| `rds_password` | RDS Password | Required |

## Output

After deployment, you will get:
- VPC and subnet IDs
- ALB DNS name
- RDS endpoint
- S3 bucket name
- Step Functions ARN
- VPC Endpoints for S3/ECR/Secrets Manager

## Cleanup

```bash
terraform destroy
```

## Notes

- **Spot instances** can be terminated by AWS (cost savings ~70%)
- **Cluster Autoscaler** automatically manages worker nodes
- **Redis in-pod** saves ~$12/month vs ElastiCache
- **VPC Endpoints** save ~$45/month vs NAT Gateway
- **Secrets** are managed through AWS Secrets Manager
- **CloudWatch** monitors CPU, memory, and node health

*Costs may vary based on usage and region*