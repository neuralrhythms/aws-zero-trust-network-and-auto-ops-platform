# Architectural Decision Records

This document consolidates all architectural decisions made for the AWS Zero-Trust Network Egress & Automated Operations Platform. Each decision record captures the context, options considered, the chosen direction, and the resulting consequences. Together, these ten records form the evidence trail that underpins the platform design documented in `docs/architecture-reference.md`.

---

## ADR-001: AWS Transit Gateway over VPC Peering

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

The platform spans eight AWS accounts across three Organisational Units. Workload accounts (dev, test, staging, prod) require routed connectivity to the centralised Network Firewall and NAT Gateway in the `network-hub` account, as well as to each other in selected cases. A connectivity model is required that supports centralised egress inspection, scalable spoke attachment, and granular audit capabilities.

A dedicated `/28` `tgw-attach` subnet is provisioned in every VPC specifically for Transit Gateway Elastic Network Interface (ENI) placement. This subnet isolation serves four purposes:
1. **Route-table isolation** — the `tgw-attach` subnet has its own route table, allowing precise control over what traffic is directed to the TGW without affecting other subnet tiers.
2. **Symmetric firewall routing** — separating TGW ENIs ensures that both north-bound and south-bound flows traverse the same Network Firewall endpoint, satisfying stateful inspection requirements.
3. **Blast-radius containment** — if a TGW route table is misconfigured, the impact is limited to the isolated `/28` subnet rather than propagating to application or data tiers.
4. **Flow-log auditability** — VPC Flow Logs on the `tgw-attach` subnet capture all inter-account traffic at the TGW boundary, providing a clean audit trail for compliance and forensic investigation.

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **AWS Transit Gateway** | Centralised hub-and-spoke topology; single attachment point per VPC; supports route table segmentation for inspection routing; scales to thousands of VPCs; native VPC Flow Log integration per attachment; enables consistent egress path through Network Firewall | Additional per-attachment and per-GB data processing cost; requires dedicated `tgw-attach` subnets; cross-region peering adds latency |
| **VPC Peering** | No additional cost beyond data transfer; low-latency direct path; simple for small numbers of VPCs | Does not support transitive routing — each VPC pair requires a separate peering; scales poorly beyond ~10 VPCs; cannot route all traffic through a central inspection point without complex per-VPC route manipulation; no single audit point for inter-account traffic |

### Decision

AWS Transit Gateway is adopted as the central connectivity hub. All workload spoke VPCs attach to the TGW via dedicated `/28` `tgw-attach` subnets. Separate TGW route tables are maintained for spoke VPCs and the Network Firewall inspection VPC to enforce symmetric routing.

### Consequences

- All inter-account and egress traffic flows through a single, auditable Transit Gateway, enabling centralised Network Firewall inspection.
- Dedicated `tgw-attach` subnets must be provisioned in every VPC, consuming a small CIDR allocation per availability zone.
- TGW route table management becomes a critical operational concern — misconfiguration can black-hole traffic or bypass firewall inspection.
- Adding new spoke accounts is a repeatable, low-effort operation: provision a VPC, create a TGW attachment, associate with the spoke route table.
- VPC Peering is not used anywhere in the platform; all cross-account routing is via TGW.

---

## ADR-002: AWS Network Firewall for Centralised Egress Inspection

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

The client's current-state risk assessment identifies unfiltered internet egress as a primary threat vector. Workload pods and EC2 instances can reach arbitrary external endpoints, creating data exfiltration risk and violating the zero-trust principle of least-privilege network access. A centralised egress inspection capability is required that enforces an FQDN-based allowlist, provides deep-packet inspection, and integrates natively with the AWS-managed network hub.

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **AWS Network Firewall** | Fully managed; no EC2 instances to patch or scale; native integration with TGW and VPC route tables; stateful FQDN domain-list rule groups with HTTP_HOST and TLS_SNI inspection; pay-per-use pricing; CloudWatch metrics and Flow Logs built-in; no licensing costs | FQDN inspection requires TLS SNI (encrypted payload not inspected); limited layer-7 capabilities compared to next-gen appliances; no inline decryption |
| **Third-party virtual appliance (e.g. Palo Alto VM-Series, Fortinet FortiGate)** | Full SSL/TLS decryption and deep packet inspection; advanced threat prevention signatures; URL categorisation beyond FQDN lists; familiar to on-premises security teams | Requires EC2 instances that must be patched, scaled, and made highly available; significant licensing cost; operational burden of managing appliance lifecycle; HA configuration is complex (GWLB or active/passive); onboarding time longer; introduces vendor dependency |

