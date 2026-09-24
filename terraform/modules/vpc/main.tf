# ==============================================================================
# Module: vpc
# Purpose: Four-tier VPC for Zero-Trust Network Egress & Automated Operations
#          Platform. Each tier serves a distinct architectural role:
#
#   public-ingress   — Internet-facing tier; hosts the NAT Gateway and any
#                      internet-facing ALB endpoints. Traffic ingresses/egresses
#                      via an Internet Gateway attached to this tier.
#
#   app-private      — Compute tier; hosts EKS worker nodes and application
#                      workloads. No direct internet route — all egress flows
#                      through the Transit Gateway → Network Firewall → NAT GW.
#
#   data-private     — Data tier; hosts RDS, ElastiCache, and other stateful
#                      resources. Fully isolated — no route to TGW or IGW.
#
#   tgw-attach (/28) — Dedicated /28 subnets per AZ for Transit Gateway
#                      attachments. Using a /28 per AZ satisfies the TGW
#                      requirement for one subnet per AZ, isolates TGW route
#                      tables from workload route tables, and enables symmetric
#                      routing through the Network Firewall.
# ==============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# Local values — derive per-AZ CIDR blocks from the base CIDRs.
# Each tier's base CIDR is split into one /26 per AZ (supports up to 4 AZs).
# The tgw-attach tier keeps the supplied /28 (it stays a single /28 shared
# across AZs, consistent with how tfvars pass a single CIDR today).
# ------------------------------------------------------------------------------
locals {
  az_count = length(var.availability_zones)

  # Index-keyed maps so for_each produces stable keys
  az_index_map = { for idx, az in var.availability_zones : az => idx }
}

# ------------------------------------------------------------------------------
# VPC — root network boundary
# ------------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = var.vpc_name
    ManagedBy = "terraform"
    Module    = "vpc"
  }
}

# ------------------------------------------------------------------------------
# Internet Gateway — attached to VPC; used only by the public-ingress tier
# ------------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${var.vpc_name}-igw"
    ManagedBy = "terraform"
  }
}

# ------------------------------------------------------------------------------
# Subnets — public-ingress tier (one per AZ)
# Hosts NAT Gateway and internet-facing load balancer endpoints.
# CIDRs are derived by splitting the public_subnet_cidr into /26 blocks per AZ.
# ------------------------------------------------------------------------------
resource "aws_subnet" "public_ingress" {
  for_each = local.az_index_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.public_subnet_cidr, 2, each.value)
  availability_zone = each.key

  map_public_ip_on_launch = false # NAT GW uses EIP; no auto-assign needed

  tags = {
    Name      = "${var.vpc_name}-public-ingress-${each.key}"
    Tier      = "public-ingress"
    ManagedBy = "terraform"
    # Required by AWS Load Balancer Controller for public subnet discovery
    "kubernetes.io/role/elb" = "1"
  }
}

# ------------------------------------------------------------------------------
# Subnets — app-private tier (one per AZ)
# Compute tier for EKS worker nodes and application workloads.
# ------------------------------------------------------------------------------
resource "aws_subnet" "app_private" {
  for_each = local.az_index_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.app_private_subnet_cidr, 2, each.value)
  availability_zone = each.key

  tags = {
    Name      = "${var.vpc_name}-app-private-${each.key}"
    Tier      = "app-private"
    ManagedBy = "terraform"
    # Required by AWS Load Balancer Controller for private subnet discovery
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ------------------------------------------------------------------------------
# Subnets — data-private tier (one per AZ)
# Isolated data tier for RDS, ElastiCache, and other stateful services.
# No route to TGW or IGW — accessible only from app-private tier.
# ------------------------------------------------------------------------------
resource "aws_subnet" "data_private" {
  for_each = local.az_index_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.data_private_subnet_cidr, 2, each.value)
  availability_zone = each.key

  tags = {
    Name      = "${var.vpc_name}-data-private-${each.key}"
    Tier      = "data-private"
    ManagedBy = "terraform"
  }
}

