variable "cluster_name" {
  description = "Name of the EKS cluster into which the add-ons (AWS Load Balancer Controller, Karpenter, Fluent Bit) are deployed."
  type        = string
}

variable "splunk_hec_host" {
  description = "Hostname (or IP) of the Splunk Cloud HTTP Event Collector (HEC) endpoint. Example: 'inputs.splunkcloud.com'. Injected into fluentbit-values.yaml at Helm install time."
  type        = string
}

variable "splunk_hec_token" {
  description = "Splunk HEC authentication token used by Fluent Bit to ship container logs to Splunk Cloud. Marked sensitive — retrieve from AWS Secrets Manager; never hardcode in terraform.tfvars or any committed file."
  type        = string
  sensitive   = true
}

variable "karpenter_node_role_arn" {
  description = "ARN of the IAM role associated with the Karpenter service account via IRSA. This role grants Karpenter the permissions required to provision and manage EC2 node instances on behalf of the EKS cluster."
  type        = string
}
