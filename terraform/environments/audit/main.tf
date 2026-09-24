# =============================================================================
# Environment: audit
# Account role: Security OU — delegated admin for GuardDuty, Inspector;
#               read-only security toolset hub; no workload resources.
#
# Per ADR-009, the `audit` account is the GuardDuty delegated administrator:
#   findings → `audit` aggregation → EventBridge → `logging` account S3 → Splunk HEC
#   high-severity findings → SNS → on-call
#
# Per ADR-010, the `audit` account is also the Amazon Inspector delegated
# administrator, providing continuous vulnerability management across the
# organisation (EC2, ECR enhanced, Lambda scan types).
#
# This environment instantiates only security modules (guardduty, inspector).
# No workload resources (VPC, EKS, ECR) are declared here (REQ-5.3).
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
# GuardDuty — organisation-wide threat detection (ADR-009)
# The audit account acts as the GuardDuty delegated administrator, aggregating
# findings from all member accounts. High-severity findings are routed to SNS
# for on-call alerting. All 4 protection plans are enabled:
#   S3 Data Events, EKS Audit Logs, EC2 Malware Protection, RDS Login Activity
# ---------------------------------------------------------------------------
module "guardduty" {
  source = "../../modules/guardduty"

  member_account_ids           = var.member_account_ids
  finding_publishing_frequency = var.finding_publishing_frequency
  sns_topic_arn                = var.sns_topic_arn
}

# ---------------------------------------------------------------------------
# Inspector — organisation-wide vulnerability management (ADR-010)
# The audit account acts as the Amazon Inspector v2 delegated administrator.
# Scan types: EC2 (OS/package CVEs), ECR enhanced (container images), Lambda.
# Relationship to GuardDuty:
#   Inspector  → what is exploitable (vulnerability data)
#   GuardDuty  → what is being exploited / attacked (threat detection)
# ---------------------------------------------------------------------------
module "inspector" {
  source = "../../modules/inspector"

  member_account_ids = var.member_account_ids
}
