# ADR-010: Amazon Inspector for Continuous Vulnerability Management

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

The platform runs EC2 instances, EKS workloads with container images stored in ECR, and Lambda functions. All compute must be continuously scanned for known CVEs and software vulnerabilities. Options evaluated were Amazon Inspector v2, AWS Security Hub aggregated findings from third-party scanners, ECR Basic Scanning, and a standalone vulnerability scanner (Trivy in CI only).

| Criterion | ECR Basic Scan + Trivy CI | Amazon Inspector v2 |
|-----------|---------------------------|---------------------|
| Runtime EC2 scanning | No | Yes — agent-based, continuous |
| ECR Enhanced scanning | No (push-time only) | Yes — continuous re-scan on new CVE publication |
| Lambda scanning | No | Yes — package and layer scanning |
| Organisation-wide | Manual per-account setup | Delegated admin via `audit` account |
| Finding aggregation | Multiple tools, multiple consoles | Single Inspector findings console |

---

## Decision

Enable **Amazon Inspector v2** organisation-wide with the `audit` account as the delegated administrator. Three scan types are enabled: **EC2 scanning** (SSM Agent-based, agentless fallback), **ECR Enhanced scanning** (continuous re-scan triggered by new CVE publications, not just image push), and **Lambda standard scanning**. Critical and high findings trigger an EventBridge rule → SNS notification. All findings are exported to the `logging` account S3 bucket and forwarded to Splunk Cloud via the Splunk Add-on for AWS.

---

## Consequences

**Positive:** ECR Enhanced scanning re-evaluates existing images when new CVEs are published — a critical gap in push-time-only scanning. EC2 scanning uses the SSM Agent already deployed for Session Manager, requiring no additional agent. Lambda scanning covers function code and layers without instrumentation.

**Negative:** ECR Enhanced scanning incurs a per-image continuous scanning fee in addition to the basic scan fee. Inspector findings must be reviewed and prioritised; without a triage process, high finding volumes can cause alert fatigue.

**Risk mitigated:** Closes the window between image build and CVE publication — an image that was clean at push time is re-flagged automatically when a new critical CVE is published for one of its packages, allowing the team to re-build and re-deploy before exploitation.
