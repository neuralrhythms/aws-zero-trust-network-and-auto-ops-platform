################################################################################
# Environment: workload-prod
# Account role: Live production workloads (Workloads BU OU)
#
# Module composition:
#   - vpc           : 4-tier spoke VPC (public-ingress, app-private, data-private, tgw-attach)
#   - tgw_attachment: Connects this spoke VPC to the shared Transit Gateway
#   - eks_cluster   : EKS with Linux (AL2) + Windows (Server 2019 Core) managed node groups
#   - eks_addons    : AWS LBC, Karpenter, Fluent Bit → Splunk HEC
#   - ecr           : Immutable container image repositories with scan-on-push
#
# Production differentiators:
#   - m6i.xlarge Linux nodes and m6i.2xlarge Windows nodes (REQ-5.4)
#   - Strictest SCP boundaries: deny-direct-internet-egress + deny-open-ssh-rdp
#   - All egress routed via network-hub Network Firewall inspection path
#   - 3 AZs for HA (eu-west-1a, eu-west-1b, eu-west-1c)
#
# No inline resource definitions — all resources live in shared modules (REQ-5.3).
# Transit Gateway ID and spoke route table ID are read from the network-hub
# remote state, which is the canonical source of truth for shared networking.
#
# REQ-5.1, REQ-5.2, REQ-5.3, REQ-5.5
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------------------
# Remote state — network-hub
# Reads the Transit Gateway ID and spoke route table ID from the network-hub
# account's Terraform state. These outputs are the stable cross-account
# interface defined in terraform/environments/network-hub/outputs.tf.
# ------------------------------------------------------------------------------
data "terraform_remote_state" "network_hub" {
  backend = "s3"

  config = {
    bucket = var.network_hub_state_bucket
    key    = "network-hub/terraform.tfstate"
    region = var.aws_region
  }
}

# ------------------------------------------------------------------------------
# VPC — 4-tier spoke network
# Provides subnet outputs (vpc_id, app_private_subnet_ids, tgw_attach_subnet_ids)
# consumed by the downstream modules in this root module.
# ------------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  vpc_name                 = var.cluster_name
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidr       = var.public_subnet_cidr
  app_private_subnet_cidr  = var.app_private_subnet_cidr
  data_private_subnet_cidr = var.data_private_subnet_cidr
  tgw_attach_subnet_cidr   = var.tgw_attach_subnet_cidr
  availability_zones       = var.availability_zones
  flow_log_destination_arn = var.flow_log_destination_arn
}

# ------------------------------------------------------------------------------
# Transit Gateway attachment
# Attaches this spoke VPC to the shared TGW and associates it with the spoke
# route table so all egress traffic is routed through the Network Firewall in
# the network-hub account.
# ------------------------------------------------------------------------------
module "tgw_attachment" {
  source = "../../modules/tgw-attachment"

  transit_gateway_id             = data.terraform_remote_state.network_hub.outputs.transit_gateway_id
  vpc_id                         = module.vpc.vpc_id
  tgw_attach_subnet_ids          = module.vpc.tgw_attach_subnet_ids
  transit_gateway_route_table_id = data.terraform_remote_state.network_hub.outputs.spoke_route_table_id
}

# ------------------------------------------------------------------------------
# EKS cluster — heterogeneous managed node groups (production-grade sizing)
# Linux (AL2) nodes: m6i.xlarge for production throughput.
# Windows (Server 2019 Core) nodes: m6i.2xlarge; tainted os=windows:NoSchedule.
# Instance types sourced exclusively from variables — never hardcoded (REQ-5.5).
# ------------------------------------------------------------------------------
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  node_subnet_ids = module.vpc.app_private_subnet_ids

  linux_instance_types = var.linux_instance_types
  linux_min_size       = var.linux_min_size
  linux_max_size       = var.linux_max_size
  linux_desired_size   = var.linux_desired_size

  windows_instance_types = var.windows_instance_types
  windows_min_size       = var.windows_min_size
  windows_max_size       = var.windows_max_size
  windows_desired_size   = var.windows_desired_size
}

# ------------------------------------------------------------------------------
# EKS add-ons — AWS Load Balancer Controller, Karpenter, Fluent Bit
# Fluent Bit ships container logs to Splunk Cloud HEC. The HEC token is
# sensitive and must be sourced from AWS Secrets Manager — never hardcoded.
# ------------------------------------------------------------------------------
module "eks_addons" {
  source = "../../modules/eks-addons"

  cluster_name            = module.eks_cluster.cluster_name
  splunk_hec_host         = var.splunk_hec_host
  splunk_hec_token        = var.splunk_hec_token
  karpenter_node_role_arn = var.karpenter_node_role_arn
}

# ------------------------------------------------------------------------------
# ECR — immutable container image repositories
# scan_on_push and IMMUTABLE tags enforce supply-chain security. A 30-day
# lifecycle policy expires untagged images to control storage costs.
# ------------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  repository_names = var.ecr_repository_names
}
