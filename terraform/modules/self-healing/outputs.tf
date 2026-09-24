output "state_machine_arn" {
  description = "ARN of the Step Functions self-healing state machine; used by EventBridge target and for monitoring/alerting configuration"
  value       = null
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule that triggers the self-healing workflow on CloudWatch Alarm state-change events"
  value       = null
}

output "ssm_document_name" {
  description = "Name of the SSM Run Command document for Linux triage; referenced by the Step Functions Detect state and by SSM Send Command API calls"
  value       = null
}
