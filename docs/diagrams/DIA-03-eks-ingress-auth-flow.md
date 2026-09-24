# DIA-03: EKS Ingress & IRSA Authentication Flow

This diagram shows two concurrent flows for an EKS-hosted workload. The ingress request flow traces an external client through the Application Load Balancer — managed by the AWS Load Balancer Controller from a Kubernetes `Ingress` object — down to the target Pod. The IRSA (IAM Roles for Service Accounts) token exchange flow shows how that same Pod obtains short-lived AWS credentials: it presents a projected service account token to the OIDC provider, which validates the token and forwards the request to AWS STS, and STS returns temporary IAM role credentials scoped to the pod's identity — with no broad node-level instance profile required.

```mermaid
sequenceDiagram
    autonumber

    participant Client as "External Client"
    participant ALB as "Application Load Balancer (ALB)"
    participant LBC as "AWS Load Balancer Controller"
    participant Ingress as "K8s Ingress Object"
    participant Svc as "K8s Service"
    participant Pod as "Workload Pod"
    participant OIDC as "EKS OIDC Provider"
    participant STS as "AWS STS"

    Note over LBC,Ingress: Controller reconcile loop (control plane)
    LBC->>Ingress: Watch Ingress resources
    LBC->>ALB: Create / update ALB rules & target groups

    Note over Client,Pod: Ingress request flow (data plane)
    Client->>ALB: HTTPS request
    ALB->>Svc: Forward to target group (matched rule)
    Svc->>Pod: Route to healthy pod endpoint
    Pod-->>Client: HTTP response (via ALB)

    Note over Pod,STS: IRSA token exchange (credential issuance)
    Pod->>OIDC: Present projected service account JWT\n(mounted at /var/run/secrets/kubernetes.io/serviceaccount)
    OIDC->>OIDC: Validate JWT signature & audience claim
    OIDC->>STS: AssumeRoleWithWebIdentity\n(RoleArn bound to service account annotation)
    STS->>STS: Verify OIDC trust policy &\ncheck permission boundaries
    STS-->>Pod: Temporary credentials\n(AccessKeyId, SecretAccessKey, SessionToken)
    Pod->>Pod: Use credentials for AWS API calls\n(scoped to annotated IAM role only)
```
