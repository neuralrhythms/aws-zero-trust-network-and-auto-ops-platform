# AWS Zero-Trust Network Egress & Automated Operations Platform

## Problem Statement

Many AWS environments accumulate risk through three compounding gaps: **unfiltered egress** — workloads route directly to the internet without inspection, allowing exfiltration, command-and-control traffic, and access to malicious destinations; **manual operations** — there is no automated remediation or self-healing capability, so incidents that could be resolved in seconds instead wait for on-call engineers, increasing mean time to recovery and operational toil; and **lack of SSH-free access** — reliance on open SSH (port 22) and RDP (port 3389) exposes instances to brute-force attacks, lateral movement, and audit-trail gaps. This repository demonstrates a production-grade AWS architecture that closes all three gaps: a hub-spoke Transit Gateway network with AWS Network Firewall enforces allow-listed egress; an EventBridge → Step Functions → SSM Run Command pipeline delivers event-driven self-healing; and Service Control Policies combined with SSM Session Manager eliminate direct SSH/RDP access across the entire AWS Organisation.

---

## Repository Layout

```
aws-zero-trust-network-and-auto-ops-platform/
├── README.md                                    ← You are here — master artefact index
│
├── docs/
│   ├── architecture-reference.md               ← Full 12-section architecture reference
│   ├── sow.md                                  ← Client-facing Statement of Work
│   │
│   ├── adr/                                    ← Architecture Decision Records (10 ADRs)
│   │   ├── ADR-001-transit-gateway.md
│   │   ├── ADR-002-network-firewall.md
│   │   ├── ADR-003-eks-managed-node-groups.md
│   │   ├── ADR-004-splunk-observability.md
│   │   ├── ADR-005-ssm-over-ssh.md
│   │   ├── ADR-006-step-functions-self-healing.md
│   │   ├── ADR-007-irsa-pod-identities.md
│   │   ├── ADR-008-logging-account.md
│   │   ├── ADR-009-guardduty.md
│   │   └── ADR-010-inspector.md
│   │
│   ├── diagrams/                               ← Mermaid architecture diagrams (8 diagrams)
│   │   ├── DIA-01-multi-account-layout.md
│   │   ├── DIA-02-hub-spoke-network.md
│   │   ├── DIA-03-eks-ingress-auth-flow.md
│   │   ├── DIA-04-cross-account-iam.md
│   │   ├── DIA-05-self-healing-workflow.md
│   │   ├── DIA-06-observability-data-flow.md
│   │   ├── DIA-07-threat-detection-data-flow.md
│   │   └── DIA-08-cicd-promotion-pipeline.md
│   │
│   └── runbooks/
│       ├── hybrid-os-operations-runbook.md     ← Incident Response & Systems Operations Guide
│       ├── escalation-playbook.md              ← Escalation path runbook
│       └── scripts/
│           ├── linux-triage.sh                 ← Linux diagnostic script (SSM Run Command)
│           └── windows-triage.ps1              ← Windows diagnostic script (SSM Run Command)
│
└── terraform/
    ├── environments/                           ← 8 account root modules (one per AWS account)
    │   ├── management/                         ← SCPs, AWS Organizations root
    │   ├── network-hub/                        ← TGW, Network Firewall, NAT GW
    │   ├── audit/                              ← GuardDuty + Inspector delegated admin
    │   ├── logging/                            ← Immutable S3 log archive (S3 Object Lock)
    │   ├── workload-dev/                       ← Dev EKS cluster (t3.* instance types)
    │   ├── workload-test/                      ← Test EKS cluster (t3.* instance types)
    │   ├── workload-staging/                   ← Staging EKS cluster (m6i.* instance types)
    │   └── workload-prod/                      ← Production EKS cluster (m6i.* instance types)
    │
    └── modules/                                ← 11 shared reusable modules
        ├── vpc/                                ← 4-tier VPC (public-ingress, app-private, data-private, tgw-attach)
        ├── tgw-attachment/                     ← Spoke VPC → Transit Gateway attachment
        ├── network-firewall/                   ← AWS Network Firewall with FQDN allow-list
        ├── eks-cluster/                        ← EKS cluster with Linux + Windows Managed Node Groups
        ├── eks-addons/                         ← ALB Controller, Karpenter, Fluent Bit DaemonSet
        ├── ecr/                                ← ECR repositories (immutable tags, scan-on-push)
        ├── self-healing/                       ← EventBridge → Step Functions → SSM Run Command
        ├── guardduty/                          ← GuardDuty org-wide detector + protection plans
        ├── inspector/                          ← Inspector EC2/ECR/Lambda org configuration
        ├── scp-policies/                       ← SCP JSON policies (deny egress, deny SSH/RDP)
        └── multi-account-example/              ← Canonical cross-account module composition demo
```

