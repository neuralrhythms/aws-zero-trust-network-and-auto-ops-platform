# Module: `guardduty`

This module enables Amazon GuardDuty organisation-wide from the `audit` account, which acts as the GuardDuty delegated administrator for the AWS Organisation. It creates a GuardDuty detector with all required protection plans active — S3 Data Events, EKS Audit Logs (Kubernetes), EC2 Malware Protection (EBS volumes), and RDS Login Activity — and configures organisation-wide auto-enablement so every current and future member account automatically inherits the same protection posture. High-severity findings (severity ≥ 7) are routed via an EventBridge rule to a configurable SNS topic for on-call notification.

> **Instantiation note:** This module is instantiated exclusively from
> `terraform/environments/audit/main.tf`. The `audit` account must be registered
> as the GuardDuty delegated administrator in AWS Organizations before applying
> this module. See ADR-009 in `docs/adr/architectural-decision-record.md` for
> the full decision rationale.

---

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `member_account_ids` | `list(string)` | *(required)* | AWS account IDs of all GuardDuty member accounts in the organisation |
| `finding_publishing_frequency` | `string` | `"ONE_HOUR"` | How often GuardDuty publishes aggregated findings. Valid: `FIFTEEN_MINUTES`, `ONE_HOUR`, `SIX_HOURS` |
| `sns_topic_arn` | `string` | *(required)* | ARN of the SNS topic that receives high-severity finding alerts |

## Outputs

| Name | Description |
|------|-------------|
| `detector_id` | ID of the GuardDuty detector in the audit account |
| `organization_configuration_id` | ID of the organisation configuration resource confirming org-wide auto-enable |

---

## Protection Plans

| Plan | Resource | Auto-enabled for members |
|------|----------|--------------------------|
| S3 Data Events | `datasources.s3_logs` | Yes |
| EKS Audit Logs | `datasources.kubernetes.audit_logs` | Yes |
| EC2 Malware Protection (EBS) | `datasources.malware_protection.scan_ec2_instance_with_findings.ebs_volumes` | Yes |
| RDS Login Activity | `aws_guardduty_organization_configuration_feature` (`RDS_LOGIN_EVENTS`) | Yes (`ALL`) |
