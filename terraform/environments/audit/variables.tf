# =============================================================================
# Variables — audit environment
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
# GuardDuty + Inspector module inputs
# ---------------------------------------------------------------------------

variable "member_account_ids" {
  description = "List of member AWS account IDs in the organisation. Passed to both GuardDuty and Inspector delegated-admin modules."
  type        = list(string)

  validation {
    condition     = length(var.member_account_ids) > 0
    error_message = "At least one member account ID must be provided."
  }

  validation {
    condition     = alltrue([for id in var.member_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "All member_account_ids must be 12-digit AWS account IDs."
  }
}

variable "finding_publishing_frequency" {
  description = "Frequency at which GuardDuty publishes findings to CloudWatch Events. Valid values: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  type        = string
  default     = "ONE_HOUR"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.finding_publishing_frequency)
    error_message = "finding_publishing_frequency must be one of: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  }
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic that receives high-severity GuardDuty finding alerts for on-call notification."
  type        = string
}
