# ADR-005: SSM Session Manager over SSH/RDP

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

Operators need interactive shell access to EC2 instances and EKS nodes for incident investigation, patching verification, and systems operations. Traditional approaches rely on SSH (port 22) for Linux and RDP (port 3389) for Windows, which require bastion hosts, open inbound security group rules, and key pair management. The Zero-Trust posture of this platform requires eliminating all open inbound ports and maintaining a complete, immutable audit trail of all operator access.

| Criterion | SSH / RDP + Bastion | SSM Session Manager |
|-----------|---------------------|---------------------|
| Inbound port exposure | Port 22 / 3389 open to bastion CIDR | No inbound ports required |
| Key/credential management | SSH key pairs; RDP passwords | IAM identity; no long-lived credentials |
| Session audit trail | Manual — depends on bastion logging config | Full session transcript to CloudTrail + S3 |
| SCP enforcement | Cannot enforce via SCP | SCP `deny-open-ssh-rdp` blocks port 22/3389 SG rules |
| Windows support | RDP over bastion | SSM Fleet Manager native RDP tunnel |

---

## Decision

Eliminate all SSH and RDP access. All interactive access uses **AWS Systems Manager Session Manager** for shell sessions and **SSM Fleet Manager** for Windows RDP tunnels. The SCP `deny-open-ssh-rdp` blocks any security group rule that opens port 22 or 3389 across all member accounts, making the control structurally enforced rather than operationally dependent. Automated remediation uses **SSM Run Command** invoked by the Step Functions self-healing pipeline.

---

## Consequences

**Positive:** No bastion hosts to maintain, patch, or pay for. No SSH keys to rotate. Every session is logged to CloudTrail and, via the session transcript, to the `logging` account S3 bucket. The SCP means even an operator with broad IAM permissions cannot open a direct SSH port.

**Negative:** SSM Agent must be installed and running on all EC2 instances. Instances must have outbound HTTPS to the SSM regional endpoint (allow-listed in the Network Firewall). Initial SSM connectivity troubleshooting can be harder than SSH connectivity checks.

**Risk mitigated:** Eliminates the most common lateral-movement vector (compromised bastion or leaked SSH key). The SCP enforcement means the control survives operator error — a misconfigured security group rule is rejected by the policy engine before it takes effect.
