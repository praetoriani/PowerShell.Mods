<#
.SYNOPSIS
    Reads the current value of a variable from inside a running Runspace.

.DESCRIPTION
    Provides read access to the live session state of a background Runspace
    without stopping it. The main use cases are:

      - Reading $requestCount from the HTTP runspace to display live
        statistics in Get-LocalHttpServerStatus.
      - Reading $serverStartTime for uptime calculation.
      - Inspecting internal flags or counters set by the server loop for
        debugging or control-route responses.
      - Reading the $httpListener object reference so that
        Stop-ManagedRunspace can call $httpListener.Stop() on it directly,
        which forces BeginGetContext() to return immediately.

    Uses SessionStateProxy.GetVariable() — the symmetric counterpart to
    the SetVariable() call used in Set-RunspaceVariable. The variable value
    is returned as-is (by reference for objects, by value for value types),
    so mutations to a returned hashtable or array will affect the object
    inside the Runspace.

    Returns $null on any failure (runspace not found, variable does not
    exist, runspace disposed). The caller should always treat $null as a
    "not available" signal rather than an error, because the variable may
    simply not have been set yet in a newly started runspace.

.PARAMETER RunspaceName
    The key under which the target Runspace is registered in
    $script:RunspaceStore. Must match the Name used in New-ManagedRunspace.

.PARAMETER VariableName
    The name of the variable to read from inside the Runspace.
    Do NOT include the $ prefix — pass 'requestCount', not '$requestCount'.

.OUTPUTS
    The variable's current value, or $null if the variable could not be
    read (runspace missing, variable undefined, or Runspace disposed).

.EXAMPLE
    # Read live request counter from the running HTTP server
    $count = Get-RunspaceVariable -RunspaceName 'http' -VariableName 'requestCount'

    # Read the HttpListener object to stop it externally
    $listener = Get-RunspaceVariable -RunspaceName 'http' -VariableName 'httpListener'
    if ($null -ne $listener -and $listener.IsListening) { $listener.Stop() }

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/Get-RunspaceVariable.ps1
#>
function Get-RunspaceVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VariableName
    )

    # ------------------------------------------------------------------
    # Guard: runspace must be registered in the store
    # ------------------------------------------------------------------
    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Warning "[Get-RunspaceVariable] No runspace named '$RunspaceName' found in RunspaceStore."
        return $null
    }

    $entry = $script:RunspaceStore[$RunspaceName]

    # ------------------------------------------------------------------
    # Guard: runspace object must still exist (not yet disposed)
    # ------------------------------------------------------------------
    # After Stop-ManagedRunspace the entry is removed from the store, so
    # this guard catches edge cases where the store entry exists but the
    # Runspace object has been disposed by an unexpected shutdown path.
    if ($null -eq $entry.Runspace) {
        Write-Warning "[Get-RunspaceVariable] Runspace object for '$RunspaceName' is null. It may have been disposed externally."
        return $null
    }

    # ------------------------------------------------------------------
    # Read the variable via SessionStateProxy
    # ------------------------------------------------------------------
    # GetVariable() returns $null both when the variable does not exist
    # and when its value genuinely is $null. This is a known limitation
    # of SessionStateProxy and is acceptable for our use cases, because
    # we always initialise critical variables (like requestCount = 0)
    # before starting the runspace job, so a $null return reliably
    # indicates "not set yet" rather than "value is $null".
    try {
        $value = $entry.Runspace.SessionStateProxy.GetVariable($VariableName)
        return $value
    }
    catch {
        # A RunspaceNotOpenException here means the runspace was closed
        # between our guard check and the GetVariable call (race condition).
        # Return $null gracefully instead of bubbling up a .NET exception.
        Write-Warning "[Get-RunspaceVariable] Could not read `$$VariableName from '$RunspaceName': $($_.Exception.Message)"
        return $null
    }
}
