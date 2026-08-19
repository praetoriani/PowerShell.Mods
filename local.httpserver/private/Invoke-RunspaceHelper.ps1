<#
.SYNOPSIS
    Private helper functions for Runspace lifecycle management.

.DESCRIPTION
    This file contains all private functions required to create, configure,
    monitor and cleanly shut down PowerShell Runspaces used by local.httpserver.

    Function overview:
      New-ManagedRunspace             - Creates and registers a new Runspace
      Set-RunspaceVariable            - Injects a variable into an open Runspace
      Get-RunspaceVariable            - Reads a variable from a running Runspace
      New-RunspaceJob                 - Starts a ScriptBlock asynchronously inside a Runspace
      Get-RunspaceStatus              - Returns the current state of a registered Runspace
      Stop-ManagedRunspace            - Signals, waits for and cleanly disposes a Runspace
      Test-RunspaceExists             - Returns $true if a named Runspace is active
      Invoke-RunspaceFunctionInjection - Injects named PS functions into an open Runspace

    IMPORTANT: All functions in this file operate on $script:RunspaceStore,
    which is initialised in Section 2b of local.httpserver.psm1.
    Never call these functions before the module has been fully loaded.

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1+, PowerShell 7.x
#>


# ___________________________________________________________________________
# FUNCTION: New-ManagedRunspace
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
<#
.SYNOPSIS
    Creates a new, fully configured PowerShell Runspace and registers it
    in $script:RunspaceStore.

.DESCRIPTION
    This is always the FIRST step in launching a background task.
    It creates the Runspace object, sets threading options, creates a
    cancellation token (ManualResetEventSlim) and registers everything
    in the central RunspaceStore under the given Name.

    After calling this function the Runspace is OPEN but NOT yet running
    any code. Use Set-RunspaceVariable / Invoke-RunspaceFunctionInjection
    to prepare the Runspace, then call New-RunspaceJob to start execution.

.PARAMETER Name
    A short, unique identifier for this Runspace, e.g. 'http', 'pipe', 'tray'.
    Used as the key in $script:RunspaceStore.

.PARAMETER ApartmentState
    Threading apartment model for the Runspace thread.
    - MTA (default): Multi-Threaded Apartment. Correct for HTTP servers,
      background jobs, pipe servers and all non-UI work.
    - STA: Single-Threaded Apartment. REQUIRED for WinForms and WPF (Phase 6).
    Specifying this now keeps Phase 6 (systray, desktop) a drop-in change.

.OUTPUTS
    PSCustomObject - the store entry that was created. Contains all fields
    described in Section 2b of local.httpserver.psm1.

.EXAMPLE
    $entry = New-ManagedRunspace -Name 'http'
    $entry = New-ManagedRunspace -Name 'tray' -ApartmentState STA
