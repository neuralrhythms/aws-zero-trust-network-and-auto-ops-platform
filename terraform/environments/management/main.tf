# =============================================================================
# Environment: management
# Account role: AWS Organizations root — SCPs, consolidated billing, Control Tower
# Modules instantiated: scp-policies
#
# This root module applies Service Control Policies at the OU level via the
# scp-policies shared module. All resource definitions live in the module;
# no inline resources are declared here (REQ-5.3).
# =============================================================================

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

# ---------------------------------------------------------------------------
# SCP Policies — applied at the OU level via AWS Organizations
# Enforces deny-direct-internet-egress and deny-open-ssh-rdp across all
# member accounts in the target OU.
# ---------------------------------------------------------------------------
module "scp_policies" {
  source = "../../modules/scp-policies"

  target_ou_id          = var.target_ou_id
  management_account_id = var.management_account_id
}
