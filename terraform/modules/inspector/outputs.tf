# -----------------------------------------------------------------------------
# Outputs — inspector module
# -----------------------------------------------------------------------------

output "organization_configuration_status" {
  description = "The auto-enable status of the Inspector v2 organisation configuration. Reflects whether EC2, ECR, and Lambda auto-enablement is active for new member accounts joining the organisation."
  value = {
    ec2    = aws_inspector2_organization_configuration.this.auto_enable[0].ec2
    ecr    = aws_inspector2_organization_configuration.this.auto_enable[0].ecr
    lambda = aws_inspector2_organization_configuration.this.auto_enable[0].lambda
  }
}

output "audit_account_id" {
  description = "The AWS account ID of the delegated administrator (audit account) running this module."
  value       = data.aws_caller_identity.current.account_id
}

output "associated_member_account_ids" {
  description = "The set of member account IDs that have been associated with the Inspector v2 delegated admin."
  value       = toset(var.member_account_ids)
}
