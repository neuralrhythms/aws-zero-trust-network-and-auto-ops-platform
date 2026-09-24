################################################################################
# Outputs — network-firewall module
################################################################################

output "firewall_arn" {
  description = "ARN of the deployed AWS Network Firewall"
  value       = aws_networkfirewall_firewall.this.arn
}

output "firewall_endpoint_id" {
  description = "VPC endpoint ID for the Network Firewall (used in route tables to direct egress traffic through the firewall)"
  value       = tolist(aws_networkfirewall_firewall.this.firewall_status[0].sync_states)[0].attachment[0].endpoint_id
}
