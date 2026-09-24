# ADR-003: EKS Managed Node Groups over Self-Managed Nodes

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Platform Architecture Team

---

## Context

The platform runs heterogeneous Kubernetes workloads requiring both Linux (Amazon Linux 2) and Windows (Server 2019 Core) compute. Node provisioning and lifecycle management options evaluated were EKS Managed Node Groups (MNG), self-managed node groups using Launch Templates, and Karpenter as the sole provisioning mechanism.

| Criterion | Self-Managed Nodes | Managed Node Groups |
|-----------|--------------------|---------------------|
| AMI patching | Manual — operator builds and rotates AMIs | AWS manages AMI updates; rolling replacement |
| Node registration | Operator manages bootstrap script | Automatic via EKS-optimised AMI |
| Graceful drain on termination | Manual SIGTERM handling required | Built-in graceful node draining |
| Windows support | Supported with custom bootstrap | Supported natively (`WINDOWS_CORE_2019_x86_64`) |
| Karpenter compatibility | Required for dynamic scaling | MNG provides baseline; Karpenter layers on top |

---

## Decision

Use **EKS Managed Node Groups** for baseline compute: one Linux MNG (`AL2_x86_64`) and one Windows MNG (`WINDOWS_CORE_2019_x86_64`). Windows nodes carry a `os=windows:NoSchedule` taint so only pods with a matching toleration are scheduled on Windows capacity. Karpenter NodePools layer on top of the MNG baseline for burst scaling, using the same taint/toleration convention for OS-specific pod placement.

---

## Consequences

**Positive:** AWS handles AMI lifecycle, security patching, and node drain/replace orchestration. OIDC provider (`enable_irsa = true`) is provisioned automatically, enabling IRSA for all workload pods. No node bootstrap scripts to maintain.

**Negative:** Less control over node configuration compared to self-managed nodes. MNG updates may require a maintenance window to perform rolling node replacements.

**Risk mitigated:** The Windows taint prevents Linux-only workloads from accidentally scheduling on Windows nodes, avoiding container image compatibility failures at runtime.
