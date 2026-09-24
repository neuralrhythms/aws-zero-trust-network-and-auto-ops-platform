# ADR-009: Amazon GuardDuty for Organisation-Wide Threat Detection

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

The platform requires continuous threat detection across all eight accounts covering network anomalies, credential compromise, malware, and data exfiltration. Options evaluated were Amazon GuardDuty, a third-party SIEM-integrated threat detection tool (e.g. Lacework, Wiz), and manual CloudTrail/VPC Flow Log alerting via CloudWatch metric filters.

| Criterion | Manual CW Metric Filters | Third-Party Tool | GuardDuty |
|-----------|--------------------------|------------------|-----------|
| AWS-native events | Partial — manually crafted | API-based polling | Direct integration (CloudTrail, DNS, VPC Flow) |
| Organisation-wide | Complex — per-account setup | Varies by vendor | Single delegated admin via `audit` account |
| ML-based anomaly detection | None | Yes | Yes — baseline + anomaly models |
| EKS runtime threat detection | No | Vendor-specific | Native EKS Runtime Monitoring |
| Cost | CloudWatch filter costs | Per-seat or resource-based | Per-volume (finding processing) |

---

## Decision

Enable **Amazon GuardDuty** organisation-wide with the `audit` account as the delegated administrator. All protection plans are enabled: EKS Audit Log Monitoring, EKS Runtime Monitoring, S3 Protection, EC2 Malware Protection, RDS Login Activity Monitoring, and Lambda Network Activity Monitoring. High-severity findings trigger an EventBridge rule → SNS notification for immediate on-call alerting. All findings are exported to the `logging` account S3 bucket.

---

## Consequences

**Positive:** Zero operational overhead for detector maintenance — AWS manages the ML models and threat intelligence feeds. Organisation-wide coverage from a single delegated admin account. EKS Runtime Monitoring detects in-container threats (reverse shells, cryptomining, privilege escalation) that network-level controls cannot see.

**Negative:** GuardDuty findings require tuning to suppress false positives for expected behaviour (e.g. EC2 instance profile credential use from Lambda). Per-GB finding processing cost scales with log volume.

**Risk mitigated:** Provides detection coverage for the attack vectors not prevented by preventive controls — for example, a valid IAM credential used from an unusual location, or an EKS pod executing an unexpected binary after a supply-chain compromise.
