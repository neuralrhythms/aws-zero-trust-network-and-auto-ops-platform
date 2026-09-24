################################################################################
# Outputs — network-hub environment
#
# These outputs are the primary interface consumed by workload account root
# modules via `data "terraform_remote_state" "network_hub"`. Keys must remain
# stable — renaming an output is a breaking change for all downstream consumers.
#
# REQ-5.2, REQ-9.3
################################################################################

output "transit_gateway_id" {
  description = "ID of the Transit Gateway owned by the network-hub account. Consumed by workload environments to create their TGW attachments."
  value       = var.transit_gateway_id
}

output "spoke_route_table_id" {
  description = "ID of the TGW route table for spoke VPC associations. Workload environments pass this to the tgw-attachment module as transit_gateway_route_table_id."
  value       = var.spoke_route_table_id
}

output "inspection_route_table_id" {
  description = "ID of the TGW route table for the Network Firewall inspection path. Referenced when configuring symmetric routing for the hub VPC."
  value       = var.inspection_route_table_id
}

output "vpc_id" {
  description = "ID of the network-hub VPC."
  value       = module.vpc.vpc_id
}

output "tgw_attach_subnet_ids" {
  description = "List of /28 subnet IDs in the tgw-attach tier of the hub VPC (one per Availability Zone). Used to reference hub attachment subnets."
  value       = module.vpc.tgw_attach_subnet_ids
}

output "firewall_arn" {
  description = "ARN of the AWS Network Firewall deployed in the network-hub VPC."
  value       = module.network_firewall.firewall_arn
}

output "firewall_endpoint_id" {
  description = "VPC endpoint ID of the Network Firewall. Used in route table entries to direct egress traffic through the firewall before reaching the NAT Gateway."
  value       = module.network_firewall.firewall_endpoint_id
}

output "tgw_attachment_id" {
  description = "ID of the hub VPC's Transit Gateway attachment. Used for route table propagations and monitoring."
  value       = module.tgw_attachment.attachment_id
}