#>
function New-ManagedRunspace {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Runspaces.ApartmentState]
        $ApartmentState = [System.Management.Automation.Runspaces.ApartmentState]::MTA
    )

    # Guard: reject duplicate names to prevent accidentally overwriting a
    # running runspace. The caller must stop the existing one first.
    if ($script:RunspaceStore.ContainsKey($Name)) {
        Write-Warning "[New-ManagedRunspace] A runspace named '$Name' already exists in the store. Use Stop-ManagedRunspace first."
        return $null
    }

    # -----------------------------------------------------------------------
    # Step 1: Build the InitialSessionState
    # -----------------------------------------------------------------------
    # CreateDefault() is used instead of CreateDefault2() for full
    # PowerShell 5.1 compatibility. CreateDefault2() is PS 7+ only.
    # CreateDefault() loads the standard built-in cmdlets (Write-Host,
    # New-Object, Add-Type, etc.) which the server loop needs.
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

    # -----------------------------------------------------------------------
    # Step 2: Create the Runspace object
    # -----------------------------------------------------------------------
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)

    # Set the apartment state BEFORE opening the runspace.
    # Changing it after Open() has no effect.
    $rs.ApartmentState = $ApartmentState

    # ReuseThread: The runspace reuses the same OS thread for every invocation.
    # This avoids the overhead of spinning up a new thread per BeginInvoke()
    # call and is the correct setting for a long-running server loop.
    $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread

    # -----------------------------------------------------------------------
    # Step 3: Open the Runspace
    # -----------------------------------------------------------------------
    # Open() allocates resources and makes the runspace ready to receive
    # variable injections and function definitions.
    # It does NOT start running any code yet.
    try {
        $rs.Open()
        Write-Verbose "[New-ManagedRunspace] Runspace '$Name' opened successfully."
    }
    catch {
        Write-Error "[New-ManagedRunspace] Failed to open runspace '$Name': $($_.Exception.Message)"
        return $null
    }

    # -----------------------------------------------------------------------
    # Step 4: Create a cancellation token (ManualResetEventSlim)
    # -----------------------------------------------------------------------
    # ManualResetEventSlim is a lightweight, thread-safe signalling primitive.
    # The server loop inside the runspace polls $CancelToken.IsSet on every
    # iteration (or after each BeginGetContext timeout).
    # When Stop-ManagedRunspace calls $CancelToken.Set(), the loop exits
    # cleanly on its next check - no thread abort, no data corruption.
    #
    # Initial state: $false (not set = keep running).
    $cancelToken = New-Object System.Threading.ManualResetEventSlim($false)

    # -----------------------------------------------------------------------
    # Step 5: Build the store entry and register it
    # -----------------------------------------------------------------------
    $storeEntry = [PSCustomObject]@{
        Runspace    = $rs
        PowerShell  = $null          # Populated by New-RunspaceJob
        Handle      = $null          # Populated by New-RunspaceJob (IAsyncResult)
        CancelToken = $cancelToken
        StartTime   = Get-Date
        State       = 'created'
        Name        = $Name
    }

    $script:RunspaceStore[$Name] = $storeEntry

    Write-Verbose "[New-ManagedRunspace] Runspace '$Name' registered in store (State: created)."
    return $storeEntry
}


# ___________________________________________________________________________
# FUNCTION: Set-RunspaceVariable
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
<#
.SYNOPSIS
    Injects a variable into an already-open Runspace via SessionStateProxy.

.DESCRIPTION
    A Runspace has complete scope isolation: it cannot see any $script:
    variables from the host module. Every value the background code needs
    (configuration hashtables, the cancellation token, etc.) must be
    explicitly pushed in using this function BEFORE New-RunspaceJob is called.

    Uses SessionStateProxy.SetVariable(), which is the correct low-level API
    for this purpose. It works whether the runspace is idle or actively
    running code (as long as there is no concurrent write conflict).

.PARAMETER RunspaceName
    The name under which the target Runspace is registered in $script:RunspaceStore.

.PARAMETER VariableName
    The name the variable will have inside the Runspace (without the $ prefix).

.PARAMETER Value
    The value to inject. Any PowerShell type is supported.

.OUTPUTS
    [bool] $true on success, $false on failure.

.EXAMPLE
    Set-RunspaceVariable -RunspaceName 'http' -VariableName 'httpHost'    -Value $script:httpHost
    Set-RunspaceVariable -RunspaceName 'http' -VariableName 'httpRouter'  -Value $script:httpRouter
    Set-RunspaceVariable -RunspaceName 'http' -VariableName 'mimeType'    -Value $script:mimeType
    Set-RunspaceVariable -RunspaceName 'http' -VariableName 'CancelToken' -Value $entry.CancelToken
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

    # Guard: runspace must exist in the store
    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Warning "[Set-RunspaceVariable] Runspace '$RunspaceName' not found in store."
        return $false
    }

    $entry = $script:RunspaceStore[$RunspaceName]

    # Guard: runspace must be in Opened state
    # Variables can only be injected into a runspace that has been opened
    # but is not yet disposed. 'Running' also works for non-conflicting writes.
    $rsState = $entry.Runspace.RunspaceStateInfo.State
    $validStates = @(
        [System.Management.Automation.Runspaces.RunspaceState]::Opened,
        [System.Management.Automation.Runspaces.RunspaceState]::Running
    )
    if ($rsState -notin $validStates) {
        Write-Warning "[Set-RunspaceVariable] Runspace '$RunspaceName' is in state '$rsState'. Expected Opened or Running."
        return $false
    }

    try {
        $entry.Runspace.SessionStateProxy.SetVariable($VariableName, $Value)
        Write-Verbose "[Set-RunspaceVariable] `$$VariableName injected into runspace '$RunspaceName'."
        return $true
    }
    catch {
        Write-Error "[Set-RunspaceVariable] Failed to inject `$$VariableName into '$RunspaceName': $($_.Exception.Message)"
        return $false
    }
}


