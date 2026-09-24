# Terraform Module: eks-addons

This module deploys three EKS cluster add-ons via Helm into a workload EKS cluster: **AWS Load Balancer Controller**, which watches Kubernetes `Ingress` objects and provisions Application Load Balancers in the workload VPC; **Karpenter**, a dynamic node provisioner that replaces Cluster Autoscaler and uses OS-specific NodePools to ensure Linux and Windows workloads land on the correct node type; and **Fluent Bit**, a lightweight log processor deployed as a DaemonSet that ships container logs from all cluster nodes to Splunk Cloud via the HTTP Event Collector (HEC) output plugin.

## Linux / Windows Toleration Strategy

The `fluentbit-values.yaml` file defines two tolerations to achieve full DaemonSet coverage across the heterogeneous node groups:

1. **`os=windows:NoSchedule`** — explicitly tolerates the taint applied to Windows managed node group instances, so the Fluent Bit pod is scheduled onto Windows nodes.
2. **`Exists` operator (no key)** — tolerates any taint, covering Linux nodes which carry no OS-specific taint by default.

This dual-toleration pattern ensures every node in the cluster — regardless of operating system — runs a Fluent Bit instance and ships its container logs to Splunk without any manual node-selector or affinity configuration on individual workload pods.

## Scaffold Note

`main.tf` resource blocks are commented out and require population before production deployment. Chart versions, repository URLs, IRSA role ARNs, and Secrets Manager references must be supplied before running `terraform apply`.

## Input Variables

| Name | Type | Description |
|------|------|-------------|
| `cluster_name` | `string` | Name of the EKS cluster into which the add-ons are deployed |
| `splunk_hec_host` | `string` | Hostname of the Splunk Cloud HEC endpoint (e.g. `inputs.splunkcloud.com`) |
| `splunk_hec_token` | `string` *(sensitive)* | Splunk HEC authentication token — retrieve from AWS Secrets Manager; never hardcode |
| `karpenter_node_role_arn` | `string` | ARN of the IAM role for the Karpenter IRSA service account |

## Outputs

| Name | Description |
|------|-------------|
| `alb_controller_status` | Deployment status of the AWS Load Balancer Controller Helm release |
| `karpenter_status` | Deployment status of the Karpenter Helm release |
| `fluent_bit_status` | Deployment status of the Fluent Bit DaemonSet Helm release |
