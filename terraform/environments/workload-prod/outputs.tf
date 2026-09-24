################################################################################
# Outputs — workload-prod environment
#
# These outputs expose the key resource identifiers produced by this environment.
# They can be consumed by other Terraform configurations that need to reference
# workload-prod resources (e.g. CI/CD pipelines reading cluster endpoints).
#
# REQ-5.2, REQ-9.3
################################################################################

output "vpc_id" {
  description = "ID of the workload-prod VPC. Referenced when attaching additional resources to this spoke network."
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster in this workload-prod environment. Used by kubectl, Helm, and GitOps tooling to target the correct cluster."
  value       = module.eks_cluster.cluster_name
}

output "eks_cluster_endpoint" {
  description = "API server endpoint URL for the workload-prod EKS cluster. Used to configure kubeconfig and CI/CD tooling."
  value       = module.eks_cluster.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "ARN of the EKS cluster's OIDC provider. Required when creating IRSA IAM role trust policies for service accounts in this cluster."
  value       = module.eks_cluster.oidc_provider_arn
}

output "ecr_repository_urls" {
  description = "Map of ECR repository name to repository URL for all repositories created in this workload-prod account. Consumed by CI/CD pipelines to construct image push destinations."
  value       = module.ecr.repository_urls
}

output "tgw_attachment_id" {
  description = "ID of the Transit Gateway attachment for this workload-prod spoke VPC. Used for TGW route table propagations and network monitoring."
  value       = module.tgw_attachment.attachment_id
}
