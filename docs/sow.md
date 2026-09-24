# Statement of Work: AWS Zero-Trust Network Egress & Automated Operations Platform

---

## 1. Executive Summary

This engagement delivers a production-grade AWS platform that eliminates three critical risks present in the client's current environment: unfiltered internet egress from workload accounts, manual and SSH/RDP-dependent operational procedures, and absence of a centrally enforced least-privilege access model. The programme will establish a hub-spoke multi-account AWS Organization enforced by Service Control Policies, deploy an AWS Transit Gateway with centralised Network Firewall egress inspection, build heterogeneous EKS clusters supporting both Linux and Windows workloads, and implement an event-driven self-healing operations capability using EventBridge, Step Functions, and SSM Run Command — eliminating all SSH/RDP access surface. A dedicated `logging` account under the Security OU will serve as an immutable, WORM-compliant log archive, while the `audit` account will act as the delegated administrator for GuardDuty and Amazon Inspector across the organisation. The engagement concludes with validated GitOps pipelines, Splunk-based observability, and a full set of operational runbooks, leaving the client with a well-architected, reviewable platform ready for production workload onboarding.

**Note:** The phases, timelines, and milestones outlined herein represent the planned delivery sequence and are intended to provide a high-level execution framework. Certain activities may be executed in parallel or overlap across phases where dependencies and project readiness permit. The actual execution sequence may therefore vary from the illustrative week-by-week plan while maintaining the agreed scope, milestones, and overall delivery objectives.

---

## 2. Delivery Phases

### Phase 1: Discovery & Architectural Alignment (Weeks 1–4)

**Objectives:** Establish shared understanding of current-state risks, agree on target architecture, and obtain stakeholder sign-off on all key decisions before any infrastructure work begins.

**Key Activities:**

- **Stakeholder Interviews & Current-State Assessment**
  - Interview platform, security, and operations teams to catalogue existing VPC topology, IAM posture, egress controls (or lack thereof), and incident response procedures
  - Document all SSH/RDP access patterns and manual runbooks in scope for automation
  - Identify workload types, OS requirements (Linux/Windows), and containerisation maturity

- **Architecture Workshops**
  - Conduct two structured workshops: (1) Network Architecture — covering AWS Organizations design, Transit Gateway hub-spoke topology, Network Firewall FQDN allowlist strategy, and SCP guardrails; (2) Platform Operations — covering EKS Managed Node Group design (Linux + Windows), IRSA/Pod Identity model, self-healing Step Functions state machine, and Splunk observability integration
  - Present the Trade-Off Matrix to stakeholders and walk through all 10 architectural decisions

- **ADR Review & Approval**
  - Circulate `docs/adr/architectural-decision-record.md` containing ADR-001 through ADR-010 to the Platform Architecture Team and client technical leads
  - Obtain written acceptance on all 10 decisions before proceeding to Phase 2
  - Log any client-requested amendments as change requests against the approved baseline

**Deliverables:**
- Current-state assessment report
- Approved `docs/adr/architectural-decision-record.md`
- Architecture workshop slide deck
- Signed-off target architecture based on `docs/architecture-reference.md`

---

### Phase 2: Core Platform & Landing Zone Construction (Weeks 5–12)

**Objectives:** Build and validate all foundational infrastructure across all 8 AWS accounts, from the Management root through the Security OU accounts and into the workload landing zones.

**Key Activities:**

- **AWS Organizations & Landing Zone Baseline (Weeks 5-6)**
  - Configure AWS Organizations with three OUs: Infrastructure OU, Security OU, and Workloads BU OU
  - Deploy SCPs from the `scp-policies` module: `deny-direct-internet-egress` (blocks `ec2:CreateInternetGateway` and direct IGW route creation) and `deny-open-ssh-rdp` (blocks port 22/3389 ingress from `0.0.0.0/0`) to all workload accounts
  - Apply Terraform state isolation — one S3 backend key per account using `terraform/environments/<account>/backend.tf`

