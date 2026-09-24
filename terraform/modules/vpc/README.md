# Module: `vpc`

This module creates the four-tier VPC that underpins every account in the Zero-Trust Network Egress & Automated Operations Platform. The tiers are segregated by function and trust level: **public-ingress** hosts the NAT Gateway and internet-facing endpoints; **app-private** hosts EKS worker nodes and application workloads with no direct internet route; **data-private** isolates stateful services (RDS, ElastiCache) with no outbound path to the TGW or Internet Gateway; and **tgw-attach** provides dedicated `/28` subnets per Availability Zone exclusively for Transit Gateway attachments, ensuring TGW route propagation is isolated from workload route tables and enabling the symmetric routing required for all egress traffic to traverse the same Network Firewall endpoint in both directions.

> **Scaffold note:** This module is a demonstration scaffold. All `resource` blocks in `main.tf` are commented out and labelled with their architectural role. The variable and output interfaces are fully declared to show the module contract. Populate the resource blocks before production deployment.

---

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `vpc_name` | `string` | Name tag applied to the VPC and all derived resources. |
| `vpc_cidr` | `string` | Primary IPv4 CIDR block for the VPC (RFC 1918). |
| `public_subnet_cidr` | `string` | CIDR for the public-ingress subnet tier. |
| `app_private_subnet_cidr` | `string` | CIDR for the app-private compute tier (EKS nodes). |
| `data_private_subnet_cidr` | `string` | CIDR for the data-private tier (RDS, ElastiCache). |
| `tgw_attach_subnet_cidr` | `string` | `/28` CIDR for the Transit Gateway attachment tier. |
| `availability_zones` | `list(string)` | AZ names in the target region; one subnet per tier per AZ is created. |
| `flow_log_destination_arn` | `string` | ARN of the S3 bucket or CloudWatch Logs group that receives VPC Flow Logs. |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC. |
| `public_subnet_ids` | Subnet IDs for the public-ingress tier (one per AZ). |
| `app_private_subnet_ids` | Subnet IDs for the app-private tier; passed to the `eks-cluster` module as `node_subnet_ids`. |
| `data_private_subnet_ids` | Subnet IDs for the data-private tier; used for RDS/ElastiCache subnet groups. |
| `tgw_attach_subnet_ids` | `/28` subnet IDs for the tgw-attach tier; passed to the `tgw-attachment` module. |
