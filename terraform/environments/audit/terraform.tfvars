# =============================================================================
# Variable values — audit environment
#
# SECURITY NOTE: Replace every <PLACEHOLDER> with the real value before running
# terraform plan/apply. Do NOT commit real account IDs or sensitive values to
# version control — use a secrets manager or CI/CD variable injection instead.
# =============================================================================

# ---------------------------------------------------------------------------
# Provider / backend
# ---------------------------------------------------------------------------

# AWS region where the audit account resources are deployed.
aws_region = "us-east-1"

# Name of the S3 bucket holding all Terraform remote state files.
tf_state_bucket = "<TF_STATE_BUCKET_PLACEHOLDER>"

# Name of the DynamoDB table used for Terraform state locking.
tf_lock_table = "<TF_LOCK_TABLE_PLACEHOLDER>"

# ---------------------------------------------------------------------------
# GuardDuty + Inspector modules — member account IDs
# ---------------------------------------------------------------------------

# All member accounts in the organisation whose findings are aggregated by the
# audit account acting as delegated administrator for GuardDuty and Inspector.
# Obtain account IDs from: aws organizations list-accounts
member_account_ids = [
  "<WORKLOAD_DEV_ACCOUNT_ID_PLACEHOLDER>",     # workload-dev account
  "<WORKLOAD_TEST_ACCOUNT_ID_PLACEHOLDER>",    # workload-test account
  "<WORKLOAD_STAGING_ACCOUNT_ID_PLACEHOLDER>", # workload-staging account
  "<WORKLOAD_PROD_ACCOUNT_ID_PLACEHOLDER>",    # workload-prod account
  "<NETWORK_HUB_ACCOUNT_ID_PLACEHOLDER>",      # network-hub account (Infrastructure OU)
  "<LOGGING_ACCOUNT_ID_PLACEHOLDER>",          # logging account (Security OU)
]

# ---------------------------------------------------------------------------
# GuardDuty module
# ---------------------------------------------------------------------------

# Frequency at which GuardDuty publishes findings to CloudWatch Events.
# ONE_HOUR is the recommended default balancing alerting latency vs cost.
finding_publishing_frequency = "ONE_HOUR"

# ARN of the SNS topic for high-severity GuardDuty finding alerts (→ on-call).
# Obtain from: aws sns list-topics --region us-east-1
sns_topic_arn = "<SNS_TOPIC_ARN_PLACEHOLDER>"