---

## Documentation Index

### Core Documents

| Document | Description |
|----------|-------------|
| [Architecture Reference](docs/architecture-reference.md) | Full 12-section architecture reference covering all design decisions, network topology, EKS platform, self-healing operations, observability, security controls, and Well-Architected compliance |
| [Architecture Decision Record](docs/adr/architectural-decision-record.md) | A consolidated ADR document with 10 sections. This is intentionally kept concise to prevent documentation explosion considering the scope of the deliverables to a demonstration project. Place holders for detailed ADRs are put in place for use in a enterprise grade engagement. |
| [Statement of Work](docs/sow.md) | Client-facing engagement plan with three delivery phases, milestones, ADR summary, and governance approach |

### Architecture Decision Records

| ADR | Decision |
|-----|----------|
| [ADR-001: Transit Gateway](docs/adr/ADR-001-transit-gateway.md) | AWS Transit Gateway over VPC Peering; dedicated `tgw-attach` /28 subnet justification |
| [ADR-002: Network Firewall](docs/adr/ADR-002-network-firewall.md) | AWS Network Firewall for centralised egress inspection over third-party appliances |
| [ADR-003: EKS Managed Node Groups](docs/adr/ADR-003-eks-managed-node-groups.md) | Managed Node Groups over self-managed nodes for operational simplicity and security |
| [ADR-004: Splunk Observability](docs/adr/ADR-004-splunk-observability.md) | Splunk Cloud (Universal Forwarder + Fluent Bit) over native CloudWatch/OpenSearch |
| [ADR-005: SSM over SSH](docs/adr/ADR-005-ssm-over-ssh.md) | SSM Run Command / Session Manager over SSH/RDP for all operational access |
| [ADR-006: Step Functions Self-Healing](docs/adr/ADR-006-step-functions-self-healing.md) | Step Functions + EventBridge for self-healing orchestration over custom Lambda state machines |
| [ADR-007: IRSA / Pod Identities](docs/adr/ADR-007-irsa-pod-identities.md) | IRSA / EKS Pod Identities over node-level IAM instance profiles |
| [ADR-008: Logging Account](docs/adr/ADR-008-logging-account.md) | Dedicated Logging account in Security OU as immutable log archive (S3 Object Lock) |
| [ADR-009: GuardDuty](docs/adr/ADR-009-guardduty.md) | GuardDuty org-wide threat detection; delegated admin via `audit` account |
| [ADR-010: Inspector](docs/adr/ADR-010-inspector.md) | Inspector continuous vulnerability management; EC2, ECR enhanced, Lambda; delegated admin via `audit` account |

### Architecture Diagrams

