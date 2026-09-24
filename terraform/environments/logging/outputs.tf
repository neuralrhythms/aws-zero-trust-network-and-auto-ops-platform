# =============================================================================
# Outputs — logging environment
#
# These outputs expose the key resource identifiers that other environments
# or external consumers (e.g. the audit account's cross-account bucket policy,
# the Splunk S3 Add-on configuration) need to reference.
# =============================================================================

output "vpc_id" {
  description = "ID of the logging account VPC that hosts the Splunk Universal Forwarder EC2 instance."
  value       = module.vpc.vpc_id
}

output "log_archive_bucket_id" {
  description = "Name (ID) of the S3 log archive bucket with Object Lock WORM immutability. Used as the CloudTrail organisation trail target and Splunk S3 Add-on source."
  value       = aws_s3_bucket.log_archive.id
}

output "log_archive_bucket_arn" {
  description = "ARN of the S3 log archive bucket. Referenced in cross-account bucket policies and IAM policies that grant the audit account read-only access."
  value       = aws_s3_bucket.log_archive.arn
}
