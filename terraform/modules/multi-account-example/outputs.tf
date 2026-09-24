# =============================================================================
# Outputs — Multi-Account Example Module
# =============================================================================

output "tgw_attachment_id" {
  description = "ID of the Transit Gateway VPC attachment that connects this workload spoke VPC to the Network-Hub Transit Gateway."
  value       = module.tgw_attachment.attachment_id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster provisioned in this workload account."
  value       = module.eks_cluster.cluster_name
}

output "eks_cluster_endpoint" {
  description = "API server endpoint URL of the EKS cluster."
  value       = module.eks_cluster.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider, used to configure IRSA (IAM Roles for Service Accounts) bindings."
  value       = module.eks_cluster.oidc_provider_arn
}

output "ecr_repository_urls" {
  description = "Map of ECR repository name to repository URL for all repositories created in this workload account."
  value       = module.ecr.repository_urls
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector enabled in the audit account (delegated administrator). Returned here for cross-account reference in downstream automation."
  value       = module.guardduty.detector_id
}

output "inspector_organization_configuration_status" {
  description = "Status of the Inspector organisation configuration managed by the audit account (delegated administrator)."
  value       = module.inspector.organization_configuration_status
}
