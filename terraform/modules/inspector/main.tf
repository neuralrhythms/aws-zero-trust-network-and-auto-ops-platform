# -----------------------------------------------------------------------------
# Module: inspector
# Purpose: Enable Amazon Inspector v2 organisation-wide continuous vulnerability
#          management with delegated administration from the `audit` account.
#
# Scan types enabled:
#   - EC2        : OS/package CVE scanning via SSM agent
#   - ECR        : Container image enhanced scanning on push and continuously
#   - Lambda     : Function code and layer vulnerability scanning
#
# This module is instantiated from terraform/environments/audit/main.tf.
# The `audit` account must already be registered as the delegated administrator
# for Amazon Inspector in the AWS Organisation before applying this module.
#
# Relationship to GuardDuty:
#   - Inspector  → vulnerability management (what is exploitable)
#   - GuardDuty  → threat detection       (what is being exploited / attacked)
#   Both are delegated from the `audit` account (Security OU).
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Enable Amazon Inspector v2 in the delegated-admin (audit) account.
# This acts as the anchor detector; the organisation configuration below
# extends auto-enablement to all member accounts.
# -----------------------------------------------------------------------------
resource "aws_inspector2_enabler" "audit" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2", "ECR", "LAMBDA"]
}

# Retrieve the current account ID so we can self-reference without hardcoding.
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Organisation-wide auto-enablement.
# When a new member account joins the organisation it will automatically have
# EC2, ECR, and Lambda scanning activated.
# -----------------------------------------------------------------------------
resource "aws_inspector2_organization_configuration" "this" {
  auto_enable {
    ec2    = true
    ecr    = true
    lambda = true
  }

  # Ensure the audit-account enabler exists before configuring the org.
  depends_on = [aws_inspector2_enabler.audit]
}

# -----------------------------------------------------------------------------
# Associate member accounts so the audit account receives aggregated findings.
# Iterate over the list of member account IDs supplied by the caller.
# -----------------------------------------------------------------------------
resource "aws_inspector2_member_association" "members" {
  for_each   = toset(var.member_account_ids)
  account_id = each.value

  depends_on = [aws_inspector2_organization_configuration.this]
}
