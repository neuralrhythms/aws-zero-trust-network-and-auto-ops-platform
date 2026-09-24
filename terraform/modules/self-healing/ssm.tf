# =============================================================================
# Module: self-healing / ssm.tf
#
# Purpose:
#   Defines AWS SSM Run Command documents used by the self-healing Step
#   Functions state machine to execute diagnostic and remediation scripts on
#   target EC2 instances without SSH/RDP access (zero-trust posture).
#
# Document: Linux triage (ZeroTrustPlatform-LinuxTriage)
#   - Schema version 2.2 (aws:runShellScript action)
#   - Checks: nginx/httpd service status, critical journal errors (last 20),
#     high disk usage mounts (>85%)
#   - stdout forwarded to CloudWatch Logs group /self-healing/ssm-output,
#     then ingested by Splunk Universal Forwarder → linux_os index
#
# Required IAM permissions on calling principal:
#   ssm:SendCommand, ssm:GetCommandInvocation, ssm:ListCommandInvocations
#
# Target selection:
#   Instances are targeted via tag key "SelfHealingEnabled" = "true" so the
#   state machine does not need to hard-code instance IDs.
# =============================================================================

# TODO: populate for production deployment

# resource "aws_ssm_document" "linux_triage" {
#   name          = var.ssm_linux_triage_document_name
#   document_type = "Command"
#
#   content = jsonencode({
#     schemaVersion = "2.2"
#     description   = "Linux triage: check services, disk, and critical journal errors"
#     mainSteps = [{
#       action = "aws:runShellScript"
#       name   = "LinuxTriage"
#       inputs = {
#         runCommand = [
#           "#!/bin/bash",
#           "set -euo pipefail",
#           "echo '=== Service Status ==='",
#           "systemctl is-active nginx && echo 'nginx: active' || echo 'nginx: INACTIVE'",
#           "systemctl is-active httpd && echo 'httpd: active' || echo 'httpd: INACTIVE'",
#           "echo '=== Critical Journal Errors (last 20) ==='",
#           "journalctl -p 3 -n 20 --no-pager",
#           "echo '=== High Disk Usage (>85%) ==='",
#           "df -h | awk '$5+0 > 85 {print \"ALERT: \" $0}'"
#         ]
#       }
#     }]
#   })
# }