### Decision

AWS Network Firewall is deployed in the `network-hub` account within the inspection VPC. Stateful rule groups use FQDN domain-list rules (`ALLOWLIST` type, `HTTP_HOST` and `TLS_SNI` target types) to permit only approved egress destinations. All workload egress is routed through the firewall via the TGW hub-spoke topology.

### Consequences

- Egress traffic to non-approved FQDNs is blocked by default, satisfying the zero-trust egress requirement.
- The `allowed_domains` list in `terraform/modules/network-firewall/variables.tf` becomes a critical configuration artefact — it must be reviewed and approved before any new external dependency is introduced.
- TLS-encrypted payloads are not decrypted; threat actors using approved domains (e.g. legitimate CDNs) for C2 are not detected at this layer — GuardDuty and Inspector provide compensating controls.
- No EC2 instances are required for firewall functions, eliminating patching and HA complexity.
- Network Firewall endpoint IDs must be referenced in workload route tables; the `network-hub` account outputs these values via Terraform remote state.

---

## ADR-003: EKS Managed Node Groups over Self-Managed Nodes

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

Each workload account runs an Amazon EKS cluster supporting both Linux (Amazon Linux 2) and Windows (Windows Server 2019 Core) workloads. A heterogeneous OS node strategy requires careful handling of node provisioning, patching, OS-specific taints and tolerations, and lifecycle management. The operational model must be sustainable at scale without dedicated node management engineering effort.

Windows nodes require an explicit `os=windows:NO_SCHEDULE` taint so that Linux workloads are not inadvertently scheduled onto Windows nodes. Karpenter NodePools are layered on top of Managed Node Groups for dynamic burst scaling, with per-OS NodePool configurations enforcing the same scheduling constraints.

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **EKS Managed Node Groups** | AWS manages node bootstrapping, AMI updates, and coordinated node replacement; automatic draining before termination; native integration with EKS cluster version lifecycle; reduced operational burden for heterogeneous OS; SSM Agent pre-installed on AWS-optimised AMIs; supports both AL2 and Windows Core AMI types | Less flexibility for custom bootstrapping logic; AMI selection limited to AWS-optimised types (AL2, Bottlerocket, Windows Core); node group configuration changes may trigger rolling replacement |
| **Self-managed nodes (Launch Templates + ASGs)** | Full control over AMI selection, bootstrapping scripts, and instance configuration; can use any AMI including custom hardened images | Must manage AMI baking, patch cadence, and node drain/cordon lifecycle manually; no automated coordinated upgrades with EKS control plane; higher operational burden; security patching delays likely; HA and scaling configuration entirely self-managed |

### Decision

EKS Managed Node Groups are used for both Linux and Windows node groups. The Linux group uses `ami_type = "AL2_x86_64"` with no taints. The Windows group uses `ami_type = "WINDOWS_CORE_2019_x86_64"` with taint `os=windows:NO_SCHEDULE`. Instance types are parameterised via `var.linux_instance_types` and `var.windows_instance_types` — never hardcoded.

### Consequences

- AWS handles AMI patch coordination and rolling node replacement, significantly reducing the operational burden of maintaining a heterogeneous OS cluster.
- Windows node taints require all Windows workload manifests to include a matching toleration — this is a workload-onboarding requirement that must be documented in developer guidelines.
- Karpenter NodePools must specify OS-specific node selectors and taints to ensure correct placement during burst scaling.
- Custom AMI requirements (e.g. additional hardening beyond CIS Level 1) would require migrating Windows nodes to self-managed groups — this is an accepted constraint for the current platform phase.
- Instance type differentiation across environments (dev `t3.*`, prod `m6i.*`) is enforced exclusively through `terraform.tfvars`, not module or environment `main.tf` files.

