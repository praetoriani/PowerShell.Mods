<#
.SYNOPSIS
    Returns the current status of the local HTTP server.

.DESCRIPTION
    Reads live status information from the HTTP Runspace store and — if the
    server is running — queries the $requestCount variable directly from the
    Runspace via Get-RunspaceVariable. Outputs a formatted status report to
    the console and returns a PSCustomObject for programmatic use.

    If the server is not running, a status object with State = 'stopped'
    is returned and a short informational message is written.

    LIVE TELEMETRY:
    ─────────────────────────────────────────────────────────────────────
    $requestCount is a variable maintained by the Start-HttpRunspace loop.
    It is incremented on every successfully accepted request and is readable
    from the host thread via Get-RunspaceVariable (SessionStateProxy.GetVariable).
    This gives you a live request counter without any inter-thread messaging.

.EXAMPLE
    Get-LocalHttpServerStatus
    $status = Get-LocalHttpServerStatus
    $status.Uptime

.OUTPUTS
    PSCustomObject with properties:
        Name          [string]     — always 'http'
        State         [string]     — 'running', 'stopped', 'created', 'error', 'not_found'
        RunspaceState [string]     — raw RunspaceStateInfo.State from the .NET object
        IsCompleted   [bool]       — whether the async job has finished
        HadErrors     [bool]       — whether the PowerShell shell recorded errors
        StartTime     [DateTime]   — when Start-HTTPserver was called
        Uptime        [TimeSpan]   — how long the server has been running
        Port          [int]        — the configured port number
        wwwRoot       [string]     — the configured web root path
        RequestCount  [int]        — total requests processed since start
        Exists        [bool]       — whether a RunspaceStore entry exists

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : public/Get-LocalHttpServerStatus.ps1
#>
function Get-LocalHttpServerStatus {
    [CmdletBinding()]
    param()

    # ------------------------------------------------------------------
    # Query base status from RunspaceStore via Get-RunspaceStatus (private)
    # ------------------------------------------------------------------
    # Get-RunspaceStatus reads the store entry and the live .NET Runspace
    # state (RunspaceStateInfo.State) and returns a structured PSCustomObject.

    $status = Get-RunspaceStatus -RunspaceName 'http'

    # ------------------------------------------------------------------
    # Server not running — short report and early return
    # ------------------------------------------------------------------

    if (-not $status.Exists -or $status.State -ne 'running') {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor DarkGray
        Write-Host "  HTTP Server Status: NOT RUNNING"       -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor DarkGray
        Write-Host ""

        # Augment the status object with fields that callers may check
        $status | Add-Member -NotePropertyName 'Port'         -NotePropertyValue $script:httpHost['port'] -Force
        $status | Add-Member -NotePropertyName 'wwwRoot'      -NotePropertyValue $script:httpHost['wwwroot'] -Force
        $status | Add-Member -NotePropertyName 'RequestCount' -NotePropertyValue 0 -Force

        return $status
    }

    # ------------------------------------------------------------------
    # Server is running — read live telemetry from the Runspace
    # ------------------------------------------------------------------
    # Get-RunspaceVariable reads $requestCount directly from the Runspace's
    # SessionState via SessionStateProxy.GetVariable(). This is thread-safe
    # for a single integer read — no synchronization primitive needed.

    $liveRequestCount = Get-RunspaceVariable -RunspaceName 'http' -VariableName 'requestCount'

    # Ensure we have a numeric value even if the variable is not yet set
    # (e.g. the server just started and no request has arrived yet)
    if ($null -eq $liveRequestCount) { $liveRequestCount = 0 }

    # ------------------------------------------------------------------
    # Format uptime as a human-readable string
    # ------------------------------------------------------------------

    $uptimeString = 'unknown'
    if ($null -ne $status.Uptime) {
        $uptimeString = '{0}d {1:D2}h {2:D2}m {3:D2}s' -f `
            $status.Uptime.Days,
            $status.Uptime.Hours,
            $status.Uptime.Minutes,
            $status.Uptime.Seconds
    }

    # ------------------------------------------------------------------
    # Print formatted status report
    # ------------------------------------------------------------------

    Write-Host ""
    Write-Host "========================================"    -ForegroundColor Green
    Write-Host "  HTTP Server Status: RUNNING"               -ForegroundColor Green
    Write-Host "========================================"    -ForegroundColor Green
    Write-Host "  URL          : http://$($script:httpHost['domain']):$($script:httpHost['port'])/" -ForegroundColor White
    Write-Host "  wwwRoot      : $($script:httpHost['wwwroot'])"  -ForegroundColor White
    Write-Host "  Mode         : $($script:config['Mode'])"       -ForegroundColor White
    Write-Host "  Started      : $($status.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "  Uptime       : $uptimeString"                   -ForegroundColor White
    Write-Host "  Requests     : $liveRequestCount"               -ForegroundColor White
    Write-Host "  RS State     : $($status.RunspaceState)"        -ForegroundColor Gray
    Write-Host "  Had Errors   : $($status.HadErrors)"            -ForegroundColor Gray
    Write-Host "========================================"    -ForegroundColor Green
    Write-Host ""

    # ------------------------------------------------------------------
    # Return augmented status object for programmatic use
    # ------------------------------------------------------------------

    $status | Add-Member -NotePropertyName 'Port'         -NotePropertyValue $script:httpHost['port'] -Force
    $status | Add-Member -NotePropertyName 'wwwRoot'      -NotePropertyValue $script:httpHost['wwwroot'] -Force
    $status | Add-Member -NotePropertyName 'RequestCount' -NotePropertyValue $liveRequestCount -Force

    return $status
}
