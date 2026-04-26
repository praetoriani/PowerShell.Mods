<#
.SYNOPSIS
    Starts the local HTTP server in a background Runspace.

.DESCRIPTION
    Public orchestration function. Performs prechecks, creates a managed
    Runspace, injects all required variables and functions into it, then
    starts the server loop asynchronously via New-RunspaceJob.

    After this function returns the PowerShell console is immediately free
    for interactive use. The server runs in the background until
    Stop-LocalHttpServer is called.

    CALLING CHAIN:
    ---------------------------------------------------------------------
    local.httpserver.ps1 (launcher)
        └--► Start-HTTPserver            [this function]
                 ├-- New-ManagedRunspace      [private]
                 ├-- Set-RunspaceVariable     [private]  (×5)
                 ├-- Invoke-RunspaceFunctionInjection [private]
                 └-- New-RunspaceJob          [private]
                         └--► Start-HttpRunspace  [private, runs in Runspace]

    RUNSPACE SCOPE ISOLATION:
    ---------------------------------------------------------------------
    A Runspace has ZERO access to $script: variables of the host module.
    Every variable the server loop needs is explicitly injected via
    Set-RunspaceVariable BEFORE New-RunspaceJob is called.

    Variables injected:
        $httpHost        Hashtable  - Domain, port, wwwroot, error pages
        $httpRouter      Hashtable  - Control route path map
        $mimeType        Hashtable  - File extension → MIME type map
        $wwwRoot         String     - Resolved absolute wwwroot path
        $CancelToken     ManualResetEventSlim - Cooperative stop signal

    Functions injected via Invoke-RunspaceFunctionInjection:
        Invoke-RequestHandler - Handles static file requests
        Invoke-RouteHandler   - Handles /sys/ctrl/* control routes
        GetMimeType           - MIME type lookup (used by RequestHandler)

.PARAMETER Port
    TCP port number the server will listen on.
    Defaults to the port configured in SetCoreConfig / module.config.

.PARAMETER wwwRoot
    Filesystem path to the web root directory.
    Defaults to the path configured in SetCoreConfig / module.config.

.EXAMPLE
    Start-HTTPserver
    Start-HTTPserver -Port 9090
    Start-HTTPserver -Port 8080 -wwwRoot "C:\MyProject\wwwroot"

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : public/Start-HTTPserver.ps1
#>
function Start-HTTPserver {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$Port = $script:httpHost['port'],

        [Parameter(Mandatory = $false)]
        [string]$wwwRoot = $script:httpHost['wwwroot']
    )

    # ------------------------------------------------------------------
    # GUARD: Prevent double-start
    # ------------------------------------------------------------------
    # Test-RunspaceExists checks $script:RunspaceStore for an entry with
    # name 'http' and State = 'running'. If found, the server is already
    # running and we must not start a second instance - two HttpListeners
    # binding to the same port will throw "address already in use".

    if (Test-RunspaceExists -RunspaceName 'http') {
        Write-Warning "[Start-HTTPserver] Server is already running on port $($script:httpHost['port'])."
        Write-Warning "                  Use Stop-LocalHttpServer first, or Restart-LocalHttpServer."
        return
    }

    # ------------------------------------------------------------------
    # SECTION 1: System prechecks
    # ------------------------------------------------------------------
    # $script:syschecks is set to $true during module init (PSM1 Section 1)
    # and can be set to $false by system.precheck.ps1 if requirements fail.

    Write-Host "[INFO] Performing system prechecks..." -ForegroundColor Cyan

    if ($script:syschecks -eq $false) {
        Write-Error "[Start-HTTPserver] System prechecks failed. Server cannot start."
        return
    }

    Write-Host "[OK]   System prechecks passed." -ForegroundColor Green

    # ------------------------------------------------------------------
    # SECTION 2: Resolve and validate wwwRoot
    # ------------------------------------------------------------------
    # Resolve to an absolute path so the Runspace receives a canonical
    # filesystem path regardless of how the caller specified it.
    # [IO.Path]::GetFullPath() handles relative paths, trailing slashes, etc.

    $resolvedRoot = [System.IO.Path]::GetFullPath($wwwRoot)

    if (-not (Test-Path -Path $resolvedRoot -PathType Container)) {
        Write-Error "[Start-HTTPserver] wwwRoot directory not found: $resolvedRoot"
        return
    }

    Write-Host "[OK]   wwwRoot resolved: $resolvedRoot" -ForegroundColor Green
    Write-Host "[OK]   Port            : $Port"          -ForegroundColor Green

    # ------------------------------------------------------------------
    # SECTION 3: Create the managed Runspace
    # ------------------------------------------------------------------
    # New-ManagedRunspace:
    #   1. Creates a new Runspace with InitialSessionState.CreateDefault()
    #   2. Opens it (RunspaceState → Opened)
    #   3. Creates a ManualResetEventSlim as CancelToken
    #   4. Registers the entry in $script:RunspaceStore['http']
    #   5. Returns the store entry (PSCustomObject) for immediate use
    #
    # ApartmentState MTA (Multi-Threaded Apartment) is correct for an
    # HttpListener server. STA would be required only for WinForms/WPF UI.

    Write-Host "[INFO] Creating HTTP Runspace..." -ForegroundColor Cyan

    $rsEntry = New-ManagedRunspace -Name 'http' `
                                   -ApartmentState ([System.Threading.ApartmentState]::MTA)

    if ($null -eq $rsEntry) {
        Write-Error "[Start-HTTPserver] New-ManagedRunspace returned null. Cannot continue."
        return
    }

    Write-Host "[OK]   Runspace created and registered in RunspaceStore." -ForegroundColor Green

    # ------------------------------------------------------------------
    # SECTION 4: Inject variables into the Runspace
    # ------------------------------------------------------------------
    # The Runspace has no access to $script: variables from this module.
    # SessionStateProxy.SetVariable() is the only correct way to transfer
    # values from the host session into an already-opened Runspace.
    #
    # Order matters: inject ALL variables BEFORE calling New-RunspaceJob.
    # After BeginInvoke() the Runspace is executing and variable injection
    # via SessionStateProxy may race with the running code.

    Write-Host "[INFO] Injecting variables into Runspace..." -ForegroundColor Cyan

    # $httpHost - core configuration hashtable (domain, port, wwwroot, error pages, etc.)
    Set-RunspaceVariable -RunspaceName 'http' `
                         -VariableName 'httpHost' `
                         -Value $script:httpHost

    # $httpRouter - control route map: route-key → URL path
    # Example: @{ stop = '/sys/ctrl/http-stop'; status = '/sys/ctrl/http-getstatus'; ... }
    Set-RunspaceVariable -RunspaceName 'http' `
                         -VariableName 'httpRouter' `
                         -Value $script:httpRouter

    # $mimeType - file extension → MIME type map used by Invoke-RequestHandler
    Set-RunspaceVariable -RunspaceName 'http' `
                         -VariableName 'mimeType' `
                         -Value $script:mimeType

    # $wwwRoot - resolved absolute path to the web root directory
    # We inject the already-resolved $resolvedRoot, not the raw $wwwRoot param,
    # so the Runspace always works with a canonical absolute path.
    Set-RunspaceVariable -RunspaceName 'http' `
                         -VariableName 'wwwRoot' `
                         -Value $resolvedRoot

    # $CancelToken - ManualResetEventSlim stop signal
    # Created by New-ManagedRunspace and stored in the RunspaceStore entry.
    # Stop-ManagedRunspace calls $CancelToken.Set() to signal the server loop
    # to exit on its next poll interval (≤ PollIntervalMs, default 500 ms).
    Set-RunspaceVariable -RunspaceName 'http' `
                         -VariableName 'CancelToken' `
                         -Value $rsEntry.CancelToken

    Write-Host "[OK]   Variables injected (httpHost, httpRouter, mimeType, wwwRoot, CancelToken)." -ForegroundColor Green

    # ------------------------------------------------------------------
    # SECTION 5: Inject required functions into the Runspace
    # ------------------------------------------------------------------
    # The Runspace's InitialSessionState (CreateDefault) contains standard
    # PowerShell cmdlets but NOT the module's private functions. We inject
    # them by re-defining them inside the Runspace via PowerShell.AddScript().
    #
    # Functions injected:
    #   Invoke-RequestHandler - static file handler (called in the server loop)
    #   Invoke-RouteHandler   - /sys/ctrl/* handler (called in the server loop)
    #   GetMimeType           - MIME lookup helper (called by RequestHandler)
    #
    # Invoke-RunspaceFunctionInjection reads each function's ScriptBlock via
    # Get-Command, wraps it in "function Name { ... }" and executes it inside
    # the Runspace - making the function available as a normal PS function.

    Write-Host "[INFO] Injecting functions into Runspace..." -ForegroundColor Cyan

    $injectionResult = Invoke-RunspaceFunctionInjection `
        -RunspaceName  'http' `
        -FunctionNames @(
            'Write-RunspaceLog',
            'Invoke-RequestHandler',
            'Invoke-RouteHandler',
            'GetMimeType'
        )

    if (-not $injectionResult) {
        Write-Error "[Start-HTTPserver] Function injection failed. Cleaning up Runspace."
        # Clean up the already-created Runspace to avoid orphaned entries
        Stop-ManagedRunspace -RunspaceName 'http' -TimeoutMs 0
        return
    }

    Write-Host "[OK]   Functions injected (Write-RunspaceLog, Invoke-RequestHandler, Invoke-RouteHandler, GetMimeType)." -ForegroundColor Green

    # ------------------------------------------------------------------
    # SECTION 6: Start the server loop asynchronously
    # ------------------------------------------------------------------
    # New-RunspaceJob:
    #   1. Creates a PowerShell shell ($ps) and binds it to the Runspace
    #   2. Adds the ScriptBlock and parameters
    #   3. Calls $ps.BeginInvoke() - NON-BLOCKING, returns IAsyncResult immediately
    #   4. Stores the PS shell and Handle in $script:RunspaceStore['http']
    #   5. Sets State → 'running'
    #
    # We pass the ScriptBlock of Start-HttpRunspace (which is already dot-sourced
    # into module scope) via Get-Command. This avoids embedding a giant literal
    # ScriptBlock here in Start-HTTPserver and keeps the code DRY.
    #
    # The -Parameters hashtable passes the Port and PollIntervalMs values as
    # named parameters to the Start-HttpRunspace param() block.

    Write-Host "[INFO] Starting server loop in Runspace..." -ForegroundColor Cyan

    $serverScriptBlock = (Get-Command -Name 'Start-HttpRunspace').ScriptBlock

    $jobStarted = New-RunspaceJob `
        -RunspaceName 'http' `
        -ScriptBlock  $serverScriptBlock `
        -Parameters   @{
            Port           = $Port
            PollIntervalMs = 500
        }

    if (-not $jobStarted) {
        Write-Error "[Start-HTTPserver] New-RunspaceJob failed. Server could not be started."
        Stop-ManagedRunspace -RunspaceName 'http' -TimeoutMs 0
        return
    }

    # ------------------------------------------------------------------
    # SECTION 7: Write status file
    # ------------------------------------------------------------------
    # ServerStatusFile.ps1 (private) writes a JSON status snapshot to
    # include\httpserver.status.json. External tools (tray, pipe clients)
    # can read this file to check whether the server is running without
    # having to inspect the RunspaceStore directly.

    Write-ServerStatusFile -Status 'running'

    # ------------------------------------------------------------------
    # SECTION 8: Mode-specific post-start handling
    # ------------------------------------------------------------------
    # In 'hidden' mode the console window is hidden after the server starts
    # so the user sees no window at all. In 'console' mode the window stays
    # open - the caller (launcher) is responsible for keeping the process
    # alive (see local.httpserver.ps1 for the wait-loop pattern).

    if ($script:config['Mode'] -eq 'hidden') {
        Write-Verbose "[Start-HTTPserver] Mode = hidden - hiding console window."
        Hide-ConsoleWindow
    }

    # ------------------------------------------------------------------
    # SUCCESS: Server is running in the background
    # ------------------------------------------------------------------
    Start-Sleep -Milliseconds 3000
    Write-Host ""
    Write-Host "========================================"  -ForegroundColor Green
    Write-Host "  Local HTTP Server started (Runspace)"   -ForegroundColor Green
    Write-Host "  URL     : http://$($script:httpHost['domain']):$Port/" -ForegroundColor Green
    Write-Host "  wwwRoot : $resolvedRoot"                -ForegroundColor Green
    Write-Host "  Mode    : $($script:config['Mode'])"    -ForegroundColor Green
    Write-Host "  Stop    : Stop-LocalHttpServer"         -ForegroundColor Yellow
    Write-Host "  Status  : Get-LocalHttpServerStatus"    -ForegroundColor Yellow
    Write-Host "========================================"  -ForegroundColor Green
    Write-Host ""

    # Return nothing - the function exits here and the console is free.
    # The server continues running in the background Runspace.
}