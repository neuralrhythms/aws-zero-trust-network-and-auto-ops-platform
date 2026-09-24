#!/bin/bash
#
# Purpose:            Linux diagnostic triage script for the Zero-Trust Platform self-healing
#                     workflow. Collects service health, critical journal errors, and disk
#                     utilisation data. Output is structured for machine parsing and is
#                     forwarded to Splunk for search and alerting.
#
# Target OS:          Amazon Linux 2 / Amazon Linux 2023
#
# SSM Document Name:  ZeroTrustPlatform-LinuxTriage
#
# Required IAM Permissions:
#   ssm:SendCommand            — to invoke this document on target instances
#   ssm:GetCommandInvocation   — to retrieve command output after execution
#
# Expected Output:    Script stdout is captured by SSM Run Command, forwarded to the
#                     CloudWatch Logs group /self-healing/ssm-output, and ingested by the
#                     Splunk Universal Forwarder into the linux_os index.
#                     Section headers (=== ... ===) act as field delimiters for Splunk
#                     sourcetype parsing.
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Section 1: Service Status
# Checks whether the two primary web-server daemons are running.
# Output tokens "active" / "INACTIVE" are indexed by Splunk for alerting.
# ---------------------------------------------------------------------------
echo "=== Service Status ==="

NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || true)
if [ "${NGINX_STATUS}" = "active" ]; then
    echo "nginx: active"
else
    echo "nginx: INACTIVE (state=${NGINX_STATUS})"
fi

HTTPD_STATUS=$(systemctl is-active httpd 2>/dev/null || true)
if [ "${HTTPD_STATUS}" = "active" ]; then
    echo "httpd: active"
else
    echo "httpd: INACTIVE (state=${HTTPD_STATUS})"
fi

# ---------------------------------------------------------------------------
# Section 2: Critical Journal Errors
# Retrieves the 20 most recent log entries at priority 3 (ERR) or higher.
# Covers kernel panics, OOM kills, and service crashes.
# ---------------------------------------------------------------------------
echo ""
echo "=== Critical Journal Errors (priority<=3, last 20 entries) ==="
journalctl -p 3 -n 20 --no-pager

# ---------------------------------------------------------------------------
# Section 3: High Disk Usage
# Reports any filesystem whose use% exceeds 85 %.
# Lines are prefixed with "ALERT:" so Splunk alerts trigger on keyword match.
# ---------------------------------------------------------------------------
echo ""
echo "=== High Disk Usage (filesystems >85% full) ==="
df -h | awk '$5+0 > 85 {print "ALERT: " $0}'

echo ""
echo "=== Triage Complete ==="
