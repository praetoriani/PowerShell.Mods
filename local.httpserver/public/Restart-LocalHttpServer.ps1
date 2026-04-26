<#
.SYNOPSIS
    Restarts the local HTTP server with the same or new parameters.

.DESCRIPTION
    Performs a clean Stop → short pause → Start sequence.
    If no parameters are specified, the server restarts on the same port
    and with the same wwwRoot it was using before.

    The 1-second pause between Stop and Start allows Windows to release
    the TCP port binding. Without this pause, HttpListener.Start() may
    throw "Only one usage of each socket address is permitted" because the
    OS TCP stack has not yet fully released the port (TIME_WAIT state).

.PARAMETER Port
    New port to listen on after restart. If not specified, the currently
    configured port ($script:httpHost['port']) is used.

.PARAMETER wwwRoot
    New wwwRoot directory after restart. If not specified, the currently
    configured path ($script:httpHost['wwwroot']) is used.

.PARAMETER StopTimeoutMs
    How long to wait for the server to stop gracefully before continuing
    with the start sequence. Default: 3000 ms.

.EXAMPLE
    Restart-LocalHttpServer
    Restart-LocalHttpServer -Port 9090
    Restart-LocalHttpServer -Port 8080 -wwwRoot "C:\NewProject\wwwroot"

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : public/Restart-LocalHttpServer.ps1
#>
function Restart-LocalHttpServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [Parameter(Mandatory = $false)]
        [string]$wwwRoot,

        [Parameter(Mandatory = $false)]
        [ValidateRange(500, 30000)]
        [int]$StopTimeoutMs = 3000
    )

    # ------------------------------------------------------------------
    # Capture current values BEFORE stopping
    # ------------------------------------------------------------------
    # After Stop-LocalHttpServer the Runspace entry is removed from the store.
    # $script:httpHost is still available (it is module-level, not Runspace-level)
    # but we capture the values here for clarity and to respect any -Port or
    # -wwwRoot overrides the caller may have passed.

    $targetPort    = if ($PSBoundParameters.ContainsKey('Port'))    { $Port }    else { $script:httpHost['port'] }
    $targetWwwRoot = if ($PSBoundParameters.ContainsKey('wwwRoot')) { $wwwRoot } else { $script:httpHost['wwwroot'] }

    Write-Host "[INFO] Restarting HTTP Server (Port: $targetPort)..." -ForegroundColor Yellow

    # ------------------------------------------------------------------
    # Step 1: Stop the running server
    # ------------------------------------------------------------------

    Stop-LocalHttpServer -TimeoutMs $StopTimeoutMs

    # ------------------------------------------------------------------
    # Step 2: Wait for OS to release the TCP port
    # ------------------------------------------------------------------
    # Even after the HttpListener is fully closed and disposed, Windows
    # keeps the port in TCP TIME_WAIT state for a brief period. Attempting
    # to bind immediately results in "address already in use".
    # 1000 ms is reliably sufficient on all tested Windows versions.

    Write-Host "[INFO] Waiting 1 second for TCP port $targetPort to be released..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 1000

    # ------------------------------------------------------------------
    # Step 3: Start the server with the resolved parameters
    # ------------------------------------------------------------------

    Write-Host "[INFO] Starting server again..." -ForegroundColor Cyan
    Start-HTTPserver -Port $targetPort -wwwRoot $targetWwwRoot
}
