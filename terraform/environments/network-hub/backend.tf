################################################################################
# Backend — network-hub environment
#
# Terraform backend blocks do not support variable interpolation. Supply the
# bucket, region, and dynamodb_table values using one of:
#   1. terraform init -backend-config="bucket=<value>" -backend-config="region=<value>" ...
#   2. A partial backend configuration file: terraform init -backend-config=backend.hcl
#
# The `key` is the only hardcoded element — it uniquely identifies this
# account's state file within the shared S3 bucket.
#
# REQ-5.2, REQ-9.4
################################################################################

terraform {
  backend "s3" {
    # Values supplied via `terraform init -backend-config` flags or a backend.hcl file.
    # bucket         = "<TF_STATE_BUCKET>"   # var.tf_state_bucket
    # region         = "<AWS_REGION>"        # var.aws_region
    # dynamodb_table = "<TF_LOCK_TABLE>"     # var.tf_lock_table

    key     = "network-hub/terraform.tfstate"
    encrypt = true
  }
}
