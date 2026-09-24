################################################################################
# Module: network-firewall
# Purpose: Deploy AWS Network Firewall with a stateful FQDN domain-list rule
#          group for centralised egress inspection in the network-hub account.
#
# Architecture: Deployed in the network-hub account's app-private subnet.
#   The ALLOWLIST pattern drops all outbound HTTP/HTTPS traffic except for
#   explicitly approved FQDNs (var.allowed_domains). This is the enforcement
#   point for Zero Trust egress control (ADR-002).
#
# Checkov controls addressed:
#   CKV_AWS_344  — deletion_protection = true prevents accidental firewall removal
#   CKV_AWS_345  — encryption_configuration uses a CMK (aws_kms_key.nfw)
#   CKV_AWS_346  — firewall policy encryption_configuration uses the same CMK
#   CKV2_AWS_63  — logging_configuration ships alert and flow logs to S3
################################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# KMS key — Customer Managed Key for Network Firewall encryption (CKV_AWS_345)
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "nfw" {
  description             = "CMK for AWS Network Firewall encryption — ${var.firewall_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # CKV2_AWS_64 — explicit key policy granting account root full access and
  # allowing the Network Firewall service to use the key for encryption.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowNetworkFirewall"
        Effect = "Allow"
        Principal = {
          Service = "network-firewall.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Module    = "network-firewall"
    ManagedBy = "terraform"
  }
}

resource "aws_kms_alias" "nfw" {
  name          = "alias/nfw-${var.firewall_name}"
  target_key_id = aws_kms_key.nfw.key_id
}

# ------------------------------------------------------------------------------
# Stateful rule group — FQDN ALLOWLIST
# ------------------------------------------------------------------------------
resource "aws_networkfirewall_rule_group" "egress_domain_allowlist" {
  name     = var.rule_group_name
  type     = "STATEFUL"
  capacity = var.rule_group_capacity

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets              = var.allowed_domains
      }
    }
  }

  # CKV_AWS_345 — rule group encryption via CMK
  encryption_configuration {
    key_id = aws_kms_key.nfw.arn
    type   = "CUSTOMER_KMS"
  }

  tags = {
    Module    = "network-firewall"
    ManagedBy = "terraform"
  }
}

# ------------------------------------------------------------------------------
# Firewall policy
# ------------------------------------------------------------------------------
resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.firewall_name}-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.egress_domain_allowlist.arn
    }
  }

  # CKV_AWS_346 — policy encryption via CMK
  encryption_configuration {
    key_id = aws_kms_key.nfw.arn
    type   = "CUSTOMER_KMS"
  }

  tags = {
    Module    = "network-firewall"
    ManagedBy = "terraform"
  }
}

# ------------------------------------------------------------------------------
# Network Firewall
# ------------------------------------------------------------------------------
resource "aws_networkfirewall_firewall" "this" {
  name                = var.firewall_name
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  vpc_id              = var.vpc_id

  # CKV_AWS_344 — prevent accidental deletion
  delete_protection = true

  subnet_mapping {
    subnet_id = var.firewall_subnet_id
  }

  # CKV_AWS_345 — firewall encryption via CMK
  encryption_configuration {
    key_id = aws_kms_key.nfw.arn
    type   = "CUSTOMER_KMS"
  }

  tags = {
    Module    = "network-firewall"
    ManagedBy = "terraform"
  }
}

# ------------------------------------------------------------------------------
# Firewall logging configuration (CKV2_AWS_63)
# Ships both ALERT (matched rule hits) and FLOW (all connection metadata) logs
# to the S3 destination supplied via var.log_destination_arn.
# ------------------------------------------------------------------------------
resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    log_destination_config {
      log_destination_type = "S3"
      log_type             = "ALERT"
      log_destination = {
        bucketName = var.log_bucket_name
        prefix     = "network-firewall/alert"
      }
    }

    log_destination_config {
      log_destination_type = "S3"
      log_type             = "FLOW"
      log_destination = {
        bucketName = var.log_bucket_name
        prefix     = "network-firewall/flow"
      }
    }
  }
}
