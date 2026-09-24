# Module: `network-firewall`

This module deploys AWS Network Firewall with a stateful FQDN domain-list rule group for centralised egress inspection. The allowlist pattern blocks all outbound HTTPS and HTTP traffic except explicitly approved domains supplied via `var.allowed_domains`, enforcing Zero Trust egress control across all workload VPCs. The firewall is deployed in the `network-hub` account's `app-private` subnet, where it intercepts traffic forwarded from spoke VPCs via the Transit Gateway before it reaches the NAT Gateway and the public internet.

> **Note:** This module is the enforcement point for Zero Trust egress control (ADR-002). It is instantiated from `terraform/environments/network-hub/main.tf`.

---

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `firewall_name` | `string` | Name for the AWS Network Firewall resource and its associated policy |
| `vpc_id` | `string` | ID of the network-hub VPC in which the firewall is deployed |
| `firewall_subnet_id` | `string` | ID of the app-private subnet where the firewall endpoint is created |
| `allowed_domains` | `list(string)` | List of allowed FQDNs for egress (e.g. `.amazonaws.com`, `.splunkcloud.com`). All other HTTP/HTTPS destinations are blocked. |
| `rule_group_name` | `string` | Name for the stateful FQDN domain-list rule group |
| `rule_group_capacity` | `number` | Capacity units for the stateful rule group (each FQDN rule consumes 1 unit) |

## Outputs

| Name | Description |
|------|-------------|
| `firewall_arn` | ARN of the deployed AWS Network Firewall |
| `firewall_endpoint_id` | VPC endpoint ID for the Network Firewall (referenced in route tables to direct egress traffic through the firewall) |
