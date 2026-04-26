<#
.SYNOPSIS
    Starts a ScriptBlock asynchronously inside a registered Runspace.

.DESCRIPTION
    New-RunspaceJob is the actual "launch" step in the runspace lifecycle.
    It is called after the Runspace has been opened (New-ManagedRunspace),
    all required variables have been injected (Set-RunspaceVariable) and
    all required functions have been injected
    (Invoke-RunspaceFunctionInjection).

    Internally it:
      1. Creates a new PowerShell shell (System.Management.Automation
         .PowerShell) and binds it to the already-open Runspace. The shell
         inherits all variables and functions that were previously injected.
      2. Adds the ScriptBlock - and optional named parameters - to the shell.
      3. Calls BeginInvoke(), which starts execution on the Runspace's
         background thread and returns an IAsyncResult handle IMMEDIATELY.
         The calling thread is NOT blocked.
      4. Stores the PowerShell shell and the IAsyncResult handle in the
         store entry so that Stop-ManagedRunspace can later call EndInvoke()
         to collect results and release resources cleanly.

    After this function returns successfully, the server loop is running
    in the background. The console is immediately available to the user.

    PREREQUISITES (must be satisfied before calling this function):
      - New-ManagedRunspace has been called for this RunspaceName.
      - All variables required by ScriptBlock are injected.
      - All private functions required by ScriptBlock are injected.
      - The Runspace State is 'created' (not already 'running').

.PARAMETER RunspaceName
    The key under which the target Runspace is registered in
    $script:RunspaceStore. Must match the Name used in New-ManagedRunspace.

.PARAMETER ScriptBlock
    The code to execute inside the Runspace. For the HTTP server this is
    the ScriptBlock of the Start-HttpRunspace private function, retrieved
    via (Get-Command 'Start-HttpRunspace').ScriptBlock.
    The ScriptBlock may declare param() parameters that are populated via
    the Parameters argument.

.PARAMETER Parameters
    Optional hashtable of named arguments passed to the ScriptBlock via
    PowerShell.AddParameter(). Keys must match param() parameter names
    declared inside the ScriptBlock.
    Example: @{ Port = 8080; wwwRoot = 'C:\wwwroot' }

.OUTPUTS
    [bool] Returns $true if BeginInvoke() succeeded, $false on any error.
    On failure the store entry's State is set to 'error'.

.EXAMPLE
    # Retrieve the server loop ScriptBlock from the private function
    $serverSB = (Get-Command -Name 'Start-HttpRunspace').ScriptBlock

    # Start the server asynchronously - returns immediately
    $ok = New-RunspaceJob -RunspaceName 'http' `
                          -ScriptBlock  $serverSB `
                          -Parameters   @{ Port = 8080; wwwRoot = 'C:\wwwroot' }

    if (-not $ok) { Write-Error "Failed to start HTTP server runspace." }

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/New-RunspaceJob.ps1
#>
function New-RunspaceJob {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName,

        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )

    # ------------------------------------------------------------------
    # Guard: runspace must be registered
    # ------------------------------------------------------------------
    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Error "[New-RunspaceJob] No runspace named '$RunspaceName' found in RunspaceStore."
        return $false
    }

    $entry = $script:RunspaceStore[$RunspaceName]

    # ------------------------------------------------------------------
    # Guard: prevent double-starting a runspace
    # ------------------------------------------------------------------
    # If the State is already 'running', a BeginInvoke() is already in
    # flight. Starting a second one on the same Runspace would cause
    # both scripts to share the same session state, leading to variable
    # corruption and unpredictable behaviour.
    if ($entry.State -eq 'running') {
        Write-Warning "[New-RunspaceJob] Runspace '$RunspaceName' is already in 'running' state. Use Stop-ManagedRunspace first."
        return $false
    }

    # ------------------------------------------------------------------
    # Step 1: Create a PowerShell shell and bind it to the Runspace
    # ------------------------------------------------------------------
    # PowerShell.Create() creates a new shell. Assigning $entry.Runspace
    # to its .Runspace property binds it to our already-open, prepared
    # Runspace. The shell immediately sees all variables and functions
    # that were injected via SessionStateProxy before this call.
    try {
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $entry.Runspace

        # ------------------------------------------------------------------
        # Step 2: Add the ScriptBlock
        # ------------------------------------------------------------------
        # AddScript() queues the ScriptBlock for execution. Nothing runs yet.
        $ps.AddScript($ScriptBlock) | Out-Null

        # ------------------------------------------------------------------
        # Step 3: Add named parameters (if any)
        # ------------------------------------------------------------------
        # AddParameter() maps each key/value pair to a param() parameter
        # declared at the top of the ScriptBlock. Parameters not declared
        # in the ScriptBlock's param() block are silently ignored by PS.
        foreach ($key in $Parameters.Keys) {
            $ps.AddParameter($key, $Parameters[$key]) | Out-Null
        }

        # ------------------------------------------------------------------
        # Step 4: Start execution asynchronously via BeginInvoke()
        # ------------------------------------------------------------------
        # BeginInvoke() starts the ScriptBlock on the Runspace's background
        # thread and returns an IAsyncResult handle IMMEDIATELY. The caller
        # is not blocked at all - this is the key difference from Invoke().
        #
        # We store both the PowerShell shell ($ps) and the handle ($handle)
        # in the store entry. Stop-ManagedRunspace needs the handle to call
        # EndInvoke(), and the shell must be Dispose()d after EndInvoke().
        $handle = $ps.BeginInvoke()

        # ------------------------------------------------------------------
        # Step 5: Update the store entry
        # ------------------------------------------------------------------
        $entry.PowerShell = $ps
        $entry.Handle     = $handle
        $entry.State      = 'running'
        $script:RunspaceStore[$RunspaceName] = $entry

        Write-Verbose "[New-RunspaceJob] Async job started successfully in runspace '$RunspaceName'."
        return $true
    }
    catch {
        Write-Error "[New-RunspaceJob] Failed to start job in runspace '$RunspaceName': $($_.Exception.Message)"

        # Mark the entry as errored and clean up the PS shell if it was
        # partially constructed before the exception occurred.
        $entry.State = 'error'
        $script:RunspaceStore[$RunspaceName] = $entry

        if ($null -ne $ps) {
            try { $ps.Dispose() } catch { }
        }

        return $false
    }
}
