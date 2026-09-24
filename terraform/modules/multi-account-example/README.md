# Multi-Account Example Module

This module is the canonical demonstration of cross-account module composition for the Zero-Trust Network Egress & Automated Operations Platform. It shows exactly how a workload spoke account (`workload-prod`) consumes the platform's shared Terraform modules while pulling shared infrastructure outputs — Transit Gateway ID and spoke route table ID — from the Network-Hub account via `terraform_remote_state`. It is the primary evidence artefact for the submission deliverable: *"code snippets demonstrating multi-account module instantiation."*

---

## Cross-Account Pattern

The module composes five building blocks in a single root call:

```
Network-Hub account (S3 remote state)
  └── outputs: transit_gateway_id, spoke_route_table_id
        │
        ▼
workload-prod account (this module)
  ├── tgw-attachment   — attaches workload VPC to the shared Transit Gateway
  ├── eks-cluster      — provisions EKS with Linux + Windows Managed Node Groups
  ├── ecr              — creates immutable ECR repositories with scan-on-push
  ├── guardduty*       — org-wide threat detection (delegated from audit account)
  └── inspector*       — continuous vulnerability management (delegated from audit account)
```

> **\* Delegated Administrator Note:** The `guardduty` and `inspector` modules are owned and applied by the **`audit` account** (Security OU), which acts as the delegated administrator for both services across the organisation. They are instantiated here to demonstrate the complete multi-account composition pattern. In production, these modules are applied from `terraform/environments/audit/main.tf`.

---

## Directory Structure

```
terraform/modules/multi-account-example/
├── main.tf        # Cross-account module composition — all 5 patterns
├── variables.tf   # All input variable declarations
├── outputs.tf     # Key resource identifiers exposed for downstream use
└── README.md      # This file
```

The referenced shared modules all exist under `terraform/modules/`:

| Module source path | Purpose |
|--------------------|---------|
| `../../modules/tgw-attachment` | Transit Gateway VPC attachment + route table association |
| `../../modules/eks-cluster` | EKS cluster with Linux and Windows Managed Node Groups |
| `../../modules/ecr` | ECR repositories (immutable tags, scan-on-push) |
| `../../modules/guardduty` | GuardDuty org-wide detector + organisation configuration |
| `../../modules/inspector` | Inspector org-wide EC2 / ECR / Lambda scanning |

---

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `network_hub_state_bucket` | `string` | — | S3 bucket storing the Network-Hub Terraform state; used to read TGW ID and route table IDs |
| `aws_region` | `string` | — | AWS region for the remote state bucket and resource deployment |
| `vpc_id` | `string` | — | ID of the workload VPC to attach to the Transit Gateway |
| `tgw_attach_subnet_ids` | `list(string)` | — | Subnet IDs in the tgw-attach tier (/28 per AZ) for the TGW VPC attachment |
| `transit_gateway_route_table_id` | `string` | `null` | Optional override for the TGW route table association; defaults to the spoke route table from remote state |
| `cluster_name` | `string` | — | EKS cluster name |
| `cluster_version` | `string` | `"1.29"` | Kubernetes version for the EKS control plane |
| `node_subnet_ids` | `list(string)` | — | Subnet IDs (app-private tier) for EKS node group placement |
| `linux_instance_types` | `list(string)` | — | EC2 instance types for the Linux managed node group (validation: length > 0) |
| `linux_min_size` | `number` | — | Minimum node count — Linux group |
| `linux_max_size` | `number` | — | Maximum node count — Linux group |
| `linux_desired_size` | `number` | — | Desired node count — Linux group |
| `windows_instance_types` | `list(string)` | — | EC2 instance types for the Windows managed node group (validation: length > 0) |
| `windows_min_size` | `number` | — | Minimum node count — Windows group |
| `windows_max_size` | `number` | — | Maximum node count — Windows group |
| `windows_desired_size` | `number` | — | Desired node count — Windows group |
| `ecr_repository_names` | `list(string)` | — | Names of ECR repositories to create in this workload account |
| `member_account_ids` | `list(string)` | — | AWS account IDs to enrol in GuardDuty and Inspector org configurations |
| `finding_publishing_frequency` | `string` | `"SIX_HOURS"` | Frequency at which GuardDuty publishes updated findings |
| `sns_topic_arn` | `string` | — | SNS topic ARN for high-severity GuardDuty finding alerts |

---

## Outputs

| Name | Description |
|------|-------------|
| `tgw_attachment_id` | ID of the Transit Gateway VPC attachment connecting this spoke to the Network-Hub |
| `eks_cluster_name` | Name of the provisioned EKS cluster |
| `eks_cluster_endpoint` | EKS API server endpoint URL |
| `eks_oidc_provider_arn` | OIDC provider ARN for IRSA (IAM Roles for Service Accounts) configuration |
| `ecr_repository_urls` | Map of repository name → URL for all ECR repositories in this account |
| `guardduty_detector_id` | GuardDuty detector ID (managed by the `audit` account as delegated admin) |
| `inspector_organization_configuration_status` | Inspector org configuration status (managed by the `audit` account) |

---

## Usage Context

This module is consumed directly by the workload environment root modules. The `workload-prod` environment is the canonical consumer:

```hcl
# terraform/environments/workload-prod/main.tf
module "workload" {
  source = "../../modules/multi-account-example"

  network_hub_state_bucket = var.network_hub_state_bucket
  aws_region               = var.aws_region
  # ... remaining variables from terraform.tfvars
}
```

Instance type values (`linux_instance_types`, `windows_instance_types`) are supplied exclusively via `terraform.tfvars` — never hardcoded in `main.tf` or `variables.tf`. This enforces the platform's DRY principle and makes environment-to-environment differentiation (dev `t3.large` → prod `m6i.xlarge`) a single-file change.
