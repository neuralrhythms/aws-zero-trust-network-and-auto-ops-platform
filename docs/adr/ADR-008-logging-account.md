# ADR-008: Dedicated Logging Account in Security OU as Immutable Log Archive

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

The platform generates logs from multiple sources across all eight accounts: CloudTrail organisation trail, VPC Flow Logs, Network Firewall logs, GuardDuty findings, Inspector findings, and EKS audit logs. These logs must be retained immutably for compliance and forensic purposes. Options evaluated were centralising logs in the `audit` account alongside security tooling, using CloudWatch Logs in each account, and a dedicated `logging` account with S3 Object Lock.

| Criterion | Logs in Audit Account | Dedicated Logging Account |
|-----------|-----------------------|--------------------------|
| Separation of concerns | Security tooling and log storage share blast radius | Independent — compromise of audit tooling cannot affect logs |
| Immutability | Possible with S3 Object Lock | Native — purpose-built S3 Object Lock (WORM) |
| Cross-account delivery | Not required | All accounts deliver via S3 bucket policy |
| Compliance | Logs accessible to same role that manages GuardDuty | Full separation: different account, different IAM boundary |

---

## Decision

Provision a dedicated **`logging` account** in the Security OU. A single S3 bucket with **S3 Object Lock in Compliance mode** (WORM) receives all log streams: CloudTrail organisation trail, VPC Flow Logs, Network Firewall alert logs, and GuardDuty/Inspector findings exports. Object Lock prevents deletion or overwrite by any principal — including root — for the retention period. The `audit` account manages security tooling (GuardDuty, Inspector, Security Hub) but has no write access to the `logging` bucket.

---

## Consequences

**Positive:** Log integrity is independent of security tooling access. Even if the `audit` account is compromised, historical logs remain protected. S3 Object Lock satisfies common compliance requirements (PCI-DSS, SOC 2, ISO 27001) for tamper-evident log retention. Splunk can read from the S3 bucket via the Splunk Add-on for AWS.

**Negative:** Cross-account S3 bucket policies must be maintained as new accounts are added to the organisation. Object Lock Compliance mode prevents log deletion even for legitimate housekeeping — retention period must be set carefully.

**Risk mitigated:** Separates the security tooling blast radius from the audit evidence blast radius. A misconfigured GuardDuty suppression rule or compromised `audit` account credential cannot retroactively alter the forensic evidence trail.
