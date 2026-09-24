# ============================================================
# Outputs from the eks-cluster module.
# Values are proxied from the upstream community module so
# callers (environment root modules and multi-account-example)
# do not need to depend on the upstream module's internal
# structure directly.
# ============================================================

output "cluster_name" {
  description = "Name of the provisioned EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "HTTPS endpoint for the EKS Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster. Used to configure kubectl and providers."
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's OIDC identity provider. Used to create IRSA IAM role trust policies."
  value       = module.eks.oidc_provider_arn
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role attached to the EKS cluster control plane."
  value       = module.eks.cluster_iam_role_arn
}
