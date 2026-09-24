output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "List of subnet IDs for the public-ingress tier (one per Availability Zone)."
  value       = [for s in aws_subnet.public_ingress : s.id]
}

output "app_private_subnet_ids" {
  description = "List of subnet IDs for the app-private tier (one per Availability Zone). Used as node_subnet_ids for the EKS cluster module."
  value       = [for s in aws_subnet.app_private : s.id]
}

output "data_private_subnet_ids" {
  description = "List of subnet IDs for the data-private tier (one per Availability Zone). Used for RDS subnet groups and ElastiCache subnet groups."
  value       = [for s in aws_subnet.data_private : s.id]
}

output "tgw_attach_subnet_ids" {
  description = "List of /28 subnet IDs for the tgw-attach tier (one per Availability Zone). Passed to the tgw-attachment module as tgw_attach_subnet_ids."
  value       = [for s in aws_subnet.tgw_attach : s.id]
}

output "app_private_route_table_id" {
  description = "ID of the route table associated with the app-private tier. Referenced by the tgw-attachment module to add the TGW default route post-attachment."
  value       = aws_route_table.app_private.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway in the public-ingress tier."
  value       = aws_nat_gateway.this.id
}