| Diagram | Content |
|---------|---------|
| [DIA-01: Multi-Account Layout](docs/diagrams/DIA-01-multi-account-layout.md) | AWS Organization tree — all 8 accounts with OUs |
| [DIA-02: Hub-Spoke Network](docs/diagrams/DIA-02-hub-spoke-network.md) | VPCs, TGW, Network Firewall, NAT GW, 4-tier subnets, egress flow |
| [DIA-03: EKS Ingress & Auth Flow](docs/diagrams/DIA-03-eks-ingress-auth-flow.md) | ALB → AWS LBC → K8s Service → Pods; IRSA token exchange with STS |
| [DIA-04: Cross-Account IAM](docs/diagrams/DIA-04-cross-account-iam.md) | Assume-role trust relationships; SCP boundaries; permission boundaries |
| [DIA-05: Self-Healing Workflow](docs/diagrams/DIA-05-self-healing-workflow.md) | EventBridge → Step Functions (Detect → Diagnose → Remediate → Verify → Escalate) → SSM → SNS |
| [DIA-06: Observability Data Flow](docs/diagrams/DIA-06-observability-data-flow.md) | EC2 → Splunk UF → HEC; EKS pods → Fluent Bit → HEC; S3 logs → Splunk Add-on; Prometheus → Grafana |
| [DIA-07: Threat Detection Data Flow](docs/diagrams/DIA-07-threat-detection-data-flow.md) | GuardDuty + Inspector findings → `audit` aggregation → EventBridge → `logging` S3 → Splunk; high-severity → SNS |
| [DIA-08: CI/CD Promotion Pipeline](docs/diagrams/DIA-08-cicd-promotion-pipeline.md) | Developer push → GitHub Actions → Flux → Dev → Test → Staging → Prod |

### Runbooks & Scripts

| File | Description |
|------|-------------|
| [Hybrid OS Operations Runbook](docs/runbooks/hybrid-os-operations-runbook.md) | Complete Incident Response & Systems Operations Guide for Linux and Windows workloads |
| [Escalation Playbook](docs/runbooks/escalation-playbook.md) | Full escalation path from automated remediation to SNS on-call alert |
| [linux-triage.sh](docs/runbooks/scripts/linux-triage.sh) | Linux diagnostic script — service checks, disk usage, journal errors; invoked via SSM Run Command |
| [windows-triage.ps1](docs/runbooks/scripts/windows-triage.ps1) | Windows diagnostic script — IIS/W3SVC checks, App Pool status, Event Log errors; invoked via SSM Run Command |

---

## Terraform Layout

All Terraform code follows a strict **environments + modules** dual-layout pattern. Environment root modules in `terraform/environments/` contain only `module` blocks — no inline resources. All infrastructure logic lives in the shared modules under `terraform/modules/`.

Each environment directory contains 5 files: `main.tf`, `variables.tf`, `outputs.tf`, `backend.tf`, `terraform.tfvars`.

### Environments (one per AWS account)

| Environment | Account Role | Key Modules |
|-------------|--------------|-------------|
| [management](terraform/environments/management/) | AWS Organizations root, SCPs, consolidated billing | `scp-policies` |
| [network-hub](terraform/environments/network-hub/) | TGW, Network Firewall, NAT GW, VPC Flow Logs | `vpc`, `tgw-attachment`, `network-firewall` |
| [audit](terraform/environments/audit/) | GuardDuty + Inspector delegated admin | `guardduty`, `inspector` |
| [logging](terraform/environments/logging/) | Immutable S3 log archive (Security OU) | `vpc`, S3 Object Lock |
| [workload-dev](terraform/environments/workload-dev/) | Dev EKS cluster (`t3.large` / `t3.xlarge`) | `vpc`, `tgw-attachment`, `eks-cluster`, `eks-addons`, `ecr` |
| [workload-test](terraform/environments/workload-test/) | Test EKS cluster (`t3.large` / `t3.xlarge`) | `vpc`, `tgw-attachment`, `eks-cluster`, `eks-addons`, `ecr` |
| [workload-staging](terraform/environments/workload-staging/) | Staging EKS cluster (`m6i.large` / `m6i.xlarge`) | `vpc`, `tgw-attachment`, `eks-cluster`, `eks-addons`, `ecr` |
| [workload-prod](terraform/environments/workload-prod/) | Production EKS cluster (`m6i.xlarge` / `m6i.2xlarge`) | `vpc`, `tgw-attachment`, `eks-cluster`, `eks-addons`, `ecr` |

### Shared Modules