- **Network Hub Deployment (Weeks 7-8)**
  - Deploy the `network-hub` environment using `terraform/environments/network-hub/main.tf`
  - Provision the 4-tier VPC (`public-ingress`, `app-private`, `data-private`, `tgw-attach` /28 per AZ)
  - Deploy Transit Gateway (TGW) as the shared transit backbone; output `transit_gateway_id` and `spoke_route_table_id` to remote state for consumption by workload accounts
  - Deploy AWS Network Firewall with STATEFUL FQDN domain-list rule groups allowing only approved egress destinations (HTTP_HOST + TLS_SNI target types); all other egress denied by default
  - Validate end-to-end egress path: workload pod → `app-private` subnet → TGW → Network Firewall → NAT Gateway → internet

- **`audit` Account — Security Delegated Admin (Week 9)**
  - Deploy `terraform/environments/audit/main.tf` instantiating the `guardduty` and `inspector` modules
  - Enable `aws_guardduty_organization_configuration` with `auto_enable_organization_members = "ALL"` and all four protection plans: EKS Audit Logs, S3 Data Events, EC2 Malware Protection, RDS Login Activity
  - Enable `aws_inspector2_organization_configuration` with `ec2 = true`, `ecr = true`, `lambda = true`
  - The `audit` account is the delegated administrator for both GuardDuty and Inspector across the organisation; findings route to the `audit` account for aggregation, then via EventBridge to the `logging` account S3 and Splunk HEC; high-severity findings trigger SNS on-call alerts

- **`logging` Account — Immutable Log Archive (Week 9)**
  - Deploy `terraform/environments/logging/main.tf`
  - Configure S3 with `aws_s3_bucket_object_lock_configuration` in COMPLIANCE mode (WORM) to enforce immutability of all log objects
  - The `logging` account is in the Security OU and is intentionally separate from the `audit` account — log integrity must be independent of security tooling access (ADR-008)
  - CloudTrail organisation trail targets the `logging` S3 bucket; the `audit` account has read-only access, no write access

- **EKS Cluster Deployment (Weeks 10-11)**
  - Deploy EKS clusters in `workload-dev` through `workload-prod` environments using the `eks-cluster` module (`terraform-aws-modules/eks/aws` ~>20.0)
  - Linux Managed Node Group: `ami_type = "AL2_x86_64"`, instance types from `terraform.tfvars`
  - Windows Managed Node Group: `ami_type = "WINDOWS_CORE_2019_x86_64"`, taint `os=windows:NO_SCHEDULE` to enforce OS-affinity scheduling; Karpenter NodePool configured per OS
  - Deploy `eks-addons` module: AWS Load Balancer Controller (ALB ingress), Karpenter (node autoscaling), Fluent Bit DaemonSet with Linux/Windows tolerations and Splunk HEC output (TLS, port 443)
  - Deploy ECR repositories with `image_tag_mutability = "IMMUTABLE"` and `scan_on_push = true`; lifecycle policy expires untagged images older than 30 days

- **Self-Healing Automation (Week 12)**
  - Deploy the `self-healing` module (EventBridge + Step Functions + SSM)
  - CloudWatch Alarm state-change rules route to a Step Functions state machine with exactly 5 states: `Detect → Diagnose → Remediate → Verify → Escalate`
  - `Remediate` state invokes SSM Run Command with `linux-triage.sh` (Amazon Linux 2/2023) or `windows-triage.ps1` (Windows Server 2019/2022)
  - `Verify` state checks `$.healthCheckPassed`; on failure transitions to `Escalate`, which publishes to SNS (`var.sns_topic_arn`) with instance ID, alarm name, triage summary, and timestamp
  - SSM Run Command stdout captured to CloudWatch Logs group `/self-healing/ssm-output`, forwarded by Splunk Universal Forwarder to `linux_os` or `windows_os` indexes

**Deliverables:**
- All 8 Terraform environments deployed and validated
- SCPs active on all workload OUs
- GuardDuty and Inspector enabled organisation-wide (delegated admin: `audit`)
- Immutable S3 log archive active (`logging` account, Security OU)
- EKS clusters operational in all workload accounts
- Self-healing state machine tested end-to-end

---

### Phase 3: Workload Migration & Operational Readiness (Weeks 13–20)

