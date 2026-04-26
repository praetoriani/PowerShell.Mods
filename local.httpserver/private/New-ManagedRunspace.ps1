<#
.SYNOPSIS
    Creates a new, fully configured PowerShell Runspace and registers it
    in the central $script:RunspaceStore.

.DESCRIPTION
    New-ManagedRunspace is always the FIRST function to call when launching
    any background task in local.httpserver. It handles three distinct jobs:

      1. Build the Runspace object with the correct threading model and
         apartment state for the intended workload (HTTP server = MTA,
         WinForms / WPF systray = STA).

      2. Open the Runspace so it is ready to receive variable injections
         (Set-RunspaceVariable) and function injections
         (Invoke-RunspaceFunctionInjection) before any code runs.

      3. Create a ManualResetEventSlim cancellation token and register
         the complete entry in $script:RunspaceStore under the given Name.

    After this function returns, the Runspace is OPEN but NOT executing
    any code yet. The next steps are:
      - Set-RunspaceVariable        (inject config, the cancel token, etc.)
      - Invoke-RunspaceFunctionInjection  (inject private functions)
      - New-RunspaceJob             (start the actual background script)

    IMPORTANT: $script:RunspaceStore must have been initialised (Section 2b
    of local.httpserver.psm1) before this function is called. It is always
    available because the PSM1 bootstrapping runs before any dot-sourced
    function is invoked.

.PARAMETER Name
    Short, unique identifier for this Runspace. Used as the dictionary key
    in $script:RunspaceStore. Recommended names: 'http', 'pipe', 'tray'.
    The name is also stored inside the entry for diagnostic purposes.

.PARAMETER ApartmentState
    Threading apartment model for the OS thread that the Runspace runs on.

    MTA (default) - Multi-Threaded Apartment.
        Correct for all background server work: HTTP listener, named pipe
        server, file watchers. This is the default for PowerShell itself.

    STA - Single-Threaded Apartment.
        REQUIRED for any runspace that creates WinForms or WPF objects
        (systray icon, desktop UI in Phase 6). COM objects that are
        apartment-threaded (e.g. Shell.Application) also require STA.
        The apartment state must be set before Open() is called -
        changing it afterward has no effect, which is why this parameter
        exists from Phase 3 onward even though STA is only used in Phase 6.

.OUTPUTS
    PSCustomObject - the store entry that was created and registered.
    Returns $null if the Runspace could not be created (duplicate name or
    Open() failure). Always check the return value before proceeding.

.EXAMPLE
    # Standard HTTP server runspace (MTA is the default)
    $entry = New-ManagedRunspace -Name 'http'

    # Future systray runspace that will host WinForms (Phase 6)
    $entry = New-ManagedRunspace -Name 'tray' -ApartmentState STA

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/New-ManagedRunspace.ps1
#>
function New-ManagedRunspace {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [System.Threading.ApartmentState]
        $ApartmentState = [System.Threading.ApartmentState]::MTA
    )

    # ------------------------------------------------------------------
    # Guard: reject duplicate registration
    # ------------------------------------------------------------------
    # If a runspace with this name already exists in the store, refuse to
    # overwrite it silently. The caller must call Stop-ManagedRunspace
    # first to cleanly dispose the existing runspace before creating a
    # new one under the same name.
    if ($script:RunspaceStore.ContainsKey($Name)) {
        Write-Warning "[New-ManagedRunspace] A runspace named '$Name' is already registered. Call Stop-ManagedRunspace -RunspaceName '$Name' first."
        return $null
    }

    # ------------------------------------------------------------------
    # Step 1: Build the InitialSessionState
    # ------------------------------------------------------------------
    # CreateDefault() loads the standard built-in cmdlet set that the
    # server loop depends on (Write-Host, New-Object, Add-Type, etc.).
    #
    # CreateDefault() is used instead of CreateDefault2() to maintain
    # full PowerShell 5.1 compatibility. CreateDefault2() exists only in
    # PowerShell 7+ and would break on older systems.
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

    # ------------------------------------------------------------------
    # Step 2: Create the Runspace object
    # ------------------------------------------------------------------
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)

    # ApartmentState MUST be set before Open() is called.
    # Attempting to change it after Open() has no effect.
    $rs.ApartmentState = $ApartmentState

    # ReuseThread instructs the runspace to keep the same OS thread for
    # the lifetime of the runspace instead of pulling a new thread from
    # the ThreadPool on every BeginInvoke() call. For a long-running
    # server loop this eliminates per-call thread-spin overhead entirely.
    $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread

    # ------------------------------------------------------------------
    # Step 3: Open the Runspace
    # ------------------------------------------------------------------
    # Open() allocates the OS thread, initialises the session state and
    # makes the runspace ready to accept variable/function injections.
    # No user code is running at this point.
    try {
        $rs.Open()
        Write-Verbose "[New-ManagedRunspace] Runspace '$Name' opened successfully (ApartmentState: $ApartmentState)."
    }
    catch {
        Write-Error "[New-ManagedRunspace] Failed to open runspace '$Name': $($_.Exception.Message)"
        # Dispose the partially constructed runspace to avoid a handle leak
        try { $rs.Dispose() } catch { }
        return $null
    }

    # ------------------------------------------------------------------
    # Step 4: Create the cancellation token (ManualResetEventSlim)
    # ------------------------------------------------------------------
    # ManualResetEventSlim is a lightweight .NET signalling primitive that
    # is thread-safe without requiring a kernel mutex.
    #
    # How it works in practice:
    #   - Initial state is $false  →  "keep running"
    #   - Stop-ManagedRunspace calls $CancelToken.Set()  →  IsSet = $true
    #   - The server loop checks $CancelToken.IsSet after each
    #     BeginGetContext() poll timeout (500 ms) and exits when $true.
    #
    # This approach is safer than a boolean flag ($script:shouldStop)
    # because ManualResetEventSlim is designed for concurrent access -
    # the main thread writes and the background thread reads without risk
    # of a torn read or a missed update.
    $cancelToken = New-Object System.Threading.ManualResetEventSlim($false)

    # ------------------------------------------------------------------
    # Step 5: Build the store entry and register it
    # ------------------------------------------------------------------
    # The PSCustomObject layout matches the schema documented in Section 2b
    # of local.httpserver.psm1. All fields that are populated later (by
    # New-RunspaceJob) are initialised to $null here so callers can always
    # do a null-check without risking a "property does not exist" error.
    $storeEntry = [PSCustomObject]@{
        Runspace    = $rs           # The Runspace object itself
        PowerShell  = $null         # Set by New-RunspaceJob (PowerShell shell)
        Handle      = $null         # Set by New-RunspaceJob (IAsyncResult)
        CancelToken = $cancelToken  # ManualResetEventSlim for clean shutdown
        StartTime   = Get-Date      # Timestamp for uptime calculation
        State       = 'created'     # Lifecycle state: created → running → stopped
        Name        = $Name         # Mirrors the store key for diagnostics
    }

    $script:RunspaceStore[$Name] = $storeEntry

    Write-Verbose "[New-ManagedRunspace] Runspace '$Name' registered in RunspaceStore (State: created)."
    return $storeEntry
}
