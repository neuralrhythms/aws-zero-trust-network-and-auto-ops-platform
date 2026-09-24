# =============================================================================
# Remote backend — management environment
#
# IMPORTANT: Terraform's S3 backend does not support variable references inside
# the `backend` block. The bucket, region, and DynamoDB table values below are
# placeholder strings that MUST be overridden at `terraform init` time using
# either a backend config file or individual -backend-config flags, e.g.:
#
#   terraform init \
#     -backend-config="bucket=<your-tf-state-bucket>" \
#     -backend-config="region=<your-aws-region>" \
#     -backend-config="dynamodb_table=<your-lock-table>"
#
# The `key` is a literal string that uniquely identifies this environment's
# state file within the shared S3 bucket.
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "<TF_STATE_BUCKET_PLACEHOLDER>"
    key            = "management/terraform.tfstate"
    region         = "<AWS_REGION_PLACEHOLDER>"
    dynamodb_table = "<TF_LOCK_TABLE_PLACEHOLDER>"
    encrypt        = true
  }
}
