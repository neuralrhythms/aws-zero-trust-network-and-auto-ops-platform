# =============================================================================
# Module: self-healing / eventbridge.tf
#
# Purpose:
#   Defines an Amazon EventBridge rule that triggers the self-healing Step
#   Functions state machine when a CloudWatch Alarm transitions to ALARM state.
#
# Architecture flow:
#   CloudWatch Alarm (state change: ALARM)
#     └── aws_cloudwatch_event_rule   (matches CloudWatch alarm state-change events)
#           └── aws_cloudwatch_event_target  (routes matched events → Step Functions)
#
# IAM note:
#   EventBridge requires an execution role (aws_iam_role.eventbridge_sfn) with
#   permission to call states:StartExecution on the target state machine ARN.
# =============================================================================

# TODO: populate for production deployment

# resource "aws_cloudwatch_event_rule" "ec2_state_change" {
#   name        = var.event_rule_name
#   description = "Triggers self-healing Step Functions on CloudWatch Alarm state change"
#
#   event_pattern = jsonencode({
#     source      = ["aws.cloudwatch"]
#     "detail-type" = ["CloudWatch Alarm State Change"]
#     detail = {
#       state = { value = ["ALARM"] }
#     }
#   })
# }

# resource "aws_cloudwatch_event_target" "sfn" {
#   rule     = aws_cloudwatch_event_rule.ec2_state_change.name
#   arn      = aws_sfn_state_machine.self_healing.arn
#   role_arn = aws_iam_role.eventbridge_sfn.arn
# }
