<#
.SYNOPSIS
    Returns $true if a named Runspace is registered in the store AND
    is currently in 'running' state.

.DESCRIPTION
    Test-RunspaceExists is a lightweight Boolean guard function used
    throughout local.httpserver to check the server's live state before
    taking an action. It is intentionally kept minimal — no output, no
    side effects, just a single Boolean result.

    It checks TWO conditions that must both be true:
      1. The RunspaceName key exists in $script:RunspaceStore.
      2. The store entry's logical State field equals 'running'.

    Why check BOTH conditions?

    The store key alone is not sufficient. A runspace that has crashed
    (State = 'error') or finished unexpectedly (State = 'stopped') may
    still have its entry in the store if Stop-ManagedRunspace has not yet
    been called to clean it up. Those entries must return $false so that
    Start-HTTPserver correctly identifies that the server is not alive,
    rather than blocking with a "already running" warning.

    Conversely, checking only the .NET Runspace state (RunspaceState from
    Get-RunspaceStatus) would require creating a Get-RunspaceStatus object
    for every guard call — unnecessarily expensive for a condition that is
    checked at the start of Start-HTTPserver, Stop-LocalHttpServer and
    Restart-LocalHttpServer on every invocation.

    IMPORTANT: This function does NOT confirm that the background thread
    is healthy or that the HttpListener is still accepting requests. It
    only confirms that the module's internal state says 'running'. Use
    Get-RunspaceStatus for a full diagnostic snapshot.

.PARAMETER RunspaceName
    The name to look up in $script:RunspaceStore.
    Must match the Name used when New-ManagedRunspace was called.

.OUTPUTS
    [bool]
    $true  — the runspace exists in the store and has State = 'running'.
    $false — the runspace is not in the store, or its State is not 'running'.

.EXAMPLE
    # Guard in Start-HTTPserver
    if (Test-RunspaceExists -RunspaceName 'http') {
        Write-Warning "HTTP server is already running. Use Stop-LocalHttpServer first."
        return
    }

    # Guard in Stop-LocalHttpServer
    if (-not (Test-RunspaceExists -RunspaceName 'http')) {
        Write-Host "HTTP server is not running." -ForegroundColor Yellow
        return
    }

    # Guard in a while loop (console mode keep-alive)
    while (Test-RunspaceExists -RunspaceName 'http') {
        Start-Sleep -Seconds 2
    }

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/Test-RunspaceExists.ps1
#>
function Test-RunspaceExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName
    )

    # Short-circuit evaluation guarantees that ContainsKey() is always
    # evaluated first. If it returns $false, the second operand (.State
    # comparison) is never evaluated — no KeyNotFoundException possible.
    #
    # This single expression replaces an if/else block and is equally
    # readable once you understand the intent of the function.
    return (
        $script:RunspaceStore.ContainsKey($RunspaceName) -and
        $script:RunspaceStore[$RunspaceName].State -eq 'running'
    )
}
