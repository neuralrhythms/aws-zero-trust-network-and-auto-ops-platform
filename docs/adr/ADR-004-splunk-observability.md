# ADR-004: Splunk Cloud Observability over CloudWatch/OpenSearch

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

The platform requires centralised log aggregation and observability across eight AWS accounts, covering EC2 system logs, EKS container logs, VPC Flow Logs, CloudTrail events, and application metrics. The client has an existing Splunk Cloud subscription. Native AWS alternatives (CloudWatch Logs Insights + OpenSearch) were evaluated alongside the existing Splunk investment.

| Criterion | CloudWatch + OpenSearch | Splunk Cloud |
|-----------|-------------------------|--------------|
| Cross-account aggregation | Complex subscription filter fan-out | Forwarder/HEC sends directly from source |
| Existing client investment | None | Active subscription |
| Query language | CWL Insights / Lucene | SPL — familiar to client's SOC team |
| EC2 log collection | CloudWatch Agent | Splunk Universal Forwarder |
| EKS log collection | Fluent Bit → CWL | Fluent Bit → HEC |
| Long-term retention cost | S3 export required for >90 days | S3 archive tier via Splunk SmartStore |

---

## Decision

Use **Splunk Cloud** as the single observability backend. EC2 instances run the Splunk Universal Forwarder. EKS pods ship logs via a **Fluent Bit DaemonSet** (deployed by the `eks-addons` module) using the HTTP Event Collector (HEC) output. The Fluent Bit DaemonSet is configured with tolerations for both Linux nodes (no taint) and Windows nodes (`os=windows:NoSchedule`) so all pods on all node types are covered. The Splunk HEC token is marked `sensitive = true` and sourced from AWS Secrets Manager at deploy time — never committed to source control.

---

## Consequences

**Positive:** Reuses existing client licence. SOC team retains familiar SPL query interface. Single pane of glass across all eight accounts. Fluent Bit adds negligible node overhead.

**Negative:** Splunk Cloud HEC endpoint must be reachable from workload VPCs; requires an allowlist entry in the Network Firewall FQDN rule group. HEC token rotation requires a Helm upgrade of the Fluent Bit release.

**Risk mitigated:** Sensitive HEC token is injected via `data.aws_secretsmanager_secret_version` at apply time, never stored in `.tfvars` or Terraform state in plaintext.
