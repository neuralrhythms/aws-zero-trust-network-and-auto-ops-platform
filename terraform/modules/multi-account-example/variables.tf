# =============================================================================
# Variables — Multi-Account Example Module
# =============================================================================

# --- Remote state / cross-account wiring ---

variable "network_hub_state_bucket" {
  description = "Name of the S3 bucket that stores the Network-Hub Terraform state file. Used by the terraform_remote_state data source to read shared outputs (TGW ID, route table IDs)."
  type        = string
}

variable "aws_region" {
  description = "AWS region in which the Network-Hub Terraform state S3 bucket resides and where resources are deployed."
  type        = string
}

# --- VPC / networking ---

variable "vpc_id" {
  description = "ID of the workload VPC to be attached to the Transit Gateway."
  type        = string
}

variable "tgw_attach_subnet_ids" {
  description = "List of subnet IDs in the tgw-attach tier (/28 per AZ) used for the Transit Gateway VPC attachment."
  type        = list(string)
}

variable "transit_gateway_route_table_id" {
  description = "ID of the Transit Gateway route table to associate with this spoke VPC attachment. Overrides the remote-state value when an explicit route table is required."
  type        = string
  default     = null
}

# --- EKS cluster ---

variable "cluster_name" {
  description = "Name of the EKS cluster. Must be unique within the AWS account and region."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to deploy on the EKS control plane (e.g. '1.29')."
  type        = string
  default     = "1.29"
}

variable "node_subnet_ids" {
  description = "List of subnet IDs (app-private tier) where EKS managed node group EC2 instances are launched."
  type        = list(string)
}

variable "linux_instance_types" {
  description = "List of EC2 instance types for the Linux (Amazon Linux 2) managed node group. Supplied via terraform.tfvars; no instance type strings appear in main.tf."
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

variable "windows_instance_types" {
  description = "List of EC2 instance types for the Windows Server 2019 managed node group. Supplied via terraform.tfvars; no instance type strings appear in main.tf."
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

# --- ECR ---

variable "ecr_repository_names" {
  description = "List of ECR repository names to create in this workload account. Repositories are created with immutable tags and scan-on-push enabled."
  type        = list(string)
}

# --- Security (GuardDuty + Inspector — delegated from audit account) ---

variable "member_account_ids" {
  description = "List of AWS account IDs to enrol as member accounts in GuardDuty and Inspector organisation configurations. Managed from the audit account (Security OU) as delegated administrator."
  type        = list(string)
}

variable "finding_publishing_frequency" {
  description = "Frequency at which GuardDuty publishes updated findings to the audit aggregation account. Valid values: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  type        = string
  default     = "SIX_HOURS"
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic that receives high-severity GuardDuty findings for on-call alerting."
  type        = string
}
