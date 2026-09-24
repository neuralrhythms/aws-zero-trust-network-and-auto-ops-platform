# =============================================================================
# terraform.tfvars — workload-dev environment
#
# Environment-differentiated values for the development workload account.
# Instance types follow the dev/test tier: t3.* family (REQ-5.4).
#
# IMPORTANT: Values marked <PLACEHOLDER> must be replaced with real values
# before deployment. AWS account IDs and Splunk tokens must NEVER be committed
# to source control — use environment variables or a secrets manager integration
# at CI/CD time (REQ-9.4).
# =============================================================================

# ── Provider & backend ────────────────────────────────────────────────────────

aws_region               = "eu-west-1"
tf_state_bucket          = "<PLACEHOLDER: workload-dev-tf-state-bucket>"
tf_lock_table            = "<PLACEHOLDER: terraform-state-lock>"
network_hub_state_bucket = "<PLACEHOLDER: network-hub-tf-state-bucket>"

# ── VPC networking ────────────────────────────────────────────────────────────
# workload-dev uses the 10.1.0.0/16 address space.
# Ensure this does not overlap with network-hub (10.0.0.0/16) or other spokes.

vpc_cidr                 = "10.1.0.0/16"
public_subnet_cidr       = "10.1.0.0/24"
app_private_subnet_cidr  = "10.1.1.0/24"
data_private_subnet_cidr = "10.1.2.0/24"
tgw_attach_subnet_cidr   = "10.1.3.0/28"
availability_zones       = ["eu-west-1a", "eu-west-1b"]

# Flow logs ship to the immutable S3 archive in the logging account (Security OU).
flow_log_destination_arn = "<PLACEHOLDER: arn:aws:s3:::logging-account-flow-logs>"

# ── EKS cluster ───────────────────────────────────────────────────────────────

cluster_name    = "workload-dev-eks"
cluster_version = "1.29"

# ── Linux node group — dev tier uses t3.large ─────────────────────────────────

linux_instance_types = ["t3.large"]
linux_min_size       = 1
linux_max_size       = 5
linux_desired_size   = 2

# ── Windows node group — dev tier uses t3.xlarge ─────────────────────────────

windows_instance_types = ["t3.xlarge"]
windows_min_size       = 1
windows_max_size       = 3
windows_desired_size   = 1

# ── EKS add-ons ───────────────────────────────────────────────────────────────
# splunk_hec_token must be injected from AWS Secrets Manager at deploy time.

splunk_hec_host         = "<PLACEHOLDER: splunk-hec-endpoint>"
splunk_hec_token        = "<PLACEHOLDER: splunk-hec-token>"
karpenter_node_role_arn = "<PLACEHOLDER: arn:aws:iam::ACCOUNT_ID:role/KarpenterNodeRole>"

# ── ECR ───────────────────────────────────────────────────────────────────────

ecr_repository_names = ["app-frontend", "app-backend", "app-worker"]
