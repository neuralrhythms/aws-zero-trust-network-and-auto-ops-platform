# =============================================================================
# Variable values — management environment
#
# SECURITY NOTE: Replace every <PLACEHOLDER> with the real value before running
# terraform plan/apply. Do NOT commit real account IDs or sensitive values to
# version control — use a secrets manager or CI/CD variable injection instead.
# =============================================================================

# ---------------------------------------------------------------------------
# Provider / backend
# ---------------------------------------------------------------------------

# AWS region where the management account resources are deployed.
aws_region = "us-east-1"

# Name of the S3 bucket holding all Terraform remote state files.
# Pattern: <org-prefix>-tf-state-management
tf_state_bucket = "<TF_STATE_BUCKET_PLACEHOLDER>"

# Name of the DynamoDB table used for Terraform state locking.
tf_lock_table = "<TF_LOCK_TABLE_PLACEHOLDER>"

# ---------------------------------------------------------------------------
# SCP Policies module
# ---------------------------------------------------------------------------

# The OU ID to which the SCPs are attached.
# Obtain from: aws organizations list-organizational-units-for-parent
# Format: ou-xxxx-yyyyyyyy
target_ou_id = "<TARGET_OU_ID_PLACEHOLDER>"

# The 12-digit account ID of the AWS Organizations management (root) account.
management_account_id = "<MANAGEMENT_ACCOUNT_ID_PLACEHOLDER>"
