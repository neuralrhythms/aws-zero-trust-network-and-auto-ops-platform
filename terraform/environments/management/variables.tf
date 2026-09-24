# =============================================================================
# Variables — management environment
#
# All sensitive or environment-specific values (account IDs, bucket names,
# region) are supplied via terraform.tfvars or -var flags at plan/apply time.
# No hardcoded account IDs, region strings, or instance types appear here
# (REQ-5.5, REQ-9.4).
# =============================================================================

# ---------------------------------------------------------------------------
# Backend / provider
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region in which this environment is deployed (e.g. us-east-1)."
  type        = string

  validation {
    condition     = length(var.aws_region) > 0
    error_message = "aws_region must be a non-empty string."
  }
}

variable "tf_state_bucket" {
  description = "Name of the S3 bucket used to store Terraform remote state for all environments."
  type        = string

  validation {
    condition     = length(var.tf_state_bucket) > 0
    error_message = "tf_state_bucket must be a non-empty string."
  }
}

variable "tf_lock_table" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  type        = string

  validation {
    condition     = length(var.tf_lock_table) > 0
    error_message = "tf_lock_table must be a non-empty string."
  }
}

# ---------------------------------------------------------------------------
# SCP Policies module inputs
# ---------------------------------------------------------------------------

variable "target_ou_id" {
  description = "The ID of the AWS Organizations OU to which the SCPs are attached (e.g. ou-xxxx-yyyyyyyy). Instantiate the scp-policies module once per additional target OU."
  type        = string

  validation {
    condition     = can(regex("^ou-[a-z0-9]+-[a-z0-9]+$", var.target_ou_id))
    error_message = "target_ou_id must be a valid AWS Organizations OU ID in the format ou-xxxx-yyyyyyyy."
  }
}

variable "management_account_id" {
  description = "The 12-digit AWS account ID of the Organizations management (root) account. Used to scope SCP attachment and prevent the management account from being inadvertently restricted."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}
