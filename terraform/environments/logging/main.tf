# =============================================================================
# Environment: logging
# Account role: Security OU — read-only, immutable log archive.
#
# Per ADR-008, the logging account is a dedicated, write-protected repository
# for all organisation logs:
#   - CloudTrail organisation trail target
#   - VPC Flow Logs from all spoke accounts
#   - AWS Config snapshots and history
#   - Application logs ingested by the Splunk S3 Add-on
#
# S3 Object Lock (COMPLIANCE mode) enforces WORM immutability so that no
# account — including the logging account itself — can delete or modify
# archived log objects within the retention window. This separation from the
# `audit` account ensures log integrity is independent of security tooling
# access (ADR-008).
#
# The `audit` account has read-only access to this bucket (cross-account
# bucket policy applied outside this Terraform root module — managed by the
# management account's AWS Organizations configuration).
#
# A minimal VPC is also provisioned to host the Splunk Universal Forwarder
# EC2 instance that ships logs from the log archive bucket to Splunk Cloud HEC.
#
# This environment instantiates only logging-account resources. No workload
# resources (EKS, ECR, GuardDuty delegated admin) are declared here (REQ-5.3).
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Minimal VPC — hosts the Splunk Universal Forwarder EC2 instance (ADR-004)
# Only the subset of subnets needed for a single-purpose forwarder host is
# required. All CIDR values come from terraform.tfvars — no hardcoded strings.
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  vpc_name                 = "logging"
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidr       = var.public_subnet_cidr
  app_private_subnet_cidr  = var.app_private_subnet_cidr
  data_private_subnet_cidr = var.data_private_subnet_cidr
  tgw_attach_subnet_cidr   = var.tgw_attach_subnet_cidr
  availability_zones       = var.availability_zones
  flow_log_destination_arn = var.flow_log_destination_arn
}

# ---------------------------------------------------------------------------
# Immutable log archive bucket (ADR-008)
# Object Lock must be enabled at bucket creation time — it cannot be added
# afterwards. The COMPLIANCE mode retention period prevents object deletion
# by any principal, including root, during the retention window.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "log_archive" {
  bucket = var.log_archive_bucket_name

  # Object Lock requires object_lock_enabled = true at creation time.
  # The default_retention is set separately in the object_lock_configuration
  # resource below so the retention period can be managed as a variable.
  object_lock_enabled = true

  tags = {
    Name        = var.log_archive_bucket_name
    Environment = "logging"
    Purpose     = "immutable-log-archive"
    OU          = "Security"
  }
}

# Versioning is a prerequisite for S3 Object Lock. Objects must be versioned
# so that Object Lock can pin a specific version against deletion.
resource "aws_s3_bucket_versioning" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access to the log archive bucket — logs must never be
# publicly readable. All access is via IAM policies or cross-account
# bucket policies only.
resource "aws_s3_bucket_public_access_block" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enforce server-side encryption using AWS-managed keys. All log objects
# written to this bucket are encrypted at rest (REQ-9.4, KMS can be
# substituted for SSE-S3 by replacing the sse_algorithm below).
resource "aws_s3_bucket_server_side_encryption_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Object Lock configuration — COMPLIANCE mode retention.
# COMPLIANCE mode: no user (including root) can shorten the retention period
# or delete an object version until the retention period expires.
# WORM (Write Once, Read Many) immutability is the logging account's primary
# security control (ADR-008, REQ-5.3).
resource "aws_s3_bucket_object_lock_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.log_archive]
}

# ---------------------------------------------------------------------------
# S3 Access Logging bucket (CKV_AWS_18)
# A separate bucket receives server access logs for the log archive bucket.
# The access logging bucket itself uses AES256 (SSE-S3) as it holds only
# HTTP access metadata, not sensitive log data.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "log_archive_access_logs" {
  bucket = "${var.log_archive_bucket_name}-access-logs"

  tags = {
    Name        = "${var.log_archive_bucket_name}-access-logs"
    Environment = "logging"
    Purpose     = "s3-access-logs-for-log-archive"
  }
}

resource "aws_s3_bucket_public_access_block" "log_archive_access_logs" {
  bucket = aws_s3_bucket.log_archive_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "log_archive_access_logs" {
  bucket = aws_s3_bucket.log_archive_access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_archive_access_logs" {
  bucket = aws_s3_bucket.log_archive_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  target_bucket = aws_s3_bucket.log_archive_access_logs.id
  target_prefix = "access-logs/"
}

# Lifecycle configuration for the access-logs bucket (CKV2_AWS_61)
# Access logs don't need long-term retention — transition to IA after 30 days
# and expire after 90 days to control costs.
resource "aws_s3_bucket_lifecycle_configuration" "log_archive_access_logs" {
  bucket = aws_s3_bucket.log_archive_access_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.log_archive_access_logs]
}

# ---------------------------------------------------------------------------
# S3 Lifecycle policy for log archive bucket (CKV2_AWS_61)
# Transitions objects to cheaper storage tiers after the active retention
# window and expires incomplete multipart uploads. The Object Lock COMPLIANCE
# retention period takes precedence — lifecycle expiry only runs after lock
# expiry. Transitions are cost-optimisation; they do not affect compliance.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "log_archive" {
  bucket = aws_s3_bucket.log_archive.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    transition {
      days          = 2555
      storage_class = "DEEP_ARCHIVE"
    }

    # Abort incomplete multipart uploads after 7 days to prevent orphaned parts
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.log_archive]
}
