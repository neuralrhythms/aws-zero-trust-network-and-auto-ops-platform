# =============================================================================
# Module: self-healing / sfn.tf
#
# Purpose:
#   Defines the AWS Step Functions state machine that orchestrates the
#   five-stage self-healing workflow for EC2 and EKS node remediation.
#
# 5-State workflow (Amazon States Language):
#   1. Detect     — SSM Run Command: execute triage script on target instance;
#                   collect service status, journal errors, disk usage
#   2. Diagnose   — Lambda invocation: analyse triage output, classify fault
#                   type, and determine remediation action
#   3. Remediate  — SSM Run Command: execute remediation (e.g. service restart,
#                   config reload) based on Diagnose output
#   4. Verify     — Choice state: evaluate $.healthCheckPassed boolean;
#                   true → implicit success end; false → Escalate
#   5. Escalate   — SNS publish: notify on-call via var.sns_topic_arn with
#                   instance ID, alarm name, triage summary, timestamp;
#                   terminal state (End = true)
#
# IAM note:
#   aws_iam_role.sfn_exec must allow states:StartExecution and be trusted
#   by the states.amazonaws.com service principal.
# =============================================================================

# TODO: populate for production deployment

# resource "aws_sfn_state_machine" "self_healing" {
#   name     = var.state_machine_name
#   role_arn = aws_iam_role.sfn_exec.arn
#
#   definition = jsonencode({
#     Comment = "Zero-Trust Platform Self-Healing Workflow"
#     StartAt = "Detect"
#     States = {
#       Detect = {
#         Type     = "Task"
#         Resource = "arn:aws:states:::ssm:sendCommand.sync"
#         Parameters = {
#           DocumentName = var.ssm_detect_document_name
#           Targets      = [{ Key = "tag:SelfHealingEnabled", Values = ["true"] }]
#         }
#         Next = "Diagnose"
#       }
#       Diagnose = {
#         Type     = "Task"
#         Resource = "arn:aws:states:::lambda:invoke"
#         Parameters = {
#           FunctionName = var.diagnose_lambda_arn
#           "Payload.$"  = "$"
#         }
#         Next = "Remediate"
#       }
#       Remediate = {
#         Type     = "Task"
#         Resource = "arn:aws:states:::ssm:sendCommand.sync"
#         Parameters = {
#           DocumentName = var.ssm_remediate_document_name
#           Targets      = [{ Key = "tag:SelfHealingEnabled", Values = ["true"] }]
#         }
#         Next = "Verify"
#       }
#       Verify = {
#         Type = "Choice"
#         Choices = [{
#           Variable      = "$.healthCheckPassed"
#           BooleanEquals = true
#           Next          = "END_SUCCESS"
#         }]
#         Default = "Escalate"
#       }
#       Escalate = {
#         Type     = "Task"
#         Resource = "arn:aws:states:::sns:publish"
#         Parameters = {
#           TopicArn  = var.sns_topic_arn
#           "Message.$" = "$.escalationMessage"
#           Subject   = "Self-Healing Escalation: Manual Intervention Required"
#         }
#         End = true
#       }
#     }
#   })
# }
