# =============================================================================
# terraform.tfvars — workload-staging environment
#
# Environment-differentiated values for the staging workload account.
# KEY DIFFERENCE from workload-dev and workload-test: instance types are
# upgraded to the m6i family (production-grade compute) to validate workloads
# against realistic production sizing before promotion to workload-prod (REQ-5.4).
#
#   dev/test  → t3.large (Linux)  / t3.xlarge (Windows)
#   staging   → m6i.large (Linux) / m6i.xlarge (Windows)   ← this file
#   prod      → m6i.xlarge (Linux) / m6i.2xlarge (Windows)
#
# IMPORTANT: Values marked <PLACEHOLDER> must be replaced with real values
# before deployment. AWS account IDs and Splunk tokens must NEVER be committed
# to source control — use environment variables or a secrets manager integration
# at CI/CD time (REQ-9.4).
# =============================================================================

# ── Provider & backend ────────────────────────────────────────────────────────

aws_region               = "eu-west-1"
tf_state_bucket          = "<PLACEHOLDER: workload-staging-tf-state-bucket>"
tf_lock_table            = "<PLACEHOLDER: terraform-state-lock>"
network_hub_state_bucket = "<PLACEHOLDER: network-hub-tf-state-bucket>"

# ── VPC networking ────────────────────────────────────────────────────────────
# workload-staging uses the 10.3.0.0/16 address space.
# Address space allocation:
#   10.0.0.0/16 — network-hub
#   10.1.0.0/16 — workload-dev
#   10.2.0.0/16 — workload-test
#   10.3.0.0/16 — workload-staging   ← this environment
#   10.4.0.0/16 — workload-prod
# Ensure this does not overlap with any other VPC in the organisation.

vpc_cidr                 = "10.3.0.0/16"
public_subnet_cidr       = "10.3.0.0/24"
app_private_subnet_cidr  = "10.3.1.0/24"
data_private_subnet_cidr = "10.3.2.0/24"
tgw_attach_subnet_cidr   = "10.3.3.0/28"
availability_zones       = ["eu-west-1a", "eu-west-1b"]

# Flow logs ship to the immutable S3 archive in the logging account (Security OU).
flow_log_destination_arn = "<PLACEHOLDER: arn:aws:s3:::logging-account-flow-logs>"

# ── EKS cluster ───────────────────────────────────────────────────────────────

cluster_name    = "workload-staging-eks"
cluster_version = "1.29"

# ── Linux node group — staging uses m6i.large (production-grade uplift) ───────

linux_instance_types = ["m6i.large"]
linux_min_size       = 2
linux_max_size       = 6
linux_desired_size   = 2

# ── Windows node group — staging uses m6i.xlarge (production-grade uplift) ───

windows_instance_types = ["m6i.xlarge"]
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
