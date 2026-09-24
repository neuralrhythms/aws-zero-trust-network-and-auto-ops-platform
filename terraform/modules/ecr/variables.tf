variable "repository_names" {
  description = "List of ECR repository names to create. Each repository will have immutable tags, scan-on-push, KMS encryption, and a 30-day untagged image expiry policy."
  type        = list(string)

  validation {
    condition     = length(var.repository_names) > 0
    error_message = "At least one repository name must be provided."
  }
}

variable "create_kms_key" {
  description = "When true (default), a dedicated AWS KMS key is created for ECR repository encryption. Set to false and supply kms_key_arn to use an existing key."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to use for ECR encryption. Only used when create_kms_key = false. Leave empty to fall back to AES256 (not recommended for production)."
  type        = string
  default     = ""
}
