variable "state_machine_name" {
  description = "Name of the Step Functions state machine that orchestrates the self-healing workflow (Detect → Diagnose → Remediate → Verify → Escalate)"
  type        = string
}

variable "event_rule_name" {
  description = "Name of the EventBridge rule that matches CloudWatch Alarm state-change events and triggers the Step Functions state machine"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic to which the Escalate state publishes on-call notifications when automated remediation fails"
  type        = string
}

variable "ssm_detect_document_name" {
  description = "Name of the SSM Run Command document executed by the Detect state to collect triage data from the target instance"
  type        = string
}

variable "ssm_remediate_document_name" {
  description = "Name of the SSM Run Command document executed by the Remediate state to apply automated fixes (e.g. service restart, config reload)"
  type        = string
}

variable "ssm_linux_triage_document_name" {
  description = "Name of the SSM Run Command document that runs the Linux triage script (linux-triage.sh) on target Amazon Linux instances"
  type        = string
}

variable "diagnose_lambda_arn" {
  description = "ARN of the Lambda function invoked by the Diagnose state to analyse triage output and determine the appropriate remediation action"
  type        = string
}
