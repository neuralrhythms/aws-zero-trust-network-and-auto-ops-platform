output "attachment_id" {
  description = "The ID of the Transit Gateway VPC attachment. Consumed by workload environments and the network-hub environment to reference the attachment in route table propagations and monitoring."
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}