**Objectives:** Onboard first-wave workloads, establish GitOps pipelines and observability, validate all runbooks, and conduct disaster recovery testing.

**Key Activities:**

- **Workload Onboarding (Weeks 13–15)**
  - Migrate first-wave applications to EKS clusters in `workload-dev` and `workload-test`
  - Validate TGW attachment connectivity from each spoke VPC to the `network-hub` inspection VPC
  - Confirm Network Firewall FQDN allowlist covers all required egress destinations for migrated workloads; submit change requests for any additions
  - Validate IRSA/Pod Identity bindings for each workload requiring AWS API access

- **GitOps Pipeline Establishment (Weeks 16-17)**
  - Configure dual-repository GitOps pattern:
    - **Application Repository:** source code, Dockerfiles, GitHub Actions CI workflows (lint → Checkov static analysis → `terraform plan` → image build → push to ECR)
    - **GitOps Repository:** Helm/Kustomize manifests + Flux CD reconciliation; environment overlays for dev → test → staging → prod promotion via pull-request review
  - Validate Flux CD reconciliation loop: image tag update in GitOps repo → Flux detects change → applies to target cluster
  - Demonstrate promotion pipeline: dev → test → staging → prod via PR-based environment overlay

- **Splunk Observability & Dashboards (Week 18)**
  - Configure Splunk Universal Forwarder on EC2 instances in the `logging` account
  - Validate Fluent Bit DaemonSet shipping container logs to Splunk HEC (`k8s_containers` index)
  - Build Splunk dashboards: egress traffic by destination FQDN, GuardDuty high-severity findings, Inspector vulnerability counts by account, self-healing invocation rate, SSM Run Command success/failure
  - Configure Prometheus + Grafana for EKS cluster metrics (node CPU/memory, pod restarts, ALB request latency)
  - Validate X-Ray tracing for distributed application traces

- **Runbook Validation (Week 19)**
  - Execute `hybrid-os-operations-runbook.md` procedures against live environment for each platform type: Linux Compute, Linux Containers (EKS), Windows Server, Windows Containers (EKS)
  - Validate `linux-triage.sh` via SSM Run Command: confirm nginx/httpd status checks, `journalctl` critical error capture, and high-disk-usage alerts appear in Splunk `linux_os` index
  - Validate `windows-triage.ps1` via SSM Run Command: confirm W3SVC/IIS status, application pool enumeration, and Application Event Log errors appear in Splunk `windows_os` index
  - Walk through `escalation-playbook.md` end-to-end: simulate failed health check → Step Functions `Escalate` state → SNS → PagerDuty → on-call engineer receipt

- **Disaster Recovery Testing (Week 20)**
  - Simulate TGW attachment failure and validate failover routing
  - Simulate EKS node group scaling event; validate Karpenter provisioning
  - Simulate GuardDuty high-severity finding; validate SNS on-call alert delivery within SLA
  - Document DR test results and incorporate lessons learned into runbooks

**Deliverables:**
- First-wave workloads live in `workload-dev` and `workload-test`
- GitOps pipelines operational with promotion through all environments
- Splunk dashboards live and validated
- All runbooks executed and signed off
- DR test report
- Handover documentation and knowledge transfer sessions

---

## 3. Milestones and Timeline