# ___________________________________________________________________________
# FUNCTION: Get-RunspaceVariable
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
<#
.SYNOPSIS
    Reads the current value of a variable from inside a running Runspace.

.DESCRIPTION
    Allows the host thread to inspect live state from a background Runspace
    without stopping it. Typical use cases:
    - Reading the $requestCount from the HTTP runspace for status reports
    - Reading $serverStartTime for uptime calculation
    - Checking internal flags set by the server loop

    Uses SessionStateProxy.GetVariable() - the symmetric counterpart to
    SetVariable() used in Set-RunspaceVariable.

.PARAMETER RunspaceName
    The name of the target Runspace in $script:RunspaceStore.

.PARAMETER VariableName
    The name of the variable to read (without the $ prefix).

.OUTPUTS
    The variable's current value, or $null if not found / on error.

.EXAMPLE
    $count = Get-RunspaceVariable -RunspaceName 'http' -VariableName 'requestCount'
    $start = Get-RunspaceVariable -RunspaceName 'http' -VariableName 'serverStartTime'
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

    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Warning "[Get-RunspaceVariable] Runspace '$RunspaceName' not found in store."
        return $null
    }

    $entry = $script:RunspaceStore[$RunspaceName]

    # Runspace must still be accessible (not disposed)
    if ($null -eq $entry.Runspace) {
        Write-Warning "[Get-RunspaceVariable] Runspace object for '$RunspaceName' is null."
        return $null
    }

    try {
        $value = $entry.Runspace.SessionStateProxy.GetVariable($VariableName)
        return $value
    }
    catch {
        Write-Warning "[Get-RunspaceVariable] Could not read `$$VariableName from '$RunspaceName': $($_.Exception.Message)"
        return $null
    }
}


# ___________________________________________________________________________
# FUNCTION: New-RunspaceJob
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
<#
.SYNOPSIS
    Starts a ScriptBlock asynchronously inside a registered Runspace.

.DESCRIPTION
    This is the actual "launch" step. It:
    1. Creates a PowerShell shell and binds it to the named Runspace.
    2. Adds the ScriptBlock (and optional parameters) to the shell.
    3. Calls BeginInvoke() which starts execution on a background thread
       and returns IMMEDIATELY to the caller.
    4. Stores the PowerShell shell and the IAsyncResult handle in the
       store entry so Stop-ManagedRunspace can call EndInvoke() later.

    Prerequisites (must be done before calling this function):
    - New-ManagedRunspace must have been called for this Name.
    - All required variables must have been injected via Set-RunspaceVariable.
    - All required functions must have been injected via
      Invoke-RunspaceFunctionInjection.

.PARAMETER RunspaceName
    The name of the target Runspace in $script:RunspaceStore.

.PARAMETER ScriptBlock
    The code to execute inside the Runspace. This is typically the
    server loop ScriptBlock from Start-HttpRunspace.

.PARAMETER Parameters
    Optional hashtable of named parameters to pass to the ScriptBlock.
    These map to param() parameters defined inside the ScriptBlock.
    Example: @{ Port = 8080; wwwRoot = 'C:\wwwroot' }

.OUTPUTS
    [bool] $true if the job was started successfully, $false on error.

