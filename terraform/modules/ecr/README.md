# Module: `ecr`

This module provisions one or more Amazon ECR repositories with production-grade security defaults: image tags are set to **immutable** (preventing tag overwrites), **scan-on-push** is enabled so every pushed image is assessed by Amazon Inspector for OS and package vulnerabilities, and a **lifecycle policy** automatically expires untagged images older than 30 days to control storage costs. The module is instantiated from workload environment root modules (`terraform/environments/workload-*/main.tf`) and accepts a list of repository names so multiple application images can be managed with a single module call.

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `repository_names` | `list(string)` | List of ECR repository names to create. Must contain at least one entry. |

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `repository_urls` | `map(string)` | Map of repository name → repository URL for all created repositories. |

## Usage

```hcl
module "ecr" {
  source           = "../../modules/ecr"
  repository_names = ["app-backend", "app-frontend", "batch-processor"]
}
```

> **Note:** This module is a shared building block. It does not set cross-account registry policies or replication rules — those concerns are handled at the environment layer if required.
