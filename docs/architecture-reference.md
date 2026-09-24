# Architecture Reference: Zero-Trust Network Egress & Automated Operations Platform

**Document type:** Architecture Reference
**Status:** Final — Customer Demonstration
**Date:** 2026-09-22
**Prepared by:** Platform Architecture Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Strategic Recommendations](#2-strategic-recommendations)
3. [Trade-Off Matrix](#3-trade-off-matrix)
4. [Multi-Account Organisation Design](#4-multi-account-organisation-design)
5. [Hub-Spoke Network Architecture](#5-hub-spoke-network-architecture)
6. [EKS Platform Design](#6-eks-platform-design)
7. [Event-Driven Self-Healing Operations](#7-event-driven-self-healing-operations)
8. [Observability & Log Aggregation](#8-observability--log-aggregation)
9. [Security Controls](#9-security-controls)
10. [Infrastructure as Code Strategy](#10-infrastructure-as-code-strategy)
11. [End-to-End Request Flows](#11-end-to-end-request-flows)
12. [Well-Architected Framework Compliance Matrix](#12-well-architected-framework-compliance-matrix)

---

## 1. Executive Summary

### Current-State Risks

The organisation's AWS environment presents three categories of material risk that, left unaddressed, create exposure to data exfiltration, compliance failure, and extended incident recovery times.

**Unfiltered internet egress.** Workload accounts can create Internet Gateways and attach them directly to route tables, allowing compute resources to reach arbitrary internet destinations without inspection. Outbound traffic bypasses any centralised control point, making it impossible to enforce domain-level allowlists, detect exfiltration attempts in real time, or demonstrate network-layer compliance to auditors. A single misconfigured or compromised workload can exfiltrate data or call back to attacker-controlled infrastructure with no preventative or detective control in the data path.

**Manual and inconsistent operations.** Operational tasks — service restarts, configuration changes, log collection — are performed ad hoc by engineers who connect directly to instances. Without a structured, audited operational framework, mean time to detect (MTTD) and mean time to resolve (MTTR) are driven by individual operator knowledge rather than documented procedure. There is no automated first-responder capability: a web server that crashes at 03:00 waits for a human to notice and intervene.

**SSH and RDP exposure.** Direct SSH (port 22) and RDP (port 3389) access to compute resources remains open as a fallback operational pathway. These protocols require long-lived credentials (key pairs, passwords) and produce audit trails that are difficult to centralise and correlate. Open ingress rules for these ports represent the most commonly exploited attack surface in cloud environments, and their presence fails basic CIS and AWS Foundational Security Best Practices benchmarks.

### Target-State Outcomes

This platform architecture addresses all three risk categories:

- **Zero-trust egress** — all internet-bound traffic from every workload account is routed through a centralised Network Firewall inspection point. Service Control Policies enforced at the OU level prevent any account from creating Internet Gateways or routing directly to one. Only explicitly allowlisted FQDNs can egress to the internet.
- **Automated self-healing operations** — an event-driven pipeline (CloudWatch Alarm → EventBridge → Step Functions → SSM Run Command) detects, diagnoses, and attempts remediation of common failures within minutes, without human intervention. Unresolved incidents escalate to on-call via SNS. Every remediation step is audited.
- **SSH/RDP-free access model** — AWS Systems Manager Session Manager and Run Command replace all direct SSH and RDP access. No inbound security group rules are required. All session activity is logged to CloudWatch and forwarded to Splunk. SCPs deny `ec2:AuthorizeSecurityGroupIngress` for ports 22 and 3389 from `0.0.0.0/0` at the organisation level.

The resulting platform is a production-grade, defence-in-depth AWS landing zone suitable for regulated workloads, with full auditability from network egress to operator action.

---

## 2. Strategic Recommendations

The following recommendations are listed in order of risk-reduction priority. Each maps directly to an Architecture Decision Record in [`docs/adr/architectural-decision-record.md`](adr/architectural-decision-record.md).

### Priority 1 — Eliminate Direct Internet Egress (ADR-001, ADR-002)

Deploy AWS Transit Gateway as the central routing hub for all inter-VPC and egress traffic (ADR-001). Route all outbound internet traffic through an AWS Network Firewall inspection VPC deployed in the `network-hub` account (ADR-002). Apply Service Control Policies at the Workloads BU OU level to deny `ec2:CreateInternetGateway` and any route table association that targets an Internet Gateway prefix. This combination eliminates the risk of unfiltered egress and provides a single, auditable chokepoint for all outbound traffic.

**Rationale:** Transit Gateway provides a scalable, managed routing fabric that avoids the operational complexity and route-limit constraints of VPC Peering. Network Firewall is a managed service with stateful FQDN domain-list rule groups — no virtual appliance lifecycle management is required.

### Priority 2 — Enforce SSH/RDP-Free Access Model (ADR-005)

Replace all SSH and RDP access with AWS Systems Manager Session Manager and Run Command. Remove all inbound security group rules permitting ports 22 and 3389. Apply the `deny-open-ssh-rdp` SCP at the OU level to prevent re-introduction. All SSM sessions are logged to CloudWatch Logs and forwarded to Splunk for central audit.

**Rationale:** Session Manager eliminates the credential management overhead of key pairs and passwords. It works entirely over HTTPS via the SSM agent — no inbound security group rules are required. The attack surface reduction is immediate and the audit trail is superior to SSH logs.

### Priority 3 — Establish Multi-Account Security Isolation (ADR-008, ADR-009, ADR-010)

Create dedicated `audit` and `logging` accounts within Security OU. The `audit` account acts as delegated administrator for GuardDuty (ADR-009), Inspector (ADR-010), Security Hub, Config Aggregator, and IAM Access Analyzer. The `logging` account holds all logs in an immutable S3 archive with Object Lock (ADR-008). Separating log storage from security tooling access ensures that a compromised security tool cannot tamper with log evidence.

**Rationale:** Immutable, dedicated log storage is the foundation of forensic capability and compliance posture. Centralised threat detection via delegated admin removes the operational burden of per-account GuardDuty and Inspector management while ensuring complete coverage.

### Priority 4 — Modernise Compute Platform (ADR-003, ADR-007)

Deploy EKS with Managed Node Groups for both Linux (Amazon Linux 2) and Windows (Windows Server 2019) workloads (ADR-003). Use IRSA (IAM Roles for Service Accounts) and EKS Pod Identities to grant pods least-privilege IAM access without node-level instance profiles (ADR-007). Implement Karpenter for cost-efficient dynamic scaling with OS-specific NodePools and taints.

**Rationale:** Managed Node Groups offload AMI patching, node replacement, and security updates to AWS. IRSA provides cryptographically verifiable pod-level identity — the blast radius of a compromised pod is limited to the permissions of its service account role.

### Priority 5 — Implement Event-Driven Self-Healing (ADR-006)

Build an automated operations pipeline using Step Functions + EventBridge (ADR-006). Define a 5-state machine (Detect → Diagnose → Remediate → Verify → Escalate) triggered by CloudWatch Alarms. Use SSM Run Command to execute triage and remediation scripts without requiring SSH access.

**Rationale:** Step Functions provides durable, observable state machine execution with built-in retry, timeout, and error-handling semantics. It eliminates the need for custom Lambda orchestration code while providing a visual execution history for post-incident analysis.

### Priority 6 — Centralise Observability (ADR-004)

Deploy Splunk Cloud as the unified observability platform. Use Splunk Universal Forwarder on EC2 instances and Fluent Bit DaemonSet on EKS pods to ship all logs to Splunk HEC. Complement with Prometheus + Grafana for cluster metrics and AWS X-Ray for distributed tracing.

**Rationale:** Splunk provides correlation across log sources (OS, application, network, security) in a single pane of glass. Native CloudWatch/OpenSearch lacks Splunk's field extraction capabilities, correlation search, and established security analytics ecosystem. The Splunk S3 Add-on ingests archived logs from the `logging` account, providing long-term forensic search without retaining data in Splunk's hot/warm tier.

---

## 3. Trade-Off Matrix

| Option A | Option B | Decision | Rationale |
|----------|----------|----------|-----------|
| **AWS Transit Gateway** — managed, scalable hub-and-spoke routing fabric; supports route table isolation, symmetric routing, and cross-account attachment | **VPC Peering** — point-to-point connections between VPCs; no transitive routing; scales poorly beyond a handful of VPCs; no centralised route control | **Transit Gateway** (ADR-001) | With 8 accounts and multiple VPCs, VPC Peering would require O(n²) connections and separate route table entries per peer. TGW supports separate route tables for spoke and inspection VPCs, enabling symmetric traffic flow through the Network Firewall without source NAT. VPC Peering cannot enforce this routing constraint. |
| **AWS Network Firewall** — managed service; stateful FQDN domain-list rules; intrusion detection signatures; no appliance lifecycle management | **Third-party virtual appliances** (e.g. Palo Alto VM-Series, Fortinet FortiGate) — richer policy languages; familiar to enterprise security teams; require patching, HA configuration, and licence management | **AWS Network Firewall** (ADR-002) | Network Firewall integrates natively with TGW routing, Gateway Load Balancer endpoints, and CloudWatch. It eliminates appliance lifecycle overhead while meeting the core requirement: FQDN-based egress inspection. Third-party appliances introduce HA complexity and software patching obligations that are disproportionate for this deployment model. |
| **EKS Managed Node Groups** — AWS manages the underlying Auto Scaling Group, AMI selection, and node replacement; supports mixed OS (Linux + Windows) | **Self-managed nodes** — full control over instance bootstrapping, AMI versioning, and node lifecycle; requires custom tooling for patching and replacement | **Managed Node Groups** (ADR-003) | Self-managed nodes require the platform team to own AMI pipelines, node drain automation, and security patching workflows for both Linux and Windows node types. Managed Node Groups handle this with AWS-managed AMIs and automated node replacement, significantly reducing operational burden without sacrificing configurability via launch templates. |
| **Splunk Cloud** — unified log aggregation, search, correlation, and alerting; Splunk UF (EC2) and Fluent Bit (containers) agents; S3 Add-on for archived log ingestion | **CloudWatch + OpenSearch** — native AWS integration; lower initial cost; limited cross-source correlation; no equivalent to Splunk's SPL for complex security analytics | **Splunk Cloud** (ADR-004) | The requirement to correlate OS logs, application logs, network flow logs, GuardDuty findings, and Inspector findings in a single platform favours Splunk's mature data model and SPL query language. OpenSearch lacks the field-extraction richness and established security analytics content packs that Splunk provides. The S3 Add-on enables cost-effective long-term log retention in the `logging` account. |
| **AWS Systems Manager Session Manager / Run Command** — sessionless HTTPS access via SSM agent; full audit trail to CloudWatch; no inbound security group rules required | **SSH / RDP** — direct protocol access; requires inbound firewall rules; relies on long-lived credentials (key pairs, passwords); audit trail fragmented | **SSM Session Manager / Run Command** (ADR-005) | SSH and RDP require open inbound ports and long-lived credentials — both fail CIS benchmarks. Session Manager works over the existing HTTPS control plane; no new attack surface is introduced. Every session is logged to CloudWatch Logs and every Run Command invocation is auditable via CloudTrail. SCPs prevent re-introduction of open SSH/RDP rules. |
| **Step Functions + EventBridge** — managed state machine execution; built-in retry, timeout, catch, and parallel states; visual execution history; ASL JSON definition | **Custom Lambda orchestration** — flexible; no service cost for short executions; but requires custom state management, retry logic, timeout handling, and error propagation code | **Step Functions + EventBridge** (ADR-006) | Custom Lambda state machines push the complexity of durable execution, retry back-off, timeout enforcement, and partial failure handling into application code. Step Functions provides all of these as first-class primitives. The visual execution history in the AWS console significantly accelerates post-incident root cause analysis. |

---

## 4. Multi-Account Organisation Design

### AWS Organisation Structure

The organisation uses a three-tier OU structure under a Management root account. Service Control Policies are applied at the OU level to enforce security baselines across all member accounts without requiring per-account configuration.

```
Root (Management account)
├── Infrastructure OU
│   └── network-hub
├── Security OU
│   ├── audit
│   └── logging
└── Workloads BU OU
    ├── workload-dev
    ├── workload-test
    ├── workload-staging
    └── workload-prod
```

### Account Purpose Summary

| Account | OU | Purpose |
|---------|-----|---------|
| `management` | Root | AWS Organizations root, SCPs, consolidated billing, Control Tower |
| `network-hub` | Infrastructure OU | TGW, Network Firewall, NAT GW, shared DNS, VPC Flow Logs |
| `audit` | Security OU | Delegated admin for GuardDuty, Inspector, Security Hub, Config Aggregator, IAM Access Analyzer; read-only security toolset hub |
| `logging` | Security OU | Read-only, immutable S3 log archive; CloudTrail organisation trail target; Splunk Add-on ingestion; S3 Object Lock |
| `workload-dev` | Workloads BU OU | Development EKS cluster and workloads |
| `workload-test` | Workloads BU OU | Integration and functional testing workloads |
| `workload-staging` | Workloads BU OU | Pre-production / UAT workloads |
| `workload-prod` | Workloads BU OU | Live production workloads; strictest SCP boundaries |

### SCP Strategy

Service Control Policies are the primary mechanism for enforcing organisation-wide security invariants. They act as permission guardrails — even an account administrator cannot perform a denied action. SCPs are applied at the OU level so that new accounts added to an OU automatically inherit the baseline.

Two SCPs are applied to the Workloads BU OU and Infrastructure OU (excluding `network-hub` from the egress SCP, which owns the legitimate Internet Gateway):

| SCP | Target OU(s) | Effect |
|-----|-------------|--------|
| `deny-direct-internet-egress` | Workloads BU OU | Denies `ec2:CreateInternetGateway` and route table associations that target an Internet Gateway (`igw-*`). Prevents any workload account from bypassing the centralised Network Firewall inspection path. |
| `deny-open-ssh-rdp` | Workloads BU OU, Infrastructure OU | Denies `ec2:AuthorizeSecurityGroupIngress` for ports 22 (SSH) and 3389 (RDP) from `0.0.0.0/0`. Prevents open management access rules from being created in any member account. |

The `management` account (root) is exempt from both SCPs by AWS design — the management account cannot have SCPs applied to it. The `network-hub` account is exempt from `deny-direct-internet-egress` because it legitimately owns the Internet Gateway and NAT Gateway for centralised egress.

The `audit` and `logging` accounts in Security OU operate under a separate SCP posture that restricts write access to workload resources, enforcing their read-only and immutable-archive roles respectively.

### Control Tower Integration

AWS Control Tower manages account vending, baseline guardrails, and the Account Factory for new member accounts. All new accounts are provisioned into the appropriate OU and automatically receive the OU-level SCPs. Control Tower's mandatory guardrails (e.g. disabling public S3 bucket ACLs, enabling CloudTrail) complement the custom SCPs.

---

## 5. Hub-Spoke Network Architecture

### Design Overview

All network egress to the internet flows through a single, inspected path in the `network-hub` account. Workload VPCs are spoke networks connected to a central Transit Gateway. The TGW routes egress traffic to a Network Firewall inspection VPC before it reaches the NAT Gateway and the Internet Gateway. This architecture guarantees that no workload can bypass the inspection layer.

### Transit Gateway

The Transit Gateway is deployed in the `network-hub` account and shared with all workload accounts via AWS Resource Access Manager (RAM). Each workload VPC attaches to the TGW via a dedicated `/28` `tgw-attach` subnet — a subnet reserved exclusively for TGW Elastic Network Interfaces (ENIs), ensuring that TGW routing is cleanly separated from application traffic routing at the subnet level.

The TGW maintains two route tables:

- **Spoke route table** — associated with all workload VPC attachments. Routes to `0.0.0.0/0` point to the Network Firewall inspection VPC attachment. This ensures all internet-bound traffic from workload VPCs is directed to the firewall before egress.
- **Inspection route table** — associated with the Network Firewall inspection VPC attachment. After the firewall passes traffic, it is forwarded to the NAT Gateway. Return traffic from the internet follows the same path in reverse, maintaining flow symmetry — a requirement for stateful firewall inspection.

Separate TGW route tables enforce symmetric routing: both ingress and egress for any given flow traverse the same firewall endpoint, which is required for the stateful inspection engine to correlate request and response packets.

### Four-Tier Subnet Architecture

Every VPC — both the `network-hub` VPC and all workload spoke VPCs — uses a consistent four-tier subnet layout across two Availability Zones:

| Tier | Subnet Name | CIDR Size | Purpose |
|------|-------------|-----------|---------|
| 1 | `public-ingress` | /20 per AZ | Internet-facing load balancers, NAT Gateway (hub only) |
| 2 | `app-private` | /20 per AZ | Application compute: EC2, EKS node groups, containerised workloads |
| 3 | `data-private` | /20 per AZ | Databases, caches, and stateful data services |
| 4 | `tgw-attach` | /28 per AZ | Transit Gateway Elastic Network Interfaces only — no compute resources |

The `/28` size for `tgw-attach` subnets is deliberate: TGW requires one ENI per subnet, and the small CIDR prevents accidental workload placement in a subnet that must remain free of conflicting routes.

### AWS Network Firewall

The Network Firewall is deployed in the `network-hub` account within the `app-private` subnet tier of the hub VPC. Firewall endpoints are created in each AZ for high availability. Traffic routed through the firewall is evaluated against a stateful FQDN domain-list rule group:

- **Rule type:** STATEFUL, ALLOWLIST
- **Target types:** `HTTP_HOST` and `TLS_SNI`
- **Targets:** An explicit list of approved FQDNs (e.g. package registries, AWS service endpoints, approved SaaS APIs)

Traffic destined for any domain not on the allowlist is dropped. The firewall logs all flow records and alert events to CloudWatch Logs, which are subsequently forwarded to Splunk for correlation and alerting.

### VPC Flow Logs

VPC Flow Logs are enabled for all VPCs and published to the `logging` account S3 bucket. The `network-hub` VPC flow logs capture all inter-VPC and internet-bound traffic traversing the TGW, providing network-level visibility across the entire organisation.

### Egress Traffic Path

Outbound traffic from a workload pod follows this path:

1. Pod in `app-private` subnet generates internet-bound traffic.
2. The subnet route table has no direct route to an Internet Gateway (enforced by SCP). The default route (`0.0.0.0/0`) points to the TGW attachment in the `tgw-attach` subnet.
3. TGW receives the packet and evaluates the spoke route table. The default route points to the Network Firewall inspection VPC attachment.
4. The Network Firewall evaluates the packet against the FQDN allowlist. Permitted traffic is forwarded; denied traffic is dropped and logged.
5. Permitted traffic exits the firewall and is routed to the NAT Gateway in the `public-ingress` subnet.
6. The NAT Gateway translates the source address and forwards the packet to the Internet Gateway.
7. Return traffic follows the same path in reverse through the firewall for stateful inspection.

---

## 6. EKS Platform Design

### Cluster Architecture

One EKS cluster is deployed per workload account (`workload-dev`, `workload-test`, `workload-staging`, `workload-prod`). Cluster API endpoints are private (no public endpoint) — `kubectl` access is gated through AWS VPN or Direct Connect. Worker nodes are placed in the `app-private` subnet tier of the workload VPC.

### Managed Node Groups — Heterogeneous OS Support

Two Managed Node Groups are provisioned per cluster to support both Linux and Windows workloads:

**Linux Node Group**
- AMI type: `AL2_x86_64` (Amazon Linux 2)
- Instance types: environment-differentiated (e.g. `t3.large` in dev/test, `m6i.xlarge` in prod)
- No taints applied — Linux is the default scheduling target for all pods without an explicit node selector

**Windows Node Group**
- AMI type: `WINDOWS_CORE_2019_x86_64` (Windows Server 2019 Core)
- Instance types: environment-differentiated (e.g. `t3.xlarge` in dev/test, `m6i.2xlarge` in prod)
- Taint applied: `os=windows:NoSchedule`

The `NoSchedule` taint on Windows nodes ensures that only pods with a matching toleration land on Windows nodes. All other pods are scheduled on Linux nodes by default, preventing accidental Windows node saturation. Windows pod specs must include:

```yaml
tolerations:
  - key: "os"
    operator: "Equal"
    value: "windows"
    effect: "NoSchedule"
nodeSelector:
  kubernetes.io/os: windows
```

### Karpenter Dynamic Scaling

Karpenter is deployed as a cluster add-on (via Helm, managed in the `eks-addons` module) and layered on top of the Managed Node Groups for burst capacity and bin-packing efficiency. Two Karpenter NodePools are configured — one per OS:

- **Linux NodePool** — targets `kubernetes.io/os=linux`; no taint propagation; scales in response to pending Linux pods
- **Windows NodePool** — targets `kubernetes.io/os=windows`; propagates the `os=windows:NoSchedule` taint to provisioned nodes; scales in response to pending Windows pods

Karpenter's consolidation feature downsizes and removes underutilised nodes during off-peak hours, reducing compute cost without sacrificing availability.

### IRSA and EKS Pod Identities

Pods are granted AWS API access via IAM Roles for Service Accounts (IRSA). The EKS cluster exposes an OIDC provider endpoint. Each Kubernetes Service Account is annotated with an IAM role ARN:

```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/<role-name>
```

The EKS control plane automatically injects a projected service account token into each pod. When the pod calls an AWS API, the AWS SDK exchanges the token with AWS STS via the OIDC provider to obtain temporary credentials scoped to the annotated IAM role.

EKS Pod Identities (the newer mechanism) are also configured where available, providing the same capability with a simplified trust policy model that does not require OIDC issuer URL management.

No node-level instance profiles with broad permissions are used. The blast radius of a compromised pod is limited to the IAM role assigned to its service account.

### ALB Ingress — AWS Load Balancer Controller

The AWS Load Balancer Controller (deployed via Helm in the `eks-addons` module) manages Application Load Balancers from Kubernetes `Ingress` objects. When a developer creates an `Ingress` resource, the controller provisions and configures an ALB in the `public-ingress` subnet tier. Target groups are registered against pod IPs (IP target mode), bypassing kube-proxy for direct pod routing.

The controller itself runs on Linux nodes and assumes an IAM role via IRSA with permissions scoped to ALB, ACM, WAF, and Shield APIs.

### Dual-Repository GitOps Pattern

The platform uses a two-repository model that separates application source code from deployment configuration:

**Application Repository**
- Contains: application source code, `Dockerfile`s, unit and integration tests, and GitHub Actions CI pipeline definitions
- GitHub Actions pipelines perform: code linting, unit tests, container image build, Checkov IaC scan (if Terraform files are present), image push to ECR (tagged with the Git commit SHA)
- Responsibility boundary: produce a versioned, scanned container image and push it to ECR
- Does not contain Kubernetes manifests — deployment is fully decoupled from build

**GitOps Repository**
- Contains: Helm chart value files, Kustomize overlays, and Flux CD source and kustomization objects
- Flux CD continuously reconciles the desired state declared in this repository against the live cluster state
- Promotion model: a merged pull request updating the image tag in the relevant environment overlay triggers Flux reconciliation. The PR-based promotion gate ensures that staging and production deployments require explicit human approval.
- Flux monitors the ECR repository for new image tags. When a new tag matching the target pattern is detected, Flux updates the GitOps repository via an automated commit, triggering the reconciliation cycle.

This pattern provides a clean separation of concerns: the application team owns the build pipeline and the container image; the platform team owns the deployment configuration and promotion gates. Flux's continuous reconciliation ensures that configuration drift in the cluster is automatically corrected.

### ECR Container Registry

Amazon ECR is provisioned per workload account via the `ecr` module. All repositories are configured with:

- `image_tag_mutability = "IMMUTABLE"` — prevents overwriting of existing tags, ensuring a pushed image cannot be silently replaced
- `scan_on_push = true` — triggers an Inspector basic scan on every pushed image; Inspector enhanced scanning provides continuous CVE monitoring
- Lifecycle policy: untagged images older than 30 days are expired automatically to control storage costs

---

## 7. Event-Driven Self-Healing Operations

### Architecture Overview

The self-healing system replaces reactive, human-driven incident response with an event-driven, automated pipeline. When a CloudWatch Alarm transitions to the `ALARM` state, an EventBridge rule fires and invokes a Step Functions state machine. The state machine executes a structured 5-state workflow, attempting automated remediation before escalating to on-call personnel.

```
CloudWatch Alarm
       │
       ▼
 EventBridge Rule ──────► Step Functions State Machine
                                    │
                          ┌─────────▼─────────┐
                          │      Detect        │ SSM Run Command (triage)
                          └─────────┬─────────┘
                                    │
                          ┌─────────▼─────────┐
                          │     Diagnose       │ Lambda (log analysis)
                          └─────────┬─────────┘
                                    │
                          ┌─────────▼─────────┐
                          │    Remediate       │ SSM Run Command (restart)
                          └─────────┬─────────┘
                                    │
                          ┌─────────▼─────────┐
                          │      Verify        │ Choice state (health check)
                          └──┬──────────┬──────┘
                             │ pass      │ fail
                             ▼           ▼
                          (success)  Escalate ──► SNS → PagerDuty + On-call
```

### Step Functions State Descriptions

**State 1: Detect**
- Type: `Task`
- Resource: `arn:aws:states:::ssm:sendCommand.sync`
- Action: Invokes the `ZeroTrustPlatform-LinuxTriage` or `ZeroTrustPlatform-WindowsTriage` SSM Run Command document on the target instance (identified by the `SelfHealingEnabled=true` tag).
- Output: Triage script stdout, including service status, journal errors, and disk usage alerts. This output is passed to the next state as context.
- Failure handling: If SSM Run Command times out or fails to reach the instance, the Step Functions `Catch` block routes execution directly to `Escalate`.

**State 2: Diagnose**
- Type: `Task`
- Resource: `arn:aws:states:::lambda:invoke`
- Action: Invokes a Lambda function that parses the triage output from the `Detect` state to classify the failure type (service down, disk full, configuration error, etc.) and determine the appropriate remediation action.
- Output: A structured diagnosis object including `failureType`, `remediationAction`, and `escalationMessage`. These fields drive subsequent state transitions.
- Failure handling: Lambda errors cause Step Functions to retry with exponential back-off before routing to `Escalate`.

**State 3: Remediate**
- Type: `Task`
- Resource: `arn:aws:states:::ssm:sendCommand.sync`
- Action: Executes the remediation SSM document determined by the `Diagnose` output. Common remediations include:
  - Service restart: `systemctl restart nginx` / `systemctl restart httpd`
  - Configuration reload: `nginx -s reload`
  - Log rotation trigger for near-full partitions
- Output: Remediation command exit code and stdout, used by the `Verify` state.
- Failure handling: If remediation fails, execution proceeds to `Verify` (which will fail the health check and route to `Escalate`).

**State 4: Verify**
- Type: `Choice`
- Action: Evaluates the `$.healthCheckPassed` field in the execution context. This field is populated by a health check embedded in the remediation document (e.g. `systemctl is-active nginx && echo "HEALTH_OK"`).
- Transitions:
  - `$.healthCheckPassed == true` → execution succeeds; no further action required
  - `$.healthCheckPassed == false` (Default) → transition to `Escalate`
- Note: If the `Remediate` or any preceding state times out and a `Catch` block routes to `Escalate` directly, the `Verify` state is bypassed.

**State 5: Escalate**
- Type: `Task`
- Resource: `arn:aws:states:::sns:publish`
- Action: Publishes a structured message to the configured SNS topic. The message payload includes: instance ID, CloudWatch alarm name, triage output summary, failure classification, remediation attempt result, and timestamp.
- SNS subscribers: PagerDuty HTTP endpoint (creates a P1 incident) and on-call engineer email distribution list.
- Terminal state (`End = true`): exactly one SNS notification is sent per state machine execution, preventing alert storms.

### EventBridge Rule

The EventBridge rule in the `network-hub`-adjacent `self-healing` module fires on CloudWatch Alarm state changes where `detail.state.value == "ALARM"`. The rule targets the Step Functions state machine with an IAM role that grants `states:StartExecution`. The alarm source and instance ID are extracted from the event payload and passed as input to the state machine.

### SSM Run Command Integration

SSM Run Command requires no inbound network access — the SSM Agent on each instance maintains an outbound HTTPS connection to the SSM endpoint. Target instances are identified by the `SelfHealingEnabled=true` resource tag, set on all managed EC2 instances at provisioning time. Command output streams to CloudWatch Logs group `/self-healing/ssm-output`, from which Splunk Universal Forwarder ingests to the `linux_os` or `windows_os` Splunk index.

---

## 8. Observability & Log Aggregation

### Architecture Overview

The observability platform provides unified visibility across EC2 instances, containerised EKS workloads, and security events. All log data ultimately flows to Splunk Cloud for correlation, alerting, and long-term analysis. A dedicated `logging` account in Security OU provides an immutable archive layer that is independent of any security tooling.

### Logging Account — Immutable Log Archive

The `logging` account is the centralised, read-only sink for all organisation log data. It is a separate account from `audit` by design: if the security tooling in the `audit` account is compromised, the log archive remains intact and tamper-proof.

Key properties of the `logging` account:
- **S3 Object Lock** with Compliance mode (WORM — Write Once Read Many) prevents deletion or overwriting of log objects for the configured retention period
- **CloudTrail organisation trail** target: all API activity across all accounts is delivered to the `logging` account S3 bucket
- **VPC Flow Logs** from all accounts are delivered to this bucket
- **GuardDuty findings** are forwarded from the `audit` account via EventBridge
- **Splunk S3 Add-on** ingests from this bucket on a scheduled basis, providing long-term forensic search without requiring Splunk hot-tier retention for all historical data

The `logging` account has no write access to workload accounts. The `audit` account has read-only access to the `logging` S3 bucket for security investigation purposes but cannot modify or delete log data.

### EC2 / Bare-Metal — Splunk Universal Forwarder

On all EC2 instances, the Splunk Universal Forwarder (UF) is installed and configured as a systemd service. The UF monitors configured log paths (OS syslog, application logs, SSM command output) and forwards events directly to the Splunk Cloud HEC endpoint over HTTPS (port 443). Source types and indexes are mapped per log source:

| Log Source | Splunk Index | Source Type |
|-----------|-------------|-------------|
| Linux OS syslog | `linux_os` | `syslog` |
| Windows Application Event Log | `windows_os` | `XmlWinEventLog` |
| SSM Run Command output | `linux_os` / `windows_os` | `ssm_command_output` |
| IIS access logs | `windows_os` | `iis_access` |

### Containers — Fluent Bit DaemonSet

On EKS clusters, Fluent Bit is deployed as a DaemonSet via the Helm chart in the `eks-addons` module. It tails container log files from all pods on each node and forwards to Splunk HEC.

The Fluent Bit Helm values (`fluentbit-values.yaml`) configure:

- **Tolerations** for both Linux nodes (no taint — `Exists` toleration) and Windows nodes (`os=windows:NoSchedule`), ensuring the DaemonSet runs on all node types
- **Splunk output plugin** with TLS enabled, targeting the Splunk HEC endpoint
- **Kubernetes metadata enrichment** — pod name, namespace, container name, and node name are added as fields to each log event, enabling Kubernetes-aware search in Splunk

Container logs flow to the `k8s_containers` Splunk index. The Splunk token for HEC authentication is marked `sensitive = true` in Terraform and sourced from AWS Secrets Manager at apply time — it is never hardcoded in any configuration file.

### Metrics — Prometheus and Grafana

Prometheus is deployed in each EKS cluster (via Helm) and scrapes metrics from the Kubernetes API server, kubelet, node-exporter (Linux nodes), and application pods. Grafana is deployed alongside Prometheus and provides dashboards for:

- Cluster node resource utilisation (CPU, memory, disk)
- Pod scheduling and restart counts
- Application-specific metrics exposed via the Prometheus metrics endpoint
- Karpenter provisioning activity and cost efficiency metrics

Grafana is integrated with AWS IAM via IRSA for data source access and with the organisation's SSO provider for user authentication.

### Distributed Tracing — AWS X-Ray

AWS X-Ray is enabled for all EKS workloads via the X-Ray daemon (deployed as a DaemonSet) and SDK instrumentation in application code. X-Ray traces are sent to the X-Ray service endpoint and visualised in the AWS console. X-Ray service maps surface latency hotspots and error rates across microservice boundaries.

### Security Event Pipeline

GuardDuty findings and Inspector vulnerability reports from all member accounts are aggregated in the `audit` account (delegated admin). The `audit` account EventBridge forwards findings to the `logging` account S3 bucket via a cross-account EventBridge bus. The Splunk S3 Add-on ingests findings for correlation with OS and application logs. High-severity GuardDuty findings (CRITICAL, HIGH) trigger an additional EventBridge rule that publishes to SNS → PagerDuty for immediate on-call notification.

---

## 9. Security Controls

### Service Control Policies

SCPs form the outermost control layer — they cannot be overridden by any IAM policy within a member account. Two SCPs are applied at the Workloads BU OU level:

**deny-direct-internet-egress** prevents workload accounts from creating direct internet paths:
- Denies `ec2:CreateInternetGateway` for all principals in all workload accounts
- Denies `ec2:CreateRoute` and `ec2:ReplaceRoute` when the `ec2:GatewayId` condition matches `igw-*`, preventing routes to any Internet Gateway

**deny-open-ssh-rdp** prevents introduction of open management access rules:
- Denies `ec2:AuthorizeSecurityGroupIngress` for TCP port 22 from `0.0.0.0/0` (SSH)
- Denies `ec2:AuthorizeSecurityGroupIngress` for TCP port 3389 from `0.0.0.0/0` (RDP)

Both SCPs are defined as JSON policy documents in the `scp-policies` module and attached via the `management` account Terraform environment.

### Encryption — AWS KMS

All data at rest is encrypted using customer-managed KMS keys (CMKs) with key rotation enabled:

- S3 buckets (including the `logging` account archive) use SSE-KMS
- EBS volumes attached to EKS nodes use KMS-encrypted snapshots
- ECR image layers are encrypted at rest
- Secrets Manager values (Splunk HEC tokens, application secrets) use KMS encryption

KMS key policies follow least-privilege: only the specific roles and services that require access to encrypted resources are granted `kms:Decrypt` and `kms:GenerateDataKey`.

### AWS Config

AWS Config is enabled in all accounts and regions. The `audit` account acts as the Config Aggregator, collecting resource configuration snapshots from all member accounts. Config rules enforce:

- No public S3 buckets (`s3-bucket-public-read-prohibited`, `s3-bucket-public-write-prohibited`)
- Encryption enabled on all EBS volumes (`encrypted-volumes`)
- CloudTrail enabled and logging to S3 (`cloud-trail-enabled`, `cloud-trail-encryption-enabled`)
- No unrestricted security group ingress (`vpc-sg-open-only-to-authorized-ports`)
- Root MFA enabled (`root-account-mfa-enabled`)

Non-compliant resources trigger Config remediation actions or CloudWatch alarms depending on severity.

### Amazon GuardDuty

GuardDuty is enabled organisation-wide with the `audit` account as delegated administrator. All protection plans are active:

| Protection Plan | Coverage |
|----------------|---------|
| S3 Protection | Monitors S3 data plane API calls for data exfiltration indicators |
| EKS Audit Log Monitoring | Analyses Kubernetes API server audit logs for malicious activity patterns |
| EC2 Malware Protection | Scans EBS volumes attached to flagged instances for known malware signatures |
| RDS Login Activity | Monitors database authentication attempts for credential stuffing and anomalous access patterns |

GuardDuty findings are aggregated in the `audit` account. High-severity and critical findings trigger an EventBridge rule that:
1. Forwards the finding to the `logging` account S3 bucket (evidence preservation)
2. Publishes to an SNS topic → PagerDuty + on-call email (immediate notification)
3. Optionally triggers a Step Functions self-healing workflow for automated containment

### Amazon Inspector

Amazon Inspector provides continuous vulnerability management. The `audit` account acts as delegated administrator, enabling Inspector across all member accounts with the following scan types active:

| Scan Type | Coverage |
|-----------|---------|
| EC2 Instance Scanning | Continuously assesses running EC2 instances for OS and application package CVEs using SSM agent inventory |
| ECR Enhanced Scanning | Continuously monitors ECR repositories for newly published CVEs affecting stored container image layers; integrates with the ECR image registry — no separate scan trigger required |
| Lambda Function Scanning | Assesses Lambda function code and dependency packages for known vulnerabilities |

Inspector findings are correlated with GuardDuty findings in Splunk: a CVE identified by Inspector on an instance that is also generating GuardDuty anomaly findings creates a high-confidence indicator of compromise (IoC). Inspector findings are forwarded to the `audit` account EventBridge and ultimately to the `logging` account S3 for long-term evidence retention.

### IAM Access Analyzer

IAM Access Analyzer is enabled in the `audit` account for all member accounts, analysing resource-based policies (S3 bucket policies, IAM role trust policies, KMS key policies, Lambda function policies) to identify resources that are accessible from outside the organisation or from unintended principals. Findings are reviewed in the `audit` account console and remediated via Config remediation actions.

---

## 10. Infrastructure as Code Strategy

### Terraform Dual-Layout

The repository uses a strict separation between environment root modules and shared modules:

```
terraform/
├── environments/   — account-specific root modules (8 directories)
│   ├── management/
│   ├── network-hub/
│   ├── audit/
│   ├── logging/
│   ├── workload-dev/
│   ├── workload-test/
│   ├── workload-staging/
│   └── workload-prod/
└── modules/        — shared, reusable modules (11 directories)
    ├── vpc/
    ├── tgw-attachment/
    ├── network-firewall/
    ├── eks-cluster/
    ├── eks-addons/
    ├── ecr/
    ├── self-healing/
    ├── guardduty/
    ├── inspector/
    ├── scp-policies/
    └── multi-account-example/
```

**Environment root modules** (`terraform/environments/`) contain only `module` blocks that instantiate shared modules. They do not contain inline `resource` blocks. Each environment directory has five files: `main.tf`, `variables.tf`, `outputs.tf`, `backend.tf`, and `terraform.tfvars`. This pattern ensures that environment-specific logic (instance types, CIDR ranges, replica counts) is expressed solely in `terraform.tfvars`, making environment differentiation immediately visible in a code review.

**Shared modules** (`terraform/modules/`) contain all resource definitions. Modules expose a well-defined interface via `variables.tf` and `outputs.tf`. Module `README.md` files document the interface with an input/output table. All modules use `validation` blocks in `variables.tf` to catch misconfigured inputs at plan time.

### State Isolation Per Account

Each environment has its own Terraform state file in an S3 backend:

```hcl
terraform {
  backend "s3" {
    bucket         = var.tf_state_bucket
    key            = "<account-name>/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = var.tf_lock_table
    encrypt        = true
  }
}
```

S3 backend bucket names and DynamoDB lock table names are passed as variables (not hardcoded) and supplied via `terraform.tfvars`. The `key` path encodes the account name as the only literal string, ensuring each account's state file is uniquely keyed in the shared S3 bucket.

DynamoDB state locking prevents concurrent `terraform apply` operations from corrupting state. The state bucket uses SSE-KMS encryption and versioning, enabling point-in-time recovery of the state file.

### Cross-Account Remote State

Workload accounts read outputs from the `network-hub` account state file using the `terraform_remote_state` data source:

```hcl
data "terraform_remote_state" "network_hub" {
  backend = "s3"
  config = {
    bucket = var.network_hub_state_bucket
    key    = "network-hub/terraform.tfstate"
    region = var.aws_region
  }
}
```

This pattern is demonstrated in `terraform/modules/multi-account-example/main.tf`. It provides a type-safe, version-controlled mechanism for passing cross-account values (TGW ID, route table IDs, shared subnet IDs) without manual coordination or hardcoded values.

### DRY Principles

The module design enforces DRY (Don't Repeat Yourself) at every layer:

- Network topology (VPC, subnets, route tables, flow logs) is defined once in the `vpc` module and instantiated in each account
- TGW attachment logic is defined once in `tgw-attachment` and used by both `network-hub` and all workload accounts
- EKS cluster configuration is defined once in `eks-cluster`; only instance types and sizing vary per environment (supplied via `terraform.tfvars`)
- Security service configurations (GuardDuty, Inspector) are defined once in their respective modules and instantiated from the `audit` account root module

### Checkov Policy-as-Code

Checkov is integrated into the GitHub Actions CI pipeline to validate all Terraform files before `plan` or `apply`. Checkov checks are run against the `terraform/` directory on every pull request:

```yaml
- name: Checkov IaC Security Scan
  uses: bridgecrewio/checkov-action@master
  with:
    directory: terraform/
    framework: terraform
    soft_fail: false
```

Checkov enforces a baseline of security checks including: S3 buckets with public access blocked, encryption enabled on all storage resources, security groups without `0.0.0.0/0` ingress, IMDSv2 enforced on EC2 instances, and EKS API endpoint access restricted. Pull requests that introduce Checkov failures are blocked from merging.

---

## 11. End-to-End Request Flows

### Flow 1: Workload Pod Egress to Internet

This walkthrough describes the complete path taken by a container running in the `workload-prod` account when it makes an outbound HTTPS API call to an approved SaaS endpoint.

The pod is scheduled on a Linux node in the `app-private` subnet of the `workload-prod` VPC. The pod's process initiates a TCP connection to the target IP address on port 443. The Linux kernel's routing table inside the pod namespace forwards the packet to the node's primary network interface.

The node's subnet — `app-private` — has a route table with a single default route: `0.0.0.0/0 → tgw-<attachment-id>`. There is no route to an Internet Gateway in this route table, and an SCP enforces that no such route can be added. The packet is forwarded to the Transit Gateway via the VPC's TGW attachment ENI in the `tgw-attach` subnet.

The Transit Gateway receives the packet on the workload VPC's attachment and evaluates the spoke route table. The spoke route table contains a default route pointing to the Network Firewall inspection VPC attachment in the `network-hub` account. The TGW forwards the packet across the account boundary to the inspection VPC.

Inside the Network Firewall inspection VPC, the packet is delivered to a Network Firewall endpoint. The firewall's stateful engine evaluates the TLS SNI field in the ClientHello message against the FQDN allowlist. If the destination domain is on the allowlist, the packet is permitted and forwarded. If it is not on the allowlist, the packet is dropped and a DENY alert event is logged to CloudWatch Logs, which Splunk ingests within seconds.

For permitted traffic, the firewall forwards the packet to the `app-private` subnet in the hub VPC, which has a route to the NAT Gateway in the `public-ingress` subnet. The NAT Gateway translates the source IP to one of its Elastic IP addresses and forwards the packet to the Internet Gateway, which routes it to the internet.

The SaaS endpoint responds to the Elastic IP. Return traffic arrives at the Internet Gateway, is forwarded to the NAT Gateway, which reverse-translates the destination to the original pod IP and sends the packet back through the TGW. The TGW evaluates the inspection route table (associated with the hub VPC attachment) and routes return traffic back through the Network Firewall for symmetric stateful inspection. The firewall correlates the return packet with the existing flow state established during the outbound SYN, permits it, and forwards it back through the TGW to the workload VPC, where it is delivered to the pod.

At every hop, VPC Flow Logs capture the source and destination IP, port, protocol, and bytes transferred. These flow logs are delivered to the `logging` account S3 bucket, where they are retained under Object Lock and made available for forensic analysis.

### Flow 2: Automated Self-Healing — Web Server Failure

This walkthrough describes the complete automated response to a web server crash on an EC2 instance in the `workload-prod` account.

A CloudWatch metric alarm monitors the `nginx_active_connections` custom metric published by the Splunk Universal Forwarder. When the nginx process crashes, active connections drop to zero and the metric alarm transitions from `OK` to `ALARM` state. CloudWatch publishes the alarm state change event to EventBridge.

The EventBridge rule in the `self-healing` module evaluates the incoming event. The rule pattern matches `source: aws.cloudwatch`, `detail-type: CloudWatch Alarm State Change`, and `detail.state.value: ALARM`. The rule fires and starts a new Step Functions execution, passing the alarm name, instance ID (extracted from the alarm dimensions), and timestamp as input.

The Step Functions state machine begins execution at the `Detect` state. The state sends an SSM Run Command to the target instance using the `aws:states:::ssm:sendCommand.sync` resource, targeting the `ZeroTrustPlatform-LinuxTriage` document on the instance with the `SelfHealingEnabled=true` tag. The triage script executes: it checks `systemctl is-active nginx` (reports INACTIVE), captures the last 20 journal errors at priority 3 or higher, and checks disk usage. The script output is returned to the state machine as the task output.

The state machine transitions to the `Diagnose` state. A Lambda function receives the triage output and applies parsing logic: it detects the `nginx: INACTIVE` indicator, classifies the failure type as `service_down`, sets `remediationAction` to `restart_nginx`, and populates `escalationMessage` with a structured summary. The Lambda returns this diagnosis object.

The state machine transitions to the `Remediate` state. It sends a second SSM Run Command using the `ZeroTrustPlatform-Remediate` document, passing `remediationAction: restart_nginx`. The remediation document executes `systemctl restart nginx` and then runs a health check: `systemctl is-active nginx && curl -sf http://localhost/health`. If the health check returns success, the document sets `healthCheckPassed: true` in its output before completing.

The state machine transitions to the `Verify` state. This is a `Choice` state that evaluates `$.healthCheckPassed`. Since nginx restarted successfully and the health check passed, `healthCheckPassed` is `true`. The choice rule matches `BooleanEquals: true` and transitions to the implicit success end state. The execution completes successfully.

Step Functions logs the successful execution to CloudWatch Logs, including all state input/output and timestamps. The total elapsed time from alarm to successful remediation is typically 60–90 seconds. The on-call engineer sees no PagerDuty alert because the `Escalate` state was never reached.

In a failure scenario — for example, if nginx fails to start because a configuration file was corrupted — the remediation health check would set `healthCheckPassed: false`. The `Verify` state's default transition fires, routing execution to the `Escalate` state. `Escalate` publishes an SNS message containing the instance ID, alarm name, triage output summary, failure classification, remediation attempt result, and timestamp. SNS delivers the message to the PagerDuty HTTP endpoint (creating a P1 incident) and to the on-call engineer's email. The on-call engineer receives a fully contextualised alert: they know what broke, what was attempted, and what the current state is — without needing to SSH into the instance to gather initial diagnostic data.

---

## 12. Well-Architected Framework Compliance Matrix

| Pillar | Control | Implementation |
|--------|---------|----------------|
| **Operational Excellence** | Infrastructure as Code (IaC) for all resources | All AWS resources are defined in Terraform modules under `terraform/modules/` and instantiated from environment root modules. No manual console-provisioned resources exist in the production architecture. |
| **Operational Excellence** | Automated runbooks and self-healing | The Step Functions self-healing pipeline (Detect → Diagnose → Remediate → Verify → Escalate) automates first-response to common failures, reducing MTTR from hours to minutes and eliminating dependence on individual operator knowledge. |
| **Operational Excellence** | Continuous compliance monitoring | AWS Config with the `audit` account as aggregator continuously evaluates resource configurations against defined rules. Non-compliant resources trigger alerts or automated remediation. |
| **Security** | Zero-trust egress with FQDN allowlisting | All internet-bound traffic from workload accounts traverses AWS Network Firewall in the `network-hub` account. SCPs prevent creation of Internet Gateways or direct routes in workload accounts. Only allowlisted FQDNs can egress. |
| **Security** | Least-privilege pod identity via IRSA | Each EKS pod assumes an IAM role scoped to its specific API requirements via IRSA. No broad node-level instance profiles exist. Compromise of a pod yields only the permissions of its service account role. |
| **Security** | Immutable audit trail and organisation-wide threat detection | All logs are delivered to the `logging` account S3 bucket with Object Lock (WORM). GuardDuty and Inspector are active organisation-wide via delegated admin from the `audit` account, providing continuous threat detection and vulnerability management. |
| **Reliability** | Multi-AZ deployment for all critical components | All VPCs span two AZs. Network Firewall endpoints, NAT Gateways, and EKS node groups are deployed across AZs. TGW attachments use one ENI per AZ for path redundancy. |
| **Reliability** | Automated failure detection and recovery | CloudWatch Alarms → EventBridge → Step Functions provides automated detection and remediation of common failures. The Verify state confirms restoration before closing the incident. Unresolved failures escalate to SNS for human intervention. |
| **Reliability** | State isolation for IaC | Each AWS account maintains an independent Terraform state file in S3. A failed `terraform apply` in one account cannot corrupt or block another account's infrastructure changes. DynamoDB prevents concurrent state mutations. |
| **Performance Efficiency** | Dynamic compute scaling with Karpenter | Karpenter provisions and deprovisions nodes in response to pod scheduling demand, bin-packing workloads efficiently and consolidating underutilised nodes. OS-specific NodePools ensure Linux and Windows workloads are scheduled on appropriate hardware. |
| **Performance Efficiency** | ECR image immutability and enhanced scanning | Immutable ECR image tags ensure that CI/CD pipelines always deploy the exact image version tested and approved. Enhanced scanning provides continuous CVE monitoring without performance impact on the runtime environment. |
| **Cost Optimisation** | Environment-differentiated instance types | `workload-dev` and `workload-test` use smaller instance types (e.g. `t3.large` Linux / `t3.xlarge` Windows) while `workload-prod` uses production-grade types (e.g. `m6i.xlarge` / `m6i.2xlarge`). ECR lifecycle policies expire untagged images after 30 days, reducing storage costs. |
| **Cost Optimisation** | Centralised egress and NAT Gateway consolidation | A single NAT Gateway (per AZ) in the `network-hub` account serves all workload accounts via the TGW hub-spoke topology, eliminating the need for per-account NAT Gateways and reducing per-GB data processing charges. |
| **Sustainability** | Right-sized compute with Karpenter consolidation | Karpenter's consolidation feature continuously right-sizes the node fleet, replacing over-provisioned nodes with smaller instances that match actual workload resource requests. Idle capacity is removed automatically during off-peak periods. |
| **Sustainability** | Shared, centralised network infrastructure | The hub-spoke network model with a single `network-hub` account for TGW, Network Firewall, and NAT Gateway avoids duplicating these resources in every workload account, reducing the number of running network appliances and associated energy consumption. |
