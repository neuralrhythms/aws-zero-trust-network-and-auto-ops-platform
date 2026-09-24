# =============================================================================
# Module: guardduty
# Purpose: Enables Amazon GuardDuty organisation-wide with all required
#          protection plans. Intended to be applied from the audit account
#          acting as the GuardDuty delegated administrator.
#
# Protection plans enabled:
#   - S3 Data Events
#   - EKS Audit Logs (Kubernetes)
#   - EC2 Malware Protection (EBS volumes)
#   - RDS Login Activity
# =============================================================================

# ---------------------------------------------------------------------------
# GuardDuty detector — must be enabled in the delegated admin (audit) account
# ---------------------------------------------------------------------------
resource "aws_guardduty_detector" "this" {
  enable = true

  finding_publishing_frequency = var.finding_publishing_frequency

  datasources {
    s3_logs {
      enable = true
    }

    kubernetes {
      audit_logs {
        enable = true
      }
    }

    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Organisation-wide configuration — auto-enables GuardDuty for all member
# accounts that join the organisation now or in the future.
# ---------------------------------------------------------------------------
resource "aws_guardduty_organization_configuration" "this" {
  auto_enable_organization_members = "ALL"
  detector_id                      = aws_guardduty_detector.this.id

  datasources {
    s3_logs {
      auto_enable = true
    }

    kubernetes {
      audit_logs {
        enable = true
      }
    }

    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = true
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# RDS Login Activity protection plan (org-wide auto-enable)
# ---------------------------------------------------------------------------
resource "aws_guardduty_organization_configuration_feature" "rds_login_activity" {
  detector_id = aws_guardduty_detector.this.id
  name        = "RDS_LOGIN_EVENTS"
  auto_enable = "ALL"
}

# ---------------------------------------------------------------------------
# SNS topic subscription for high-severity finding alerts
# (subscribers — e.g. PagerDuty — are managed outside this module)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "guardduty_high_severity" {
  name        = "guardduty-high-severity-findings"
  description = "Routes GuardDuty HIGH severity findings to SNS for on-call alerting"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule = aws_cloudwatch_event_rule.guardduty_high_severity.name
  arn  = var.sns_topic_arn
}
