terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
  }
}

# Define the Kubernetes provider
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}


# Null resource to act as a dependency to ensure that the EKS cluster is available before using the provider
resource "null_resource" "eks_ready" {
  depends_on = [module.eks]  

  provisioner "local-exec" {
    command = "echo EKS Cluster is ready"
  }
}