.EXAMPLE
    $sb = (Get-Command 'Start-HttpRunspace').ScriptBlock
    New-RunspaceJob -RunspaceName 'http' -ScriptBlock $sb -Parameters @{ Port = 8080 }
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

    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Error "[New-RunspaceJob] Runspace '$RunspaceName' not found in store."
        return $false
    }

    $entry = $script:RunspaceStore[$RunspaceName]

    # Guard: do not double-start a runspace that is already running
    if ($entry.State -eq 'running') {
        Write-Warning "[New-RunspaceJob] Runspace '$RunspaceName' is already in 'running' state."
        return $false
    }

    try {
        # Create a new PowerShell shell and bind it to our prepared runspace.
        # All variables and functions already injected into the runspace are
        # now available to this shell.
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $entry.Runspace

        # Add the script to execute
        $ps.AddScript($ScriptBlock) | Out-Null

        # Add named parameters if provided
        foreach ($key in $Parameters.Keys) {
            $ps.AddParameter($key, $Parameters[$key]) | Out-Null
        }

        # BeginInvoke() starts execution asynchronously and returns an
        # IAsyncResult handle immediately. The caller is NOT blocked.
        # We store this handle so Stop-ManagedRunspace can call EndInvoke().
        $handle = $ps.BeginInvoke()

        # Update the store entry with the live objects
        $entry.PowerShell = $ps
        $entry.Handle     = $handle
        $entry.State      = 'running'
        $script:RunspaceStore[$RunspaceName] = $entry

        Write-Verbose "[New-RunspaceJob] Async job started in runspace '$RunspaceName'."
        return $true
    }
    catch {
        Write-Error "[New-RunspaceJob] Failed to start job in '$RunspaceName': $($_.Exception.Message)"
        $entry.State = 'error'
        $script:RunspaceStore[$RunspaceName] = $entry
        return $false
    }
}


# ___________________________________________________________________________
# FUNCTION: Get-RunspaceStatus
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
<#
.SYNOPSIS
    Returns a status snapshot of a registered Runspace.

.DESCRIPTION
    Aggregates state information from the store entry, the Runspace object
    itself and the async handle into a single PSCustomObject.
    Used internally by Get-LocalHttpServerStatus and by the
    /sys/ctrl/http-getstatus control route.

    Returns a valid object even when the runspace does not exist
    (with State = 'not_found' and Exists = $false), so callers do not need
    to guard against $null returns.

.PARAMETER RunspaceName
    The name of the Runspace to inspect in $script:RunspaceStore.

.OUTPUTS
    PSCustomObject with fields:
      Name, State, RunspaceState, IsCompleted, HadErrors,
      StartTime, Uptime, Exists

.EXAMPLE
    $status = Get-RunspaceStatus -RunspaceName 'http'
    if ($status.Exists) { Write-Host "Uptime: $($status.Uptime)" }
#>
function Get-RunspaceStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName
    )

    # Return a safe "not found" object so callers never receive $null
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

    # Read the actual Runspace state from the .NET object
    $rsState = if ($null -ne $rs) {
        $rs.RunspaceStateInfo.State.ToString()
    } else { 'null' }

    # Check whether the async BeginInvoke() job has finished
    $jobCompleted = if ($null -ne $entry.Handle) {
        $entry.Handle.IsCompleted
    } else { $false }

    # Check whether the PowerShell shell reported any errors
    $hasErrors = if ($null -ne $ps) { $ps.HadErrors } else { $false }

    # Calculate uptime as a formatted string if the server has been running
    $uptimeStr = $null
    if ($null -ne $entry.StartTime -and $entry.State -eq 'running') {
        $ts = (Get-Date) - $entry.StartTime
        $uptimeStr = '{0}d {1:D2}h {2:D2}m {3:D2}s' -f $ts.Days, $ts.Hours, $ts.Minutes, $ts.Seconds
    }

    return [PSCustomObject]@{
        Name          = $RunspaceName
        State         = $entry.State
        RunspaceState = $rsState
        IsCompleted   = $jobCompleted
        HadErrors     = $hasErrors
        StartTime     = $entry.StartTime
        Uptime        = $uptimeStr
        Exists        = $true
    }
}


# ___________________________________________________________________________
# FUNCTION: Stop-ManagedRunspace
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
<#
.SYNOPSIS
    Gracefully signals, waits for and fully disposes a managed Runspace.

.DESCRIPTION
    This function performs a clean, ordered shutdown sequence:

      1. Set the CancelToken  → the server loop sees .IsSet = $true and
                                exits on its next iteration (within 500ms
                                due to the BeginGetContext poll interval).
      2. Stop the HttpListener → makes GetContext()/BeginGetContext() return
                                 immediately so the loop does not have to
                                 wait for a real incoming request.
      3. Wait for completion  → AsyncWaitHandle.WaitOne(TimeoutMs). If the
                                runspace does not finish within the timeout,
                                a warning is logged and we proceed anyway.
      4. EndInvoke()           → collects the result / re-throws any unhandled
                                 exception from the background thread. Required
                                 to avoid resource leaks.
      5. Dispose PowerShell   → releases the PS shell.
      6. Close + Dispose RS   → releases the Runspace thread and .NET objects.
      7. Dispose CancelToken  → releases the event wait handle.
      8. Remove from store    → the slot is freed for a future restart.

    The order of these steps is critical. Deviating from it risks:
    - Trying to read results after the runspace is already disposed (crash)
    - Port 995 exceptions surfacing as unhandled errors
    - Memory leaks from undisposed handles

