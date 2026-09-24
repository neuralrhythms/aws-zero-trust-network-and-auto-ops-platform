################################################################################
# terraform.tfvars — network-hub environment
#
# Supplies network-hub-specific values. Sensitive placeholders (account IDs,
# ARNs, resource IDs) must be replaced with real values at deployment time.
# Never commit real account IDs or credentials to version control.
#
# REQ-5.2, REQ-5.4, REQ-9.4
################################################################################

# ------------------------------------------------------------------------------
# Backend / provider
# ------------------------------------------------------------------------------
aws_region      = "<AWS_REGION>"      # e.g. "us-east-1"
tf_state_bucket = "<TF_STATE_BUCKET>" # e.g. "myorg-tf-state-network-hub"
tf_lock_table   = "<TF_LOCK_TABLE>"   # e.g. "myorg-tf-locks"

# ------------------------------------------------------------------------------
# VPC
# ------------------------------------------------------------------------------
vpc_name                 = "network-hub-vpc"
vpc_cidr                 = "10.0.0.0/16"
public_subnet_cidr       = "10.0.0.0/24"
app_private_subnet_cidr  = "10.0.1.0/24"
data_private_subnet_cidr = "10.0.2.0/24"
tgw_attach_subnet_cidr   = "10.0.3.0/28" # /28 required by ADR-001 for TGW attachment + symmetric firewall routing

availability_zones = ["<AZ_1>", "<AZ_2>"] # e.g. ["us-east-1a", "us-east-1b"]

flow_log_destination_arn = "<FLOW_LOG_DESTINATION_ARN>"
# e.g. "arn:aws:s3:::myorg-flow-logs-logging-account" (logging account immutable archive)
# or   "arn:aws:logs:<region>:<account-id>:log-group:/network-hub/vpc-flow-logs"

# ------------------------------------------------------------------------------
# Transit Gateway
# ------------------------------------------------------------------------------
transit_gateway_id             = "<TRANSIT_GATEWAY_ID>"   # e.g. "tgw-0abc1234def56789"
transit_gateway_route_table_id = "<TGW_ROUTE_TABLE_ID>"   # inspection route table
spoke_route_table_id           = "<SPOKE_ROUTE_TABLE_ID>" # consumed by workload environments via remote state
inspection_route_table_id      = "<INSPECTION_ROUTE_TABLE_ID>"

# ------------------------------------------------------------------------------
# Network Firewall
# ------------------------------------------------------------------------------
firewall_name      = "network-hub-egress-firewall"
firewall_subnet_id = "<FIREWALL_SUBNET_ID>"
# Subnet ID within the app-private tier where the firewall endpoint is placed.
# This is one specific subnet ID, not the full list from the vpc module output.

allowed_domains = [
  "*.amazonaws.com",
  "*.github.com",
  # Add additional allowed FQDNs here — all other HTTP/HTTPS egress is denied.
  # Examples: "*.splunkcloud.com", "*.docker.io", "registry.k8s.io"
]

rule_group_name     = "network-hub-egress-allowlist"
rule_group_capacity = 100
