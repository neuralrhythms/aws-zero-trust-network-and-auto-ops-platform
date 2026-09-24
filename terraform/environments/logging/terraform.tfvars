# =============================================================================
# Variable values — logging environment
#
# SECURITY NOTE: Replace every <PLACEHOLDER> with the real value before running
# terraform plan/apply. Do NOT commit real account IDs, bucket names that
# encode account IDs, or Splunk tokens to version control — use a secrets
# manager or CI/CD variable injection instead.
#
# This account is in the Security OU. Its sole purpose is hosting the
# organisation-wide immutable log archive (S3 Object Lock, COMPLIANCE mode)
# and the Splunk Universal Forwarder EC2 instance. No workload resources are
# deployed here (ADR-008).
# =============================================================================

# ---------------------------------------------------------------------------
# Provider / backend
# ---------------------------------------------------------------------------

# AWS region where the logging account resources are deployed.
aws_region = "us-east-1"

# Name of the S3 bucket holding all Terraform remote state files.
tf_state_bucket = "<TF_STATE_BUCKET_PLACEHOLDER>"

# Name of the DynamoDB table used for Terraform state locking.
tf_lock_table = "<TF_LOCK_TABLE_PLACEHOLDER>"

# ---------------------------------------------------------------------------
# Immutable log archive (S3 + Object Lock)
# ---------------------------------------------------------------------------

# Globally unique name for the log archive bucket.
# Convention: <org-prefix>-log-archive-<logging-account-id>
# Replace the account ID placeholder — do NOT commit real account IDs.
log_archive_bucket_name = "<ORG_PREFIX>-log-archive-<LOGGING_ACCOUNT_ID_PLACEHOLDER>"

# Retention period in days for S3 Object Lock COMPLIANCE mode.
# 365 days (1 year) meets most compliance baselines (PCI-DSS, SOC 2, HIPAA).
# Increase to 2555 (7 years) for FINRA / SEC Rule 17a-4 requirements.
object_lock_retention_days = 365

# ---------------------------------------------------------------------------
# VPC — minimal, for Splunk Universal Forwarder EC2 instance
# All CIDRs are RFC 1918 private ranges (REQ-9.4 — no real public IPs).
# Adjust CIDR allocations to avoid overlap with other account VPCs.
# ---------------------------------------------------------------------------

# VPC CIDR — /16 provides ample address space for the forwarder host.
vpc_cidr = "10.3.0.0/16"

# Public-ingress subnet — /24 (NAT Gateway resides here).
public_subnet_cidr = "10.3.0.0/24"

# App-private subnet — /24 (Splunk Universal Forwarder EC2 instance).
app_private_subnet_cidr = "10.3.1.0/24"

# Data-private subnet — /24 (reserved; no database tier needed in logging account).
data_private_subnet_cidr = "10.3.2.0/24"

# TGW-attach subnet — /28 per AZ (minimal, for Transit Gateway attachment endpoint).
# A /28 provides 11 usable IPs — sufficient for TGW attachment ENIs.
tgw_attach_subnet_cidr = "10.3.3.0/28"

# Availability zones for subnet distribution.
availability_zones = ["us-east-1a", "us-east-1b"]

# ARN of the S3 bucket or CloudWatch Logs group that receives VPC Flow Logs.
# Self-referential: Flow Logs from this VPC flow to the log archive bucket.
# This value is set after the log archive bucket is created; use a two-step
# apply or use the bucket ARN output from the first apply.
flow_log_destination_arn = "<LOG_ARCHIVE_BUCKET_ARN_PLACEHOLDER>"
