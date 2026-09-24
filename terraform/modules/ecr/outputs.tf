output "repository_urls" {
  description = "Map of repository name to repository URL for all created ECR repositories."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}
