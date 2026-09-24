# =============================================================================
# Outputs — audit environment
#
# Exposes identifiers from the GuardDuty and Inspector delegated-admin modules
# so they can be referenced by other automation or shared with downstream
# consumers via remote state if required.
# =============================================================================

output "guardduty_detector_id" {
  description = "The ID of the GuardDuty detector created in the audit (delegated admin) account."
  value       = module.guardduty.detector_id
}

output "guardduty_organization_configuration_id" {
  description = "The ID of the GuardDuty organisation configuration resource, confirming org-wide auto-enable is active across all member accounts."
  value       = module.guardduty.organization_configuration_id
}

output "inspector_organization_configuration_status" {
  description = "The auto-enable status of the Inspector v2 organisation configuration (EC2, ECR, Lambda). Reflects whether auto-enablement is active for new member accounts joining the organisation."
  value       = module.inspector.organization_configuration_status
}
