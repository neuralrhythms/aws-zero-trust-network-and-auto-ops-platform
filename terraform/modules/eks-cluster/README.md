# Module: `eks-cluster`

Provisions an Amazon EKS cluster with two heterogeneous Managed Node Groups: one for Linux workloads (Amazon Linux 2, `AL2_x86_64`) and one for Windows workloads (Windows Server 2019 Core, `WINDOWS_CORE_2019_x86_64`). Windows nodes are tainted `os=windows:NoSchedule` so that only pods carrying the corresponding toleration are scheduled on Windows capacity, ensuring OS-specific workloads land on the correct node type. The cluster OIDC provider is enabled by default, enabling IRSA (IAM Roles for Service Accounts) and EKS Pod Identities so pods assume scoped IAM roles via projected service account tokens — no broad node-level instance profiles are required. The module is designed to be layered with Karpenter NodePools (deployed by the `eks-addons` module) for dynamic scaling on top of the baseline Managed Node Group capacity.

> **Community module:** this module wraps [`terraform-aws-modules/eks/aws ~> 20.0`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest). All instance type values are injected via input variables and must never be hardcoded.

---

## Usage

```hcl
module "eks_cluster" {
  source  = "../../modules/eks-cluster"

  cluster_name           = var.cluster_name
  cluster_version        = var.cluster_version
  vpc_id                 = module.vpc.vpc_id
  node_subnet_ids        = module.vpc.app_private_subnet_ids
  linux_instance_types   = var.linux_instance_types    # from terraform.tfvars
  windows_instance_types = var.windows_instance_types  # from terraform.tfvars
}
```

---

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | `string` | — | Name of the EKS cluster |
| `cluster_version` | `string` | `"1.29"` | Kubernetes version to deploy |
| `vpc_id` | `string` | — | VPC ID for the cluster and node groups |
| `node_subnet_ids` | `list(string)` | — | App-private subnet IDs for node group placement |
| `linux_instance_types` | `list(string)` | — | EC2 instance types for Linux node group (from `terraform.tfvars`) |
| `linux_min_size` | `number` | `1` | Minimum nodes in Linux node group |
| `linux_max_size` | `number` | `5` | Maximum nodes in Linux node group |
| `linux_desired_size` | `number` | `2` | Desired nodes in Linux node group |
| `windows_instance_types` | `list(string)` | — | EC2 instance types for Windows node group (from `terraform.tfvars`) |
| `windows_min_size` | `number` | `1` | Minimum nodes in Windows node group |
| `windows_max_size` | `number` | `3` | Maximum nodes in Windows node group |
| `windows_desired_size` | `number` | `1` | Desired nodes in Windows node group |

---

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | Name of the provisioned EKS cluster |
| `cluster_endpoint` | HTTPS endpoint for the Kubernetes API server |
| `cluster_certificate_authority_data` | Base64-encoded CA data for kubectl / provider configuration |
| `oidc_provider_arn` | ARN of the OIDC provider; used in IRSA IAM role trust policies |
| `cluster_iam_role_arn` | ARN of the IAM role attached to the EKS control plane |

---

## Design Notes

- **Heterogeneous OS scheduling** — Windows nodes carry a `os=windows:NO_SCHEDULE` taint. Kubernetes deployments targeting Windows must include a matching toleration and a `nodeSelector` or `nodeAffinity` for `kubernetes.io/os: windows`.
- **IRSA / Pod Identities** — `enable_irsa = true` creates the cluster OIDC provider. Downstream IAM roles reference the provider ARN (exposed via `oidc_provider_arn` output) in their trust policy.
- **Karpenter compatibility** — Managed Node Groups provide baseline capacity; Karpenter NodePools (one per OS) layer on top for burst scaling. Both node pools use taints/tolerations consistent with this module's node group definitions.
- **No hardcoded instance types** — `linux_instance_types` and `windows_instance_types` are validated list variables. Values are supplied exclusively in `terraform.tfvars` per environment (e.g. `t3.large` for dev, `m6i.xlarge` for prod).
