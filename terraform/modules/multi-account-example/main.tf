# =============================================================================
# Multi-Account Example — Cross-Account Module Composition
#
# This module is the canonical demonstration of how a workload spoke account
# (workload-prod) consumes shared Terraform modules while referencing outputs
# from the Network-Hub account via Terraform remote state data sources.
#
# Pattern overview:
#   1. Read Network-Hub outputs (TGW ID, route table IDs) from remote state
#   2. Attach the workload VPC to the Transit Gateway (tgw-attachment module)
#   3. Provision an EKS cluster with heterogeneous OS node groups (eks-cluster)
#   4. Create ECR repositories for workload container images (ecr module)
#   5. GuardDuty and Inspector are managed by the audit account (Security OU)
#      as delegated administrator — included here for compositional completeness
#
# No resources are deployed by this module; it is a demonstration scaffold for
# architectural review and customer demonstration purposes.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Read shared Network-Hub outputs via Terraform remote state
#    Provides: transit_gateway_id, spoke_route_table_id,
#              inspection_route_table_id
# -----------------------------------------------------------------------------
data "terraform_remote_state" "network_hub" {
  backend = "s3"

  config = {
    bucket = var.network_hub_state_bucket
    key    = "network-hub/terraform.tfstate"
    region = var.aws_region
  }
}

# -----------------------------------------------------------------------------
# 2. Attach workload VPC to the Transit Gateway
#    TGW ID and spoke route table ID are consumed from Network-Hub remote state
# -----------------------------------------------------------------------------
module "tgw_attachment" {
  source = "../../modules/tgw-attachment"

  transit_gateway_id             = data.terraform_remote_state.network_hub.outputs.transit_gateway_id
  vpc_id                         = var.vpc_id
  tgw_attach_subnet_ids          = var.tgw_attach_subnet_ids
  transit_gateway_route_table_id = data.terraform_remote_state.network_hub.outputs.spoke_route_table_id
}

# -----------------------------------------------------------------------------
# 3. EKS cluster with Linux and Windows Managed Node Groups
#    Instance types are supplied via variables — never hardcoded here
# -----------------------------------------------------------------------------
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = var.vpc_id
  node_subnet_ids = var.node_subnet_ids

  linux_instance_types = var.linux_instance_types
  linux_min_size       = var.linux_min_size
  linux_max_size       = var.linux_max_size
  linux_desired_size   = var.linux_desired_size

  windows_instance_types = var.windows_instance_types
  windows_min_size       = var.windows_min_size
  windows_max_size       = var.windows_max_size
  windows_desired_size   = var.windows_desired_size
}

# -----------------------------------------------------------------------------
# 4. ECR repositories for workload container images
#    Immutable tags and scan-on-push are enforced by the ecr module
# -----------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  repository_names = var.ecr_repository_names
}

# -----------------------------------------------------------------------------
# 5a. GuardDuty — org-wide threat detection
#     NOTE: In production this module is applied from
#     terraform/environments/audit/ where the audit account acts as delegated
#     administrator (Security OU). It is included here to demonstrate the full
#     multi-account module composition pattern.
# -----------------------------------------------------------------------------
module "guardduty" {
  source = "../../modules/guardduty"

  member_account_ids           = var.member_account_ids
  finding_publishing_frequency = var.finding_publishing_frequency
  sns_topic_arn                = var.sns_topic_arn
}

# -----------------------------------------------------------------------------
# 5b. Inspector — continuous vulnerability management (EC2, ECR, Lambda)
#     NOTE: In production this module is applied from
#     terraform/environments/audit/ where the audit account acts as delegated
#     administrator (Security OU). It is included here to demonstrate the full
#     multi-account module composition pattern.
# -----------------------------------------------------------------------------
module "inspector" {
  source = "../../modules/inspector"

  member_account_ids = var.member_account_ids
}
