variable "member_account_ids" {
  description = "List of AWS account IDs that are members of the GuardDuty organisation. Used to scope delegated-admin operations."
  type        = list(string)

  validation {
    condition     = length(var.member_account_ids) > 0
    error_message = "At least one member account ID must be provided."
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
