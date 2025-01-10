module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  reuse_nat_ips        = true
  enable_dns_support   = true
  enable_dns_hostnames = true
  external_nat_ip_ids  = aws_eip.nat.*.id
  depends_on = [
    aws_eip.nat # Ensure the VPC module waits for EIP creation
  ]

}
resource "aws_eip" "nat" {
  count  = 1
  domain = "vpc"
}

###################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  bootstrap_self_managed_addons = false
  cluster_addons = {
    coredns                = {
        resolve_conflicts_on_create = "OVERWRITE"
    }
    kube-proxy             = {
        resolve_conflicts_on_create = "OVERWRITE"
    }
    vpc-cni                = {
        resolve_conflicts_on_create = "OVERWRITE"
    }
  }

  # Optional
  cluster_endpoint_public_access = true

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = var.private_subnets
  #   control_plane_subnet_ids = ["subnet-xyzde987", "subnet-slkjf456", "subnet-qeiru789"]

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    instance_types = ["t2.large"]
  }

  eks_managed_node_groups = {
    linux-ng = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      #   ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t2.large"]

      min_size     = 2
      max_size     = 10
      desired_size = 2
    }
  }
}