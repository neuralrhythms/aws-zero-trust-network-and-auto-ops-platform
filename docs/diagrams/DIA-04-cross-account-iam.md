# DIA-04: Cross-Account IAM Trust Relationships

This diagram shows the IAM assume-role trust relationships and permission boundaries that govern cross-account access in the Zero-Trust platform. The `management` account enforces two Service Control Policies — denying direct internet egress and open SSH/RDP — at the OU level, constraining every member account regardless of their local IAM policies. The `audit` account holds delegated administrator trust into all workload accounts for GuardDuty, Inspector, and Security Hub (read-only), while workload accounts assume a role in `network-hub` to attach their VPCs to the Transit Gateway. The `logging` account is a write-protected archive: only the CloudTrail organisation trail may write to it, and the `audit` account has read-only cross-account access for ingestion.

```mermaid
flowchart TD
    MGMT["management\n(Organizations Root · Billing · Control Tower)"]

    SCP1[/"SCP: deny-direct-internet-egress\n(applied at OU level)"/]
    SCP2[/"SCP: deny-open-ssh-rdp\n(applied at OU level)"/]

    MGMT -->|"enforces"| SCP1
    MGMT -->|"enforces"| SCP2

    SCP1 -->|"constrains"| INFRA_OU["Infrastructure OU"]
    SCP1 -->|"constrains"| SEC_OU["Security OU"]
    SCP1 -->|"constrains"| WORK_OU["Workloads BU OU"]
    SCP2 -->|"constrains"| INFRA_OU
    SCP2 -->|"constrains"| SEC_OU
    SCP2 -->|"constrains"| WORK_OU

    INFRA_OU --> NET_HUB["network-hub\n(TGW · Network Firewall · NAT GW)"]

    SEC_OU --> AUDIT["audit\n(Delegated Admin: GuardDuty · Inspector · Security Hub)"]
    SEC_OU --> LOGGING["logging\n(Immutable S3 Archive · S3 Object Lock · WORM)"]

    WORK_OU --> DEV["workload-dev"]
    WORK_OU --> TEST["workload-test"]
    WORK_OU --> STAGING["workload-staging"]
    WORK_OU --> PROD["workload-prod"]

    AUDIT -->|"sts:AssumeRole\n(read-only delegated admin)"| DEV
    AUDIT -->|"sts:AssumeRole\n(read-only delegated admin)"| TEST
    AUDIT -->|"sts:AssumeRole\n(read-only delegated admin)"| STAGING
    AUDIT -->|"sts:AssumeRole\n(read-only delegated admin)"| PROD

    DEV -->|"sts:AssumeRole\n(TGW attachment role)"| NET_HUB
    TEST -->|"sts:AssumeRole\n(TGW attachment role)"| NET_HUB
    STAGING -->|"sts:AssumeRole\n(TGW attachment role)"| NET_HUB
    PROD -->|"sts:AssumeRole\n(TGW attachment role)"| NET_HUB

    CTRL["CloudTrail Org Trail\n(write via org trail — only allowed writer)"]
    AUDIT -->|"s3:GetObject\n(read-only)"| LOGGING
    CTRL -->|"s3:PutObject\n(org trail write)"| LOGGING

    PB[/"Permission Boundary\nLimits max permissions any role\nin workload accounts can assume"/]
    DEV -.->|"bounded by"| PB
    TEST -.->|"bounded by"| PB
    STAGING -.->|"bounded by"| PB
    PROD -.->|"bounded by"| PB

    style MGMT fill:#232F3E,color:#FFFFFF,stroke:#FF9900
    style SCP1 fill:#FF9900,color:#000000,stroke:#E65100
    style SCP2 fill:#FF9900,color:#000000,stroke:#E65100
    style INFRA_OU fill:#1A73E8,color:#FFFFFF,stroke:#1565C0
    style SEC_OU fill:#C62828,color:#FFFFFF,stroke:#B71C1C
    style WORK_OU fill:#2E7D32,color:#FFFFFF,stroke:#1B5E20
    style NET_HUB fill:#90CAF9,color:#000000,stroke:#1A73E8
    style AUDIT fill:#EF9A9A,color:#000000,stroke:#C62828
    style LOGGING fill:#EF9A9A,color:#000000,stroke:#C62828
    style DEV fill:#A5D6A7,color:#000000,stroke:#2E7D32
    style TEST fill:#A5D6A7,color:#000000,stroke:#2E7D32
    style STAGING fill:#A5D6A7,color:#000000,stroke:#2E7D32
    style PROD fill:#A5D6A7,color:#000000,stroke:#2E7D32
    style CTRL fill:#FFF9C4,color:#000000,stroke:#F9A825
    style PB fill:#E1BEE7,color:#000000,stroke:#7B1FA2
```
