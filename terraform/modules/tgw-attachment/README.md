# Module: tgw-attachment

This module attaches a spoke VPC to the AWS Transit Gateway and associates the resulting attachment with a designated TGW route table. It is the mechanism by which workload accounts join the hub-spoke network topology: all egress traffic from a spoke VPC routes through the TGW to the Network Firewall inspection VPC before reaching the NAT Gateway, enforcing centralised egress inspection on every outbound connection. The attachment is placed in a dedicated `/28` `tgw-attach` subnet tier (per ADR-001) to achieve route-table isolation — keeping TGW routing concerns separate from workload subnets — and to ensure symmetric routing so that both inbound and outbound flows traverse the same Network Firewall endpoint. The isolated subnet also contains the blast radius of any route misconfiguration and guarantees that VPC Flow Logs capture all inter-VPC traffic at the precise attachment point.

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `transit_gateway_id` | `string` | The ID of the Transit Gateway to attach the spoke VPC to. |
| `vpc_id` | `string` | The ID of the spoke VPC being attached to the Transit Gateway. |
| `tgw_attach_subnet_ids` | `list(string)` | Subnet IDs in the dedicated /28 tgw-attach tier. One subnet per Availability Zone is recommended to support symmetric routing through the Network Firewall inspection VPC. |
| `transit_gateway_route_table_id` | `string` | The ID of the TGW route table to associate this attachment with. Separate route tables for spoke VPCs and the inspection VPC enforce symmetric routing. |

## Outputs

| Name | Description |
|------|-------------|
| `attachment_id` | The ID of the Transit Gateway VPC attachment. Consumed by the network-hub and workload environments to reference the attachment in route table propagations and monitoring. |

## Usage

This module is called by:

- `terraform/environments/network-hub/` — to attach the hub inspection VPC to the TGW
- `terraform/environments/workload-dev/`, `workload-test/`, `workload-staging/`, `workload-prod/` — to attach each workload spoke VPC to the TGW
- `terraform/modules/multi-account-example/` — as the canonical demonstration of cross-account module composition using the TGW ID read from `network-hub` remote state
