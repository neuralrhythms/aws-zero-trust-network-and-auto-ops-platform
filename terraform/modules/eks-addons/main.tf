# =============================================================================
# Module: eks-addons
#
# Deploys three EKS cluster add-ons via Helm:
#
#   1. AWS Load Balancer Controller
#      Watches Kubernetes Ingress objects and provisions Application Load Balancers
#      (ALBs) in the workload VPC. Requires an IRSA role with the necessary
#      elasticloadbalancing:* and ec2:Describe* permissions.
#
#   2. Karpenter
#      Dynamic node provisioning layer that replaces Cluster Autoscaler.
#      OS-specific NodePools (one for Linux, one for Windows) ensure pods with
#      OS-specific node selectors or tolerations land on the correct node type.
#      Karpenter interruption handling and Drift detection are enabled by default.
#
#   3. Fluent Bit
#      DaemonSet deployed across all nodes (Linux and Windows) to ship container
#      logs to Splunk Cloud via the HTTP Event Collector (HEC).
#      The toleration strategy in fluentbit-values.yaml covers both node types:
#        - "os=windows:NoSchedule" toleration for Windows managed node group nodes
#        - "Exists" operator toleration for Linux nodes (which carry no OS taint)
#      splunk_hec_token is sensitive = true and sourced from AWS Secrets Manager
#      at apply time — it is never stored in state in plaintext.
#
# All helm_release blocks are commented out.  Populate chart versions, repository
# URLs, and set values before production deployment.
# =============================================================================

# -----------------------------------------------------------------------------
# Add-on 1: AWS Load Balancer Controller
# -----------------------------------------------------------------------------
# resource "helm_release" "aws_load_balancer_controller" {
#   name             = "aws-load-balancer-controller"
#   repository       = "https://aws.github.io/eks-charts"
#   chart            = "aws-load-balancer-controller"
#   version          = "<pin chart version>"
#   namespace        = "kube-system"
#   create_namespace = false
#
#   set {
#     name  = "clusterName"
#     value = var.cluster_name
#   }
#
#   set {
#     name  = "serviceAccount.create"
#     value = "true"
#   }
#
#   set {
#     name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = "<irsa_alb_controller_role_arn>"
#   }
#
#   set {
#     name  = "region"
#     value = "<var.aws_region>"
#   }
#
#   set {
#     name  = "vpcId"
#     value = "<var.vpc_id>"
#   }
# }

# -----------------------------------------------------------------------------
# Add-on 2: Karpenter
# -----------------------------------------------------------------------------
# resource "helm_release" "karpenter" {
#   name             = "karpenter"
#   repository       = "oci://public.ecr.aws/karpenter"
#   chart            = "karpenter"
#   version          = "<pin chart version>"
#   namespace        = "karpenter"
#   create_namespace = true
#
#   set {
#     name  = "settings.aws.clusterName"
#     value = var.cluster_name
#   }
#
#   set {
#     name  = "settings.aws.interruptionQueueName"
#     value = "<interruption_queue_name>"
#   }
#
#   set {
#     name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = var.karpenter_node_role_arn
#   }
#
#   # Linux NodePool (no OS taint — default scheduling)
#   # Windows NodePool (taint: os=windows:NoSchedule)
#   # NodePool manifests are applied separately via kubectl or Flux CD reconciliation.
# }

# -----------------------------------------------------------------------------
# Add-on 3: Fluent Bit — container log shipping to Splunk HEC
#
# NOTE: splunk_hec_token is marked sensitive = true in variables.tf.
# At deployment time, retrieve the token from AWS Secrets Manager and pass it
# as a Terraform variable (e.g. via a data.aws_secretsmanager_secret_version
# data source in the calling environment root module).  Do NOT hardcode the
# token in terraform.tfvars or any committed file.
# -----------------------------------------------------------------------------
# resource "helm_release" "fluent_bit" {
#   name             = "fluent-bit"
#   repository       = "https://fluent.github.io/helm-charts"
#   chart            = "fluent-bit"
#   version          = "<pin chart version>"
#   namespace        = "logging"
#   create_namespace = true
#
#   values = [
#     templatefile("${path.module}/fluentbit-values.yaml", {
#       splunk_hec_host  = var.splunk_hec_host
#       splunk_hec_token = var.splunk_hec_token   # sensitive
#     })
#   ]
# }

# TODO: populate for production deployment
