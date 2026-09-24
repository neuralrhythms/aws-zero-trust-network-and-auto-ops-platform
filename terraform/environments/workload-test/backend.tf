################################################################################
# Remote backend — workload-test
#
# State is stored in S3 with DynamoDB locking and server-side encryption.
# Bucket and DynamoDB table names are supplied at `terraform init` time via
# -backend-config flags or a backend config file — they cannot be variable
# references in this block (Terraform constraint).
#
# The state key "workload-test/terraform.tfstate" is the only hardcoded string;
# all other backend parameters are injected at init time (REQ-5.2).
################################################################################

terraform {
  backend "s3" {
    key     = "workload-test/terraform.tfstate"
    encrypt = true
    # bucket, region, and dynamodb_table are supplied via:
    #   terraform init -backend-config="bucket=<value>" \
    #                  -backend-config="region=<value>" \
    #                  -backend-config="dynamodb_table=<value>"
    # or via a backend.hcl config file. Never hardcode these values here.
  }
}
