# -----------------------------------------------------------------------------
# Variables — inspector module
# -----------------------------------------------------------------------------

variable "member_account_ids" {
  description = "List of AWS account IDs (member accounts) to associate with the Inspector v2 delegated-admin (audit) account. Each account will receive auto-enabled EC2, ECR, and Lambda scanning."
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
