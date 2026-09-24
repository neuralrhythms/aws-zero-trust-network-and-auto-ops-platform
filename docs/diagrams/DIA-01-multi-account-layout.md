# DIA-01: Multi-Account AWS Organisation Layout

This diagram illustrates the AWS Organizations hierarchy for the Zero-Trust Network Egress & Automated Operations Platform. Eight accounts are grouped into three Organizational Units under a Management root: Infrastructure OU (network-hub), Security OU (audit and logging), and Workloads OU (dev, test, staging, and prod). Service Control Policies applied at the OU level enforce Zero Trust controls — blocking direct internet egress and open SSH/RDP ingress — across all member accounts.

![AWS Multi-Account Organisation Layout](AWS-Multi-Account-Org.drawio.png)

```mermaid
flowchart TD
    ROOT["Management Account\n(Organizations Root)"]

    ROOT --> INFRA_OU["Infrastructure OU"]
    ROOT --> SEC_OU["Security OU"]
    ROOT --> WORK_OU["Workloads OU"]

    INFRA_OU --> NET_HUB["network-hub\n(TGW · Network Firewall · NAT GW · VPC Flow Logs)"]

    SEC_OU --> AUDIT["audit\n(Delegated Admin: GuardDuty · Inspector · Security Hub · Config)"]
    SEC_OU --> LOGGING["logging\n(Immutable S3 Log Archive · CloudTrail Org Trail · S3 Object Lock)"]

    WORK_OU --> DEV["workload-dev\n(Development EKS cluster & workloads)"]
    WORK_OU --> TEST["workload-test\n(Integration & functional testing workloads)"]
    WORK_OU --> STAGING["workload-staging\n(Pre-production / UAT workloads)"]
    WORK_OU --> PROD["workload-prod\n(Live production · strictest SCP boundaries)"]

    style ROOT fill:#232F3E,color:#FFFFFF,stroke:#FF9900
    style INFRA_OU fill:#1A73E8,color:#FFFFFF,stroke:#1A73E8
    style SEC_OU fill:#C62828,color:#FFFFFF,stroke:#C62828
    style WORK_OU fill:#2E7D32,color:#FFFFFF,stroke:#2E7D32
    style NET_HUB fill:#90CAF9,color:#000000,stroke:#1A73E8
    style AUDIT fill:#EF9A9A,color:#000000,stroke:#C62828
    style LOGGING fill:#EF9A9A,color:#000000,stroke:#C62828
    style DEV fill:#A5D6A7,color:#000000,stroke:#2E7D32
    style TEST fill:#A5D6A7,color:#000000,stroke:#2E7D32
    style STAGING fill:#A5D6A7,color:#000000,stroke:#2E7D32
    style PROD fill:#A5D6A7,color:#000000,stroke:#2E7D32
```
