# DIA-06: Observability Data Flow

This diagram illustrates how telemetry data flows from all platform layers into the centralised
Splunk Cloud observability stack. EC2 compute instances ship logs and metrics via the Splunk
Universal Forwarder over HTTPS to the Splunk HTTP Event Collector (HEC), while containerised
workloads running on EKS are covered by a Fluent Bit DaemonSet that forwards logs to the same
HEC endpoint. Immutable S3 logs stored in the dedicated `logging` account are ingested by the
Splunk S3 Add-on, and Prometheus scrapes cluster metrics that are visualised in Grafana.

```mermaid
flowchart LR
    subgraph Compute ["EC2 Compute"]
        EC2["EC2 Instance"]
        UF["Splunk Universal Forwarder"]
    end

    subgraph EKS ["EKS Cluster"]
        Pods["EKS Pods"]
        FB["Fluent Bit DaemonSet"]
        Prom["Prometheus"]
    end

    subgraph LoggingAccount ["logging account (Security OU)"]
        S3["S3 Log Archive\n(Object Lock / WORM)"]
        S3Addon["Splunk S3 Add-on"]
    end

    subgraph Observability ["Splunk Cloud"]
        HEC["HTTP Event Collector (HEC)"]
        SplunkIdx["Splunk Indexers\n(linux_os / windows_os / k8s_containers)"]
        SplunkSearch["Splunk Search Head\n& Dashboards"]
    end

    Grafana["Grafana"]

    EC2 -->|"log files / metrics"| UF
    UF -->|"HTTPS / TCP 443"| HEC

    Pods -->|"stdout / stderr"| FB
    FB -->|"HTTPS / TCP 443"| HEC

    S3 -->|"S3 event notification"| S3Addon
    S3Addon -->|"HTTPS / TCP 443"| HEC

    HEC --> SplunkIdx
    SplunkIdx --> SplunkSearch

    Prom -->|"metrics scrape"| Grafana
```
