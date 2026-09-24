# ADR-002: AWS Network Firewall for Centralised Egress Inspection

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

Zero-Trust egress requires that all outbound internet traffic from workload VPCs be inspected and filtered against an allowlist before reaching the NAT Gateway. Options evaluated were AWS Network Firewall, a third-party virtual appliance (e.g. Palo Alto VM-Series), and AWS Gateway Load Balancer with a partner appliance.

| Criterion | Third-Party Appliance | AWS Network Firewall |
|-----------|-----------------------|----------------------|
| Operational model | Self-managed AMI, patching, HA clustering | Fully managed, AWS-maintained |
| FQDN-based filtering | Vendor-specific configuration | Native stateful domain-list rule groups |
| Scaling | Manual scale-out; risk of traffic bottleneck | Auto-scales to traffic volume |
| Cost | High (VM licensing + EC2 + ELB) | Per-hour endpoint + per-GB processing |
| AWS integration | Requires GWLB attachment | Native TGW/VPC integration |

---

## Decision

Deploy **AWS Network Firewall** in the `app-private` subnet of the `network-hub` VPC. A stateful rule group using domain-list (FQDN) matching enforces an explicit allowlist of permitted egress destinations. The default action drops all traffic not matching an allowlist rule. All workload spoke traffic is routed through the TGW to the firewall endpoint before reaching the NAT Gateway.

---

## Consequences

**Positive:** No AMI patching, no HA cluster configuration, and no manual scaling. FQDN-based stateful rules block exfiltration and command-and-control traffic at the DNS level. Firewall logs ship to the `logging` account S3 bucket for immutable audit.

**Negative:** AWS Network Firewall does not perform TLS deep inspection without additional configuration. The per-GB data processing charge must be monitored as workload traffic grows.

**Risk mitigated:** All spoke VPCs are denied direct internet access by SCP (`deny-direct-internet-egress`). Even if a route table is misconfigured, the SCP prevents attaching an Internet Gateway directly to a workload VPC.