---

## ADR-004: Splunk Cloud over Native CloudWatch / OpenSearch for Unified Observability

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

The platform spans eight AWS accounts and two operating systems. Observability data — EC2 system logs, container logs, VPC Flow Logs, CloudTrail events, and application metrics — must be aggregated into a single pane of glass for operational monitoring, incident investigation, and compliance reporting. The client's security operations team has existing Splunk expertise and tooling.

Two collection agents are required:
- **Splunk Universal Forwarder** installed on EC2 instances ships OS-level logs directly to Splunk Cloud HEC.
- **Fluent Bit DaemonSet** deployed on EKS nodes ships container stdout/stderr to Splunk Cloud HEC. The DaemonSet is configured with dual tolerations to run on both Linux and Windows nodes.

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **Splunk Cloud (Universal Forwarder + Fluent Bit)** | Single unified search and dashboarding experience across all log sources; client's security team already has Splunk skills and saved searches; rich SPL query language; Splunk HEC provides a single ingestion endpoint; purpose-built add-ons for AWS S3 log ingestion, GuardDuty findings, and CloudTrail | Additional SaaS cost; HEC token management is a credential hygiene concern; Splunk Cloud ingestion volume pricing can escalate at scale |
| **Amazon CloudWatch + OpenSearch Service** | Native AWS integration; no additional SaaS cost; CloudWatch Logs Insights for ad-hoc queries; OpenSearch Dashboards (Kibana) for visualisation; Log subscription filters for routing | Fragmented experience — EC2 logs, container logs, and security findings land in different services; no single unified search layer; cross-account log aggregation requires complex CloudWatch cross-account subscription configuration; limited security team familiarity; OpenSearch cluster management overhead |

### Decision

Splunk Cloud is adopted as the unified observability platform. Splunk Universal Forwarder ships EC2 logs to Splunk HEC. Fluent Bit DaemonSet ships container logs to Splunk HEC. The Logging account S3 bucket is ingested by the Splunk S3 Add-on for VPC Flow Logs, CloudTrail, and Config snapshots. Prometheus + Grafana are retained for Kubernetes cluster metrics; X-Ray is used for distributed tracing.

### Consequences

- All operational, security, and audit logs flow into a single Splunk Cloud environment, enabling unified correlation across accounts and OS types.
- The `splunk_hec_token` variable is marked `sensitive = true` in all Terraform modules and must be sourced from AWS Secrets Manager at apply time — it must never appear in `terraform.tfvars` or version control.
- The Fluent Bit `fluentbit-values.yaml` must include both Linux and Windows tolerations to ensure container logs are collected from heterogeneous nodes.
- Splunk ingestion volume must be monitored; high-cardinality log sources (e.g. VPC Flow Logs at line-rate) should be sampled or filtered before forwarding.
- CloudWatch is retained for CloudWatch Alarms that trigger the EventBridge self-healing pipeline — it is not the primary log destination.

---

## ADR-005: SSM Session Manager over SSH/RDP Bastion Hosts

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

The client's current environment relies on SSH (port 22) and RDP (port 3389) access to EC2 instances, typically via bastion hosts or direct security group rules. This exposes the environment to brute-force attacks, credential theft, and lateral movement risk. It also makes auditing of operator actions difficult. The zero-trust security model requires elimination of all direct TCP access to instance operating systems.

The `deny-open-ssh-rdp.json` SCP enforces this at the organisational level by denying `ec2:AuthorizeSecurityGroupIngress` for ports 22 and 3389 from `0.0.0.0/0`, making it structurally impossible to open these ports via the AWS console or CLI in any member account.

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **AWS SSM Session Manager / Run Command** | No inbound ports required — uses outbound HTTPS (443) from SSM Agent to SSM service; full session audit trail in CloudTrail and CloudWatch Logs; integrates with IAM for access control; SCP can enforce no-SSH policy at OU level; supports both Linux and Windows; Session Manager logs stream to S3/CloudWatch; no bastion host infrastructure to manage | Requires SSM Agent on all instances (included in AL2 and Windows Server AMIs); requires IAM instance profile with `ssm:*` permissions; network connectivity to SSM service endpoints required (via VPC endpoints or NAT GW) |
| **SSH/RDP via bastion hosts** | Familiar to operations teams; works with existing tooling (PuTTY, RDP clients); no agent dependency | Bastion hosts are high-value attack targets; SSH keys and RDP credentials must be managed and rotated; no native session recording or audit trail; port 22/3389 must be open in security groups; does not align with zero-trust model; SCPs cannot enforce per-session auditability |

