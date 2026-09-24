################################################################################
# Variables — network-hub environment
#
# All values are supplied via terraform.tfvars or -var flags.
# No account IDs, region strings, or instance type strings are hardcoded here.
# REQ-5.5, REQ-9.4
################################################################################

# ------------------------------------------------------------------------------
# Backend / provider
# ------------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region in which all network-hub resources are deployed (e.g. 'us-east-1'). Supplied via terraform.tfvars."
  type        = string

  validation {
    condition     = length(var.aws_region) > 0
    error_message = "aws_region must not be empty."
  }
}

variable "tf_state_bucket" {
  description = "Name of the S3 bucket used for Terraform remote state storage. Referenced in backend.tf partial configuration documentation."
  type        = string
}

variable "tf_lock_table" {
  description = "Name of the DynamoDB table used for Terraform state locking. Referenced in backend.tf partial configuration documentation."
  type        = string
}

# ------------------------------------------------------------------------------
# VPC
# ------------------------------------------------------------------------------

variable "vpc_name" {
  description = "Name tag applied to the hub VPC and all derived resources (subnets, route tables, gateways)."
  type        = string
}

variable "vpc_cidr" {
  description = "Primary IPv4 CIDR block for the network-hub VPC. Must be an RFC 1918 range (e.g. '10.0.0.0/16')."
  type        = string
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR block for the public-ingress subnet tier. Hosts the NAT Gateway and internet-facing load balancers."
  type        = string
}

variable "app_private_subnet_cidr" {
  description = "IPv4 CIDR block for the app-private subnet tier. Hosts the Network Firewall endpoint and application workloads."
  type        = string
}

variable "data_private_subnet_cidr" {
  description = "IPv4 CIDR block for the data-private subnet tier. Reserved for stateful services (RDS, ElastiCache) in hub accounts."
  type        = string
}

variable "tgw_attach_subnet_cidr" {
  description = "IPv4 CIDR block for the tgw-attach subnet tier. Must be a /28 per AZ to satisfy TGW attachment requirements and support symmetric firewall routing (ADR-001)."
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zone names in the target region (e.g. ['us-east-1a', 'us-east-1b']). One subnet per tier per AZ is created."
  type        = list(string)
}

variable "flow_log_destination_arn" {
  description = "ARN of the destination for VPC Flow Logs. Accepts an S3 bucket ARN in the logging account (immutable archive) or a CloudWatch Logs group ARN."
  type        = string
}

# ------------------------------------------------------------------------------
# Transit Gateway
# ------------------------------------------------------------------------------

variable "transit_gateway_id" {
  description = "ID of the AWS Transit Gateway that the network-hub VPC attaches to. The TGW is owned by this account (network-hub)."
  type        = string
}

variable "transit_gateway_route_table_id" {
  description = "ID of the TGW route table used for the inspection VPC attachment. Enforces symmetric routing through the Network Firewall (ingress and egress traverse the same endpoint)."
  type        = string
}

variable "spoke_route_table_id" {
  description = "ID of the TGW route table used for spoke VPC attachments. Workload environments read this value from network-hub remote state to associate their TGW attachments."
  type        = string
}

variable "inspection_route_table_id" {
  description = "ID of the TGW route table for the inspection/firewall path. Exported as an output so workload environments can reference it via terraform_remote_state."
  type        = string
}

# ------------------------------------------------------------------------------
# Network Firewall
# ------------------------------------------------------------------------------

variable "firewall_name" {
  description = "Name for the AWS Network Firewall resource and its associated firewall policy."
  type        = string
}

variable "firewall_subnet_id" {
  description = "ID of the specific subnet (within the app-private tier) where the Network Firewall endpoint will be placed."
  type        = string
}

variable "allowed_domains" {
  description = "List of allowed FQDNs for egress inspection (e.g. '*.amazonaws.com', '*.github.com'). All other HTTP/HTTPS destinations are blocked by the default deny policy."
  type        = list(string)
}

variable "rule_group_name" {
  description = "Name for the stateful FQDN domain-list rule group attached to the Network Firewall policy."
  type        = string
}

variable "rule_group_capacity" {
  description = "Capacity units for the stateful rule group. Each FQDN rule consumes 1 unit; set to at least the number of entries in allowed_domains."
  type        = number
}