.PARAMETER RunspaceName
    The name of the Runspace to stop in $script:RunspaceStore.

.PARAMETER TimeoutMs
    Maximum time in milliseconds to wait for a clean shutdown before
    proceeding with force-close. Default: 5000 (5 seconds).
    Pass 0 for an immediate force-close (skips the wait).

.OUTPUTS
    [bool] $true if stopped cleanly, $false if the runspace was not found.

.EXAMPLE
    Stop-ManagedRunspace -RunspaceName 'http'
    Stop-ManagedRunspace -RunspaceName 'http' -TimeoutMs 0   # force
#>
function Stop-ManagedRunspace {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 30000)]
        [int]$TimeoutMs = 5000
    )

    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Warning "[Stop-ManagedRunspace] Runspace '$RunspaceName' not found in store."
        return $false
    }

    $entry = $script:RunspaceStore[$RunspaceName]
    Write-Verbose "[Stop-ManagedRunspace] Beginning shutdown of runspace '$RunspaceName'..."

    # ------------------------------------------------------------------
    # Step 1: Signal the CancelToken
    # ------------------------------------------------------------------
    # The server loop checks $CancelToken.IsSet after each BeginGetContext
    # timeout (500ms). Setting it here causes the loop to exit cleanly on
    # its next check without needing to abort the thread.
    if ($null -ne $entry.CancelToken -and -not $entry.CancelToken.IsSet) {
        $entry.CancelToken.Set()
        Write-Verbose "[Stop-ManagedRunspace] CancelToken set for '$RunspaceName'."
    }

    # ------------------------------------------------------------------
    # Step 2: Stop the HttpListener (if applicable)
    # ------------------------------------------------------------------
    # BeginGetContext() blocks until a request arrives OR the listener is
    # stopped. Calling Stop() here causes the pending BeginGetContext to
    # complete immediately with a HttpListenerException (ErrorCode 995),
    # which the server loop handles by breaking out of the while loop.
    # This guarantees the runspace exits within milliseconds, not minutes.
    try {
        $listener = $entry.Runspace.SessionStateProxy.GetVariable('httpListener')
        if ($null -ne $listener -and $listener.IsListening) {
            $listener.Stop()
            Write-Verbose "[Stop-ManagedRunspace] HttpListener stopped for '$RunspaceName'."
        }
    }
    catch {
        # Non-fatal: the listener may already be gone or the variable may
        # not exist (e.g. for a non-HTTP runspace like a pipe server).
        Write-Verbose "[Stop-ManagedRunspace] Could not stop listener (non-fatal): $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # Step 3: Wait for the async job to complete
    # ------------------------------------------------------------------
    if ($null -ne $entry.Handle -and $TimeoutMs -gt 0) {
        $cleanExit = $entry.Handle.AsyncWaitHandle.WaitOne($TimeoutMs)
        if (-not $cleanExit) {
            Write-Warning "[Stop-ManagedRunspace] Runspace '$RunspaceName' did not stop within ${TimeoutMs}ms. Proceeding with forced cleanup."
        } else {
            Write-Verbose "[Stop-ManagedRunspace] Runspace '$RunspaceName' exited cleanly."
        }
    }

    # ------------------------------------------------------------------
    # Step 4: EndInvoke - collect result and surface any background errors
    # ------------------------------------------------------------------
    # EndInvoke() MUST be called after BeginInvoke(), even if we don't
    # care about the return value. Skipping it leaks the IAsyncResult
    # handle and may suppress exceptions from the background thread.
    if ($null -ne $entry.PowerShell -and $null -ne $entry.Handle) {
        try {
            $entry.PowerShell.EndInvoke($entry.Handle) | Out-Null
        }
        catch {
            Write-Warning "[Stop-ManagedRunspace] EndInvoke reported an error: $($_.Exception.Message)"
        }
    }

    # ------------------------------------------------------------------
    # Step 5: Dispose the PowerShell shell
    # ------------------------------------------------------------------
    if ($null -ne $entry.PowerShell) {
        try { $entry.PowerShell.Dispose() }
        catch { Write-Verbose "[Stop-ManagedRunspace] PS Dispose (non-fatal): $($_.Exception.Message)" }
    }

    # ------------------------------------------------------------------
    # Step 6: Close and Dispose the Runspace
    # ------------------------------------------------------------------
    if ($null -ne $entry.Runspace) {
        try {
            $entry.Runspace.Close()
            $entry.Runspace.Dispose()
            Write-Verbose "[Stop-ManagedRunspace] Runspace '$RunspaceName' closed and disposed."
        }
        catch { Write-Verbose "[Stop-ManagedRunspace] RS Close/Dispose (non-fatal): $($_.Exception.Message)" }
    }

    # ------------------------------------------------------------------
    # Step 7: Dispose the CancelToken
    # ------------------------------------------------------------------
    if ($null -ne $entry.CancelToken) {
        try { $entry.CancelToken.Dispose() }
        catch { Write-Verbose "[Stop-ManagedRunspace] CancelToken Dispose (non-fatal): $($_.Exception.Message)" }
    }

    # ------------------------------------------------------------------
    # Step 8: Remove from store
    # ------------------------------------------------------------------
    $script:RunspaceStore.Remove($RunspaceName)
    Write-Verbose "[Stop-ManagedRunspace] Runspace '$RunspaceName' removed from store."
    Write-Host "[INFO] Runspace '$RunspaceName' stopped and cleaned up." -ForegroundColor Cyan

    return $true
}


