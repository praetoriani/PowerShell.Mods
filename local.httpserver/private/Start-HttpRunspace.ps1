<#
.SYNOPSIS
    Private: The server loop ScriptBlock that runs inside the HTTP Runspace.

.DESCRIPTION
    Start-HttpRunspace is a PRIVATE function. It is never called directly.
    It contains the complete server loop that Start-HTTPserver (public)
    packages as a ScriptBlock and passes to New-RunspaceJob via BeginInvoke().


    CALLING CHAIN (for orientation)

    local.httpserver.ps1 (launcher)
       └--► Start-HTTPserver          [public]
                 ├-- New-ManagedRunspace       [private]
                 ├-- Set-RunspaceVariable      [private]  (×6)
                 ├-- Invoke-RunspaceFunctionInjection [private]
                 └-- New-RunspaceJob           [private]
                         └--► Start-HttpRunspace  [private] ◄-- HERE
                                (runs inside the Runspace)

    
    SCOPE ISOLATION - INJECTED VARIABLES:
    ----------------------------------------------------------------------
    A Runspace has ZERO access to $script: variables of the host module.
    Every variable listed below must be injected via Set-RunspaceVariable
    BEFORE New-RunspaceJob is called. If any injection is missing, the
    server loop will fail with a NullReferenceException or silent misbehavior.

    Variable         Injected by         Type            Purpose
    ---------------------------------------------------------------------
    $httpHost        Set-RunspaceVariable  [hashtable]   Domain, port, wwwroot,
                                                          homepage, error pages, etc.
    $httpRouter      Set-RunspaceVariable  [hashtable]   Control route map
                                                          (path → handler name)
    $mimeType        Set-RunspaceVariable  [hashtable]   File extension → MIME map
    $wwwRoot         Set-RunspaceVariable  [string]      Resolved absolute filesystem
                                                          path for static files
    $CancelToken     Set-RunspaceVariable  [ManualResetEventSlim]
                                                          Cooperative stop signal.
                                                          Set() by Stop-ManagedRunspace
                                                          to request a clean shutdown.
    ----------------------------------------------------------------------

    INJECTED FUNCTIONS:
    ----------------------------------------------------------------------
    Invoke-RequestHandler  - Handles GET/HEAD requests for static files
    Invoke-RouteHandler    - Handles control route calls (/sys/ctrl/*)
    GetMimeType            - MIME type detection (used by Invoke-RequestHandler)
    ----------------------------------------------------------------------

    NON-BLOCKING ACCEPT PATTERN (the most important design decision):
    ----------------------------------------------------------------------
    The classic HttpListener.GetContext() blocks the thread indefinitely
    until a request arrives. In a Runspace context this means Stop-ManagedRunspace
    would have to wait for the NEXT HTTP request before the loop can check
    the CancelToken - which could be minutes or never.

    Solution: BeginGetContext() + AsyncWaitHandle.WaitOne(PollIntervalMs)

        $asyncResult = $listener.BeginGetContext($null, $null)
        $arrived     = $asyncResult.AsyncWaitHandle.WaitOne(PollIntervalMs)

    WaitOne(PollIntervalMs) blocks for AT MOST PollIntervalMs milliseconds.
    If no request arrives within that window, it returns $false and the loop
    immediately checks $CancelToken.IsSet. If the token is set → clean exit.
    If a request arrived within the window → $true → EndGetContext() → dispatch.

    Result: the server stops within at most PollIntervalMs milliseconds after
    Stop-ManagedRunspace sets the CancelToken. Default PollIntervalMs = 500.

    CONTROL ROUTE SECURITY (IP Guard):
    ----------------------------------------------------------------------
    Routes under /sys/ctrl/ are only accessible from localhost (127.0.0.1
    or ::1). Any request from a non-localhost IP receives a 403 Forbidden
    response immediately, before any routing logic is executed. This guard
    is the innermost line of defence - the outer line is the firewall or
    OS-level binding that prevents the server from listening on a public
    network interface in the first place.

    REQUEST COUNTER:
    ----------------------------------------------------------------------
    The variable $requestCount is incremented for every successfully
    accepted request. It is readable from outside the Runspace via:
        Get-RunspaceVariable -RunspaceName 'http' -VariableName 'requestCount'
    This allows Get-LocalHttpServerStatus to display live request counts.

.PARAMETER Port
    TCP port on which the HttpListener will accept connections.
    Defaults to the value stored in $httpHost['port'] at injection time.
    Pass explicitly only when the public Start-HTTPserver forwards a
    -Port override from the caller.

.PARAMETER PollIntervalMs
    How long (in milliseconds) WaitOne() waits for an incoming request
    before looping back to check $CancelToken.IsSet.

    Lower value → faster response to Stop-ManagedRunspace, more CPU.
    Higher value → slower shutdown response, less CPU during idle periods.

    Default: 500 ms is a good balance. The server is "live" (accepts
    requests immediately) but can be stopped within half a second.
    Values below 50 ms are not recommended (busy-polling overhead).

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/Start-HttpRunspace.ps1
#>
function Start-HttpRunspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Port = 8080,

        [Parameter(Mandatory = $false)]
        [ValidateRange(50, 5000)]
        [int]$PollIntervalMs = 500
    )

    # ------------------------------------------------------------------
    # Runtime variables - readable from outside via Get-RunspaceVariable
    # ------------------------------------------------------------------

    # Counts every successfully accepted request (EndGetContext succeeded).
    # Exposed to Get-LocalHttpServerStatus for live telemetry.
    $requestCount   = 0

    # Tracks the last error message for diagnostics.
    # Set on every caught exception; cleared on clean loop iteration.
    $lastError      = $null

    # Holds the HttpListener instance. Stored as a named variable so that
    # Stop-ManagedRunspace can read it via SessionStateProxy and call
    # $listener.Stop() to unblock a pending BeginGetContext().
    $httpListener   = $null

    # ------------------------------------------------------------------
    # Validate injected variables before touching any .NET objects
    # ------------------------------------------------------------------
    # Every variable in this block was injected by Start-HTTPserver via
    # Set-RunspaceVariable. If any is missing or null, we write a clear
    # error and exit - an unclear NullReferenceException deep inside the
    # loop is much harder to diagnose than this explicit check here.

    if ($null -eq $httpHost) {
        Write-RunspaceLog "[Start-HttpRunspace] Required variable `$httpHost was not injected. Aborting." `
            -ForegroundColor White -BackgroundColor DarkRed -Prefix "ERROR"
        return
    }
    if ($null -eq $mimeType) {
        Write-RunspaceLog "[Start-HttpRunspace] Required variable `$mimeType was not injected. Aborting." `
            -ForegroundColor White -BackgroundColor DarkRed -Prefix "ERROR"
        return
    }
    if ($null -eq $CancelToken) {
        Write-RunspaceLog "[Start-HttpRunspace] Required variable `$CancelToken was not injected. Aborting." `
            -ForegroundColor White -BackgroundColor DarkRed -Prefix "ERROR"
        return
    }
    if ([string]::IsNullOrEmpty($wwwRoot) -or -not (Test-Path $wwwRoot)) {
        Write-RunspaceLog "[ERROR] [Start-HttpRunspace] Required variable `$wwwRoot is missing or path does not exist: '$wwwRoot'. Aborting." `
            -ForegroundColor White -BackgroundColor DarkRed -Prefix "ERROR"
        return
    }

    # ------------------------------------------------------------------
    # Build the listener prefix from injected $httpHost config
    # ------------------------------------------------------------------
    # The prefix format required by HttpListener is:
    #     http://<host>:<port>/
    # The trailing slash is MANDATORY - HttpListener rejects prefixes
    # without it with an ArgumentException ("The prefix ... is invalid").
    #
    # If $httpHost does not contain a 'domain' key, we fall back to '+',
    # which is the HttpListener wildcard for "all hostnames on this port".
    # The explicit '$Port' parameter takes precedence over $httpHost['port']
    # so that Restart-LocalHttpServer can override the port at runtime.

    $domain = if ($httpHost.ContainsKey('domain') -and
                  -not [string]::IsNullOrEmpty($httpHost['domain'])) {
        $httpHost['domain']
    } else {
        'localhost'
    }

    $listenerPrefix = "http://${domain}:${Port}/"

    # ------------------------------------------------------------------
    # Main try/finally block - ensures $httpListener is always closed
    # ------------------------------------------------------------------
    try {

        # Create and configure the HttpListener
        $httpListener = New-Object System.Net.HttpListener
        $httpListener.Prefixes.Add($listenerPrefix)

        # AuthenticationSchemes.Anonymous: the server does not challenge
        # clients for credentials. This is correct for a local static file
        # server - authentication is handled at the application layer if
        # needed, not at the transport layer.
        $httpListener.AuthenticationSchemes = [System.Net.AuthenticationSchemes]::Anonymous

        $httpListener.Start()

        Write-RunspaceLog ""
        Write-RunspaceLog "HTTP server is listening on $listenerPrefix" -ForegroundColor Green   -Prefix "OK"
        Write-RunspaceLog "wwwRoot        : $wwwRoot"                   -ForegroundColor Green   -Prefix "OK"
        Write-RunspaceLog "Poll interval  : ${PollIntervalMs}ms"        -ForegroundColor Green   -Prefix "OK"

        # ==============================================================
        # SERVER LOOP
        # ==============================================================
        # Each iteration represents ONE request-accept cycle.
        # The loop continues as long as:
        #   a) The HttpListener is listening (IsListening = $true), AND
        #   b) The CancelToken has NOT been set ($CancelToken.IsSet = $false)
        #
        # Stop-ManagedRunspace breaks this loop by:
        #   1. Setting $CancelToken  → loop condition (b) becomes false
        #   2. Calling $listener.Stop() → forces any pending BeginGetContext()
        #      to complete immediately with HttpListenerException code 995

        while ($httpListener.IsListening -and -not $CancelToken.IsSet) {

            # ----------------------------------------------------------
            # Phase 1: Non-blocking accept with poll timeout
            # ----------------------------------------------------------
            # BeginGetContext() starts an asynchronous wait for the next
            # incoming HTTP request. It returns an IAsyncResult immediately
            # without blocking the thread.
            #
            # WaitOne(PollIntervalMs):
            #   Returns $true  → a request arrived; call EndGetContext()
            #   Returns $false → timeout elapsed; loop back and re-check
            #                    $CancelToken.IsSet and $httpListener.IsListening

            $asyncResult = $null
            try {
                $asyncResult = $httpListener.BeginGetContext($null, $null)
            }
            catch [System.Net.HttpListenerException] {
                # ErrorCode 995 = ERROR_OPERATION_ABORTED
                # This is thrown when Stop() is called while BeginGetContext()
                # is in progress. This is a NORMAL, EXPECTED shutdown path -
                # not an error. Break the loop silently.
                if ($_.Exception.ErrorCode -eq 995) {
                    Write-RunspaceLog "BeginGetContext() aborted (995) - clean shutdown." `
                                    -ForegroundColor DarkGray -Prefix "INFO"
                    break
                }
                # Any other HttpListenerException is genuinely unexpected.
                $lastError = $_.Exception.Message
                Write-RunspaceLog "BeginGetContext() failed (code $($_.Exception.ErrorCode)): $lastError" `
                                -ForegroundColor Yellow -Prefix "WARN"
                break
            }
            catch {
                $lastError = $_.Exception.Message
                Write-RunspaceLog "[WARN] [Start-HttpRunspace] BeginGetContext() unexpected error: $lastError" `
                                -ForegroundColor Yellow -Prefix "WARN"
                break
            }

            # Wait up to PollIntervalMs for a request to arrive
            $requestArrived = $asyncResult.AsyncWaitHandle.WaitOne($PollIntervalMs)

            # Check stop conditions first - even if a request arrived,
            # honour the CancelToken immediately if it was set during WaitOne()
            if ($CancelToken.IsSet -or -not $httpListener.IsListening) {
                # A request may have arrived simultaneously with the stop signal.
                # We do NOT process it - the server is shutting down.
                # The client will receive a connection reset, which is acceptable
                # during a deliberate server shutdown.
                Write-RunspaceLog "CancelToken set or listener stopped. Exiting loop." `
                                -ForegroundColor DarkGray -Prefix "INFO"
                break
            }

            # No request within the poll window → loop back
            if (-not $requestArrived) {
                continue
            }

            # ----------------------------------------------------------
            # Phase 2: Accept the request (EndGetContext)
            # ----------------------------------------------------------
            $context = $null
            try {
                $context = $httpListener.EndGetContext($asyncResult)
            }
            catch [System.Net.HttpListenerException] {
                if ($_.Exception.ErrorCode -eq 995) {
                    [Console]::WriteLine("[VERBOSE] [Start-HttpRunspace] EndGetContext() aborted (995) - clean shutdown.")
                    break
                }
                Write-RunspaceLog "EndGetContext() failed (code $($_.Exception.ErrorCode)): $($_.Exception.Message)" `
                                -ForegroundColor Yellow -Prefix "WARN"
                continue    # skip this cycle, try again
            }
            catch {
                Write-RunspaceLog "[WARN] [Start-HttpRunspace] EndGetContext() unexpected error: $($_.Exception.Message)" `
                                -ForegroundColor Yellow -Prefix "WARN"
                continue
            }

            # ----------------------------------------------------------
            # Phase 3: Log the request
            # ----------------------------------------------------------
            $requestCount++

            # Refresh Telemetry (thread-safe, no SessionStateProxy!)
            if ($null -ne $RunspaceTelemetry) {
                $RunspaceTelemetry['http.requestCount'] = $requestCount
                $RunspaceTelemetry['http.lastRequest']  = $timestamp
                $RunspaceTelemetry['http.lastPath']     = $urlPath
            }

            $req       = $context.Request
            $urlPath   = $req.RawUrl.Split('?')[0]
            $clientIP  = $req.RemoteEndPoint.Address.ToString()
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            Write-RunspaceLog "[$timestamp] #$requestCount $($req.HttpMethod) $urlPath  [from $clientIP]" `
                            -ForegroundColor Cyan -Prefix "REQUEST"

            # ----------------------------------------------------------
            # Phase 4: IP Guard for control routes
            # ----------------------------------------------------------
            # Any path that starts with /sys/ctrl/ (case-insensitive) is a
            # control route. Control routes are ONLY accessible from localhost.
            # This check is performed here, in the loop, rather than inside
            # Invoke-RouteHandler, so that the guard runs before ANY routing
            # logic is executed - including route-lookup table access.

            $isSysCtrlPath = $urlPath.StartsWith(
                '/sys/ctrl/',
                [System.StringComparison]::OrdinalIgnoreCase
            )

            if ($isSysCtrlPath) {
                $isLocalhost = ($clientIP -eq '127.0.0.1') -or
                               ($clientIP -eq '::1')       -or
                               ($clientIP -eq '0:0:0:0:0:0:0:1')   # IPv6 full form

                if (-not $isLocalhost) {
                    # Remote client attempting to access a control route.
                    # Respond with 403 and close the connection immediately.
                    Write-RunspaceLog "Control route access denied for IP: $clientIP -> $urlPath" `
                                    -ForegroundColor Yellow -Prefix "WARN"
                    try {
                        $denyBytes = [System.Text.Encoding]::UTF8.GetBytes("403 Forbidden")
                        $context.Response.StatusCode      = 403
                        $context.Response.ContentType     = "text/plain; charset=utf-8"
                        $context.Response.ContentLength64 = $denyBytes.Length
                        $context.Response.OutputStream.Write($denyBytes, 0, $denyBytes.Length)
                        $context.Response.OutputStream.Close()
                    }
                    catch {
                        Write-RunspaceLog "[Start-HttpRunspace] Could not send 403 for IP guard: $($_.Exception.Message)" `
                            -ForegroundColor DarkGray -Prefix "INFO"
                    }
                    continue    # next request
                }
            }

            # ----------------------------------------------------------
            # Phase 5: Dispatch to the appropriate handler
            # ----------------------------------------------------------
            # Routing decision:
            #   /sys/ctrl/* → Invoke-RouteHandler  (control plane)
            #   everything else → Invoke-RequestHandler  (static files)
            #
            # Both functions were injected into this Runspace by
            # Invoke-RunspaceFunctionInjection before the loop started.
            # They are available as normal functions - no special calling
            # convention required.

            try {
                if ($isSysCtrlPath) {
                    # Control route - handler owns the full response lifecycle
                    Invoke-RouteHandler -Context $context -UrlPath $urlPath
                }
                else {
                    # -------------------------------------------------------
                    # Static file request - dispatch to Invoke-RequestHandler.
                    #
                    # We pass three parameters explicitly:
                    #
                    # -Context    The HttpListenerContext for this request.
                    #             Contains Request, Response and User objects.
                    #
                    # -WwwRoot    The resolved absolute filesystem path for
                    #             the wwwroot directory. Passed explicitly so
                    #             Invoke-RequestHandler does not need to resolve
                    #             it from $httpHost internally (defensive design).
                    #
                    # -ErrorPages The hashtable of custom error page paths from
                    #             $httpHost['error']. Passed explicitly here for
                    #             the same reason: Invoke-RequestHandler no longer
                    #             reads $script:httpHost - it only uses what it
                    #             receives as parameters. This makes the function
                    #             fully self-contained and Runspace-safe.
                    #
                    # $httpHost and $wwwRoot are both plain variables injected
                    # into this Runspace via Set-RunspaceVariable. No $script:
                    # prefix is needed or valid here.
                    # -------------------------------------------------------
                    $errorPages = if ($null -ne $httpHost -and $httpHost.ContainsKey('error') -and
                                      $null -ne $httpHost['error']) {
                        # Safely read the error pages hashtable from injected $httpHost.
                        $httpHost['error']
                    } else {
                        # No error pages configured - pass an empty hashtable.
                        # This prevents null-reference errors in Invoke-RequestHandler's
                        # ContainsKey() calls for 404, 500, 403 etc.
                        @{}
                    }

                    Invoke-RequestHandler -Context $context `
                                          -WwwRoot $wwwRoot `
                                          -ErrorPages $errorPages
                }
            }
            catch {
                # Last-resort catch: if a handler throws an unhandled exception,
                # log it and attempt to send a 500 response if the stream is
                # still open. The server loop continues - one bad request should
                # not kill the entire server.
                $lastError = $_.Exception.Message
                Write-RunspaceLog "Unhandled exception in request handler: $lastError" `
                                -ForegroundColor White -BackgroundColor Red -Prefix "ERROR"

                try {
                    if ($context.Response.OutputStream.CanWrite) {
                        $errBytes = [System.Text.Encoding]::UTF8.GetBytes("500 Internal Server Error")
                        $context.Response.StatusCode      = 500
                        $context.Response.ContentType     = "text/plain; charset=utf-8"
                        $context.Response.ContentLength64 = $errBytes.Length
                        $context.Response.OutputStream.Write($errBytes, 0, $errBytes.Length)
                        $context.Response.OutputStream.Close()
                    }
                }
                catch {
                    # Stream already closed by the handler - nothing to do
                    Write-RunspaceLog "[Start-HttpRunspace] Could not send 500 fallback: $($_.Exception.Message)" `
                        -ForegroundColor DarkGray -Prefix "INFO"
                }
            }

        }
        # ==============================================================
        # END SERVER LOOP
        # ==============================================================

    }
    catch {
        # Fatal exception outside the loop (e.g. HttpListener.Start() failed
        # because the port is already in use, or the prefix is invalid).
        $lastError = $_.Exception.Message
        Write-RunspaceLog "Fatal error - server could not start or crashed: $lastError" `
                        -ForegroundColor White -BackgroundColor DarkRed -Prefix "ERROR"
    }
    finally {
        # ------------------------------------------------------------------
        # Guaranteed cleanup: always runs, even on unhandled exceptions
        # ------------------------------------------------------------------
        # Close the HttpListener. This releases the TCP port binding and
        # frees the underlying kernel socket handle. IsListening becomes
        # $false after Close() completes.
        #
        # We call both Close() and then check CanClose to handle the edge
        # case where Start() was never reached (e.g. prefix error).
        if ($null -ne $httpListener) {
            try {
                if ($httpListener.IsListening) {
                    $httpListener.Stop()
                }
                $httpListener.Close()
            }
            catch {
                Write-RunspaceLog "[Start-HttpRunspace] HttpListener cleanup error (non-fatal): $($_.Exception.Message)" `
                    -ForegroundColor DarkGray -Prefix "INFO"
            }
        }

        Write-RunspaceLog ""
        Write-RunspaceLog "HTTP server stopped. Total requests served: $requestCount" `
                        -ForegroundColor Cyan -Prefix "INFO"
    }
}