### Decision

AWS SSM Session Manager is the sole permitted method for interactive instance access. SSM Run Command is used by the self-healing Step Functions state machine to execute triage and remediation scripts (`linux-triage.sh`, `windows-triage.ps1`). The `deny-open-ssh-rdp.json` SCP is applied at the Workloads BU OU and Infrastructure OU levels to prevent any SSH/RDP security group rule from being created.

### Consequences

- No bastion host infrastructure is required, eliminating a class of attack surface and reducing infrastructure cost.
- All operator session activity is logged to CloudTrail and optionally to CloudWatch Logs, providing a complete audit trail for compliance.
- All EC2 instances must have a valid IAM instance profile with SSM permissions and network access to the SSM service endpoint (via NAT GW or VPC Interface Endpoint).
- Triage scripts (`linux-triage.sh`, `windows-triage.ps1`) are executed via `aws_ssm_document` resources of type `Command`, ensuring consistent, auditable script invocation.
- Emergency access procedures must be documented — if SSM connectivity is lost due to network misconfiguration, an out-of-band recovery path (e.g. EC2 Instance Connect Endpoint or Serial Console) must be defined.

---

## ADR-006: AWS Step Functions + EventBridge over Custom Lambda Orchestration

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

The self-healing operations pipeline must detect EC2 health failures, execute triage diagnostics, attempt automated remediation, verify recovery, and escalate to on-call engineers if remediation fails. This is a multi-step, stateful workflow with branching logic (verify → escalate or succeed) and timeout handling. A durable orchestration mechanism is required that provides visual workflow observability, retry/catch semantics, and a clear audit trail.

The workflow defines exactly five states: `Detect`, `Diagnose`, `Remediate`, `Verify`, `Escalate`.

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **AWS Step Functions (Standard Workflow) + EventBridge** | Native state machine with visual workflow editor in AWS console; built-in retry, catch, and timeout semantics per state; execution history retained for 90 days; EventBridge triggers Step Functions directly without custom integration code; CloudWatch Metrics for execution tracking; ASL (Amazon States Language) is declarative and auditable | ASL JSON syntax has a learning curve; Standard Workflow cost is per state transition; does not support sub-second latency requirements (not a constraint here) |
| **Custom Lambda orchestration (chained Lambda functions)** | Full flexibility in Python/Node.js; team may be more familiar with Lambda than ASL; no Step Functions cost | State management must be hand-coded (DynamoDB or in-memory); no native visual workflow; retry/timeout logic must be re-implemented per function; execution history must be custom-built; harder to audit and debug; brittle to Lambda cold starts and timeouts during long-running operations |

### Decision

AWS Step Functions Standard Workflows, triggered by EventBridge CloudWatch Alarm State Change rules, are used for all self-healing orchestration. The state machine defines exactly five states (`Detect`, `Diagnose`, `Remediate`, `Verify`, `Escalate`). The `Escalate` state publishes to an SNS topic (supplied via `var.sns_topic_arn`) and is terminal (`End = true`).

### Consequences

- The self-healing workflow is fully auditable via Step Functions execution history in the AWS console.
- Retry and catch semantics are declarative in ASL, reducing the risk of silent failures that plague chained Lambda architectures.
- The `Verify` state uses a `Choice` state to evaluate `$.healthCheckPassed` — if the health check boolean is `false`, execution routes to `Escalate` rather than succeeding silently.
- Adding new remediation actions (e.g. EBS volume recovery, RDS failover) requires extending the ASL definition in `sfn.tf`, not modifying Lambda function code.
- Step Functions Standard Workflow pricing (per state transition) is acceptable for the expected execution frequency — this is an infrequent self-healing workflow, not a high-throughput pipeline.
- The `diagnose_lambda_arn` variable in the `Diagnose` state allows plugging in a bespoke Lambda function for more sophisticated diagnosis without restructuring the state machine.

