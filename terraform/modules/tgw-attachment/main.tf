# ==============================================================================
# Module: tgw-attachment
#
# Purpose: Attaches a spoke VPC to the AWS Transit Gateway and associates the
# attachment with a dedicated TGW route table. The dedicated /28 tgw-attach
# subnet tier (per ADR-001) provides route-table isolation, enforces symmetric
# firewall routing through the Network Firewall inspection VPC, contains the
# blast radius of any misconfiguration to the attachment subnet only, and
# ensures VPC Flow Logs capture all inter-VPC traffic at the attachment point.
# ==============================================================================

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = var.vpc_id
  subnet_ids         = var.tgw_attach_subnet_ids

  tags = {
    Name = "${var.transit_gateway_id}-attachment"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = var.transit_gateway_route_table_id
}
