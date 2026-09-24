################################################################################
# network-hub environment — root module
#
# This account sits in the Infrastructure OU and owns the hub-and-spoke network:
#   - 4-tier VPC (public-ingress, app-private, data-private, tgw-attach /28)
#   - Transit Gateway attachment + route table association
#   - AWS Network Firewall for centralised egress inspection
#
# Outputs from this root module (transit_gateway_id, spoke_route_table_id,
# inspection_route_table_id) are consumed by workload environments via
# terraform_remote_state data sources.
#
# REQ-5.1, REQ-5.2, REQ-5.3, REQ-5.5
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------------------
# VPC — 4-tier hub network
# ------------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  vpc_name                 = var.vpc_name
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidr       = var.public_subnet_cidr
  app_private_subnet_cidr  = var.app_private_subnet_cidr
  data_private_subnet_cidr = var.data_private_subnet_cidr
  tgw_attach_subnet_cidr   = var.tgw_attach_subnet_cidr
  availability_zones       = var.availability_zones
  flow_log_destination_arn = var.flow_log_destination_arn
}

# ------------------------------------------------------------------------------
# Transit Gateway attachment
# Attaches the network-hub VPC to the TGW and associates with the inspection
# route table so all spoke-bound traffic is inspected by the Network Firewall.
# ------------------------------------------------------------------------------
module "tgw_attachment" {
  source = "../../modules/tgw-attachment"

  transit_gateway_id             = var.transit_gateway_id
  vpc_id                         = module.vpc.vpc_id
  tgw_attach_subnet_ids          = module.vpc.tgw_attach_subnet_ids
  transit_gateway_route_table_id = var.transit_gateway_route_table_id
}

# ------------------------------------------------------------------------------
# Network Firewall — centralised egress inspection
# Deployed in the app-private subnet tier of the hub VPC. All egress from
# spoke VPCs is routed through this firewall before reaching the NAT Gateway.
# firewall_subnet_id is the specific subnet ID in the app-private tier chosen
# for the firewall endpoint.
# ------------------------------------------------------------------------------
module "network_firewall" {
  source = "../../modules/network-firewall"

  firewall_name       = var.firewall_name
  vpc_id              = module.vpc.vpc_id
  firewall_subnet_id  = var.firewall_subnet_id
  allowed_domains     = var.allowed_domains
  rule_group_name     = var.rule_group_name
  rule_group_capacity = var.rule_group_capacity
}