---

## ADR-007: IRSA / EKS Pod Identities over Node-Level IAM Instance Profiles

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

EKS workload pods require AWS API access (e.g. reading from S3, publishing to SNS, calling STS). The identity mechanism used to vend short-lived credentials to pods determines the blast radius of any pod compromise. Node-level IAM instance profiles grant all pods on a node the same permissions, violating the least-privilege principle. Pod-level identity scoping is required.

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **IRSA (IAM Roles for Service Accounts) / EKS Pod Identities** | Per-pod IAM role binding via Kubernetes Service Account annotation; credentials are short-lived tokens projected into the pod via OIDC; blast radius of a compromised pod is limited to that pod's role; audit trail in CloudTrail per role assumption; EKS Pod Identities (newer mechanism) simplify OIDC configuration | Requires OIDC provider configuration on the EKS cluster; developers must annotate Service Accounts correctly; Pod Identity agent DaemonSet required for EKS Pod Identities |
| **Node-level IAM instance profile** | Simple to configure — attach one role to the node group; no per-pod configuration required | All pods on a node share the same IAM role; a single compromised pod can access any AWS resource the node is permitted to access; violates least-privilege and zero-trust principles; IAM permissions tend to grow unbounded over time as new workloads are added |

### Decision

IRSA and EKS Pod Identities are used for all pod-level AWS API access. Node group IAM roles are scoped to the minimum permissions required for node operation (EKS node bootstrap, ECR pull, SSM agent). Workload-specific AWS access is granted exclusively via annotated Kubernetes Service Accounts bound to dedicated IAM roles.

### Consequences

- Each workload must define a Kubernetes Service Account with the correct IRSA annotation — this is a developer responsibility documented in the onboarding guide.
- The EKS OIDC provider ARN is exported from the `eks-cluster` module as `oidc_provider_arn` for use in IAM role trust policy construction.
- Credential rotation is automatic — STS issues short-lived tokens (default 1-hour TTL) projected into pods via the Kubernetes projected volume mechanism.
- Node IAM instance profiles have minimal permissions, ensuring that node-level compromise does not yield broad AWS access.
- Cross-account AWS API calls from pods require trust policy configuration in the target account's IAM role — this must be handled in workload-specific Terraform configuration, not in the EKS cluster module.

---

## ADR-008: Dedicated `logging` Account in Security OU as Immutable Log Archive

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

Three architectural questions drive this decision:

**(a) Why a dedicated logging account is needed:** Log centralisation is a compliance and forensic requirement. VPC Flow Logs, CloudTrail organisation trails, Config snapshots, and application logs must be retained in a location that is independent of the accounts that generated them. If logs are stored in the same account as the workloads, an account compromise could result in log tampering or deletion, destroying the forensic evidence trail.

**(b) Why Security OU, not Infrastructure OU:** The `logging` account stores audit evidence — its primary consumers are security and compliance teams, not infrastructure operators. Placing it in Security OU aligns access boundaries with the principle of least privilege: Infrastructure OU SCPs should not govern audit evidence storage. Security OU SCPs can enforce stricter controls (e.g. deny all write operations from non-pipeline principals).

**(c) Why separate from the `audit` account:** The `audit` account hosts active security tooling — GuardDuty, Inspector, Security Hub, Config Aggregator, and IAM Access Analyzer. If log storage and security tooling access are co-located, a compromise of the security tooling account could allow an attacker to simultaneously access and tamper with audit logs. Separation ensures log integrity is independent of security tooling access. The `audit` account has read-only access to `logging` S3 — it cannot write or delete.

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **Dedicated `logging` account with S3 Object Lock (WORM)** | Complete separation of log storage from security tooling; S3 Object Lock enforces immutability at the object level (WORM — Write Once Read Many); account-level SCPs can deny all delete and put operations from non-CloudTrail principals; `audit` has read-only access; blast radius of any single account compromise is contained | Additional account to manage; cross-account S3 bucket policies required for CloudTrail, VPC Flow Logs, and Config delivery; slightly increased complexity in Splunk S3 Add-on configuration |
| **Log storage in `audit` account alongside security tooling** | Simpler account model; single Security OU account to manage | Log integrity is coupled to security tooling access — a compromise of the `audit` account could destroy both detection capability and evidence; does not satisfy independence requirement for regulatory compliance |

