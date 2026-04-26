<#
.SYNOPSIS
    Writes and removes the httpserver.status.json runtime status file.

.DESCRIPTION
    This file contains two tightly related functions that manage the
    httpserver.status.json file in the include\ directory:

      Write-ServerStatusFile — creates or overwrites the status file with
                               the current server state and runtime metadata.
      Remove-ServerStatusFile — deletes the status file when the server stops.

    PURPOSE OF THE STATUS FILE
    ──────────────────────────
    The status file is the bridge between the running server process and any
    external tool that needs to know whether the server is active — without
    having access to $script:RunspaceStore, which exists only inside the
    loaded PowerShell module session.

    Practical use cases:
      - The local.httpserver.ps1 launcher script can check the file at
        startup to detect a previous unclean shutdown (leftover status file
        with state = 'running' but no matching process).
      - Future IPC clients (named pipe, tray icon) can read port and PID
        from the file without needing to import the module.
      - Monitoring scripts or health checks can poll the file.
      - Phase 4 (named pipe server) uses the file to determine whether an
        HTTP server is already running before starting its own listener.

    FILE LOCATION
    ─────────────
    include\httpserver.status.json — relative to $script:root
    (the module root, set in Section 1 of local.httpserver.psm1).

    FILE FORMAT (JSON)
    ──────────────────
    {
      "status"    : "running",          // "running" | "stopped" | "error"
      "pid"       : 12345,              // PID of the PowerShell host process
      "port"      : 8080,               // TCP port the HttpListener is bound to
      "wwwroot"   : "C:\\wwwroot",      // Resolved absolute wwwroot path
      "startTime" : "2026-04-26T...",   // ISO 8601, null when status != running
      "timestamp" : "2026-04-26T..."    // ISO 8601, always present
    }

    CALL POINTS
    ───────────
    Write-ServerStatusFile is called from:
      - Start-HTTPserver  (after New-RunspaceJob succeeds → state = 'running')
      - Stop-LocalHttpServer  (just before Stop-ManagedRunspace → state = 'stopped')

    Remove-ServerStatusFile is called from:
      - Stop-LocalHttpServer  (after Stop-ManagedRunspace succeeds)

    These two functions are co-located in one file because they share
    the same file path resolution logic. Splitting them into separate
    files would require duplicating the path logic or extracting a third
    helper — neither of which adds value for just two small functions.

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/ServerStatusFile.ps1
    Contains      : Write-ServerStatusFile, Remove-ServerStatusFile
#>


# ===========================================================================
# FUNCTION: Write-ServerStatusFile
# ===========================================================================
<#
.SYNOPSIS
    Creates or overwrites include\httpserver.status.json with current
    server state and runtime metadata.

.PARAMETER Status
    The logical server state to write into the file.
    Accepted values: 'running', 'stopped', 'error'.
    The 'startTime' field is only populated when Status = 'running'.

.OUTPUTS
    [bool] $true on success, $false if the file could not be written.

.EXAMPLE
    # Called by Start-HTTPserver after the runspace job starts
    Write-ServerStatusFile -Status 'running'

    # Called by Stop-LocalHttpServer before the runspace is stopped
    Write-ServerStatusFile -Status 'stopped'
#>
function Write-ServerStatusFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('running', 'stopped', 'error')]
        [string]$Status
    )

    # ------------------------------------------------------------------
    # Resolve the status file path
    # ------------------------------------------------------------------
    # $script:root is set in Section 1 of local.httpserver.psm1 to
    # $PSScriptRoot of the module file. Join-Path constructs the absolute
    # path regardless of the current working directory.
    $statusFilePath = Join-Path $script:root "include\httpserver.status.json"

    # ------------------------------------------------------------------
    # Build the status data hashtable
    # ------------------------------------------------------------------
    # startTime is only meaningful when the server is actively running.
    # For 'stopped' and 'error' states it is explicitly set to $null so
    # the JSON contains "startTime": null rather than a stale timestamp
    # from a previous run.
    #
    # $PID is an automatic PowerShell variable containing the process ID
    # of the current PowerShell host — always available without import.
    $statusData = [ordered]@{
        status    = $Status
        pid       = $PID
        port      = $script:httpHost['port']
        wwwroot   = $script:httpHost['wwwroot']
        startTime = if ($Status -eq 'running') {
                        (Get-Date).ToString('o')   # ISO 8601 round-trip format
                    } else {
                        $null
                    }
        timestamp = (Get-Date).ToString('o')       # always present
    }

    # ------------------------------------------------------------------
    # Serialise to JSON and write the file
    # ------------------------------------------------------------------
    # ConvertTo-Json with -Depth 2 is sufficient for a flat hashtable.
    # Set-Content with -Encoding UTF8 ensures consistent BOM-less UTF-8
    # output on both PS 5.1 (where UTF8 = UTF-8 with BOM by default on
    # some versions) and PS 7 (where UTF8 = UTF-8 without BOM).
    # Using [System.IO.File]::WriteAllText avoids the BOM entirely:
    try {
        $jsonContent = $statusData | ConvertTo-Json -Depth 2
        [System.IO.File]::WriteAllText($statusFilePath, $jsonContent, [System.Text.Encoding]::UTF8)
        Write-Verbose "[Write-ServerStatusFile] Status '$Status' written to: $statusFilePath"
        return $true
    }
    catch {
        Write-Warning "[Write-ServerStatusFile] Failed to write status file: $($_.Exception.Message)"
        return $false
    }
}


# ===========================================================================
# FUNCTION: Remove-ServerStatusFile
# ===========================================================================
<#
.SYNOPSIS
    Deletes include\httpserver.status.json after a clean server shutdown.

.DESCRIPTION
    Called by Stop-LocalHttpServer after Stop-ManagedRunspace has returned
    successfully. The absence of the status file is the canonical signal
    that no server is running — this is safer than relying on a 'stopped'
    state inside the file, because a file with state = 'stopped' could
    theoretically be left behind by a crash before this call was reached.

    If the file does not exist (e.g. it was already deleted manually or
    was never created because Start-HTTPserver failed before the write),
    the function exits silently without error.

.OUTPUTS
    [bool] $true if the file was deleted or did not exist.
             $false if deletion was attempted but failed.

.EXAMPLE
    # Called by Stop-LocalHttpServer after Stop-ManagedRunspace succeeds
    Remove-ServerStatusFile
#>
function Remove-ServerStatusFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $statusFilePath = Join-Path $script:root "include\httpserver.status.json"

    # Silent no-op if the file is already gone
    if (-not (Test-Path $statusFilePath)) {
        Write-Verbose "[Remove-ServerStatusFile] Status file not found — nothing to remove."
        return $true
    }

    try {
        Remove-Item -Path $statusFilePath -Force -ErrorAction Stop
        Write-Verbose "[Remove-ServerStatusFile] Status file removed: $statusFilePath"
        return $true
    }
    catch {
        Write-Warning "[Remove-ServerStatusFile] Failed to remove status file: $($_.Exception.Message)"
        return $false
    }
}