| Milestone | Phase | Target Week | Success Criteria |
|-----------|-------|-------------|-----------------|
| Architecture workshops complete and all 10 ADRs reviewed | Phase 1 | Week 1-2 | Workshop notes distributed; ADR-001–010 reviewed by all technical stakeholders |
| All 10 ADRs formally accepted and baselined | Phase 1 | Week 3-4 | Signed `architectural-decision-record.md`; no open objections; change request process agreed |
| SCPs enforced: no direct IGW creation or open SSH/RDP | Phase 2 | Week 6 | SCP `deny-direct-internet-egress` and `deny-open-ssh-rdp` active on Workloads OU; `aws organizations policy list` confirms attachment |
| Network hub operational: TGW, Network Firewall, NAT GW active | Phase 2 | Week 7-8 | `terraform apply` completes in `network-hub`; egress test traffic passes through Network Firewall FQDN allowlist; denied traffic blocked |
| `audit` delegated admin active for GuardDuty and Inspector | Phase 2 | Week 9 | GuardDuty detector enabled in all member accounts; Inspector scanning EC2, ECR, Lambda org-wide; findings visible in `audit` account |
| EKS clusters deployed in all 4 workload accounts | Phase 2 | Week 10-11 | Managed Node Groups (Linux AL2 + Windows 2019) active; Fluent Bit DaemonSet shipping to Splunk HEC; ALB ingress controller responding |
| Self-healing state machine tested end-to-end | Phase 2 | Week 12 | Simulated CloudWatch Alarm triggers Step Functions; all 5 states execute (Detect → Diagnose → Remediate → Verify → Escalate); SNS escalation message received |
| GitOps promotion pipeline operational | Phase 3 | Week 16-17 | GitHub Actions CI builds image, pushes to ECR; Flux reconciles to `workload-dev`; PR promotion to `workload-test` and `workload-staging` validated |
| All runbooks validated against live environment | Phase 3 | Week 19 | Linux and Windows triage scripts executed via SSM Run Command; output confirmed in Splunk `linux_os`/`windows_os` indexes; escalation playbook walkthrough complete |
| DR test report accepted and handed over | Phase 3 | Week 20 | DR scenarios tested and documented; lessons incorporated into runbooks; client operations team signed off |

---

## 4. Key Architectural Decisions

The following table summarises the 10 architectural decisions that underpin this platform. Full context, options considered, and consequences for each decision are documented in [`docs/adr/architectural-decision-record.md`](./adr/architectural-decision-record.md).

