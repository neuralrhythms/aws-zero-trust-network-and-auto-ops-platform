# Module: inspector

Enables **Amazon Inspector v2** organisation-wide for continuous vulnerability management. This module is instantiated from `terraform/environments/audit/main.tf` — the `audit` account acts as the **delegated administrator** for Inspector across the AWS Organisation.

## What this module does

| Resource | Purpose |
|---|---|
| `aws_inspector2_enabler` | Activates Inspector v2 in the `audit` (delegated-admin) account for EC2, ECR, and Lambda resource types |
| `aws_inspector2_organization_configuration` | Sets `auto_enable = true` for EC2, ECR, and Lambda so every new member account is automatically enrolled |
| `aws_inspector2_member_association` | Associates existing member accounts so aggregated findings flow to the `audit` account |

### Scan types enabled

- **EC2** — OS and software package CVE scanning via the SSM agent (no agent installation required beyond SSM)
- **ECR (enhanced)** — Container image scanning on push *and* continuously as new CVEs are published
- **Lambda** — Function code and dependency layer vulnerability scanning

## Relationship to GuardDuty

Both Inspector and GuardDuty are delegated from the `audit` account (Security OU), but they serve complementary purposes:

- **Inspector** → *Vulnerability management* — identifies what is potentially exploitable (CVEs, misconfigurations)
- **GuardDuty** → *Threat detection* — identifies what is actively being attacked or exploited

Findings from both services aggregate in the `audit` account and are forwarded via EventBridge to the `logging` account S3 bucket and onward to Splunk.

## Pre-requisite

The `audit` account must be registered as the Inspector v2 delegated administrator in the AWS Organisation **before** this module is applied:

```bash
aws inspector2 enable-delegated-admin-account \
  --delegated-admin-account-id <AUDIT_ACCOUNT_ID> \
  --region <AWS_REGION>
```

This is a one-time manual step (or performed via the `management` account's SCP/org bootstrap).

## Inputs

| Name | Type | Description |
|---|---|---|
| `member_account_ids` | `list(string)` | AWS account IDs of member accounts to associate with the delegated admin. Must be 12-digit IDs; at least one required. |

## Outputs

| Name | Description |
|---|---|
| `organization_configuration_status` | Map of `ec2`, `ecr`, `lambda` auto-enable boolean values from the org configuration resource |
| `audit_account_id` | Account ID of the delegated administrator running this module |
| `associated_member_account_ids` | Set of member account IDs associated with Inspector v2 |

## Usage example

```hcl
# terraform/environments/audit/main.tf

module "inspector" {
  source = "../../modules/inspector"

  member_account_ids = var.member_account_ids   # supplied via terraform.tfvars
}
```

## Directory structure

```
terraform/modules/inspector/
├── main.tf        # aws_inspector2_enabler, aws_inspector2_organization_configuration,
│                  # aws_inspector2_member_association
├── variables.tf   # member_account_ids
├── outputs.tf     # organization_configuration_status, audit_account_id,
│                  # associated_member_account_ids
└── README.md      # this file
```
