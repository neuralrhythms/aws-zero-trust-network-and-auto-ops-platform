# Terraform Module: self-healing

This module implements the event-driven self-healing automation layer for the Zero-Trust
platform. When a CloudWatch Alarm fires, an EventBridge rule routes the event to a Step
Functions state machine that executes a five-stage workflow — triage, diagnosis,
remediation, verification, and escalation — entirely through SSM Run Command, eliminating
the need for SSH/RDP access to target instances. If automated remediation fails the health
re-check, the state machine publishes an on-call notification to an SNS topic.

## Architecture

```
CloudWatch Alarm (ALARM state)
  └── EventBridge Rule
        └── Step Functions State Machine
              ├── Detect     — SSM Run Command: execute triage script on target instance
              ├── Diagnose   — Lambda: analyse triage output, classify fault type
              ├── Remediate  — SSM Run Command: apply fix (service restart / config reload)
              ├── Verify     — Choice: check $.healthCheckPassed; pass → end, fail → Escalate
              └── Escalate   — SNS publish: notify on-call with instance ID, alarm,
                               triage summary, and timestamp (terminal state)
```

Instance targeting uses the tag `SelfHealingEnabled = true`, so no instance IDs are
hardcoded. Diagnostic script stdout is captured by SSM and forwarded to CloudWatch Logs
group `/self-healing/ssm-output`, then ingested into Splunk via the Universal Forwarder
(`linux_os` index) or Fluent Bit (`k8s_containers` index for container workloads).

## Inputs

| Variable | Description |
|----------|-------------|
| `state_machine_name` | Name of the Step Functions state machine |
| `event_rule_name` | Name of the EventBridge rule matching CloudWatch Alarm state-change events |
| `sns_topic_arn` | ARN of the SNS topic for on-call escalation notifications |
| `ssm_detect_document_name` | SSM document executed in the Detect state to collect triage data |
| `ssm_remediate_document_name` | SSM document executed in the Remediate state to apply automated fixes |
| `ssm_linux_triage_document_name` | SSM document that runs `linux-triage.sh` on Amazon Linux instances |
| `diagnose_lambda_arn` | ARN of the Lambda function that classifies faults in the Diagnose state |

## Outputs

| Output | Description |
|--------|-------------|
| `state_machine_arn` | ARN of the Step Functions self-healing state machine |
| `event_rule_arn` | ARN of the EventBridge rule that triggers the workflow |
| `ssm_document_name` | Name of the SSM Run Command document for Linux triage |

## Related files

- `eventbridge.tf` — EventBridge rule and Step Functions target
- `sfn.tf` — Step Functions state machine with 5-state ASL definition
- `ssm.tf` — SSM Run Command document for Linux instance triage
- Triage script: [`docs/runbooks/scripts/linux-triage.sh`](../../../docs/runbooks/scripts/linux-triage.sh)
- Escalation runbook: [`docs/runbooks/escalation-playbook.md`](../../../docs/runbooks/escalation-playbook.md)

---

> **Note:** This module is a demonstration scaffold. Resource blocks are commented out and
> require population before production deployment.
