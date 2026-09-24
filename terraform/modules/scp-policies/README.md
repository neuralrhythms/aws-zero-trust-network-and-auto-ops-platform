# Terraform Module: scp-policies

This module creates and attaches two AWS Organizations Service Control Policies (SCPs) that form the foundational Zero Trust network guardrails for the platform. The first SCP eliminates the risk of direct internet breakout by denying Internet Gateway creation and any route table entry that points to an IGW, ensuring all egress traffic is forced through the hub-and-spoke path (Transit Gateway → AWS Network Firewall → NAT Gateway). The second SCP closes the attack surface for lateral movement and credential theft by denying any Security Group rule that exposes SSH (port 22/TCP) or RDP (port 3389/TCP) to `0.0.0.0/0`, mandating that all operational access uses AWS Systems Manager Session Manager or Run Command instead. Together, these two SCPs enforce the Zero Trust principle of "never trust, always verify" at the network perimeter, regardless of individual account configurations.

---

## SCP Details

### `deny-direct-internet-egress`

| Attribute | Value |
|-----------|-------|
| File | `deny-direct-internet-egress.json` |
| Attached to | Workloads BU OU; recommended for Infrastructure OU spoke accounts |
| Attack surface reduced | Prevents rogue Internet Gateways from bypassing Network Firewall inspection and NAT Gateway controls |

**Statements:**

| Sid | Effect | Action(s) | Condition |
|-----|--------|-----------|-----------|
| `DenyDirectInternetGatewayCreation` | Deny | `ec2:CreateInternetGateway` | None — unconditional deny |
| `DenyRouteToInternetGateway` | Deny | `ec2:CreateRoute`, `ec2:ReplaceRoute` | `ec2:GatewayId` matches `igw-*` |

---

### `deny-open-ssh-rdp`

| Attribute | Value |
|-----------|-------|
| File | `deny-open-ssh-rdp.json` |
| Attached to | All OUs — Infrastructure OU, Security OU, Workloads BU OU |
| Attack surface reduced | Prevents internet-accessible SSH/RDP endpoints; forces all shell/desktop access through SSM Session Manager (no open ports, full audit trail) |

**Statements:**

| Sid | Effect | Action | Condition |
|-----|--------|--------|-----------|
| `DenyOpenSSH` | Deny | `ec2:AuthorizeSecurityGroupIngress` | Protocol `tcp`, Port `22`, CIDR `0.0.0.0/0` |
| `DenyOpenRDP` | Deny | `ec2:AuthorizeSecurityGroupIngress` | Protocol `tcp`, Port `3389`, CIDR `0.0.0.0/0` |

---

## Inputs

| Variable | Type | Description |
|----------|------|-------------|
| `target_ou_id` | `string` | The AWS Organizations OU ID to attach the SCPs to (e.g. `ou-xxxx-yyyyyyyy`). Instantiate the module once per target OU. |
| `management_account_id` | `string` | The AWS account ID of the Organizations management (root) account. Ensures the management account is not inadvertently targeted. |

## Outputs

| Output | Description |
|--------|-------------|
| `scp_deny_egress_id` | Policy ID of the `deny-direct-internet-egress` SCP. Use to attach to additional OUs or reference from other modules. |
| `scp_deny_ssh_rdp_id` | Policy ID of the `deny-open-ssh-rdp` SCP. Use to attach to additional OUs or reference from other modules. |

---

## Usage

```hcl
# terraform/environments/management/main.tf
module "scp_policies" {
  source = "../../modules/scp-policies"

  target_ou_id          = var.workloads_ou_id
  management_account_id = var.management_account_id
}
```

For multiple OU targets, instantiate the module with an alias:

```hcl
module "scp_policies_workloads" {
  source = "../../modules/scp-policies"
  target_ou_id          = var.workloads_ou_id
  management_account_id = var.management_account_id
}

module "scp_policies_infrastructure" {
  source = "../../modules/scp-policies"
  target_ou_id          = var.infrastructure_ou_id
  management_account_id = var.management_account_id
}
```

---

> **Scaffold note:** The `main.tf` resource blocks (`aws_organizations_policy` and
> `aws_organizations_policy_attachment`) are commented out and require population before
> production deployment. The JSON policy documents (`deny-direct-internet-egress.json` and
> `deny-open-ssh-rdp.json`) are complete and production-ready. The Terraform provider must
> be configured with `aws_organizations` permissions in the management account, and the
> executing IAM principal requires `organizations:CreatePolicy` and
> `organizations:AttachPolicy` permissions.
