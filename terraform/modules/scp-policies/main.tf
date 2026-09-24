# =============================================================================
# Module: scp-policies
# =============================================================================
# Purpose: Creates and attaches two AWS Organizations Service Control Policies
#          (SCPs) that enforce Zero Trust network boundaries across all OUs.
#
# SCP 1 — deny-direct-internet-egress
#   Prevents any account from creating an Internet Gateway or adding a route
#   to an IGW in a route table. All internet egress MUST flow through the
#   Network-Hub account via Transit Gateway → Network Firewall → NAT Gateway.
#   Attached to: Workloads BU OU (and recommended for Infrastructure OU
#   to prevent accidental IGW creation in spoke accounts).
#
# SCP 2 — deny-open-ssh-rdp
#   Prevents any account from opening SSH (port 22/TCP) or RDP (port 3389/TCP)
#   to 0.0.0.0/0 in any Security Group. All operational access MUST use
#   AWS Systems Manager Session Manager / Run Command.
#   Attached to: All OUs (Infrastructure OU, Security OU, Workloads BU OU).
#
# Instantiated from: terraform/environments/management/main.tf
# =============================================================================

# TODO: populate for production deployment

# -----------------------------------------------------------------------------
# SCP: Deny Direct Internet Egress
# Prevents creation of Internet Gateways and route table entries pointing to IGWs.
# -----------------------------------------------------------------------------
# resource "aws_organizations_policy" "deny_direct_internet_egress" {
#   name        = "deny-direct-internet-egress"
#   description = "Denies creation of Internet Gateways and routes to IGWs. All egress must flow through Transit Gateway and Network Firewall."
#   type        = "SERVICE_CONTROL_POLICY"
#   content     = file("${path.module}/deny-direct-internet-egress.json")
#
#   tags = {
#     Module     = "scp-policies"
#     ManagedBy  = "Terraform"
#   }
# }

# resource "aws_organizations_policy_attachment" "deny_direct_internet_egress" {
#   policy_id = aws_organizations_policy.deny_direct_internet_egress.id
#   target_id = var.target_ou_id
# }

# -----------------------------------------------------------------------------
# SCP: Deny Open SSH / RDP
# Prevents opening inbound port 22 (SSH) or port 3389 (RDP) to 0.0.0.0/0
# in any Security Group. Operational access must use SSM Session Manager.
# -----------------------------------------------------------------------------
# resource "aws_organizations_policy" "deny_open_ssh_rdp" {
#   name        = "deny-open-ssh-rdp"
#   description = "Denies Security Group rules that expose SSH (22/TCP) or RDP (3389/TCP) to the internet. All access must use AWS Systems Manager."
#   type        = "SERVICE_CONTROL_POLICY"
#   content     = file("${path.module}/deny-open-ssh-rdp.json")
#
#   tags = {
#     Module     = "scp-policies"
#     ManagedBy  = "Terraform"
#   }
# }

# resource "aws_organizations_policy_attachment" "deny_open_ssh_rdp" {
#   policy_id = aws_organizations_policy.deny_open_ssh_rdp.id
#   target_id = var.target_ou_id
# }