### Decision

A dedicated `logging` account is provisioned in the Security OU. The CloudTrail organisation trail targets the `logging` account S3 bucket. S3 Object Lock is configured in `COMPLIANCE` mode to enforce WORM immutability — no principal, including the account root, can delete or overwrite log objects within the retention period. The `audit` account is granted read-only access to the `logging` S3 bucket via bucket policy.

### Consequences

- CloudTrail organisation trail targets the `logging` account S3 bucket — all management, infrastructure, and application API activity is captured in a tamper-proof archive.
- Splunk S3 Add-on is configured to ingest from the `logging` account S3 bucket, providing Splunk visibility into CloudTrail, VPC Flow Logs, and Config change history.
- The `audit` account has read-only access to `logging` S3 — it can consume findings and correlate with log data, but cannot write or delete log objects.
- S3 Object Lock retention policies must be defined in `terraform/environments/logging/main.tf` before the bucket is used — post-creation modification of Object Lock is restricted.
- The `logging` account `main.tf` must include an `aws_s3_bucket_object_lock_configuration` resource with `COMPLIANCE` mode and an appropriate retention period (e.g. 365 days minimum).
- Any new log source onboarded to the platform must be directed to the `logging` account S3 bucket — this is a platform onboarding requirement.

---

## ADR-009: Amazon GuardDuty for Organisation-Wide Threat Detection

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

The platform requires continuous threat detection across all eight accounts. Individual account-level threat detection creates blind spots and requires each account team to independently manage findings. An organisation-wide, centrally managed detection capability with a single findings aggregation point is required. GuardDuty findings must flow to Splunk for correlation with other security data, and high-severity findings must trigger immediate on-call notification.

The delegated administrator model designates the `audit` account as the single point of GuardDuty management across the organisation. All member account findings are aggregated in the `audit` account. From there, EventBridge routes findings to the `logging` account S3 bucket for archival and to Splunk HEC for real-time analysis. High-severity findings additionally trigger SNS → PagerDuty → on-call.

Protection plans enabled: **EKS Audit Logs** (Kubernetes control plane activity), **S3 Data Events** (abnormal S3 access patterns), **EC2 Malware Protection** (EBS volume scanning on suspicious findings), **RDS Login Activity** (anomalous database authentication).

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **Amazon GuardDuty with delegated admin via `audit` account** | Fully managed ML-based threat detection; no infrastructure to deploy; native AWS integration with CloudTrail, VPC Flow Logs, DNS logs, EKS audit logs; organisation-wide coverage with single delegated admin; findings aggregated centrally; pay-per-usage pricing; continuous model updates by AWS | Findings may require tuning to reduce false positives; EBS scanning (Malware Protection) adds cost proportional to volume scanned; limited customisation of detection logic compared to dedicated SIEM rules |
| **Manual threat detection / third-party SIEM ingestion only** | Full control over detection rules; leverages existing SIEM investment; can ingest raw log data for custom correlation | Requires dedicated security engineering effort to build and maintain detection rules; no baseline threat intelligence integration; delayed time-to-detect for novel attack patterns; no native EKS or S3 data event analysis capability |

### Decision

Amazon GuardDuty is enabled across all member accounts with the `audit` account designated as delegated administrator via `aws_guardduty_organization_configuration` with `auto_enable_organization_members = "ALL"`. All four protection plans are enabled. Findings flow: `audit` account aggregation → EventBridge rule → `logging` account S3 (archival) → Splunk S3 Add-on (ingestion). High-severity findings additionally trigger SNS → PagerDuty → on-call engineer.

### Consequences

