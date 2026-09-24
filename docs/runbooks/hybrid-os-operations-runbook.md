# Incident Response & Systems Operations Guide

**Platform:** AWS Zero-Trust Network & Automated Operations Platform
**Scope:** Hybrid OS — Linux Compute, Linux Containers (EKS), Windows Server, Windows Containers (EKS)
**Maintained by:** Platform Operations Team
**Last revised:** 2026-09-22

---

## Table of Contents

1. [Incident Classification](#1-incident-classification)
2. [Platform Coverage Matrix](#2-platform-coverage-matrix)
3. [Diagnostic Procedure: Linux](#3-diagnostic-procedure-linux)
4. [Diagnostic Procedure: Windows](#4-diagnostic-procedure-windows)
5. [Log Processing Workflow](#5-log-processing-workflow)
6. [Container Triage Supplement](#6-container-triage-supplement)
7. [Automated vs Manual Remediation](#7-automated-vs-manual-remediation)
8. [Script References](#8-script-references)

---

## 1. Incident Classification

All incidents detected by the platform's self-healing pipeline are assigned a severity level at the **Detect** state of the Step Functions state machine. Severity drives escalation timing, on-call paging behaviour, and SLA commitments.

| Severity | Label    | Initial Response SLA | Description / Criteria                                                                                                                                                   |
|----------|----------|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **P1**   | Critical | **15 minutes**       | Complete service outage or data-plane failure affecting production workloads. Examples: EKS node not ready (all pods evicted), web server unreachable from ALB health check, critical GuardDuty finding (severity ≥ 7.0), disk usage ≥ 98% on system volume. Automated remediation is attempted immediately; SNS on-call page fires in parallel. |
| **P2**   | High     | **1 hour**           | Degraded service — partial outage or performance impact. Examples: one of N replicas failing, disk usage 85–98%, application pool stopped on a non-primary Windows node, elevated error rate in Splunk alerting dashboard. Automated remediation is attempted; SNS alert fires if `Verify` state fails within the Step Functions timeout. |
| **P3**   | Medium   | **4 hours**          | Non-urgent operational issue with no immediate user impact. Examples: stale certificate approaching expiry (> 14 days), non-critical service failure on a development cluster, low-priority Inspector finding, CloudWatch metric anomaly below alarm threshold. Automated remediation may be attempted; SNS notification sent to team channel (non-paging). |

### Severity Determination

The Step Functions **Detect** state evaluates the incoming CloudWatch Alarm payload and tags the execution context with the severity level before transitioning to **Diagnose**. The mapping is:

- `AlarmState = ALARM` + production account tag → P1 or P2 based on metric threshold crossed
- `AlarmState = ALARM` + non-production account tag → P2 or P3
- GuardDuty findings routed via EventBridge: severity ≥ 7.0 → P1; 4.0–6.9 → P2; < 4.0 → P3

---

## 2. Platform Coverage Matrix

| Operating System / Platform       | Log Sources & Targets                                                                                                     | Automation Scripting Tool                  | Diagnostic Objective                                                                                       |
|-----------------------------------|--------------------------------------------------------------------------------------------------------------------------|--------------------------------------------|------------------------------------------------------------------------------------------------------------|
| **Linux Compute** (EC2 / AL2)     | SSM Run Command stdout → CloudWatch Logs `/self-healing/ssm-output` → Splunk UF → index `linux_os`                       | `linux-triage.sh` via SSM Run Command      | Check nginx/httpd service state, capture critical journal errors, identify high disk usage (> 85%)         |
| **Linux Containers** (EKS)        | Fluent Bit DaemonSet → Splunk Cloud HEC → index `k8s_containers`; `kubectl logs` for ad-hoc capture                     | `kubectl`, Fluent Bit sidecar              | Inspect pod logs, exec into containers for live diagnostics, verify Fluent Bit pipeline health             |
| **Windows Server** (EC2 / 2019)   | SSM Run Command stdout → CloudWatch Logs `/self-healing/ssm-output` → Splunk UF → index `windows_os`                    | `windows-triage.ps1` via SSM Run Command   | Check W3SVC/IIS service state, enumerate app pool status, surface Application Event Log errors (last 2 hr) |
| **Windows Containers** (EKS)      | Fluent Bit DaemonSet (Windows toleration) → Splunk Cloud HEC → index `k8s_containers`; `kubectl logs` for ad-hoc capture | `kubectl`, Fluent Bit DaemonSet            | Inspect Windows container stdout/stderr, verify Fluent Bit toleration on Windows nodes, exec for diagnostics |

> **Note on Fluent Bit dual-OS toleration:** The Fluent Bit DaemonSet is deployed with two toleration entries — one matching `os=windows:NoSchedule` for Windows nodes and one `Exists` toleration covering Linux nodes with no taint. This ensures full coverage across the heterogeneous EKS cluster without deploying separate DaemonSets. See `terraform/modules/eks-addons/fluentbit-values.yaml` for the exact Helm values.

---

## 3. Diagnostic Procedure: Linux

### 3.1 Target Identification

The self-healing pipeline operates exclusively on EC2 instances and Auto Scaling groups tagged with:

```
SelfHealingEnabled = true
```

Before invoking any SSM Run Command, confirm the target instance carries this tag. This prevents accidental execution against unmanaged or non-standard hosts.

```bash
aws ec2 describe-instances \
  --filters "Name=tag:SelfHealingEnabled,Values=true" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name'].Value|[0]]" \
  --output table
```

### 3.2 Invoking the Triage Script via SSM Run Command

The Step Functions **Diagnose** state invokes `linux-triage.sh` using the `ZeroTrustPlatform-LinuxTriage` SSM document. For manual invocation:

```bash
aws ssm send-command \
  --document-name "ZeroTrustPlatform-LinuxTriage" \
  --targets "Key=tag:SelfHealingEnabled,Values=true" \
  --cloud-watch-output-config \
      "CloudWatchLogGroupName=/self-healing/ssm-output,CloudWatchOutputEnabled=true" \
  --region <AWS_REGION>
```

Retrieve the command output:

```bash
COMMAND_ID=<returned-command-id>
INSTANCE_ID=<target-instance-id>

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "StandardOutputContent" \
  --output text
```

### 3.3 Interpreting Triage Output

The script produces labelled sections for reliable Splunk parsing. A healthy host produces output similar to:

```
=== Service Status ===
nginx: active
httpd: INACTIVE (not installed)

=== Critical Journal Errors (last 20) ===
(no critical entries)

=== High Disk Usage (> 85%) ===
(no volumes above threshold)
```

**Decision matrix:**

| Observed Output                                       | Interpretation                          | Next Action                                      |
|-------------------------------------------------------|-----------------------------------------|--------------------------------------------------|
| `nginx: INACTIVE` or `httpd: INACTIVE`                | Web server stopped                      | Step Functions **Remediate** state restarts it   |
| Critical journal entries present                      | Application or kernel error             | Review entries; may require human intervention   |
| `ALERT:` line in disk section                         | Volume usage > 85%                      | Automated remediation cannot reclaim space — escalate |
| `nginx: active` + no errors + no disk alerts          | Host is healthy                         | Step Functions **Verify** state confirms; alarm resolves |

### 3.4 Interpreting Step Functions State Outcomes

| State        | Action Taken                                          | Success Transition | Failure Transition         |
|--------------|-------------------------------------------------------|--------------------|----------------------------|
| **Detect**   | Parses CloudWatch Alarm; sets severity + instance ID  | → Diagnose         | → Escalate (parse failure) |
| **Diagnose** | Runs `ZeroTrustPlatform-LinuxTriage` via SSM          | → Remediate        | → Escalate (SSM error)     |
| **Remediate**| Executes `systemctl restart nginx` or `httpd`         | → Verify           | → Escalate                 |
| **Verify**   | Checks `$.healthCheckPassed` (ALB or custom probe)    | → End (resolved)   | → Escalate                 |
| **Escalate** | Publishes to SNS; on-call paged via PagerDuty         | End (alert sent)   | —                          |

---

## 4. Diagnostic Procedure: Windows

### 4.1 Target Identification

Same tagging requirement as Linux:

```
SelfHealingEnabled = true
```

Confirm the target Windows Server 2019 instance is reachable via SSM (not SSH/RDP — direct remote access is denied by the `deny-open-ssh-rdp.json` SCP):

```bash
aws ssm describe-instance-information \
  --filters "Key=tag:SelfHealingEnabled,Values=true" \
  --query "InstanceInformationList[*].[InstanceId,PlatformType,PlatformName,PingStatus]" \
  --output table
```

Confirm `PlatformType = Windows` and `PingStatus = Online` before proceeding.

### 4.2 Invoking the Triage Script via SSM Run Command

The Step Functions **Diagnose** state invokes `windows-triage.ps1` using the `ZeroTrustPlatform-WindowsTriage` SSM document. For manual invocation:

```bash
aws ssm send-command \
  --document-name "ZeroTrustPlatform-WindowsTriage" \
  --targets "Key=tag:SelfHealingEnabled,Values=true" \
  --cloud-watch-output-config \
      "CloudWatchLogGroupName=/self-healing/ssm-output,CloudWatchOutputEnabled=true" \
  --region <AWS_REGION>
```

Retrieve the output:

```bash
COMMAND_ID=<returned-command-id>
INSTANCE_ID=<target-instance-id>

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "StandardOutputContent" \
  --output text
```

### 4.3 Interpreting Triage Output

A healthy Windows host produces output similar to:

```
=== W3SVC (IIS) Service Status ===
Name   Status  StartType
----   ------  ---------
W3SVC  Running Automatic

=== Application Pool Status ===
Name          State   ManagedRuntimeVersion
----          -----   ---------------------
DefaultAppPool Started v4.0

=== Application Event Log Errors (last 2 hours, first 10) ===
(no errors in time window)
```

**Decision matrix:**

| Observed Output                                          | Interpretation                           | Next Action                                          |
|----------------------------------------------------------|------------------------------------------|------------------------------------------------------|
| `W3SVC  Stopped`                                         | IIS service stopped                      | Step Functions **Remediate** state restarts W3SVC    |
| Application pool `State = Stopped`                       | App pool crashed                         | Step Functions **Remediate** attempts pool restart   |
| Application Event Log errors present                     | Application exception or config error    | Review event details; may require human intervention |
| `W3SVC  Running` + no pool errors + no event log errors  | Host is healthy                          | **Verify** state confirms; alarm resolves            |

### 4.4 Step Functions State Outcomes (Windows)

The state machine follows the same five-state flow as Linux (see Section 3.4). The **Remediate** state distinguishes OS via the instance's `platform_type` attribute and executes the appropriate SSM document:

- Linux: `systemctl restart nginx` or `systemctl restart httpd`
- Windows: `Restart-Service W3SVC` or `Start-WebAppPool -Name <pool>`

---

## 5. Log Processing Workflow

### 5.1 EC2 Diagnostic Log Path (Linux and Windows)

```
SSM Run Command execution
        │
        ▼
  StandardOutput (stdout)
        │
        ▼
CloudWatch Logs — log group: /self-healing/ssm-output
  └── log stream: <instance-id>/<command-id>
        │
        ▼
Splunk Universal Forwarder (running on EC2 in logging account)
  reads from CloudWatch via Splunk Add-on for AWS
        │
        ├── Linux hosts  →  Splunk index: linux_os
        └── Windows hosts →  Splunk index: windows_os
```

**Key configuration points:**

- The CloudWatch Logs agent (or the SSM `CloudWatchOutputEnabled` flag) writes SSM stdout in near real-time to `/self-healing/ssm-output`.
- The Splunk Add-on for AWS (deployed in the `logging` account) polls this log group and forwards entries to Splunk Cloud HEC.
- Sourcetype is set to `linux_ssm_triage` or `windows_ssm_triage` to enable field extraction of the labelled sections (`=== Service Status ===`, `=== Critical Journal Errors ===`, etc.).
- Splunk alerts are configured on the `linux_os` and `windows_os` indexes to surface `INACTIVE` service states and `ALERT:` disk lines.

### 5.2 Container Log Path (Linux and Windows EKS Pods)

```
Application container (stdout / stderr)
        │
        ▼
Fluent Bit DaemonSet (deployed on every EKS node — Linux + Windows)
  uses dual toleration: os=windows:NoSchedule + Exists
        │
        ▼
Splunk Cloud HEC endpoint (TLS, port 443)
  Host: ${splunk_hec_host}
  Token: ${splunk_hec_token}  (sourced from Secrets Manager)
        │
        ▼
Splunk index: k8s_containers
```

**Key configuration points:**

- Fluent Bit is deployed as a DaemonSet via the `eks-addons` Terraform module using Helm.
- The `fluentbit-values.yaml` file (at `terraform/modules/eks-addons/fluentbit-values.yaml`) defines the `[OUTPUT]` block targeting Splunk HEC with TLS enabled.
- Kubernetes metadata (namespace, pod name, container name, node name) is enriched by the Kubernetes filter plugin and appended to each log record.
- Windows container stdout is captured by Fluent Bit running on the Windows nodes under the `os=windows:NoSchedule` toleration.

### 5.3 Splunk Search Examples

Search for recent Linux service failures:

```
index=linux_os sourcetype=linux_ssm_triage "INACTIVE"
| table _time, host, instanceId, message
| sort -_time
```

Search for Windows IIS failures:

```
index=windows_os sourcetype=windows_ssm_triage "Stopped"
| table _time, host, instanceId, message
| sort -_time
```

Search container errors across all namespaces:

```
index=k8s_containers level=error
| stats count by kubernetes.namespace_name, kubernetes.pod_name
| sort -count
```

---

## 6. Container Triage Supplement

SSM Run Command cannot reach Kubernetes pods directly — pods are ephemeral and do not have stable instance IDs. The following techniques complement the SSM-based approach for container workloads.

### 6.1 Streaming Pod Logs with `kubectl logs`

Retrieve the last 100 lines from a running pod:

```bash
kubectl logs <pod-name> -n <namespace> --tail=100
```

Stream logs in real time:

```bash
kubectl logs <pod-name> -n <namespace> --follow
```

For multi-container pods, specify the container:

```bash
kubectl logs <pod-name> -n <namespace> -c <container-name> --tail=100
```

For a crashed or restarted pod, retrieve the previous container's logs:

```bash
kubectl logs <pod-name> -n <namespace> --previous
```

### 6.2 Live Diagnostics with `kubectl exec`

Open a shell in a running Linux container:

```bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
```

Run a one-off diagnostic command without an interactive shell:

```bash
kubectl exec <pod-name> -n <namespace> -- df -h
kubectl exec <pod-name> -n <namespace> -- cat /etc/nginx/nginx.conf
kubectl exec <pod-name> -n <namespace> -- curl -s http://localhost:8080/health
```

For Windows containers:

```bash
kubectl exec -it <pod-name> -n <namespace> -- powershell.exe
kubectl exec <pod-name> -n <namespace> -- powershell.exe -Command "Get-Process"
```

> **Note:** `kubectl exec` requires the `exec` RBAC permission on the target pod. Ensure your IAM role (mapped via `aws-auth` ConfigMap or EKS Access Entries) has the appropriate Kubernetes RBAC binding. Access is audit-logged via EKS audit log → GuardDuty EKS Audit Logs protection plan → `audit` account.

### 6.3 Fluent Bit Sidecar Capture

For workloads that write logs to files rather than stdout/stderr (a common pattern for legacy applications), a Fluent Bit sidecar container can be deployed alongside the application container to tail the log file and forward to Splunk HEC.

Example sidecar pod spec excerpt:

```yaml
volumes:
  - name: app-logs
    emptyDir: {}

containers:
  - name: app
    image: <ecr-image>
    volumeMounts:
      - name: app-logs
        mountPath: /var/log/app

  - name: fluent-bit-sidecar
    image: fluent/fluent-bit:latest
    env:
      - name: SPLUNK_HEC_HOST
        valueFrom:
          secretKeyRef:
            name: splunk-hec-secret
            key: host
      - name: SPLUNK_HEC_TOKEN
        valueFrom:
          secretKeyRef:
            name: splunk-hec-secret
            key: token
    volumeMounts:
      - name: app-logs
        mountPath: /var/log/app
```

The sidecar Fluent Bit instance reads `/var/log/app/*.log` and forwards entries to Splunk HEC, with the same field enrichment as the DaemonSet approach. This pattern is used when the application cannot be modified to write to stdout.

### 6.4 Correlating SSM and Container Diagnostics

When a CloudWatch Alarm fires on an EKS node metric (e.g., high CPU on a node), the self-healing pipeline targets the underlying EC2 node instance (identified by its `SelfHealingEnabled` tag). The SSM triage script captures OS-level metrics (disk, service state). For application-level diagnosis, the on-call engineer should then use `kubectl` to correlate which pods are running on the affected node and inspect their logs:

```bash
# Find pods scheduled on the affected node
kubectl get pods --all-namespaces -o wide \
  --field-selector spec.nodeName=<node-instance-id>
```

---

## 7. Automated vs Manual Remediation

### 7.1 What the Step Functions State Machine Attempts Automatically

The **Remediate** state executes targeted SSM Run Command documents to address the most common service failures without human intervention.

**Linux — automated remediation actions:**

| Condition Detected                        | Automated Action                                             |
|-------------------------------------------|--------------------------------------------------------------|
| `nginx: INACTIVE`                         | `systemctl restart nginx`                                    |
| `httpd: INACTIVE`                         | `systemctl restart httpd`                                    |
| Service started but health check failing  | `systemctl reload nginx` (config reload without full restart) |
| CloudWatch alarm on custom application metric | Invoke application-specific SSM document (if registered)  |

**Windows — automated remediation actions:**

| Condition Detected                        | Automated Action                                             |
|-------------------------------------------|--------------------------------------------------------------|
| `W3SVC  Stopped`                          | `Restart-Service W3SVC`                                      |
| Application pool in `Stopped` state       | `Start-WebAppPool -Name <pool-name>`                         |
| IIS site stopped                          | `Start-Website -Name <site-name>`                            |

After each remediation, the **Verify** state checks `$.healthCheckPassed`. If the ALB health check or custom probe returns healthy, the execution ends successfully and the CloudWatch Alarm is expected to auto-resolve. If verification fails, the state machine transitions to **Escalate**.

### 7.2 What Requires Human Intervention

The following conditions are detected by the triage scripts but cannot be resolved by the automated remediation state. When the Step Functions execution reaches **Escalate** for these conditions, an SNS notification is sent and the on-call engineer must intervene manually:

| Condition                          | Reason Automation Cannot Resolve                                                      | Required Human Action                                                              |
|------------------------------------|---------------------------------------------------------------------------------------|------------------------------------------------------------------------------------|
| **Disk full** (`ALERT:` in triage output, usage ≥ 98%) | Reclaiming disk space requires understanding which data to delete or archive — automation cannot make this determination safely | Log into instance via SSM Session Manager; identify large files/directories; archive or delete as appropriate; review log rotation policies |
| **Certificate expiry**             | Renewing or replacing TLS certificates requires coordination with PKI/CA processes and may involve DNS validation | Rotate certificate via ACM or internal CA; update ALB listener or application config; restart service |
| **Code defects**                   | Application exceptions surfaced in journal or Event Log indicate bugs in deployed code | Roll back deployment via GitOps (update image tag in GitOps repo; Flux reconciles); engage development team |
| **Infrastructure failures**        | Underlying AWS resource failures (EBS volume, network interface, AZ outage) cannot be remediated by OS-level scripts | Engage AWS Support if AZ issue; restore EBS from snapshot; replace instance via Auto Scaling group |
| **Security incidents**             | GuardDuty P1 findings (e.g., cryptocurrency mining, exfiltration) require containment, not service restart | Follow the escalation playbook (`docs/runbooks/escalation-playbook.md`); isolate instance; preserve forensic state |
| **Configuration drift**            | Service fails to start due to corrupted or incorrect config file | Review config in version control; redeploy via GitOps or Terraform; investigate how drift occurred |

### 7.3 Escalation Trigger

The **Escalate** state publishes to the SNS topic specified by `var.sns_topic_arn` with a structured message containing:

- `instanceId` — target EC2 instance ID
- `alarmName` — originating CloudWatch Alarm name
- `triageOutputSummary` — first 1,000 characters of SSM command output
- `timestamp` — ISO 8601 UTC timestamp of escalation
- `severity` — P1 / P2 / P3 classification

SNS subscribers include the PagerDuty integration endpoint (for P1/P2 incidents) and the team operations email list (for P3 notifications). The on-call engineer receives the triage output summary directly in the PagerDuty alert, enabling informed triage before opening an SSM session.

---

## 8. Script References

The diagnostic scripts are version-controlled alongside the platform code. The exact repository paths are:

| Script | Repository Path | Target OS | SSM Document Name |
|--------|----------------|-----------|-------------------|
| Linux triage | `docs/runbooks/scripts/linux-triage.sh` | Amazon Linux 2 / Amazon Linux 2023 | `ZeroTrustPlatform-LinuxTriage` |
| Windows triage | `docs/runbooks/scripts/windows-triage.ps1` | Windows Server 2019 / 2022 | `ZeroTrustPlatform-WindowsTriage` |

Both scripts are registered as `aws_ssm_document` resources of type `Command` in `terraform/modules/self-healing/ssm.tf`. The `aws_sfn_state_machine` resource in `terraform/modules/self-healing/sfn.tf` references these document names in the **Diagnose** and **Remediate** state definitions.

### Required IAM Permissions for Manual Invocation

The IAM role used to manually invoke SSM Run Command must have the following permissions:

```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:SendCommand",
    "ssm:GetCommandInvocation",
    "ssm:ListCommandInvocations"
  ],
  "Resource": "*"
}
```

Note: Direct SSH (port 22) and RDP (port 3389) access is blocked organisation-wide by the `deny-open-ssh-rdp.json` SCP attached to all workload OUs. All operational access to EC2 instances is via SSM Session Manager or SSM Run Command exclusively.

---

*For escalation procedures and post-incident review guidance, see [`docs/runbooks/escalation-playbook.md`](./escalation-playbook.md).*
