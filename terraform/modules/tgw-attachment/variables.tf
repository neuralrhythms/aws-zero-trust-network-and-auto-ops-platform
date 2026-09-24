variable "transit_gateway_id" {
  description = "The ID of the Transit Gateway to attach the spoke VPC to."
  type        = string
}

variable "vpc_id" {
  description = "The ID of the spoke VPC being attached to the Transit Gateway."
  type        = string
}

variable "tgw_attach_subnet_ids" {
  description = "Subnet IDs in the dedicated /28 tgw-attach tier. One subnet per Availability Zone is recommended to support symmetric routing through the Network Firewall inspection VPC."
  type        = list(string)
}

variable "transit_gateway_route_table_id" {
  description = "The ID of the TGW route table to associate this attachment with. Separate route tables for spoke VPCs and the inspection VPC enforce symmetric routing."
  type        = string
}
