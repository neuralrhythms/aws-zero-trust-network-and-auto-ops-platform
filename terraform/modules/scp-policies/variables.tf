variable "target_ou_id" {
  description = "The ID of the AWS Organizations OU to which the SCPs are attached (e.g. ou-xxxx-yyyyyyyy). For multi-OU attachment, instantiate this module once per target OU."
  type        = string
}

variable "management_account_id" {
  description = "The AWS account ID of the Organizations management (root) account. Used to scope policy attachment and to ensure the management account is never the target of restrictive SCPs inadvertently."
  type        = string
}
