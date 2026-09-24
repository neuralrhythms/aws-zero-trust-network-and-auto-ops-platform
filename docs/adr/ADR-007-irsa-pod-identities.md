# ADR-007: IRSA / EKS Pod Identities over Node-Level IAM Instance Profiles

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

EKS workload pods require AWS API access (e.g. Fluent Bit writing to S3, AWS Load Balancer Controller managing ALBs, application pods reading Secrets Manager). The traditional approach attaches an IAM instance profile to the EC2 node, granting all pods on the node the same broad permissions. The Zero-Trust posture requires per-pod, least-privilege IAM credentials with no ambient node-level permissions.

| Criterion | Node Instance Profile | IRSA / Pod Identities |
|-----------|----------------------|----------------------|
| Credential scope | All pods on node share the same role | Each pod's service account has its own role |
| Least privilege | Impossible — broadest permissions wins | Per-pod role with minimal policy |
| Credential rotation | Long-lived EC2 metadata credentials | Short-lived STS tokens (1-hour TTL) |
| Audit trail | CloudTrail logs node role ARN | CloudTrail logs pod service account ARN |
| Complexity | Simple | Requires OIDC provider + trust policy per role |

---

## Decision

Enable **IRSA (IAM Roles for Service Accounts)** via `enable_irsa = true` in the `eks-cluster` module. This provisions the cluster OIDC provider. Each workload that needs AWS access is assigned a dedicated Kubernetes service account annotated with an IAM role ARN. The IAM role trust policy references the cluster OIDC provider and the specific namespace/service-account, ensuring the STS `AssumeRoleWithWebIdentity` call succeeds only for the intended pod identity.

---

## Consequences

**Positive:** Pods receive short-lived STS tokens injected via a projected volume — no long-lived credentials stored anywhere. CloudTrail events show the exact service account ARN, enabling precise attribution. A compromised pod cannot escalate to other pods' IAM roles.

**Negative:** Each new workload requiring AWS access needs a dedicated IAM role and trust policy. OIDC provider ARN must be threaded through to any module creating IRSA roles, creating a soft dependency on the `eks-cluster` module output `oidc_provider_arn`.

**Risk mitigated:** Eliminates the most common EKS privilege escalation path — a compromised pod on a broadly-permissioned node. Each pod's maximum blast radius is bounded by its own least-privilege role.
