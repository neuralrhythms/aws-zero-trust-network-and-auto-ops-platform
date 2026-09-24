################################################################################
# Variables — network-firewall module
################################################################################

variable "firewall_name" {
  description = "Name for the AWS Network Firewall resource and its associated policy."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC in which the Network Firewall will be deployed (network-hub VPC)."
  type        = string
}

variable "firewall_subnet_id" {
  description = "ID of the subnet (app-private tier) where the Network Firewall endpoint will be created."
  type        = string
}

variable "allowed_domains" {
  description = "List of allowed FQDNs for egress (e.g. .amazonaws.com, .splunkcloud.com). All other HTTP/HTTPS destinations are blocked."
  type        = list(string)
}

variable "rule_group_name" {
  description = "Name for the stateful FQDN domain-list rule group."
  type        = string
}

variable "rule_group_capacity" {
  description = "Capacity units for the stateful rule group (each FQDN rule consumes 1 unit; set to at least the number of entries in allowed_domains)."
  type        = number
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket (in the logging account) that receives Network Firewall ALERT and FLOW logs. Required for CKV2_AWS_63 compliance."
  type        = string
}
