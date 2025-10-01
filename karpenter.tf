# karpenter.tf

# -------------------------
# Karpenter Node Pool (replaces Cluster Autoscaler)
# -------------------------
resource "aws_iam_role" "karpenter_node_instance_profile" {
  name = "KarpenterNodeInstanceProfile-paas"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_instance_profile_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter_node_instance_profile.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_instance_profile_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node_instance_profile.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_instance_profile_csi" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CSI_Driver_Policy"
  role       = aws_iam_role.karpenter_node_instance_profile.name
}

resource "aws_iam_instance_profile" "karpenter_node_instance_profile" {
  name = "KarpenterNodeInstanceProfile-paas"
  role = aws_iam_role.karpenter_node_instance_profile.name
}

# -------------------------
# Karpenter Controller IAM Role
# -------------------------
resource "aws_iam_role" "karpenter_controller" {
  name = "KarpenterControllerRole-paas"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.karpenter.arn
        }
        Condition = {
          StringEquals = {
            "oidc.eks.${var.aws_region}.amazonaws.com/id/${data.aws_eks_cluster.paas_cluster.identity[0].oidc[0].issuer}:sub": "system:serviceaccount:karpenter:karpenter"
            "oidc.eks.${var.aws_region}.amazonaws.com/id/${data.aws_eks_cluster.paas_cluster.identity[0].oidc[0].issuer}:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name = "KarpenterControllerPolicy-paas"
  role = aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeImages",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ssm:GetParameter",
          "iam:PassRole",
          "eks:DescribeCluster"
        ]
        Resource = "*"
      }
    ]
  })
}

# -------------------------
# OIDC Provider for Karpenter
# -------------------------
data "aws_eks_cluster" "paas_cluster" {
  name = "paas-cluster"
}

data "aws_eks_cluster_auth" "paas_cluster" {
  name = "paas-cluster"
}

resource "aws_iam_openid_connect_provider" "karpenter" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.karpenter.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.paas_cluster.identity[0].oidc[0].issuer

  tags = {
    Name = "Karpenter-paas"
  }
}

data "tls_certificate" "karpenter" {
  url = data.aws_eks_cluster.paas_cluster.identity[0].oidc[0].issuer
}
