variable "vpc_name" {
  description = "Name tag applied to the VPC and all derived resources (subnets, route tables, gateways)."
  type        = string
}

variable "vpc_cidr" {
  description = "Primary IPv4 CIDR block for the VPC (e.g. '10.0.0.0/16'). Must be an RFC 1918 range."
  type        = string
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR block for the public-ingress subnet tier. In production, supply a per-AZ map; this variable accepts a single CIDR for scaffold clarity."
  type        = string
}

variable "app_private_subnet_cidr" {
  description = "IPv4 CIDR block for the app-private subnet tier, which hosts EKS worker nodes and application workloads."
  type        = string
}

variable "data_private_subnet_cidr" {
  description = "IPv4 CIDR block for the data-private subnet tier, which hosts RDS, ElastiCache, and other stateful services."
  type        = string
}

variable "tgw_attach_subnet_cidr" {
  description = "IPv4 CIDR block for the tgw-attach subnet tier. Must be a /28 per AZ to satisfy the Transit Gateway attachment requirement and support symmetric firewall routing."
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zone names in the target region (e.g. ['us-east-1a', 'us-east-1b', 'us-east-1c']). One subnet per tier per AZ is created."
  type        = list(string)
}

variable "flow_log_destination_arn" {
  description = "ARN of the destination for VPC Flow Logs. Accepts an S3 bucket ARN (logging account immutable archive) or a CloudWatch Logs group ARN."
  type        = string
}
