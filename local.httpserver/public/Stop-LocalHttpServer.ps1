<#
.SYNOPSIS
    Stops the running local HTTP server gracefully.

.DESCRIPTION
    Sends a cooperative stop signal to the HTTP Runspace by setting the
    CancelToken (ManualResetEventSlim), then waits for the server loop to
    exit cleanly within the specified timeout. After the loop exits, all
    Runspace resources (PowerShell shell, Runspace, handle) are disposed
    and the entry is removed from the RunspaceStore.

    The stop sequence inside Stop-ManagedRunspace (called by this function):
        1. CancelToken.Set()         — signals the server loop to exit
        2. $httpListener.Stop()       — unblocks any pending BeginGetContext()
        3. AsyncWaitHandle.WaitOne()  — waits up to TimeoutMs for clean exit
        4. EndInvoke()               — retrieves result and collects errors
        5. PowerShell.Dispose()      — releases PS shell resources
        6. Runspace.Close()          — releases .NET Runspace
        7. Runspace.Dispose()        — frees unmanaged kernel resources
        8. RunspaceStore.Remove()    — removes the entry from the registry

.PARAMETER TimeoutMs
    Maximum time in milliseconds to wait for the server loop to exit
    cleanly before force-closing the Runspace.

    The server loop polls the CancelToken every PollIntervalMs (default 500 ms).
    A TimeoutMs of 3000 gives the loop 6 poll cycles to react — more than enough
    under normal conditions.

    Default: 5000 ms.

.PARAMETER Force
    If specified, TimeoutMs is set to 0 — the Runspace is closed immediately
    without waiting for the server loop to finish its current request.
    Use only when the server is unresponsive.

.EXAMPLE
    Stop-LocalHttpServer
    Stop-LocalHttpServer -TimeoutMs 10000
    Stop-LocalHttpServer -Force

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : public/Stop-LocalHttpServer.ps1
#>
function Stop-LocalHttpServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 60000)]
        [int]$TimeoutMs = 5000,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # ------------------------------------------------------------------
    # GUARD: Nothing to stop if the server is not running
    # ------------------------------------------------------------------

    if (-not (Test-RunspaceExists -RunspaceName 'http')) {
        Write-Host "[INFO] HTTP Server is not running. Nothing to stop." -ForegroundColor Yellow
        return
    }

    # ------------------------------------------------------------------
    # Resolve effective timeout
    # ------------------------------------------------------------------
    # -Force overrides any explicit -TimeoutMs value and sets it to 0.
    # With TimeoutMs = 0 Stop-ManagedRunspace skips the WaitOne() call
    # and proceeds directly to EndInvoke + Dispose (force-close).

    $effectiveTimeout = if ($Force) { 0 } else { $TimeoutMs }

    if ($Force) {
        Write-Host "[WARN] Force-stop requested. Server will be closed immediately without waiting." -ForegroundColor Yellow
    }
    else {
        Write-Host "[INFO] Stopping HTTP Server (timeout: ${effectiveTimeout}ms)..." -ForegroundColor Cyan
    }

    # ------------------------------------------------------------------
    # Delegate to Stop-ManagedRunspace (private)
    # ------------------------------------------------------------------
    # Stop-ManagedRunspace executes the full 8-step teardown sequence
    # described in the .DESCRIPTION block above.

    $result = Stop-ManagedRunspace -RunspaceName 'http' -TimeoutMs $effectiveTimeout

    # ------------------------------------------------------------------
    # Update the status file
    # ------------------------------------------------------------------
    # Write-ServerStatusFile updates include\httpserver.status.json so
    # external tools know the server has stopped.

    Remove-ServerStatusFile

    # ------------------------------------------------------------------
    # Report result
    # ------------------------------------------------------------------

    if ($result) {
        Write-Host "[OK]   HTTP Server stopped successfully." -ForegroundColor Green
    }
    else {
        Write-Warning "[WARN] Stop-ManagedRunspace reported issues. The server may not have stopped cleanly."
        Write-Warning "       Use 'Get-LocalHttpServerStatus' to verify, or restart PowerShell."
    }
}