| Module | Purpose |
|--------|---------|
| [vpc](terraform/modules/vpc/) | 4-tier VPC: `public-ingress`, `app-private`, `data-private`, `tgw-attach` (/28) |
| [tgw-attachment](terraform/modules/tgw-attachment/) | Attaches spoke VPC to Transit Gateway; route table association |
| [network-firewall](terraform/modules/network-firewall/) | AWS Network Firewall with stateful FQDN domain-list allow-list rule group |
| [eks-cluster](terraform/modules/eks-cluster/) | EKS cluster; Linux (AL2) + Windows (Server 2019) Managed Node Groups; instance types from variables |
| [eks-addons](terraform/modules/eks-addons/) | AWS Load Balancer Controller, Karpenter, Fluent Bit DaemonSet (dual Linux/Windows tolerations) |
| [ecr](terraform/modules/ecr/) | ECR repositories with immutable tags and scan-on-push; lifecycle policy for untagged images |
| [self-healing](terraform/modules/self-healing/) | EventBridge rule → Step Functions (5 states) → SSM Run Command → SNS |
| [guardduty](terraform/modules/guardduty/) | GuardDuty detector + org configuration; EKS, S3, EC2 malware, RDS protection plans |
| [inspector](terraform/modules/inspector/) | Inspector org configuration; EC2, ECR enhanced, Lambda scan types |
| [scp-policies](terraform/modules/scp-policies/) | SCP JSON policies: deny direct internet egress, deny open SSH/RDP |
| [multi-account-example](terraform/modules/multi-account-example/) | Canonical cross-account module composition — remote state, TGW attachment, EKS, ECR, GuardDuty, Inspector |

---

## Terraform Validation

All four workload account environments have been validated with `terraform validate`. The validation confirms that the Terraform configuration is syntactically correct, all module inputs and outputs are consistently typed, all required variables are declared, and all cross-module references resolve correctly — without requiring AWS credentials or a live backend.

### What `terraform validate` verifies

- All resource and module block arguments match their provider/module schema
- Every required variable is declared in `variables.tf` and supplied a value path (via `terraform.tfvars` or a default)
- All output references (`module.<name>.<output>`) point to outputs that exist in the referenced module
- Provider version constraints are declared and consistent across the module graph
- No undefined local references, missing required arguments, or type mismatches exist anywhere in the configuration

### Prerequisites

Terraform 1.5.0 or later is required. The commands below use `-backend=false` to skip S3 backend initialisation — the placeholder bucket names in `terraform.tfvars` never need to connect to AWS for validation to succeed.

### Validation steps

```bash
# Navigate to the environments directory
cd aws-zero-trust-network-and-auto-ops-platform/terraform/environments
```

```bash
# workload-dev
terraform -chdir=workload-dev init -backend=false
terraform -chdir=workload-dev validate
```

```bash
# workload-test
terraform -chdir=workload-test init -backend=false
terraform -chdir=workload-test validate
```

```bash
# workload-staging
terraform -chdir=workload-staging init -backend=false
terraform -chdir=workload-staging validate
```

```bash
# workload-prod
terraform -chdir=workload-prod init -backend=false
terraform -chdir=workload-prod validate
```

### Expected output

Each environment produces the following on success:

```
Success! The configuration is valid.
```

This was confirmed across all four workload environments. The `init` step downloads the `terraform-aws-modules/eks/aws ~> 20.0` community module on first run (30–60 seconds); subsequent runs use the local cache and complete in seconds.

### Module graph validated

The validation exercises the full module dependency chain for each workload environment:

```
workload-{dev,test,staging,prod}
  ├── modules/vpc                  (aws_vpc, aws_subnet ×4 tiers, IGW, NAT GW, route tables, flow logs)
  ├── modules/tgw-attachment       (aws_ec2_transit_gateway_vpc_attachment, route table association)
  ├── modules/eks-cluster          (terraform-aws-modules/eks/aws ~> 20.0 — Linux + Windows MNG)
  ├── modules/eks-addons           (AWS LBC, Karpenter, Fluent Bit — scaffold with typed variables)
  └── modules/ecr                  (aws_ecr_repository, aws_ecr_lifecycle_policy)
```

---

## Quick-Start Reading Order

Follow this order for a complete architectural walkthrough:

