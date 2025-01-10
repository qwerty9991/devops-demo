module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name

  subnet_ids = var.private_subnets
}
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  private_subnets = var.private_subnets
  azs             = var.azs

}
  # cluster_name    = var.cluster_name
  # cluster_version = "1.31"

resource "aws_iam_policy" "alb_ingress_controller_policy" {
  name        = "ALBIngressControllerIAMPolicy"
  description = "IAM policy for ALB Ingress Controller"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "acm:DescribeCertificate",
                "acm:ListCertificates",
                "acm:GetCertificate",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:AuthorizeSecurityGroupEgress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupEgress",
                "ec2:CreateSecurityGroup",
                "ec2:DeleteSecurityGroup",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeTags",
                "ec2:DescribeVpcs",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:CreateTargetGroup",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:DeleteRule",
                "elasticloadbalancing:DeleteTargetGroup",
                "elasticloadbalancing:DeregisterTargets",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:ModifyRule",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:RemoveTags",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:SetWebAcl",
                "iam:CreateServiceLinkedRole",
                "iam:GetServerCertificate",
                "iam:ListServerCertificates",
                "waf-regional:GetWebACLForResource",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:AssociateWebACL",
                "wafv2:DisassociateWebACL",
                "shield:DescribeProtection",
                "shield:GetSubscriptionState",
                "shield:DeleteProtection",
                "shield:CreateProtection",
                "shield:DescribeSubscription",
                "shield:ListProtections",
                "cognito-idp:DescribeUserPoolClient",
                "waf:GetWebACL"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

# Fetch existing OIDC provider if it exists
data "aws_iam_openid_connect_provider" "existing_oidc" {
  url = "https://oidc.eks.${var.aws_region}.amazonaws.com/id/${local.oidc_provider_url_suffix}"
  count = 1
}

# Fetch the EKS Cluster information
data "aws_eks_cluster" "cluster_info" {
  name = var.cluster_name
}


# Fetch the OIDC Issuer URL from the EKS Cluster
locals {
  oidc_provider_url_suffix = regex("[^/]+$", data.aws_eks_cluster.cluster_info.identity[0].oidc[0].issuer)
  cluster_endpoint = try(data.aws_eks_cluster.cluster_info.endpoint, "")
  cluster_certificate_authority_data = try(data.aws_eks_cluster.cluster_info.certificate_authority[0].data, "")
}

# Fetch the Thumbprint for the OIDC URL
data "tls_certificate" "eks_oidc" {
  url = data.aws_eks_cluster.cluster_info.identity[0].oidc[0].issuer
}

# Create the IAM OIDC provider only if it doesn't exist
resource "aws_iam_openid_connect_provider" "eks" {
  count = length(data.aws_iam_openid_connect_provider.existing_oidc) == 0 ? 1 : 0
  
  url = data.aws_eks_cluster.cluster_info.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint
  ]
}

# Output OIDC provider ARN (either from existing or created resource)
output "oidc_provider_arn" {
  value = coalesce(
    data.aws_iam_openid_connect_provider.existing_oidc[0].arn,
    aws_iam_openid_connect_provider.eks[0].arn
  )
}

# Output OIDC provider URL suffix (for debugging or further use)
output "oidc_provider_url_suffix" {
  value = local.oidc_provider_url_suffix
}

# ALB Ingress Controller IAM Role
resource "aws_iam_role" "alb_ingress_controller_role" {
  name = "alb-ingress-controller-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Effect": "Allow",
      "Principal": {
        "Federated": "${coalesce(
          data.aws_iam_openid_connect_provider.existing_oidc[0].arn,
          aws_iam_openid_connect_provider.eks[0].arn
        )}"
      },
      "Condition": {
        "StringEquals": {
          "oidc.eks.${var.aws_region}.amazonaws.com/id/${local.oidc_provider_url_suffix}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }
  ]
}
EOF

  # Ensure this role creation depends on the OIDC provider being created or fetched first
  depends_on = [
    aws_iam_openid_connect_provider.eks,    
    data.aws_iam_openid_connect_provider.existing_oidc, 
    module.eks
  ]
}

resource "aws_iam_role_policy_attachment" "alb_policy_attachment" {
  policy_arn = aws_iam_policy.alb_ingress_controller_policy.arn
  role       = aws_iam_role.alb_ingress_controller_role.name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.4.0"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
}

resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_ingress_controller_role.arn
    }
  }
}


# Fetch the authentication token for the EKS cluster
data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}
