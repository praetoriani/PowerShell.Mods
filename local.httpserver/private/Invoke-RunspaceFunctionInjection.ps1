<#
.SYNOPSIS
    Injects one or more named PowerShell functions into an open Runspace
    so they are available as normal functions inside the background code.

.DESCRIPTION
    Because a Runspace has complete scope isolation, NONE of the functions
    defined in the host module (private/ or public/ .ps1 files loaded via
    dot-sourcing in local.httpserver.psm1) are automatically available
    inside the Runspace. If the server loop calls Invoke-RequestHandler,
    Invoke-RouteHandler or GetMimeType without those functions being
    present, it will immediately fail with "The term '...' is not
    recognized as the name of a cmdlet".

    Invoke-RunspaceFunctionInjection solves this by:
      1. Retrieving each function's ScriptBlock from the current session
         via Get-Command.
      2. Building a function definition string:
         "function FunctionName { <ScriptBlock body> }"
      3. Creating a temporary PowerShell shell bound to the target Runspace
         and invoking the definition string synchronously (Invoke(), not
         BeginInvoke()) so the function is fully defined BEFORE
         New-RunspaceJob starts the server loop.
      4. Disposing the temporary shell immediately after definition.

    This approach is called "function string injection" and is the
    standard pattern for making module-private functions available inside
    a Runspace that was created with InitialSessionState.CreateDefault().

    An alternative would be to use InitialSessionState.Commands.Add() to
    pre-populate the session state before the Runspace is opened, but that
    requires the function definitions to be available as
    SessionStateFunctionEntry objects at Runspace creation time — before
    variables are injected. The string injection approach is more flexible
    and works correctly with functions that reference $script: variables
    that are injected separately via Set-RunspaceVariable.

    IMPORTANT PREREQUISITE:
    All functions listed in FunctionNames must already exist in the CALLING
    session (i.e. in the module scope). They are loaded automatically by
    the dot-sourcing loop in Section 5 of local.httpserver.psm1. This
    function must therefore be called AFTER the module is fully imported,
    which is always the case in normal usage.

    Call order in Start-HTTPserver:
      1. New-ManagedRunspace       — open the Runspace
      2. Set-RunspaceVariable      — inject config variables
      3. Invoke-RunspaceFunctionInjection  ← HERE
      4. New-RunspaceJob           — start the server loop

.PARAMETER RunspaceName
    The key under which the target Runspace is registered in
    $script:RunspaceStore.

.PARAMETER FunctionNames
    String array of function names to inject. Each name must match an
    existing function in the current PowerShell session.

    For the HTTP server, the required set is:
      'Invoke-RequestHandler'
      'Invoke-RouteHandler'
      'GetMimeType'

    Additional functions (e.g. logging helpers) can be added here as
    the project grows without any changes to this function itself.

.OUTPUTS
    [bool]
    $true  — all listed functions were injected successfully.
    $false — the runspace was not found, or one or more functions failed
             to inject. Individual failures are logged via Write-Warning.

.EXAMPLE
    $ok = Invoke-RunspaceFunctionInjection `
            -RunspaceName  'http' `
            -FunctionNames @(
                'Invoke-RequestHandler',
                'Invoke-RouteHandler',
                'GetMimeType'
            )

    if (-not $ok) {
        Write-Error "Function injection failed. Aborting server start."
        Stop-ManagedRunspace -RunspaceName 'http'
        return
    }

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/Invoke-RunspaceFunctionInjection.ps1
#>
function Invoke-RunspaceFunctionInjection {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$FunctionNames
    )

    # ------------------------------------------------------------------
    # Guard: runspace must exist in the store
    # ------------------------------------------------------------------
    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Warning "[Invoke-RunspaceFunctionInjection] No runspace named '$RunspaceName' found in RunspaceStore."
        return $false
    }

    $entry        = $script:RunspaceStore[$RunspaceName]
    $allSucceeded = $true   # tracks overall result; set to $false on any failure

    foreach ($funcName in $FunctionNames) {

        # --------------------------------------------------------------
        # Step 1: Retrieve the function from the current session
        # --------------------------------------------------------------
        # Get-Command returns a FunctionInfo object whose .ScriptBlock
        # property contains the parsed, compiled ScriptBlock of the
        # function body (everything between the outermost { }).
        # If the function does not exist, Get-Command returns $null
        # (with -ErrorAction SilentlyContinue) and we skip it with a
        # warning instead of crashing the entire injection loop.
        $funcInfo = Get-Command -Name $funcName -CommandType Function -ErrorAction SilentlyContinue

        if ($null -eq $funcInfo) {
            Write-Warning "[Invoke-RunspaceFunctionInjection] Function '$funcName' not found in current session. Ensure the private .ps1 file is loaded before calling this function."
            $allSucceeded = $false
            continue    # skip to next function in the list
        }

        # --------------------------------------------------------------
        # Step 2: Build the function definition string
        # --------------------------------------------------------------
        # We wrap the ScriptBlock in a "function Name { body }" string.
        # When this string is executed inside the Runspace (Step 3), it
        # defines the function in that Runspace's session state, making
        # it callable by name from the server loop ScriptBlock.
        #
        # $funcInfo.ScriptBlock already contains only the body — not the
        # "function FunctionName { ... }" wrapper — so we add it here.
        $funcDefinitionString = "function $funcName {`n$($funcInfo.ScriptBlock)`n}"

        # --------------------------------------------------------------
        # Step 3: Execute the definition string inside the Runspace
        # --------------------------------------------------------------
        # A temporary, short-lived PowerShell shell is created, bound to
        # the target Runspace and used to Invoke() the definition string
        # synchronously. Synchronous execution (Invoke, not BeginInvoke)
        # is intentional: we MUST be certain the function is defined
        # before New-RunspaceJob starts the server loop that calls it.
        # The shell is disposed immediately after use.
        $tempShell = $null
        try {
            $tempShell = [System.Management.Automation.PowerShell]::Create()
            $tempShell.Runspace = $entry.Runspace

            $tempShell.AddScript($funcDefinitionString) | Out-Null
            $tempShell.Invoke() | Out-Null   # synchronous — blocks until done

            # Check whether the definition script itself produced errors
            if ($tempShell.HadErrors) {
                $errMsg = ($tempShell.Streams.Error | Select-Object -First 1).ToString()
                Write-Warning "[Invoke-RunspaceFunctionInjection] Function '$funcName' injected but shell reported an error: $errMsg"
                $allSucceeded = $false
            }
            else {
                Write-Verbose "[Invoke-RunspaceFunctionInjection] Function '$funcName' successfully injected into runspace '$RunspaceName'."
            }
        }
        catch {
            Write-Warning "[Invoke-RunspaceFunctionInjection] Failed to inject '$funcName' into '$RunspaceName': $($_.Exception.Message)"
            $allSucceeded = $false
        }
        finally {
            # Always dispose the temporary shell, even if an exception occurred.
            # A non-disposed shell holds a reference to the Runspace and
            # prevents it from being closed cleanly later.
            if ($null -ne $tempShell) {
                try { $tempShell.Dispose() } catch { }
            }
        }
    }

    if ($allSucceeded) {
        Write-Verbose "[Invoke-RunspaceFunctionInjection] All $($FunctionNames.Count) function(s) injected successfully into '$RunspaceName'."
    }
    else {
        Write-Warning "[Invoke-RunspaceFunctionInjection] One or more functions could not be injected into '$RunspaceName'. Check the warnings above."
    }

    return $allSucceeded
}