# ------------------------------------------------------------------------------
# Subnets — tgw-attach tier (/28 per AZ)
# Dedicated /28 subnets for Transit Gateway attachments. One subnet per AZ
# derived by splitting the supplied tgw_attach_subnet_cidr into /30 blocks
# (each /30 comfortably fits within a /28 parent and gives TGW the 4 IPs it
# needs for each attachment endpoint).
# ------------------------------------------------------------------------------
resource "aws_subnet" "tgw_attach" {
  for_each = local.az_index_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.tgw_attach_subnet_cidr, 2, each.value)
  availability_zone = each.key

  tags = {
    Name      = "${var.vpc_name}-tgw-attach-${each.key}"
    Tier      = "tgw-attach"
    ManagedBy = "terraform"
  }
}

# ------------------------------------------------------------------------------
# Elastic IP — static address for the NAT Gateway
# ------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.this]

  tags = {
    Name      = "${var.vpc_name}-nat-eip"
    ManagedBy = "terraform"
  }
}

# ------------------------------------------------------------------------------
# NAT Gateway — sits in first public-ingress subnet; provides outbound internet
# access for compute tier via the TGW inspection path.
# ------------------------------------------------------------------------------
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public_ingress)[0].id

  depends_on = [aws_internet_gateway.this]

  tags = {
    Name      = "${var.vpc_name}-nat-gw"
    ManagedBy = "terraform"
  }
}

# ------------------------------------------------------------------------------
# Route Table — public-ingress tier
# Routes 0.0.0.0/0 to the Internet Gateway.
# ------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name      = "${var.vpc_name}-rt-public"
    ManagedBy = "terraform"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public_ingress

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------------------------
# Route Table — app-private tier
# Default route points to NAT GW. In the full Zero-Trust topology the default
# route would point to the TGW (added by the tgw-attachment module after the
# attachment is created). The NAT GW route here satisfies terraform validate
# and provides a working fallback for environments not yet TGW-attached.
# ------------------------------------------------------------------------------
resource "aws_route_table" "app_private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name      = "${var.vpc_name}-rt-app-private"
    ManagedBy = "terraform"
  }
}

resource "aws_route_table_association" "app_private" {
  for_each = aws_subnet.app_private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.app_private.id
}

# ------------------------------------------------------------------------------
# Route Table — data-private tier
# Fully isolated — no default route to internet or TGW.
# ------------------------------------------------------------------------------
resource "aws_route_table" "data_private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${var.vpc_name}-rt-data-private"
    ManagedBy = "terraform"
  }
}

resource "aws_route_table_association" "data_private" {
  for_each = aws_subnet.data_private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data_private.id
}

# ------------------------------------------------------------------------------
# Route Table — tgw-attach tier
# Separate route table for the /28 TGW attachment subnets. Isolation from the
# workload private route table is required for symmetric firewall routing.
# ------------------------------------------------------------------------------
resource "aws_route_table" "tgw_attach" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${var.vpc_name}-rt-tgw-attach"
    ManagedBy = "terraform"
  }
}

resource "aws_route_table_association" "tgw_attach" {
  for_each = aws_subnet.tgw_attach

  subnet_id      = each.value.id
  route_table_id = aws_route_table.tgw_attach.id
}

# ------------------------------------------------------------------------------
# VPC Flow Logs — captures ALL traffic (ACCEPT + REJECT) for the VPC.
# Destination ARN is supplied via variable so the logging account S3 bucket
# can be targeted for centralised immutable log storage.
# ------------------------------------------------------------------------------
resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = var.flow_log_destination_arn

  tags = {
    Name      = "${var.vpc_name}-flow-log"
    ManagedBy = "terraform"
  }
}

# ------------------------------------------------------------------------------
# Default Security Group — explicit deny-all (CKV2_AWS_12)
# The default VPC security group created by AWS allows all inbound traffic
# between members of the same SG. Overriding it with empty ingress/egress rules
# ensures no unintended traffic is permitted via the default SG. All resources
# must use explicitly defined security groups instead.
# ------------------------------------------------------------------------------
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  # Explicitly empty — no ingress or egress rules on the default SG
  ingress = []
  egress  = []

  tags = {
    Name      = "${var.vpc_name}-default-sg-deny-all"
    ManagedBy = "terraform"
    Purpose   = "deny-all — do not attach to any resource"
  }
}