- All eight accounts have GuardDuty enabled automatically as new accounts join the organisation, with no per-account configuration required.
- The `audit` account's `terraform/environments/audit/main.tf` instantiates the `guardduty` module — this is the single source of truth for organisation-wide GuardDuty configuration.
- Finding routing from `audit` EventBridge to `logging` S3 requires a cross-account EventBridge target configuration — this is handled in `terraform/environments/audit/main.tf`.
- GuardDuty and Inspector are both delegated from the `audit` account, creating a unified security tooling hub without compromising log archive integrity in the `logging` account.
- EBS volume scanning (Malware Protection) incurs per-GB scanning cost when GuardDuty identifies suspicious EC2 activity — this is an accepted cost for the security posture improvement.
- GuardDuty suppression rules should be reviewed quarterly to reduce false positive noise in Splunk dashboards.

---

## ADR-010: Amazon Inspector for Continuous Vulnerability Management

**Status:** Accepted | **Date:** 2026-09-22 | **Deciders:** Platform Architecture Team

### Context

The platform runs EC2 instances (Linux and Windows), EKS container workloads with images stored in ECR, and Lambda functions. Each compute type has a distinct vulnerability surface: OS-level CVEs for EC2, container image CVEs for ECR, and dependency CVEs for Lambda. A continuous, automated vulnerability scanning capability is required that covers all three compute types without requiring agents or scheduled scan jobs.

Inspector complements GuardDuty: Inspector provides **vulnerability data** (known CVEs, software package exposure), while GuardDuty provides **threat detection** (anomalous behaviour, active threats). Both are delegated from the `audit` account, creating a unified security control plane.

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| **Amazon Inspector v2 with delegated admin via `audit` account** | Agentless continuous scanning for EC2 (SSM-based) and ECR (registry integration); organisation-wide coverage via delegated admin; findings aggregated in `audit` account alongside GuardDuty; native ECR enhanced scanning replaces basic ECR scan-on-push; Lambda function package scanning; CVSS scoring and exploitability context; no scheduling required | SSM Agent must be present on EC2 instances for Inspector EC2 scanning; ECR enhanced scanning replaces basic scanning — existing scan-on-push configuration must be migrated; Inspector findings add to Splunk ingestion volume |
| **Manual vulnerability scanning / third-party tools (e.g. Qualys, Tenable)** | Existing enterprise tooling may already be procured; rich reporting features; supports non-AWS workloads | Agent deployment and management required on every EC2 instance; no native ECR or Lambda integration; scan scheduling required; findings must be ingested into Splunk separately; organisational management less integrated with AWS accounts |

### Decision

Amazon Inspector v2 is enabled organisation-wide via `aws_inspector2_organization_configuration` with `auto_enable` for `ec2 = true`, `ecr = true`, and `lambda = true`. The `audit` account acts as delegated administrator, consistent with GuardDuty. Inspector findings are aggregated in the `audit` account and routed to the `logging` account S3 bucket and Splunk via the same EventBridge pipeline used by GuardDuty findings.

### Consequences

- All EC2 instances, ECR repositories, and Lambda functions across all eight accounts are continuously scanned for known CVEs without any per-account configuration or scan scheduling.
- ECR enhanced scanning (Inspector) supersedes basic scan-on-push — the `aws_ecr_repository` resources in `terraform/modules/ecr/main.tf` retain `scan_on_push = true` as a defence-in-depth measure, but Inspector provides the primary vulnerability signal.
- Inspector and GuardDuty findings share the same `audit` account aggregation point and the same EventBridge → `logging` S3 → Splunk routing pipeline, reducing operational complexity.
- The `audit` account `terraform/environments/audit/main.tf` instantiates both `guardduty` and `inspector` modules, making it the single Terraform entry point for all organisation-wide security tooling.
- Critical CVE findings (CVSS ≥ 9.0) should be mapped to the `Escalate` SNS topic for immediate on-call notification — this integration is a post-platform-build configuration item in Splunk.
- SSM Agent must be present and healthy on all EC2 instances for Inspector EC2 scanning to function — this dependency is satisfied by the SSM-first access model adopted in ADR-005.