| ADR | Title | Decision Summary |
|-----|-------|-----------------|
| [ADR-001](./adr/architectural-decision-record.md#adr-001-aws-transit-gateway-over-vpc-peering) | AWS Transit Gateway over VPC Peering | AWS TGW selected as the shared transit backbone; dedicated `tgw-attach` /28 subnet per AZ enforces route-table isolation, ensures symmetric traffic flow through Network Firewall, and provides per-flow auditability via VPC Flow Logs |
| [ADR-002](./adr/architectural-decision-record.md#adr-002-aws-network-firewall-for-centralised-egress-inspection) | AWS Network Firewall for Centralised Egress Inspection | AWS-managed Network Firewall with STATEFUL FQDN domain-list rule groups (HTTP_HOST + TLS_SNI) selected over third-party virtual appliances; eliminates unfiltered egress by allowing only approved destination FQDNs |
| [ADR-003](./adr/architectural-decision-record.md#adr-003-eks-managed-node-groups) | EKS Managed Node Groups | AWS-managed node groups (Linux AL2 + Windows Server 2019) selected over self-managed nodes; AWS handles AMI patching, node replacement, and lifecycle management, reducing operational burden and attack surface |
| [ADR-004](./adr/architectural-decision-record.md#adr-004-splunk-cloud-over-cloudwatchopensearch) | Splunk Cloud (UF + Fluent Bit) over CloudWatch/OpenSearch | Splunk Cloud with Universal Forwarder (EC2) and Fluent Bit DaemonSet (containers) selected for unified observability across OS types; provides single pane of glass correlating infrastructure, container, and security telemetry |
| [ADR-005](./adr/architectural-decision-record.md#adr-005-ssm-run-command--session-manager-over-sshrpd) | SSM Run Command / Session Manager over SSH/RDP | All operational access via SSM; SSH/RDP blocked by SCP; eliminates bastion host management, provides complete audit trail of all commands executed, and integrates directly with the self-healing Step Functions workflow |
| [ADR-006](./adr/architectural-decision-record.md#adr-006-step-functions--eventbridge-over-custom-lambda-state-machines) | Step Functions + EventBridge over Custom Lambda State Machines | AWS Step Functions with EventBridge as the event source selected for self-healing orchestration; provides built-in state persistence, visual workflow monitoring, retry logic, and timeout handling without custom state management code |
| [ADR-007](./adr/architectural-decision-record.md#adr-007-irsa--eks-pod-identities-over-node-level-iam-instance-profiles) | IRSA / EKS Pod Identities over Node-Level IAM Instance Profiles | Pod-level IAM bindings via IRSA/EKS Pod Identities selected; eliminates overly broad node instance profiles, enforces least-privilege per workload, and provides per-pod credential audit trails via CloudTrail |
| [ADR-008](./adr/architectural-decision-record.md#adr-008-dedicated-logging-account-as-immutable-log-archive) | Dedicated `logging` Account as Immutable Log Archive | A dedicated `logging` account in the Security OU holds all CloudTrail, VPC Flow Logs, and application logs in S3 with Object Lock (WORM); separated from the `audit` account to ensure log integrity is independent of security tooling access |
| [ADR-009](./adr/architectural-decision-record.md#adr-009-amazon-guardduty-organisation-wide) | Amazon GuardDuty Organisation-Wide | GuardDuty enabled across all member accounts with `audit` as delegated administrator; all four protection plans active (EKS Audit Logs, S3 Data Events, EC2 Malware Protection, RDS Login Activity); high-severity findings route to SNS on-call |
| [ADR-010](./adr/architectural-decision-record.md#adr-010-amazon-inspector-for-continuous-vulnerability-management) | Amazon Inspector for Continuous Vulnerability Management | Inspector enabled org-wide with `audit` as delegated administrator; scans EC2 instances, ECR container images (enhanced), and Lambda functions; provides complementary vulnerability data alongside GuardDuty threat detection |

---

## 5. Client Communication & Governance

### Weekly Status Calls

A recurring 45-minute status call will be held every Wednesday throughout the engagement. The agenda will cover:

- Progress against the current week's milestones
- Decisions required from the client team (e.g., FQDN allowlist additions, instance type approvals)
- Risks, issues, and dependencies
- Preview of next week's planned activities

Meeting notes and action items will be distributed within 24 hours. The client technical lead and engagement delivery lead are standing attendees; additional stakeholders join as needed.

### Architecture Review Board Cadence

An Architecture Review Board (ARB) session will be convened at the following gates:

| Gate | Timing | Purpose |
|------|--------|---------|
| ARB-1: Design Sign-Off | End of Week 2 | Formal acceptance of all 10 ADRs and the architecture reference document before Phase 2 begins |
| ARB-2: Network & Security Baseline | End of Week 5 | Review of deployed network hub, SCP enforcement, and Security OU account configuration |
| ARB-3: Platform Readiness | End of Week 8 | Review of EKS clusters, self-healing automation, and observability integration before workload onboarding |
| ARB-4: Operational Readiness | End of Week 12 | Final sign-off covering runbook validation, DR test results, and production readiness assessment |

ARB sessions include the Platform Architecture Team, client technical lead, security lead, and operations lead. Quorum requires at least two client representatives with authority to accept or raise change requests.

### Change Control Process

All changes to the approved architecture baseline (scope additions, ADR amendments, or deviations from the agreed SCP policy set) are subject to the following process:

1. **Change Request (CR) Raised** — the requesting party submits a CR describing the change, rationale, and estimated impact on timeline and cost
2. **Impact Assessment** — the engineering team assesses the change within 2 business days
3. **ARB Review** — changes with architectural impact are reviewed at the next ARB session or an ad-hoc session if urgent
4. **Approval & Baseline Update** — approved changes are recorded in the ADR document with a revised date and the relevant deliverable is updated
5. **Rejected Changes** — documented with rationale; the original baseline remains in effect

Minor changes (e.g., FQDN allowlist additions, Terraform variable value adjustments) follow an expedited path requiring only written sign-off from the client technical lead.

### Escalation Path

Issues that cannot be resolved at the weekly status call level are escalated as follows:

| Level | Trigger | Owner | Target Resolution |
|-------|---------|-------|-----------------|
| L1: Engineering | Technical blocker, dependency delay | Engagement delivery lead + client technical lead | 2 business days |
| L2: Architecture | ADR conflict, scope disagreement, security control question | Platform Architecture Team + client security lead | 5 business days |
| L3: Executive | Commercial dispute, timeline slip > 1 week, unresolved L2 after 5 days | Engagement sponsor + client executive sponsor | 10 business days |

All escalations are logged, tracked in the weekly status call notes, and closed only when both parties confirm resolution in writing.
