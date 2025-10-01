# external-secrets.tf

# -------------------------
# External Secrets Operator IAM Role
# -------------------------
resource "aws_iam_role" "external_secrets" {
  name = "ExternalSecretsRole-paas"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.external_secrets.arn
        }
        Condition = {
          StringEquals = {
            "oidc.eks.${var.aws_region}.amazonaws.com/id/${data.aws_eks_cluster.paas_cluster.identity[0].oidc[0].issuer}:sub": "system:serviceaccount:external-secrets-system:external-secrets"
            "oidc.eks.${var.aws_region}.amazonaws.com/id/${data.aws_eks_cluster.paas_cluster.identity[0].oidc[0].issuer}:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "ExternalSecretsPolicy-paas"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          aws_secretsmanager_secret.app_secrets.arn,
          "arn:aws:ssm:${var.aws_region}:*:parameter/paas/*"
        ]
      }
    ]
  })
}

# -------------------------
# OIDC Provider for External Secrets
# -------------------------
resource "aws_iam_openid_connect_provider" "external_secrets" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.external_secrets.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.paas_cluster.identity[0].oidc[0].issuer

  tags = {
    Name = "ExternalSecrets-paas"
  }
}

data "tls_certificate" "external_secrets" {
  url = data.aws_eks_cluster.paas_cluster.identity[0].oidc[0].issuer
}
