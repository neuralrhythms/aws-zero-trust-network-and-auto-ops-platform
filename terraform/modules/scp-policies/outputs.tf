output "scp_deny_egress_id" {
  description = "The policy ID of the deny-direct-internet-egress SCP. Reference this output to attach the policy to additional OUs or to pass the ID to other modules."
  value       = null # Populated when aws_organizations_policy.deny_direct_internet_egress is uncommented in main.tf
}

output "scp_deny_ssh_rdp_id" {
  description = "The policy ID of the deny-open-ssh-rdp SCP. Reference this output to attach the policy to additional OUs or to pass the ID to other modules."
  value       = null # Populated when aws_organizations_policy.deny_open_ssh_rdp is uncommented in main.tf
}
