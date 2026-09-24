# =============================================================================
# Variables — logging environment
#
# The logging account (Security OU) hosts the read-only, immutable S3 log
# archive for the entire organisation (CloudTrail org trail, VPC Flow Logs,
# Config snapshots) and a minimal VPC for the Splunk Universal Forwarder EC2
# instance. No workload resources are declared in this account (ADR-008).
#
# All sensitive or environment-specific values are supplied via terraform.tfvars
# or -var flags at plan/apply time. No hardcoded account IDs, region strings,
# or instance types appear here (REQ-5.5, REQ-9.4).
# =============================================================================

# ---------------------------------------------------------------------------
# Backend / provider
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region in which this environment is deployed (e.g. us-east-1)."
  type        = string

  validation {
    condition     = length(var.aws_region) > 0
    error_message = "aws_region must be a non-empty string."
  }
}

variable "tf_state_bucket" {
  description = "Name of the S3 bucket used to store Terraform remote state for all environments."
  type        = string

  validation {
    condition     = length(var.tf_state_bucket) > 0
    error_message = "tf_state_bucket must be a non-empty string."
  }
}

variable "tf_lock_table" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  type        = string

  validation {
    condition     = length(var.tf_lock_table) > 0
    error_message = "tf_lock_table must be a non-empty string."
  }
}

# ---------------------------------------------------------------------------
# Immutable log archive (S3 + Object Lock)
# ---------------------------------------------------------------------------

variable "log_archive_bucket_name" {
  description = "Name of the S3 bucket that serves as the organisation-wide immutable log archive. Must be globally unique."
  type        = string

  validation {
    condition     = length(var.log_archive_bucket_name) >= 3 && length(var.log_archive_bucket_name) <= 63
    error_message = "log_archive_bucket_name must be between 3 and 63 characters."
  }
}

variable "object_lock_retention_days" {
  description = "Number of days log objects are retained under S3 Object Lock COMPLIANCE mode (WORM). Minimum recommended value is 365 for audit compliance."
  type        = number
  default     = 365

  validation {
    condition     = var.object_lock_retention_days >= 1
    error_message = "object_lock_retention_days must be at least 1."
  }
}

# ---------------------------------------------------------------------------
# VPC (minimal — hosts Splunk Universal Forwarder EC2 instance)
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the logging account VPC. Must be an RFC 1918 private address range."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. 10.3.0.0/16)."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public-ingress subnet tier (NAT Gateway, load balancers)."
  type        = string

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid CIDR block."
  }
}

variable "app_private_subnet_cidr" {
  description = "CIDR block for the app-private subnet tier (compute workloads, Splunk UF EC2)."
  type        = string

  validation {
    condition     = can(cidrhost(var.app_private_subnet_cidr, 0))
    error_message = "app_private_subnet_cidr must be a valid CIDR block."
  }
}

variable "data_private_subnet_cidr" {
  description = "CIDR block for the data-private subnet tier (databases, persistent storage)."
  type        = string

  validation {
    condition     = can(cidrhost(var.data_private_subnet_cidr, 0))
    error_message = "data_private_subnet_cidr must be a valid CIDR block."
  }
}

variable "tgw_attach_subnet_cidr" {
  description = "CIDR block for the tgw-attach subnet tier (/28 per AZ). Used for Transit Gateway attachment endpoints to enforce route-table isolation and symmetric firewall routing."
  type        = string

  validation {
    condition     = can(cidrhost(var.tgw_attach_subnet_cidr, 0))
    error_message = "tgw_attach_subnet_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of Availability Zone names in which subnets are created (e.g. [\"us-east-1a\", \"us-east-1b\"])."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 1
    error_message = "At least one availability zone must be specified."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of the S3 bucket or CloudWatch Logs group that receives VPC Flow Logs. Typically points to the log archive bucket in this account."
  type        = string

  validation {
    condition     = length(var.flow_log_destination_arn) > 0
    error_message = "flow_log_destination_arn must be a non-empty string."
  }
}
