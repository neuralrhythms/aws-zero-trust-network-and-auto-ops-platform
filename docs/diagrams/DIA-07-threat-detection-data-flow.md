# DIA-07: Threat Detection Data Flow

This diagram illustrates how security findings from Amazon GuardDuty and Amazon Inspector flow through the platform's centralised detection and response architecture. All findings are aggregated in the `audit` account, which acts as the delegated administrator for both services across the AWS Organisation. An EventBridge rule in the `audit` account routes findings to the `logging` account's immutable S3 archive for long-term retention and Splunk ingestion, while high-severity findings trigger an SNS notification to the on-call team for immediate response.

```mermaid
flowchart TD
    GD["Amazon GuardDuty\n(all member accounts)"]
    INS["Amazon Inspector\n(all member accounts)"]
    AUDIT["audit account\nFindings Aggregation"]
    EB["EventBridge Rule\n(audit account)"]
    S3["logging account\nS3 Bucket\n(Object Lock — WORM)"]
    SPLUNK_S3["Splunk S3 Add-on"]
    SPLUNK["Splunk Cloud"]
    SNS["SNS Topic\n(high-severity alerts)"]
    ONCALL["On-Call Team\n(PagerDuty / Email)"]

    GD -->|"findings"| AUDIT
    INS -->|"vulnerability findings"| AUDIT
    AUDIT --> EB
    EB -->|"all findings"| S3
    S3 --> SPLUNK_S3
    SPLUNK_S3 --> SPLUNK
    EB -->|"severity = HIGH or CRITICAL"| SNS
    SNS --> ONCALL
```