1. **[README.md](README.md)** ← You are here — orientation and index
2. **[Architecture Reference](docs/architecture-reference.md)** — Full narrative of all design decisions, network topology, EKS platform design, self-healing operations, observability, and security controls
3. **Architecture Decision Records** — Read in sequence for the evidence trail:
   - [ADR-001](docs/adr/ADR-001-transit-gateway.md) → [ADR-002](docs/adr/ADR-002-network-firewall.md) → [ADR-003](docs/adr/ADR-003-eks-managed-node-groups.md) → [ADR-004](docs/adr/ADR-004-splunk-observability.md) → [ADR-005](docs/adr/ADR-005-ssm-over-ssh.md)
   - [ADR-006](docs/adr/ADR-006-step-functions-self-healing.md) → [ADR-007](docs/adr/ADR-007-irsa-pod-identities.md) → [ADR-008](docs/adr/ADR-008-logging-account.md) → [ADR-009](docs/adr/ADR-009-guardduty.md) → [ADR-010](docs/adr/ADR-010-inspector.md)
4. **Architecture Diagrams** — Visual representations to accompany the narrative:
   - [DIA-01](docs/diagrams/DIA-01-multi-account-layout.md) (org layout) → [DIA-02](docs/diagrams/DIA-02-hub-spoke-network.md) (network) → [DIA-03](docs/diagrams/DIA-03-eks-ingress-auth-flow.md) (EKS ingress) → [DIA-04](docs/diagrams/DIA-04-cross-account-iam.md) (IAM)
   - [DIA-05](docs/diagrams/DIA-05-self-healing-workflow.md) (self-healing) → [DIA-06](docs/diagrams/DIA-06-observability-data-flow.md) (observability) → [DIA-07](docs/diagrams/DIA-07-threat-detection-data-flow.md) (threat detection) → [DIA-08](docs/diagrams/DIA-08-cicd-promotion-pipeline.md) (CI/CD)
5. **Runbooks** — Operational procedures:
   - [Hybrid OS Operations Runbook](docs/runbooks/hybrid-os-operations-runbook.md)
   - [Escalation Playbook](docs/runbooks/escalation-playbook.md)
   - [linux-triage.sh](docs/runbooks/scripts/linux-triage.sh) / [windows-triage.ps1](docs/runbooks/scripts/windows-triage.ps1)
6. **Terraform Environments** — Review environments in dependency order:
   - [management](terraform/environments/management/) → [network-hub](terraform/environments/network-hub/) → [audit](terraform/environments/audit/) → [logging](terraform/environments/logging/)
   - [workload-dev](terraform/environments/workload-dev/) → [workload-test](terraform/environments/workload-test/) → [workload-staging](terraform/environments/workload-staging/) → [workload-prod](terraform/environments/workload-prod/)
7. **Terraform Modules** — Review shared modules, starting with the canonical cross-account example:
   - [multi-account-example](terraform/modules/multi-account-example/) (cross-account composition pattern)
   - [vpc](terraform/modules/vpc/) → [tgw-attachment](terraform/modules/tgw-attachment/) → [network-firewall](terraform/modules/network-firewall/)
   - [eks-cluster](terraform/modules/eks-cluster/) → [eks-addons](terraform/modules/eks-addons/) → [ecr](terraform/modules/ecr/)
   - [self-healing](terraform/modules/self-healing/) → [guardduty](terraform/modules/guardduty/) → [inspector](terraform/modules/inspector/) → [scp-policies](terraform/modules/scp-policies/)
8. **[Statement of Work](docs/sow.md)** — Client-facing engagement plan and delivery phases

---

## Key Design Principles

- **Zero-Trust Egress** — all outbound internet traffic is forced through AWS Network Firewall via TGW; only explicitly allow-listed FQDNs are permitted
- **No SSH/RDP** — SCPs deny security group rules that open port 22 or 3389; all operational access uses SSM Session Manager and SSM Run Command
- **Event-Driven Self-Healing** — CloudWatch Alarms trigger EventBridge → Step Functions (Detect → Diagnose → Remediate → Verify → Escalate) automatically, with SNS escalation only when automation cannot resolve the issue
- **Immutable Audit Trail** — all logs centralised in the `logging` account S3 bucket with S3 Object Lock (WORM); separated from the `audit` security tooling account to ensure log integrity is independent of security tooling access
- **DRY Terraform** — all infrastructure logic in `terraform/modules/`; environments contain only `module` blocks; instance types appear only in `terraform.tfvars`
