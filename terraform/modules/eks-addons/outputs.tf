output "alb_controller_status" {
  description = "Deployment status of the AWS Load Balancer Controller Helm release. Will reflect the helm_release resource status once the main.tf scaffold is populated and deployed. Currently a placeholder — this module is in scaffold state."
  value       = "scaffold — helm_release not yet deployed"
}

output "karpenter_status" {
  description = "Deployment status of the Karpenter Helm release. Will reflect the helm_release resource status once the main.tf scaffold is populated and deployed. Currently a placeholder — this module is in scaffold state."
  value       = "scaffold — helm_release not yet deployed"
}

output "fluent_bit_status" {
  description = "Deployment status of the Fluent Bit DaemonSet Helm release. Will reflect the helm_release resource status once the main.tf scaffold is populated and deployed. Currently a placeholder — this module is in scaffold state."
  value       = "scaffold — helm_release not yet deployed"
}
