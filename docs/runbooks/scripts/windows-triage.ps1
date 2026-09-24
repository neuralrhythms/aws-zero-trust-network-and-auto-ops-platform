<#
.SYNOPSIS
    Windows Server triage script for the Zero-Trust Network & Auto-Ops Platform.

.DESCRIPTION
    Collects IIS service state, application pool health, and recent Application Event Log
    errors from a Windows Server instance. Designed to be invoked remotely via AWS Systems
    Manager Run Command and to produce structured output suitable for forwarding to Splunk.

.NOTES
    Purpose          : Automated diagnostic triage for Windows compute nodes
    Target OS        : Windows Server 2019 / 2022
    SSM Document     : ZeroTrustPlatform-WindowsTriage
    Required IAM     : ssm:SendCommand, ssm:GetCommandInvocation
    Expected Output  : Forwarded to Splunk index  windows_os
                       Fields: TimeGenerated, Source, EventID, Message, ServiceStatus, PoolState
    Author           : Platform Architecture Team
    Version          : 1.0.0
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"   # allow non-terminating errors; keep output flowing

# ---------------------------------------------------------------------------
# 1. W3SVC (IIS) Service Status
# ---------------------------------------------------------------------------
Write-Output "=== W3SVC (IIS) Service Status ==="
try {
    Get-Service -Name W3SVC -ErrorAction Stop |
        Select-Object Name, Status, StartType
} catch {
    Write-Output "WARNING: Could not retrieve W3SVC status. IIS may not be installed. Error: $_"
}

# ---------------------------------------------------------------------------
# 2. Application Pool Status
# ---------------------------------------------------------------------------
Write-Output ""
Write-Output "=== Application Pool Status ==="
Import-Module WebAdministration -ErrorAction SilentlyContinue
if (Get-Module -Name WebAdministration) {
    try {
        Get-WebAppPool |
            Select-Object Name, State, ManagedRuntimeVersion
    } catch {
        Write-Output "WARNING: Could not enumerate application pools. Error: $_"
    }
} else {
    Write-Output "WARNING: WebAdministration module not available on this instance."
}

# ---------------------------------------------------------------------------
# 3. Application Event Log Errors — last 2 hours, first 10 entries
# ---------------------------------------------------------------------------
Write-Output ""
Write-Output "=== Application Event Log Errors (last 2 hours, first 10) ==="
$since = (Get-Date).AddHours(-2)
try {
    $events = Get-EventLog -LogName Application -EntryType Error -After $since -Newest 10 -ErrorAction Stop |
        Select-Object TimeGenerated, Source, EventID, Message
    if ($events) {
        $events
    } else {
        Write-Output "No Application Event Log errors in the last 2 hours."
    }
} catch {
    Write-Output "WARNING: Could not retrieve Application Event Log. Error: $_"
}

# ---------------------------------------------------------------------------
# End of triage output — forwarded to Splunk windows_os index via SSM Run Command
# ---------------------------------------------------------------------------
Write-Output ""
Write-Output "=== Triage Complete: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ') ==="