# ___________________________________________________________________________
# FUNCTION: Test-RunspaceExists
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
<#
.SYNOPSIS
    Returns $true if a named Runspace exists in the store AND is running.

.DESCRIPTION
    Lightweight guard used by Start-HTTPserver, Stop-LocalHttpServer and
    Restart-LocalHttpServer to check server state before taking action.
    Checks both store membership AND logical state ('running'), so a
    runspace that has crashed or been stopped but not yet removed returns
    $false as expected.

.PARAMETER RunspaceName
    The name to look up in $script:RunspaceStore.

.OUTPUTS
    [bool] $true if the runspace exists and is in 'running' state.

.EXAMPLE
    if (Test-RunspaceExists -RunspaceName 'http') {
        Write-Host "Server is running."
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

    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        return $false
    }
    return ($script:RunspaceStore[$RunspaceName].State -eq 'running')
}


# ___________________________________________________________________________
# FUNCTION: Invoke-RunspaceFunctionInjection
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
<#
.SYNOPSIS
    Injects one or more named PowerShell functions into an open Runspace.

.DESCRIPTION
    Because a Runspace has complete scope isolation, none of the module's
    private or public functions (Invoke-RequestHandler, Invoke-RouteHandler,
    GetMimeType, etc.) are available inside it by default.

    This function reads the ScriptBlock of each named function from the
    current host session using Get-Command, then executes a function
    definition statement inside the target Runspace, making the function
    callable from the server loop code.

    CALL ORDER: Must be called AFTER New-ManagedRunspace (Runspace must be
    Opened) and BEFORE New-RunspaceJob (before the loop starts).

.PARAMETER RunspaceName
    The name of the target Runspace in $script:RunspaceStore.

.PARAMETER FunctionNames
    Array of function names to inject.
    All listed functions must exist in the current session at the time of
    this call (they are loaded by the bootstrapper in Section 5 of psm1).

.OUTPUTS
    [bool] $true if all functions were injected successfully, $false if
    any function failed (individual failures are logged as errors).

.EXAMPLE
    Invoke-RunspaceFunctionInjection -RunspaceName 'http' -FunctionNames @(
        'Invoke-RequestHandler',
        'Invoke-RouteHandler',
        'GetMimeType'
    )

