# =============================================================================
# Input variables — workload-test environment
#
# All values are supplied via terraform.tfvars. No default values reference
# hardcoded account IDs, region strings, or instance type strings (REQ-5.5).
# Sensitive variables (splunk_hec_token) are marked accordingly and must be
# injected from AWS Secrets Manager or a CI/CD secrets store, never committed.
# =============================================================================

# ── Provider & backend ────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region in which all resources for this workload account are deployed (e.g. 'eu-west-1')."
  type        = string
}

variable "tf_state_bucket" {
  description = "Name of the S3 bucket used to store Terraform state for this workload-test environment. Must already exist and have versioning enabled."
  type        = string
}

variable "tf_lock_table" {
  description = "Name of the DynamoDB table used for Terraform state locking. Must already exist with a 'LockID' string hash key."
  type        = string
}

variable "network_hub_state_bucket" {
  description = "Name of the S3 bucket holding the network-hub account's Terraform state. Used by the terraform_remote_state data source to retrieve TGW ID and spoke route table ID."
  type        = string
}

# ── VPC networking ────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "Primary IPv4 CIDR block for the workload-test VPC. Must be an RFC 1918 range and must not overlap with the network-hub or other spoke VPCs."
  type        = string
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR block for the public-ingress subnet tier (Application Load Balancer endpoints)."
  type        = string
}

variable "app_private_subnet_cidr" {
  description = "IPv4 CIDR block for the app-private subnet tier. EKS managed node group instances are launched into this tier."
  type        = string
}

variable "data_private_subnet_cidr" {
  description = "IPv4 CIDR block for the data-private subnet tier (RDS, ElastiCache, and other stateful services)."
  type        = string
}

variable "tgw_attach_subnet_cidr" {
  description = "IPv4 CIDR block for the tgw-attach subnet tier. Must be a /28 per AZ to satisfy the Transit Gateway attachment requirement and support symmetric firewall routing."
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zone names in the target region (e.g. ['eu-west-1a', 'eu-west-1b']). One subnet per tier per AZ is created by the vpc module."
  type        = list(string)
}

variable "flow_log_destination_arn" {
  description = "ARN of the destination for VPC Flow Logs. Should reference the immutable S3 bucket in the logging account to ensure audit trail integrity."
  type        = string
}

# ── EKS cluster ───────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the EKS cluster for this workload-test environment. Also used as the vpc_name tag for derived network resources."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to deploy (e.g. '1.29'). Must be a version currently supported by Amazon EKS."
  type        = string
}

# ── Linux node group ──────────────────────────────────────────────────────────

variable "linux_instance_types" {
  description = "EC2 instance types for the Linux (AL2) managed node group. Sourced from terraform.tfvars — never hardcoded in main.tf or this file (REQ-5.5)."
  type        = list(string)

  validation {
    condition     = length(var.linux_instance_types) > 0
    error_message = "At least one Linux instance type must be specified."
  }
}

variable "linux_min_size" {
  description = "Minimum number of nodes in the Linux managed node group."
  type        = number
}

variable "linux_max_size" {
  description = "Maximum number of nodes in the Linux managed node group."
  type        = number
}

variable "linux_desired_size" {
  description = "Desired (initial) number of nodes in the Linux managed node group."
  type        = number
}

# ── Windows node group ────────────────────────────────────────────────────────

variable "windows_instance_types" {
  description = "EC2 instance types for the Windows (Server 2019 Core) managed node group. Sourced from terraform.tfvars — never hardcoded in main.tf or this file (REQ-5.5)."
  type        = list(string)

  validation {
    condition     = length(var.windows_instance_types) > 0
    error_message = "At least one Windows instance type must be specified."
  }
}

variable "windows_min_size" {
  description = "Minimum number of nodes in the Windows managed node group."
  type        = number
}

variable "windows_max_size" {
  description = "Maximum number of nodes in the Windows managed node group."
  type        = number
}

variable "windows_desired_size" {
  description = "Desired (initial) number of nodes in the Windows managed node group."
  type        = number
}

# ── EKS add-ons ───────────────────────────────────────────────────────────────

variable "splunk_hec_host" {
  description = "Hostname of the Splunk Cloud HTTP Event Collector (HEC) endpoint used by the Fluent Bit DaemonSet to ship container logs (e.g. 'inputs.splunkcloud.com')."
  type        = string
}

variable "splunk_hec_token" {
  description = "Splunk HEC authentication token used by Fluent Bit. Marked sensitive — must be injected from AWS Secrets Manager or a CI/CD secrets store. Never commit a real token."
  type        = string
  sensitive   = true
}

variable "karpenter_node_role_arn" {
  description = "ARN of the IAM role associated with the Karpenter service account via IRSA. Grants Karpenter permissions to provision EC2 node instances on behalf of the EKS cluster."
  type        = string
}

# ── ECR ───────────────────────────────────────────────────────────────────────

variable "ecr_repository_names" {
  description = "List of ECR repository names to create in this workload-test account. Each repository gets immutable tags, scan-on-push, and a 30-day untagged image expiry policy."
  type        = list(string)
}
