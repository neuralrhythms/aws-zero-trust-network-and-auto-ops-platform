# -----------------------------------------------------------------------------
# Module: ecr
# Purpose: Create ECR repositories with immutable image tags, scan-on-push
#          enabled, KMS encryption at rest, and a lifecycle policy that expires
#          untagged images after 30 days. Instantiated from workload environment
#          root modules.
#
# CKV_AWS_136: KMS encryption is applied via a dedicated aws_kms_key resource
#              when var.create_kms_key = true (default). An existing key ARN can
#              be supplied via var.kms_key_arn instead.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "ecr" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for ECR repository encryption — ${var.repository_names[0]}-family"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # CKV2_AWS_64 — explicit key policy granting the account root full access
  # and allowing ECR service to use the key for encryption operations.
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
        Sid    = "AllowECRService"
        Effect = "Allow"
        Principal = {
          Service = "ecr.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Module    = "ecr"
    ManagedBy = "terraform"
  }
}

resource "aws_kms_alias" "ecr" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/ecr-${var.repository_names[0]}"
  target_key_id = aws_kms_key.ecr[0].key_id
}

locals {
  # Resolve the KMS key ARN: use the created key, fall back to supplied ARN,
  # fall back to null (AWS-managed key) if neither is provided.
  kms_key_arn = var.create_kms_key ? aws_kms_key.ecr[0].arn : (
    var.kms_key_arn != "" ? var.kms_key_arn : null
  )
}

resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repository_names)
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = local.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = local.kms_key_arn
  }

  tags = {
    Module    = "ecr"
    ManagedBy = "terraform"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images older than 30 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}
