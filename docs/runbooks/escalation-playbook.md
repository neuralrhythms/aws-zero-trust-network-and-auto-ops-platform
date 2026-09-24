# Escalation Playbook

**Platform:** AWS Zero-Trust Network & Automated Operations Platform
**Scope:** Automated Escalation Path — Step Functions → SNS → On-Call Response
**Maintained by:** Platform Operations Team
**Last revised:** 2026-09-22

---

## Table of Contents

1. [Overview](#1-overview)
2. [Escalation Trigger Conditions](#2-escalation-trigger-conditions)
3. [SNS Alert Format and Content](#3-sns-alert-format-and-content)
4. [PagerDuty Integration](#4-pagerduty-integration)
5. [On-Call Engineer Response Procedures](#5-on-call-engineer-response-procedures)
6. [Manual Investigation Steps](#6-manual-investigation-steps)
7. [Escalation Tiers and Response SLAs](#7-escalation-tiers-and-response-slas)
8. [Resolution and Closure Procedures](#8-resolution-and-closure-procedures)
9. [Post-Incident Process](#9-post-incident-process)

---

## 1. Overview

The platform's self-healing pipeline handles the majority of common failure conditions — stopped web servers, crashed application pools, transient process failures — without human intervention. When automated remediation is exhausted or cannot be applied safely, the pipeline escalates to the on-call engineer via SNS.

### Automated Pipeline Summary

```
CloudWatch Alarm (threshold crossed)
        │
        ▼
EventBridge Rule (aws.cloudwatch / CloudWatch Alarms state change)
        │
        ▼
Step Functions State Machine — "Zero-Trust Platform Self-Healing Workflow"
        │
        ├── [1] Detect     → SSM Run Command: execute triage script on target instance
        ├── [2] Diagnose   → Lambda invocation: classify fault type, determine remediation
        ├── [3] Remediate  → SSM Run Command: service restart / config reload
        ├── [4] Verify     → Choice state: evaluate $.healthCheckPassed
        │       ├── true  → END_SUCCESS (incident resolved; alarm auto-clears)
        │       └── false → Escalate
        └── [5] Escalate   → SNS publish to var.sns_topic_arn → PagerDuty + email
```

The Terraform definition for this pipeline lives in:

- `terraform/modules/self-healing/eventbridge.tf` — EventBridge rule and target
- `terraform/modules/self-healing/sfn.tf` — Step Functions state machine (ASL definition)
- `terraform/modules/self-healing/ssm.tf` — SSM Run Command documents
- `terraform/modules/self-healing/variables.tf` — `sns_topic_arn`, `state_machine_name`, etc.

The SNS topic ARN is supplied as the `sns_topic_arn` variable. Real values are set in `terraform.tfvars` at deployment time — no credentials or ARNs are hardcoded in the module.

---

## 2. Escalation Trigger Conditions

### 2.1 Primary Trigger: Verify State Failure

The **Verify** state is a Step Functions Choice state that evaluates the `$.healthCheckPassed` boolean in the execution's input/output context. This boolean is populated by the **Remediate** state's post-action health probe (ALB target group health check or custom application endpoint probe).

```json
"Verify": {
  "Type": "Choice",
  "Choices": [
    {
      "Variable": "$.healthCheckPassed",
      "BooleanEquals": true,
      "Next": "END_SUCCESS"
    }
  ],
  "Default": "Escalate"
}
```

The **Escalate** state is triggered when:

- `$.healthCheckPassed = false` after the **Remediate** state completes
- The health probe returns unhealthy for the target instance or pod
- The **Remediate** state itself catches an error (SSM command failure, timeout) and the catch rule routes directly to **Escalate**
- The **Diagnose** state's Lambda returns an unrecognised fault classification that the remediation document cannot handle

### 2.2 Secondary Triggers (Direct Escalation)

Some conditions bypass the Remediate/Verify cycle entirely and route directly from **Detect** or **Diagnose** to **Escalate**:

| Condition | Routing |
|-----------|---------|
| SSM agent unreachable on target instance | Detect → Escalate |
| Instance not tagged `SelfHealingEnabled = true` | Detect → Escalate |
| Diagnose Lambda classifies fault as `DISK_FULL` or `CERT_EXPIRY` | Diagnose → Escalate |
| Diagnose Lambda classifies fault as `SECURITY_INCIDENT` (GuardDuty P1 routing) | Diagnose → Escalate (with `severity = P1`) |
| Remediate SSM command times out after 10 minutes | Remediate → Escalate |
| Step Functions execution exceeds 30-minute total timeout | State machine → Escalate |

### 2.3 GuardDuty and Inspector Sourced Escalations

GuardDuty findings and Inspector vulnerability alerts that exceed severity thresholds are also routed via EventBridge into the self-healing pipeline or directly to the SNS escalation topic, bypassing the remediation flow entirely:

- GuardDuty finding severity ≥ 7.0 → EventBridge rule in `audit` account → SNS topic → PagerDuty P1
- Inspector critical vulnerability (CVSS ≥ 9.0) on production ECR image or EC2 instance → SNS topic → team email P2

These flows are defined in `terraform/modules/guardduty/main.tf` and `terraform/modules/inspector/main.tf`, both instantiated from `terraform/environments/audit/main.tf` as the delegated administrator account.

---

## 3. SNS Alert Format and Content

### 3.1 SNS Message Structure

The **Escalate** state publishes to the SNS topic with the following message payload. The `Subject` line appears in email notifications and is passed as the PagerDuty alert title.

**Subject:**

```
Self-Healing Escalation: Manual Intervention Required
```

**Message body (JSON):**

```json
{
  "instanceId": "<ec2-instance-id>",
  "alarmName": "<cloudwatch-alarm-name>",
  "triageOutputSummary": "<first-1000-chars-of-SSM-stdout>",
  "timestamp": "<ISO-8601-UTC>",
  "severity": "<P1|P2|P3>",
  "accountId": "<aws-account-id>",
  "region": "<aws-region>",
  "stateMachineArn": "<arn:aws:states:...:stateMachine:...>",
  "executionArn": "<arn:aws:states:...:execution:...>",
  "remediationAttempted": true,
  "healthCheckPassed": false,
  "faultClassification": "<INACTIVE_SERVICE|DISK_FULL|CERT_EXPIRY|SECURITY_INCIDENT|UNKNOWN>"
}
```

### 3.2 Field Descriptions

| Field | Source | Description |
|-------|--------|-------------|
| `instanceId` | CloudWatch Alarm dimensions | EC2 instance ID that triggered the alarm |
| `alarmName` | EventBridge event payload | Name of the CloudWatch Alarm that initiated the execution |
| `triageOutputSummary` | SSM Run Command stdout | First 1,000 characters of triage script output; enables pre-diagnosis before opening an SSM session |
| `timestamp` | Step Functions `$$.Execution.StartTime` | ISO 8601 UTC timestamp when the execution was initiated |
| `severity` | Detect state classification | P1 / P2 / P3 based on alarm metadata and account environment tag |
| `accountId` | `$$.Execution.Name` context | AWS account ID where the alarm fired |
| `region` | Execution context | AWS region of the affected resource |
| `stateMachineArn` | `$$.StateMachine.Id` | ARN of the state machine for CloudWatch Logs correlation |
| `executionArn` | `$$.Execution.Id` | Specific execution ARN — use this to view the full execution history in the AWS Console |
| `remediationAttempted` | Boolean | `true` if the Remediate state was reached; `false` if escalation was triggered directly from Detect/Diagnose |
| `healthCheckPassed` | Remediate state output | Always `false` when escalation fires via Verify state |
| `faultClassification` | Diagnose Lambda output | Structured fault type enabling Splunk dashboard filtering |

### 3.3 Locating the Execution in AWS Console

The `executionArn` field in the SNS message provides a direct link to the Step Functions execution history:

```
https://<region>.console.aws.amazon.com/states/home?region=<region>#/executions/details/<executionArn>
```

The execution history shows the exact state at which the failure occurred, input/output for each state, and the full error message if a state threw an exception.

---

## 4. PagerDuty Integration

### 4.1 Integration Architecture

The SNS topic (`var.sns_topic_arn`) has two subscribers configured at deployment time:

1. **PagerDuty Events API v2 integration endpoint** — receives the SNS message and creates a PagerDuty incident
2. **On-call engineer distribution email list** — backup notification channel; also used for P3 non-paging alerts

The PagerDuty integration is configured as an HTTPS subscription on the SNS topic. The endpoint URL is a PagerDuty integration key URL of the form:

```
https://events.pagerduty.com/integration/<integration-key>/enqueue
```

This value is stored as an SNS subscription and never hardcoded in Terraform — it is supplied as a `<PLACEHOLDER>` in `terraform.tfvars` and populated at deployment time.

### 4.2 PagerDuty Alert Behaviour by Severity

| Severity | PagerDuty Urgency | Notification Method | Escalation Policy |
|----------|-------------------|--------------------|--------------------|
| **P1** | High | Phone call + push notification + SMS | Immediate; escalates to secondary on-call after 10 minutes if unacknowledged |
| **P2** | High | Push notification + email | Escalates to team lead after 30 minutes if unacknowledged |
| **P3** | Low | Email only (no page) | No automatic escalation; reviewed in next business-hours window |

The `severity` field in the SNS message JSON is mapped to PagerDuty urgency by the PagerDuty SNS integration transformer rule. Ensure the rule is configured to parse the `severity` key from the JSON body.

### 4.3 PagerDuty Incident Fields

When the SNS message is received, PagerDuty creates an incident with:

- **Title:** `Self-Healing Escalation: Manual Intervention Required` (from SNS Subject)
- **Service:** Platform Operations — Zero-Trust AWS
- **Dedup key:** `<stateMachineArn>/<executionArn>` (prevents duplicate incidents for the same execution)
- **Custom details:** All fields from the SNS message JSON are mapped as PagerDuty custom detail fields for immediate visibility in the mobile app

### 4.4 Acknowledging and Resolving in PagerDuty

- **Acknowledge** the incident as soon as you begin investigation to stop escalation notifications.
- **Resolve** the incident only after the CloudWatch Alarm has returned to `OK` state and the root cause has been identified.
- Add notes to the PagerDuty incident timeline as you work — these feed the post-incident review.

---

## 5. On-Call Engineer Response Procedures

### 5.1 Initial Triage (First 5 Minutes)

1. **Acknowledge the PagerDuty alert** to stop escalation notifications.
2. **Read the `triageOutputSummary`** in the alert details — this is the first 1,000 characters of the triage script output captured during the **Diagnose** state. It will contain service states (`nginx: INACTIVE`), disk alerts (`ALERT: /dev/xvda1 92%`), or Event Log errors.
3. **Check the `faultClassification`** field to understand what the Diagnose Lambda determined.
4. **Note the `executionArn`** — open the Step Functions execution history in the AWS Console to see the exact failure point and full state I/O.
5. **Assess severity**: confirm the P1/P2/P3 classification matches the observed impact. If impact is more severe than classified, treat as P1 regardless.

### 5.2 Accessing the Affected Instance

All direct SSH and RDP access is blocked organisation-wide by the `deny-open-ssh-rdp.json` SCP. Use SSM Session Manager exclusively:

```bash
# Start an interactive session (Linux)
aws ssm start-session \
  --target <instanceId> \
  --region <region>

# Start a session with port forwarding (e.g. for local log review)
aws ssm start-session \
  --target <instanceId> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}' \
  --region <region>
```

> **IAM requirement:** Your IAM role must have `ssm:StartSession` on the target instance resource. The `deny-open-ssh-rdp.json` SCP does not affect SSM — SSM Session Manager uses HTTPS over port 443, not port 22/3389.

### 5.3 Running the Triage Script Manually

If the automated triage output in the SNS alert is insufficient, re-run the triage script manually:

**Linux:**

```bash
aws ssm send-command \
  --document-name "ZeroTrustPlatform-LinuxTriage" \
  --targets "[{\"Key\":\"InstanceIds\",\"Values\":[\"<instanceId>\"]}]" \
  --cloud-watch-output-config \
      "CloudWatchLogGroupName=/self-healing/ssm-output,CloudWatchOutputEnabled=true" \
  --region <region>

# Poll for completion
aws ssm get-command-invocation \
  --command-id <command-id> \
  --instance-id <instanceId> \
  --query "StandardOutputContent" \
  --output text \
  --region <region>
```

**Windows:**

```bash
aws ssm send-command \
  --document-name "ZeroTrustPlatform-WindowsTriage" \
  --targets "[{\"Key\":\"InstanceIds\",\"Values\":[\"<instanceId>\"]}]" \
  --cloud-watch-output-config \
      "CloudWatchLogGroupName=/self-healing/ssm-output,CloudWatchOutputEnabled=true" \
  --region <region>
```

### 5.4 Interpreting Triage Output and Taking Action

Cross-reference with the decision matrices in [`docs/runbooks/hybrid-os-operations-runbook.md`](./hybrid-os-operations-runbook.md), Sections 3.3 (Linux) and 4.3 (Windows). Common escalation scenarios and manual resolutions:

| `faultClassification` | Observed Symptom | Manual Resolution |
|----------------------|-----------------|-------------------|
| `INACTIVE_SERVICE` | nginx/httpd/W3SVC stopped; restart failed | Check `journalctl -xe` or Event Log for crash reason; fix config error; restart |
| `DISK_FULL` | `ALERT:` line in triage output, usage ≥ 98% | Connect via SSM Session Manager; identify large files (`du -sh /var/log/*`); rotate/archive/delete; verify service restarts |
| `CERT_EXPIRY` | TLS certificate expired or near expiry | Renew via ACM or internal CA; update ALB listener or application config; restart affected service |
| `UNKNOWN` | No clear fault classification | Review full SSM output in CloudWatch Logs (`/self-healing/ssm-output`); check Splunk `linux_os` or `windows_os` index for correlated events |
| `SECURITY_INCIDENT` | GuardDuty P1 finding | **Do not attempt service restart.** Follow the containment steps in Section 6.3 |

### 5.5 Validating Resolution

After applying the manual fix, confirm the alarm has resolved:

```bash
aws cloudwatch describe-alarms \
  --alarm-names "<alarmName>" \
  --query "MetricAlarms[*].[AlarmName,StateValue,StateReason]" \
  --output table \
  --region <region>
```

Confirm the ALB target group health check is passing:

```bash
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region <region>
```

Once the alarm state returns to `OK`, resolve the PagerDuty incident. Do not resolve the PagerDuty incident before the alarm clears — use the alarm `OK` transition as the authoritative resolution signal.

---

## 6. Manual Investigation Steps

### 6.1 Reviewing Logs in Splunk

The SSM triage script output is ingested into Splunk via the Splunk Universal Forwarder in the `logging` account. The on-call engineer has read-only access to the `logging` account S3 bucket and Splunk.

Search for recent triage events for a specific instance:

```
index=linux_os sourcetype=linux_ssm_triage instanceId="<instanceId>"
| sort -_time
| table _time, instanceId, message
```

Search for Windows IIS failures across all instances in the last hour:

```
index=windows_os sourcetype=windows_ssm_triage "Stopped"
| where _time > relative_time(now(), "-1h")
| table _time, host, instanceId, message
```

Correlate a GuardDuty finding with instance activity:

```
index=aws_guardduty accountId="<accountId>"
| where severity >= 7
| table _time, accountId, region, type, description, resource.instanceDetails.instanceId
```

### 6.2 Reviewing Step Functions Execution History

The full execution history (including state input/output, errors, and timing) is available in CloudWatch Logs and the Step Functions console:

```bash
# List recent executions for the state machine
aws stepfunctions list-executions \
  --state-machine-arn <stateMachineArn> \
  --status-filter FAILED \
  --max-results 10 \
  --region <region>

# Get detailed history for a specific execution
aws stepfunctions get-execution-history \
  --execution-arn <executionArn> \
  --region <region>
```

In the AWS Console, navigate to **Step Functions → State Machines → Zero-Trust Platform Self-Healing → Executions** and filter by `Status = Failed` to see all escalation-triggering executions.

### 6.3 Security Incident Containment (GuardDuty P1)

If the `faultClassification` is `SECURITY_INCIDENT` or the SNS alert originates from a GuardDuty high-severity finding:

1. **Do not restart services** — this may destroy forensic evidence.
2. **Isolate the instance** by modifying its security group to deny all inbound and outbound traffic, except SSM endpoints (port 443):
   ```bash
   aws ec2 modify-instance-attribute \
     --instance-id <instanceId> \
     --groups <isolation-security-group-id> \
     --region <region>
   ```
3. **Preserve instance state** — do not terminate or stop the instance until forensic capture is complete.
4. **Capture a memory image and disk snapshot** if the GuardDuty finding type indicates active compromise (e.g., `CryptoCurrency:EC2/BitcoinTool.B!DNS`, `Trojan:EC2/DropPoint`).
5. **Notify the security team** immediately — this is a P1 security incident requiring the security team's involvement, not just the platform operations team.
6. **Review GuardDuty findings** in the `audit` account console:
   ```
   https://<region>.console.aws.amazon.com/guardduty/home?region=<region>#/findings
   ```
7. **Review Inspector findings** for the affected instance to identify any exploited vulnerabilities.

### 6.4 EKS Workload Investigation

For EKS-related escalations (node-level alarm), correlate OS-level triage with pod-level investigation:

```bash
# Find all pods on the affected node
kubectl get pods --all-namespaces -o wide \
  --field-selector spec.nodeName=<node-name>

# Check pod events for scheduling or runtime issues
kubectl describe node <node-name>

# Review recent pod logs for error patterns
kubectl logs <pod-name> -n <namespace> --tail=100

# Check Fluent Bit DaemonSet status on the node
kubectl get pods -n logging -o wide | grep <node-name>
```

If a pod is in `CrashLoopBackOff` or `OOMKilled` state, capture the previous container logs before the pod restarts:

```bash
kubectl logs <pod-name> -n <namespace> --previous
```

See [`docs/runbooks/hybrid-os-operations-runbook.md`](./hybrid-os-operations-runbook.md), Section 6 for the full container triage supplement.

---

## 7. Escalation Tiers and Response SLAs

Severity is determined by the Step Functions **Detect** state based on the CloudWatch Alarm metadata and the account's environment tag (`env = production | staging | test | dev`).

| Severity | Label | Response SLA | Notification Method | Escalation Behaviour |
|----------|-------|-------------|--------------------|-----------------------|
| **P1** | Critical | **15 minutes** to acknowledge | PagerDuty phone + push + SMS | Escalates to secondary on-call after 10 min if unacknowledged; escalates to team lead after 20 min |
| **P2** | High | **1 hour** to acknowledge | PagerDuty push notification + email | Escalates to team lead after 30 min if unacknowledged |
| **P3** | Medium | **4 hours** (next business hours window) | Email only (no PagerDuty page) | No automatic escalation; reviewed in daily ops standup |

### Severity Mapping Criteria

| Criteria | Severity |
|----------|---------|
| Production account + service unreachable from ALB | P1 |
| Production account + `DISK_FULL` on system volume (≥ 98%) | P1 |
| GuardDuty finding severity ≥ 7.0 | P1 |
| Production account + degraded service (some replicas failing) | P2 |
| Non-production account + any service failure | P2 |
| GuardDuty finding severity 4.0–6.9 | P2 |
| Any account + `CERT_EXPIRY` (> 14 days remaining) | P3 |
| Non-critical metric anomaly | P3 |
| Inspector finding CVSS < 7.0 | P3 |

### Escalation from P2 to P1

If a P2 incident is not resolved within the 1-hour SLA and impact is spreading (additional instances affected, user-visible errors increasing), the on-call engineer must manually upgrade the severity to P1 in PagerDuty and notify the team lead.

---

## 8. Resolution and Closure Procedures

### 8.1 Confirming Resolution

An incident is considered resolved when all of the following conditions are met:

1. The originating CloudWatch Alarm has transitioned to `OK` state.
2. The ALB target group health check reports all targets as `healthy`.
3. No new alarms have fired for the affected resource in the preceding 10 minutes.
4. If a GuardDuty finding triggered the escalation: the finding has been archived in the `audit` account GuardDuty console and the security team has confirmed containment.

### 8.2 Resolving the PagerDuty Incident

Once all resolution conditions are confirmed:

1. Add a final note to the PagerDuty incident timeline: `Resolved. CloudWatch Alarm returned to OK at <timestamp>. Root cause: <brief description>.`
2. Change the incident status to **Resolved** in PagerDuty.
3. Ensure the SNS/CloudWatch Alarm is not in a stuck `ALARM` state — if the alarm does not auto-clear after the fix, manually set it:
   ```bash
   aws cloudwatch set-alarm-state \
     --alarm-name "<alarmName>" \
     --state-value OK \
     --state-reason "Manually resolved after confirmed remediation" \
     --region <region>
   ```
   > **Note:** Only use manual alarm state override if the underlying metric has clearly recovered but the alarm is stuck. Overriding an alarm that is still in failure condition masks ongoing issues.

### 8.3 Incident Record Keeping

For P1 and P2 incidents, create an incident record in the team's tracking system (Jira, Confluence, or equivalent) containing:

- Incident ID and PagerDuty incident URL
- Start time and resolution time (MTTR)
- Severity and account/region affected
- Timeline of events (detection, escalation, investigation steps, fix applied)
- Root cause summary
- Action items with owners and due dates

---

## 9. Post-Incident Process

### 9.1 Blameless Retrospective

A blameless retrospective (post-mortem) is conducted for all P1 incidents and for any P2 incident that exceeded its response SLA. The retrospective is scheduled within 48 hours of resolution and focuses on system factors — not individual blame.

**Retrospective agenda:**

1. **Timeline reconstruction** — walk through the event timeline from alarm trigger to resolution using the Step Functions execution history, Splunk logs, and PagerDuty incident notes.
2. **What worked well** — identify aspects of the automated pipeline that functioned as intended.
3. **What did not work** — identify where the automation fell short and why escalation was required.
4. **Contributing factors** — infrastructure, process, tooling, or knowledge gaps that contributed to the incident.
5. **Action items** — specific, owned, time-bound improvements.

The retrospective document is stored alongside this runbook in the `docs/runbooks/` directory, named `<YYYY-MM-DD>-retrospective-<incident-id>.md`.

### 9.2 Runbook Updates

If the incident revealed a gap in this playbook or the hybrid-OS operations runbook:

1. Update the relevant runbook sections immediately following the retrospective.
2. Submit a pull request to the GitOps repository for peer review.
3. Notify the team via the operations channel that the runbook has been updated.
4. If a new triage script procedure is needed, add it to `docs/runbooks/scripts/linux-triage.sh` or `docs/runbooks/scripts/windows-triage.ps1` and update the corresponding SSM document in `terraform/modules/self-healing/ssm.tf`.

### 9.3 Automation Improvement Tracking

Recurring escalations — the same fault class triggering manual intervention more than once — indicate that the automation gap should be closed. Track improvement opportunities in a dedicated backlog with the following fields:

| Field | Description |
|-------|-------------|
| **Trigger pattern** | The `faultClassification` and alarm name that repeatedly escalates |
| **Estimated frequency** | How often this fault occurs (from Splunk historical search) |
| **Proposed automation** | New SSM document, Diagnose Lambda update, or Step Functions state extension that would handle it |
| **Risk assessment** | What could go wrong if the automation misidentifies the condition |
| **Owner** | Platform engineer responsible for designing and testing the new automation |
| **Target sprint** | When the improvement is expected to be delivered |

When a new automation handler is implemented:

1. Register the new SSM document as an `aws_ssm_document` resource in `terraform/modules/self-healing/ssm.tf`.
2. Update the Diagnose Lambda to recognise the new fault class and populate `faultClassification` accordingly.
3. Add the new fault class to the `faultClassification` field in the SNS message schema (Section 3.2).
4. Test the full pipeline end-to-end in the `workload-dev` environment before deploying to production.
5. Update Section 5.4 of this playbook with the new fault class entry.

### 9.4 Key Performance Indicators

Track the following metrics in Splunk or CloudWatch to measure the effectiveness of the self-healing pipeline over time:

| Metric | Description | Target |
|--------|-------------|--------|
| **Auto-resolution rate** | Percentage of Step Functions executions that reach `END_SUCCESS` without escalating | ≥ 80% |
| **Mean Time to Detect (MTTD)** | Time from alarm firing to Step Functions execution start | < 2 minutes |
| **Mean Time to Remediate (MTTR, automated)** | Time from execution start to `END_SUCCESS` | < 10 minutes |
| **Escalation rate by fault class** | Count of escalations per `faultClassification` per month | Trending down |
| **P1 acknowledgement time** | Time from SNS publish to PagerDuty acknowledgement | < 15 minutes (SLA) |

Review these metrics monthly in the platform operations team meeting and use them to prioritise the automation improvement backlog (Section 9.3).

---

*For platform coverage matrix, diagnostic procedures, and triage script details, see [`docs/runbooks/hybrid-os-operations-runbook.md`](./hybrid-os-operations-runbook.md).*
*For triage scripts, see [`docs/runbooks/scripts/linux-triage.sh`](./scripts/linux-triage.sh) and [`docs/runbooks/scripts/windows-triage.ps1`](./scripts/windows-triage.ps1).*
*For the Step Functions and SNS Terraform definitions, see [`terraform/modules/self-healing/`](../../terraform/modules/self-healing/).*