.NOTES
    This approach (re-defining functions via ScriptBlock injection) is the
    most reliable and PS 5.1-compatible method. The alternative - passing
    function definitions as InitialSessionState entries - requires building
    SessionStateFunction objects which is significantly more verbose and
    provides no practical benefit here.
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

    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Error "[Invoke-RunspaceFunctionInjection] Runspace '$RunspaceName' not found in store."
        return $false
    }

    $entry   = $script:RunspaceStore[$RunspaceName]
    $success = $true

    foreach ($funcName in $FunctionNames) {

        # Look up the function in the current session
        $cmd = Get-Command -Name $funcName -CommandType Function -ErrorAction SilentlyContinue
        if ($null -eq $cmd) {
            Write-Warning "[Invoke-RunspaceFunctionInjection] Function '$funcName' not found in current session. Skipping."
            $success = $false
            continue
        }

        # Build the function definition statement that will run inside the runspace.
        # The ScriptBlock of the original function is embedded verbatim so that
        # all its internal logic, including nested calls and .NET type usage, is
        # preserved exactly.
        $funcDefinition = "function $funcName {`n$($cmd.ScriptBlock)`n}"

        try {
            # Create a short-lived PS shell bound to the target runspace,
            # execute the function definition, then dispose immediately.
            # After this, the function is defined in the runspace's session
            # state and can be called by any code running in that runspace.
            $ps = [System.Management.Automation.PowerShell]::Create()
            $ps.Runspace = $entry.Runspace
            $ps.AddScript($funcDefinition) | Out-Null
            $ps.Invoke() | Out-Null

            # Surface any errors that occurred during the definition
            if ($ps.HadErrors) {
                foreach ($err in $ps.Streams.Error) {
                    Write-Error "[Invoke-RunspaceFunctionInjection] Error defining '$funcName': $($err.Exception.Message)"
                }
                $success = $false
            } else {
                Write-Verbose "[Invoke-RunspaceFunctionInjection] Function '$funcName' injected into '$RunspaceName'."
            }

            $ps.Dispose()
        }
        catch {
            Write-Error "[Invoke-RunspaceFunctionInjection] Exception while injecting '$funcName': $($_.Exception.Message)"
            $success = $false
        }
    }

    return $success
}


# ___________________________________________________________________________
# FUNCTIONS: Write-ServerStatusFile / Remove-ServerStatusFile
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
<#
.SYNOPSIS
    Writes or removes the httpserver.status.json status file.

.DESCRIPTION
    These two functions implement the status file mechanism deferred from
    Phase 2.4. The status file allows external processes (scripts, tools,
    monitoring agents) to determine the server's current state, PID, port
    and start time by simply reading a JSON file - no HTTP request required.

    Write-ServerStatusFile: Called by Start-HTTPserver after successful
    launch and by the server loop on state changes.

    Remove-ServerStatusFile: Called by Stop-LocalHttpServer after clean
    shutdown to signal that no server is currently running.

    File location: <module root>\include\httpserver.status.json
    Encoding: UTF-8 (no BOM) for maximum cross-tool compatibility.
#>
function Write-ServerStatusFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('running', 'stopped', 'error')]
        [string]$Status
    )

    $statusPath = Join-Path $script:root "include\httpserver.status.json"

    $statusData = [ordered]@{
        status    = $Status
        pid       = $PID
        port      = $script:httpHost['port']
        wwwroot   = $script:httpHost['wwwroot']
        startTime = if ($Status -eq 'running') { (Get-Date).ToString('o') } else { $null }
        timestamp = (Get-Date).ToString('o')
    }

    try {
        $statusData | ConvertTo-Json -Depth 2 | Set-Content -Path $statusPath -Encoding UTF8
        Write-Verbose "[Write-ServerStatusFile] Status file written: $Status"
    }
    catch {
        Write-Warning "[Write-ServerStatusFile] Could not write status file: $($_.Exception.Message)"
    }
}

function Remove-ServerStatusFile {
    [CmdletBinding()]
    param()

    $statusPath = Join-Path $script:root "include\httpserver.status.json"

    if (Test-Path $statusPath) {
        try {
            Remove-Item $statusPath -Force
            Write-Verbose "[Remove-ServerStatusFile] Status file removed."
        }
        catch {
            Write-Warning "[Remove-ServerStatusFile] Could not remove status file: $($_.Exception.Message)"
        }
    }
}