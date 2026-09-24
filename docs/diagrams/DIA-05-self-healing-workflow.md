# DIA-05: Self-Healing Workflow

This diagram illustrates the event-driven self-healing automation flow triggered when a workload failure is detected. A CloudWatch Alarm fires and routes through EventBridge to invoke an AWS Step Functions state machine, which orchestrates five sequential states: Detect, Diagnose, Remediate, Verify, and Escalate. SSM Run Command executes diagnostic and remediation scripts on the target instance, and SNS publishes an on-call alert if automated recovery is unsuccessful.

```mermaid
sequenceDiagram
    autonumber
    participant CW as "CloudWatch"
    participant EB as "EventBridge"
    participant SFN as "Step Functions"
    participant SSM as "SSM Run Command"
    participant CWL as "CloudWatch Logs"
    participant SNS as "SNS Topic"
    participant OC as "On-Call Engineer"

    CW->>EB: Alarm state ALARM (metric threshold breached)
    EB->>SFN: Trigger execution (rule: AlarmStateChange → ALARM)

    note over SFN: State 1 — Detect
    SFN->>SSM: SendCommand: linux-triage.sh (detect service failure)
    SSM-->>CWL: Stream command output → /self-healing/ssm-output
    SSM-->>SFN: CommandInvocation result (exit code + stdout)

    note over SFN: State 2 — Diagnose
    SFN->>SFN: Evaluate triage output (parse service status, disk, errors)

    note over SFN: State 3 — Remediate
    SFN->>SSM: SendCommand: restart service (systemctl restart nginx/httpd)
    SSM-->>CWL: Stream remediation output
    SSM-->>SFN: CommandInvocation result (exit code)

    note over SFN: State 4 — Verify
    SFN->>CW: GetMetricData / DescribeAlarms (health re-check)
    CW-->>SFN: Alarm state (OK or still ALARM)

    alt Health check passed ($.healthCheckPassed = true)
        SFN->>SFN: Transition to END — remediation successful
    else Health check failed ($.healthCheckPassed = false)
        note over SFN: State 5 — Escalate
        SFN->>SNS: Publish alert (instance ID, alarm name, triage summary, timestamp)
        SNS-->>OC: PagerDuty page + on-call email notification
    end
```
