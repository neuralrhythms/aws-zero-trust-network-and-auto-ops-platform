# =============================================================================
# Outputs — management environment
#
# Exposes the SCP policy IDs created by the scp-policies module so they can
# be referenced by other automation or shared with downstream consumers via
# remote state if required.
# =============================================================================

output "scp_deny_egress_id" {
  description = "Policy ID of the deny-direct-internet-egress SCP applied to the target OU."
  value       = module.scp_policies.scp_deny_egress_id
}

output "scp_deny_ssh_rdp_id" {
  description = "Policy ID of the deny-open-ssh-rdp SCP applied to the target OU."
  value       = module.scp_policies.scp_deny_ssh_rdp_id
}
