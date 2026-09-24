terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================
# EKS Cluster Module
#
# Provisions an Amazon EKS cluster with two Managed Node Groups:
#   - Linux (Amazon Linux 2 / AL2_x86_64) — no taint, handles general workloads
#   - Windows (Windows Server 2019 Core) — tainted os=windows:NO_SCHEDULE so
#     only pods with a matching toleration are scheduled on Windows nodes
#
# Instance types are always supplied via variables — no type strings are
# hardcoded in this file (REQ-6.4, REQ-9.4).
#
# The cluster OIDC provider is enabled by the upstream community module,
# enabling IRSA (IAM Roles for Service Accounts) / EKS Pod Identities for
# all workload pods without granting broad node-level IAM permissions.
# ============================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.node_subnet_ids

  # Enable OIDC provider so IRSA / EKS Pod Identities work out of the box
  enable_irsa = true

  eks_managed_node_groups = {
    linux = {
      ami_type       = "AL2_x86_64"
      instance_types = var.linux_instance_types

      min_size     = var.linux_min_size
      max_size     = var.linux_max_size
      desired_size = var.linux_desired_size

      # No taint — Linux nodes accept general-purpose workloads
      taints = []
    }

    windows = {
      ami_type       = "WINDOWS_CORE_2019_x86_64"
      instance_types = var.windows_instance_types

      min_size     = var.windows_min_size
      max_size     = var.windows_max_size
      desired_size = var.windows_desired_size

      # Taint ensures only Windows-tolerant pods land on these nodes
      taints = [
        {
          key    = "os"
          value  = "windows"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  tags = {
    ManagedBy = "terraform"
    Module    = "eks-cluster"
  }
}
