# ============================================================
# Input variables for the eks-cluster module.
# All instance type values are supplied by callers via
# terraform.tfvars — they must never be hardcoded here.
# ============================================================

variable "cluster_name" {
  description = "Name of the EKS cluster. Used as the identifier in the AWS console and in kubeconfig."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to deploy (e.g. \"1.29\"). Must be a version supported by Amazon EKS."
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "ID of the VPC in which the EKS cluster control plane and node groups will be deployed."
  type        = string
}

variable "node_subnet_ids" {
  description = "List of subnet IDs (app-private tier) into which managed node group instances are launched."
  type        = list(string)
}

# ── Linux node group ─────────────────────────────────────────

variable "linux_instance_types" {
  description = "EC2 instance types for the Linux (AL2) managed node group. Sourced from terraform.tfvars — not hardcoded."
  type        = list(string)
  validation {
    condition     = length(var.linux_instance_types) > 0
    error_message = "At least one Linux instance type must be specified."
  }
}

variable "linux_min_size" {
  description = "Minimum number of nodes in the Linux managed node group."
  type        = number
  default     = 1
}

variable "linux_max_size" {
  description = "Maximum number of nodes in the Linux managed node group."
  type        = number
  default     = 5
}

variable "linux_desired_size" {
  description = "Desired (initial) number of nodes in the Linux managed node group."
  type        = number
  default     = 2
}

# ── Windows node group ────────────────────────────────────────

variable "windows_instance_types" {
  description = "EC2 instance types for the Windows (Server 2019 Core) managed node group. Sourced from terraform.tfvars — not hardcoded."
  type        = list(string)
  validation {
    condition     = length(var.windows_instance_types) > 0
    error_message = "At least one Windows instance type must be specified."
  }
}

variable "windows_min_size" {
  description = "Minimum number of nodes in the Windows managed node group."
  type        = number
  default     = 1
}

variable "windows_max_size" {
  description = "Maximum number of nodes in the Windows managed node group."
  type        = number
  default     = 3
}

variable "windows_desired_size" {
  description = "Desired (initial) number of nodes in the Windows managed node group."
  type        = number
  default     = 1
}
