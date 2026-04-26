<#
.SYNOPSIS
    Injects a named variable into an open PowerShell Runspace.

.DESCRIPTION
    A Runspace is completely scope-isolated: it has no access to any
    $script: variable defined in the host module (local.httpserver.psm1),
    nor to any variable from the calling function. Every value the
    background code needs - configuration hashtables, the wwwroot path,
    the MIME type table, the cancellation token - must be explicitly
    pushed into the Runspace using this function.

    Set-RunspaceVariable must be called AFTER New-ManagedRunspace (which
    opens the Runspace) and BEFORE New-RunspaceJob (which starts execution).
    Injecting variables into an already-running Runspace is technically
    possible but should be avoided for values that the server loop reads on
    every iteration, as there is no guarantee about read/write ordering.

    Internally this uses SessionStateProxy.SetVariable(), which is the
    correct .NET API for this operation. It bypasses PowerShell's normal
    scope rules and writes directly into the target Runspace's session
    state, making the variable immediately available as a regular
    PowerShell variable ($VariableName) inside that Runspace.

.PARAMETER RunspaceName
    The key under which the target Runspace is registered in
    $script:RunspaceStore. Must match the Name used in New-ManagedRunspace.

.PARAMETER VariableName
    The name the variable will have inside the Runspace.
    Do NOT include the $ prefix - pass 'httpHost', not '$httpHost'.

.PARAMETER Value
    The value to inject. Any PowerShell type is accepted, including
    hashtables, arrays, PSCustomObjects and .NET objects such as the
    ManualResetEventSlim cancellation token.
    Passing $null is allowed (use [AllowNull()] on the param).

.OUTPUTS
    [bool] Returns $true on success, $false on any failure.
    A return value of $false is always accompanied by a Write-Warning or
    Write-Error message describing the exact reason.

.EXAMPLE
    # Inject the server configuration into the HTTP runspace
    Set-RunspaceVariable -RunspaceName 'http' -VariableName 'httpHost'    -Value $script:httpHost
    Set-RunspaceVariable -RunspaceName 'http' -VariableName 'httpRouter'  -Value $script:httpRouter
    Set-RunspaceVariable -RunspaceName 'http' -VariableName 'mimeType'    -Value $script:mimeType
    Set-RunspaceVariable -RunspaceName 'http' -VariableName 'wwwRoot'     -Value $resolvedRoot
    Set-RunspaceVariable -RunspaceName 'http' -VariableName 'CancelToken' -Value $entry.CancelToken

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/Set-RunspaceVariable.ps1
#>
function Set-RunspaceVariable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VariableName,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    # ------------------------------------------------------------------
    # Guard: runspace must exist in the store
    # ------------------------------------------------------------------
    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Warning "[Set-RunspaceVariable] No runspace named '$RunspaceName' found in RunspaceStore."
        return $false
    }

    $entry = $script:RunspaceStore[$RunspaceName]

    # ------------------------------------------------------------------
    # Guard: runspace must be in a state that accepts variable writes
    # ------------------------------------------------------------------
    # SetVariable() works on Opened and Running runspaces.
    # A runspace in Closed, Broken or Disconnected state will throw.
    # We check explicitly to give a clear, actionable error message
    # instead of a confusing .NET exception.
    $rsState = $entry.Runspace.RunspaceStateInfo.State

    $acceptableStates = @(
        [System.Management.Automation.Runspaces.RunspaceState]::Opened,
        [System.Management.Automation.Runspaces.RunspaceState]::Running
    )

    if ($rsState -notin $acceptableStates) {
        Write-Warning "[Set-RunspaceVariable] Runspace '$RunspaceName' is in state '$rsState'. Variables can only be injected into Opened or Running runspaces."
        return $false
    }

    # ------------------------------------------------------------------
    # Inject the variable via SessionStateProxy
    # ------------------------------------------------------------------
    # SessionStateProxy.SetVariable() writes directly into the Runspace's
    # PowerShell session state. After this call, $VariableName is available
    # as a normal variable inside that Runspace, with the exact Value
    # provided (no serialisation / deserialisation occurs - the actual
    # .NET object reference is shared, not a copy).
    #
    # This means complex objects (hashtables, custom .NET types) are passed
    # by reference. For the ManualResetEventSlim cancellation token this is
    # exactly what we want: the main thread sets the event on the same
    # object instance that the background loop polls.
    try {
        $entry.Runspace.SessionStateProxy.SetVariable($VariableName, $Value)
        Write-Verbose "[Set-RunspaceVariable] `$$VariableName successfully injected into runspace '$RunspaceName'."
        return $true
    }
    catch {
        Write-Error "[Set-RunspaceVariable] Failed to inject `$$VariableName into runspace '$RunspaceName': $($_.Exception.Message)"
        return $false
    }
}
