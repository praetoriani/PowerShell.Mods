<#
.SYNOPSIS
    Returns a status snapshot of a registered Runspace. Also contains
    the lightweight Test-RunspaceExists helper.

.DESCRIPTION
    Get-RunspaceStatus aggregates information from three sources into a
    single PSCustomObject:
      - The logical State stored in $script:RunspaceStore (set by the
        helper functions: 'created', 'running', 'stopped', 'error').
      - The actual RunspaceState from the .NET Runspace object itself
        (Opened, Running, Closed, Broken, etc.).
      - The IsCompleted flag from the IAsyncResult handle returned by
        BeginInvoke().

    This multi-source snapshot is intentional: the logical State in the
    store tells you what the module THINKS is happening, while the .NET
    RunspaceState tells you what is ACTUALLY happening. Discrepancies
    between the two indicate an unexpected shutdown (crash, external
    disposal, etc.) that the module has not yet processed.

    The function always returns a valid PSCustomObject - even when the
    named Runspace does not exist (Exists = $false, State = 'not_found').
    This means callers never need to guard against a $null return value.

    Also contains Test-RunspaceExists, a minimal Boolean wrapper used as
    a guard condition by Start-HTTPserver, Stop-LocalHttpServer and
    Restart-LocalHttpServer. It is co-located here because it reads from
    the same store entry and has no meaningful standalone identity.

.PARAMETER RunspaceName
    The key under which the target Runspace is registered in
    $script:RunspaceStore.

.OUTPUTS
    PSCustomObject with the following properties:
      Name          [string]   - the RunspaceName parameter value
      State         [string]   - logical state from the store
                                 ('created'|'running'|'stopped'|
                                  'error'|'not_found')
      RunspaceState [string]   - actual .NET Runspace state string
      IsCompleted   [bool]     - whether BeginInvoke() has finished
      HadErrors     [bool]     - whether the PS shell reported errors
      StartTime     [DateTime] - when New-ManagedRunspace was called
      Uptime        [string]   - formatted "Xd HH:MM:SS" or $null
      Exists        [bool]     - $false when not found in the store

.EXAMPLE
    $status = Get-RunspaceStatus -RunspaceName 'http'

    if ($status.Exists) {
        Write-Host "State  : $($status.State)"
        Write-Host "Uptime : $($status.Uptime)"
    } else {
        Write-Host "HTTP server is not running."
    }

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/Get-RunspaceStatus.ps1
    Contains      : Get-RunspaceStatus, Test-RunspaceExists
#>

# ===========================================================================
# FUNCTION: Get-RunspaceStatus
# ===========================================================================
function Get-RunspaceStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName
    )

    # ------------------------------------------------------------------
    # Runspace not found: return a safe "not_found" object
    # ------------------------------------------------------------------
    # Returning a structured object instead of $null means every caller
    # can use the same code path regardless of whether the server is
    # running. No null-check required before accessing .Exists or .State.
    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        return [PSCustomObject]@{
            Name          = $RunspaceName
            State         = 'not_found'
            RunspaceState = 'n/a'
            IsCompleted   = $false
            HadErrors     = $false
            StartTime     = $null
            Uptime        = $null
            Exists        = $false
        }
    }

    $entry = $script:RunspaceStore[$RunspaceName]
    $rs    = $entry.Runspace
    $ps    = $entry.PowerShell

    # ------------------------------------------------------------------
    # Read the actual .NET Runspace state
    # ------------------------------------------------------------------
    # This is independent of our logical $entry.State and can reveal
    # situations where the runspace died (Broken) without the module
    # being notified - for example if the background thread threw an
    # unhandled exception that was not caught inside the server loop.
    $dotNetRsState = if ($null -ne $rs) {
        $rs.RunspaceStateInfo.State.ToString()
    } else {
        'null'
    }

    # ------------------------------------------------------------------
    # Check async job completion
    # ------------------------------------------------------------------
    # IsCompleted = $true means BeginInvoke() has finished executing.
    # For a healthy running server this should be $false.
    # IsCompleted = $true while State = 'running' indicates the server
    # loop exited unexpectedly (unhandled error or external stop).
    $jobCompleted = if ($null -ne $entry.Handle) {
        $entry.Handle.IsCompleted
    } else {
        $false
    }

    # ------------------------------------------------------------------
    # Check whether the PowerShell shell reported errors
    # ------------------------------------------------------------------
    $hasErrors = if ($null -ne $ps) {
        $ps.HadErrors
    } else {
        $false
    }

    # ------------------------------------------------------------------
    # Calculate a human-readable uptime string
    # ------------------------------------------------------------------
    # Only calculated when the server is in 'running' state and has a
    # valid StartTime. Format: "0d 00h 00m 00s"
    $uptimeStr = $null
    if ($entry.State -eq 'running' -and $null -ne $entry.StartTime) {
        $ts        = (Get-Date) - $entry.StartTime
        $uptimeStr = '{0}d {1:D2}h {2:D2}m {3:D2}s' -f `
                     $ts.Days, $ts.Hours, $ts.Minutes, $ts.Seconds
    }

    # ------------------------------------------------------------------
    # Assemble and return the status snapshot
    # ------------------------------------------------------------------
    return [PSCustomObject]@{
        Name          = $RunspaceName
        State         = $entry.State
        RunspaceState = $dotNetRsState
        IsCompleted   = $jobCompleted
        HadErrors     = $hasErrors
        StartTime     = $entry.StartTime
        Uptime        = $uptimeStr
        Exists        = $true
    }
}


# ===========================================================================
# FUNCTION: Test-RunspaceExists
# ===========================================================================
<#
.SYNOPSIS
    Returns $true if a named Runspace is registered AND in 'running' state.

.DESCRIPTION
    Lightweight Boolean guard used by Start-HTTPserver, Stop-LocalHttpServer
    and Restart-LocalHttpServer to check server state before acting.

    Checks BOTH conditions:
      1. The name exists as a key in $script:RunspaceStore.
      2. The store entry's logical State equals 'running'.

    A runspace that has crashed (State = 'error') or been stopped but not
    yet removed from the store correctly returns $false, so callers can
    safely treat $true as "the server is live and healthy".

.PARAMETER RunspaceName
    The name to look up in $script:RunspaceStore.

.OUTPUTS
    [bool] $true if the runspace exists and is actively running.

.EXAMPLE
    if (Test-RunspaceExists -RunspaceName 'http') {
        Write-Host "HTTP server is running."
    } else {
        Write-Host "HTTP server is not running."
    }
#>
function Test-RunspaceExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName
    )

    # A single expression covers both the "key missing" and "wrong state"
    # cases without branching. Short-circuit evaluation ensures ContainsKey
    # is always checked first so no KeyNotFoundException can occur.
    return (
        $script:RunspaceStore.ContainsKey($RunspaceName) -and
        $script:RunspaceStore[$RunspaceName].State -eq 'running'
    )
}
