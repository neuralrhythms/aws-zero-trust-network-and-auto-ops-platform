# =============================================================================
# terraform.tfvars — workload-prod environment
#
# Production account — strictest SCP boundaries apply (deny-direct-internet-egress,
# deny-open-ssh-rdp). All egress routed via network-hub Network Firewall.
#
# Instance types follow the production tier: m6i.* family (REQ-5.4).
# Linux nodes: m6i.xlarge | Windows nodes: m6i.2xlarge
#
# IMPORTANT: Values marked <PLACEHOLDER> must be replaced with real values
# before deployment. AWS account IDs and Splunk tokens must NEVER be committed
# to source control — use environment variables or a secrets manager integration
# at CI/CD time (REQ-9.4).
# =============================================================================

# ── Provider & backend ────────────────────────────────────────────────────────

aws_region               = "eu-west-1"
tf_state_bucket          = "<PLACEHOLDER: workload-prod-tf-state-bucket>"
tf_lock_table            = "<PLACEHOLDER: terraform-state-lock>"
network_hub_state_bucket = "<PLACEHOLDER: network-hub-tf-state-bucket>"

# ── VPC networking ────────────────────────────────────────────────────────────
# workload-prod uses the 10.4.0.0/16 address space.
# Ensure this does not overlap with network-hub (10.0.0.0/16) or other spokes
# (workload-dev: 10.1.0.0/16, workload-test: 10.2.0.0/16, workload-staging: 10.3.0.0/16).

vpc_cidr                 = "10.4.0.0/16"
public_subnet_cidr       = "10.4.0.0/24"
app_private_subnet_cidr  = "10.4.1.0/24"
data_private_subnet_cidr = "10.4.2.0/24"
tgw_attach_subnet_cidr   = "10.4.3.0/28"
availability_zones       = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

# Flow logs ship to the immutable S3 archive in the logging account (Security OU).
flow_log_destination_arn = "<PLACEHOLDER: arn:aws:s3:::logging-account-flow-logs>"

# ── EKS cluster ───────────────────────────────────────────────────────────────

cluster_name    = "workload-prod-eks"
cluster_version = "1.29"

# ── Linux node group — production tier uses m6i.xlarge ───────────────────────

linux_instance_types = ["m6i.xlarge"]
linux_min_size       = 3
linux_max_size       = 20
linux_desired_size   = 6

# ── Windows node group — production tier uses m6i.2xlarge ────────────────────

windows_instance_types = ["m6i.2xlarge"]
windows_min_size       = 2
windows_max_size       = 10
windows_desired_size   = 2

# ── EKS add-ons ───────────────────────────────────────────────────────────────
# splunk_hec_token must be injected from AWS Secrets Manager at deploy time.

splunk_hec_host         = "<PLACEHOLDER: splunk-hec-endpoint>"
splunk_hec_token        = "<PLACEHOLDER: splunk-hec-token>"
karpenter_node_role_arn = "<PLACEHOLDER: arn:aws:iam::ACCOUNT_ID:role/KarpenterNodeRole>"

# ── ECR ───────────────────────────────────────────────────────────────────────

ecr_repository_names = ["app-frontend", "app-backend", "app-worker"]
