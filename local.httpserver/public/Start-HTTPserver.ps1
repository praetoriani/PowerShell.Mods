<#
.SYNOPSIS
    Starts the local HTTP server

.DESCRIPTION
    Public function to start the local HTTP server with specified configuration.
    Performs system prechecks, initializes the HttpListener, and processes incoming requests.

.PARAMETER Port
    The port number to listen on (default: 8080)

.PARAMETER wwwRoot
    The root directory for serving files (default: ./wwwroot)

.EXAMPLE
    Start-HTTPserver
    Start-HTTPserver -Port 8080 -wwwRoot "C:\inetpub\wwwroot"

.NOTES
    Author: praetoriani
    Version: 1.0
#>
function Start-HTTPserver {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [int]$Port = $script:httpHost['port'],

        [Parameter(Mandatory = $false)]
        [string]$wwwRoot = $script:httpHost['wwwroot']
    )

    # Request counter for logging
    $requestCount = 0

    # Record the exact time the server started.
    # This value is used later by the /sys/ctrl/http-getstatus route
    # to calculate and display the server uptime.
    $script:serverStartTime = Get-Date

    # Reboot flag: set to $false on every (re)start.
    # The /sys/ctrl/http-reboot route sets this to $true.
    # After the while-loop ends, we check this flag to decide
    # whether to restart the server or exit completely.
    $script:shouldReboot = $false    

    try {
        # ----------------------------------------------------------------
        # -> SECTION 1: System prechecks
        # ----------------------------------------------------------------
        Write-Host "[INFO] Performing system prechecks..." -ForegroundColor Cyan
        
        if ($script:syschecks -eq $false) {
            Write-Error "System precheck failed. Server cannot start."
            return
        }

        Write-Host "[OK] System prechecks passed" -ForegroundColor Green

        # ----------------------------------------------------------------
        # -> SECTION 2: Initialize configuration
        # ----------------------------------------------------------------
        Write-Host "[INFO] Initializing server configuration..." -ForegroundColor Cyan
        
        # Set core configuration
        $script:Port = $Port
        $script:wwwRoot = $wwwRoot
        
        # Resolve and validate wwwRoot path
        $script:wwwRoot = [System.IO.Path]::GetFullPath($script:wwwRoot)
        
        if (-not (Test-Path -Path $script:wwwRoot)) {
            Write-Error "wwwRoot directory does not exist: $($script:wwwRoot)"
            return
        }

        Write-Host "[OK] Server will serve files from: $($script:wwwRoot)" -ForegroundColor Green
        Write-Host "[OK] Server will listen on port: $Port" -ForegroundColor Green

        # ----------------------------------------------------------------
        # -> SECTION 3: Initialize HttpListener
        # ----------------------------------------------------------------
        Write-Host "[INFO] Starting HttpListener..." -ForegroundColor Cyan
        
        $script:httpListener = New-Object System.Net.HttpListener
        $script:httpListener.Prefixes.Add("http://$($script:httpHost['domain']):$Port/")
        
        try {
            $script:httpListener.Start()
            Write-Host "[OK] HttpListener started successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to start HttpListener: $($_.Exception.Message)"
            return
        }

        # ----------------------------------------------------------------
        # -> SECTION 4: Main server loop
        # ----------------------------------------------------------------
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  Local HTTP Server is running" -ForegroundColor Green  
        Write-Host "  Listening on: http://$($script:httpHost['domain']):$Port" -ForegroundColor Green
        Write-Host "  Press Ctrl+C to stop the server" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Green

        while ($script:httpListener.IsListening) {
            try {


                # Wait for incoming request (blocking call)
                $context = $script:httpListener.GetContext()
                $requestCount++
                $request  = $context.Request
                $urlPath  = $request.RawUrl.Split('?')[0]  # Query-String abschneiden

                # Log request
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Write-Host "[$timestamp] #$requestCount $($request.HttpMethod) $urlPath from $($request.RemoteEndPoint)" -ForegroundColor White
                
                # Router-Check for all defined routes
                #------------------------------------

                # Check if the URL is a known control route.
                $isControlRoute = $false
                foreach ($routeKey in $script:httpRouter.Keys) {
                    if ($urlPath -eq $script:httpRouter[$routeKey]) {
                        $isControlRoute = $true
                        break
                    }
                }

                # Check if the URL is in the /sys/ctrl/ namespace (even if unknown)
                # Used to intercept unknown control routes BEFORE they are delegated to the
                # file handler — otherwise, Invoke-RequestHandler will look
                # for a file wwwroot/sys/ctrl/xxx, which of course does not exist.
                $isSysCtrlPath = $urlPath.StartsWith('/sys/ctrl/', [System.StringComparison]::OrdinalIgnoreCase)

                # Router-Check
                if ($urlPath -eq $script:httpRouter['stop']) {
                    # Stop-Route: first send the response and then shutdown the server
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Server stopping...")
                    $context.Response.StatusCode = 200
                    $context.Response.ContentLength64 = $bytes.Length
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $context.Response.OutputStream.Close()
                    $script:httpListener.Stop()
                    break
                }
                # Add more routes (restart, status, alive, ...) here

                elseif ($urlPath -eq $script:httpRouter['home']) {
                    # Route: /sys/ctrl/gohome
                    # Sends an HTTP 302 redirect to the configured homepage.
                    # The browser receives the Location header and automatically
                    # navigates to the target URL - no user interaction required.

                    # Build the target URL from the configuration values in $httpHost
                    $homeUrl = "$($script:httpHost['protocol'])://$($script:httpHost['domain']):$($script:httpHost['port'])/"

                    # HTTP 302 = temporary redirect
                    # Important: do NOT use 301 (permanent redirect) here!
                    # A 301 is cached by the browser - it would never call this
                    # server route again after the first visit.
                    $context.Response.StatusCode        = 302
                    $context.Response.StatusDescription = "Found"

                    # The Location header tells the browser where to go next.
                    # This is the only header required for a redirect to work.
                    $context.Response.Headers.Add("Location", $homeUrl)

                    # No body content needed - the browser follows the Location
                    # header immediately and ignores any body in a redirect response.
                    $context.Response.ContentLength64 = 0
                    $context.Response.OutputStream.Close()
                }

                elseif ($urlPath -eq $script:httpRouter['status']) {
                    # Route: /sys/ctrl/http-getstatus
                    # Returns a JSON response with detailed server status information.
                    # The response includes uptime, network config, filesystem paths,
                    # request statistics and all defined control routes.

                    # ------------------------------------------------------------------
                    # PART 1: Calculate server uptime
                    # ------------------------------------------------------------------
                    # $script:serverStartTime was set when the server started (see above).
                    # (Get-Date) gives us the current time.
                    # Subtracting two DateTime objects in PowerShell gives a TimeSpan object.
                    # A TimeSpan has properties: Days, Hours, Minutes, Seconds - perfect for formatting.
                    $uptimeString = "unknown"
                    if ($null -ne $script:serverStartTime) {
                        $uptime       = (Get-Date) - $script:serverStartTime
                        $uptimeString = "{0}d {1:D2}h {2:D2}m {3:D2}s" -f `
                            $uptime.Days,
                            $uptime.Hours,
                            $uptime.Minutes,
                            $uptime.Seconds
                    }

                    # ------------------------------------------------------------------
                    # PART 2: Build the status object
                    # ------------------------------------------------------------------
                    # This is a nested PowerShell hashtable.
                    # ConvertTo-Json will turn it into proper JSON later.
                    # We group the data into logical sections so the JSON stays readable.
                    $statusData = @{

                        # General server info
                        server = @{
                            name      = $script:httpCore.app.name
                            version   = $script:httpCore.app.version
                            status    = "running"
                            startTime = $script:serverStartTime.ToString("yyyy-MM-dd HH:mm:ss")
                            uptime    = $uptimeString
                        }

                        # Network configuration
                        network = @{
                            protocol = $script:httpHost['protocol']
                            domain   = $script:httpHost['domain']
                            port     = $script:httpHost['port']
                            url      = "$($script:httpHost['protocol'])://$($script:httpHost['domain']):$($script:httpHost['port'])/"
                        }

                        # Filesystem paths
                        filesystem = @{
                            wwwroot  = $script:httpHost['wwwroot']
                            homepage = $script:httpHost['homepage']
                            logfile  = $script:httpHost['logfile']
                        }

                        # Live request statistics
                        # Note: $requestCount is a local variable defined at the top
                        # of Start-HTTPserver - it counts every request since the server started.
                        statistics = @{
                            totalRequests = $requestCount
                        }

                        # All defined control routes - useful for quick reference
                        routes = $script:httpRouter
                    }

                    # ------------------------------------------------------------------
                    # PART 3: Serialize the hashtable to JSON
                    # ------------------------------------------------------------------
                    # ConvertTo-Json converts a PowerShell hashtable/object into a JSON string.
                    # -Depth 3 means: serialize nested objects up to 3 levels deep.
                    # Without -Depth, nested hashtables (like $statusData.server) would
                    # appear as "System.Collections.Hashtable" instead of their actual values!
                    $jsonString = $statusData | ConvertTo-Json -Depth 3
                    $jsonBytes  = [System.Text.Encoding]::UTF8.GetBytes($jsonString)

                    # ------------------------------------------------------------------
                    # PART 4: Send the response
                    # ------------------------------------------------------------------
                    $context.Response.StatusCode      = 200
                    $context.Response.StatusDescription = "OK"

                    # THIS IS CRITICAL: The Content-Type header tells the browser
                    # exactly what kind of data it is receiving.
                    # With "application/json" the browser knows it is JSON and can
                    # display it formatted (e.g. Firefox shows a collapsible JSON tree).
                    # Without this header, the browser would treat it as plain text.
                    $context.Response.ContentType     = "application/json; charset=utf-8"
                    $context.Response.ContentLength64 = $jsonBytes.Length

                    # Write the JSON bytes into the response stream and close it.
                    # ContentLength64 tells the browser exactly how many bytes to expect -
                    # it knows the response is complete when it has received that many bytes.
                    $context.Response.OutputStream.Write($jsonBytes, 0, $jsonBytes.Length)
                    $context.Response.OutputStream.Close()
                }

                elseif ($urlPath -eq $script:httpRouter['restart']) {
                    # Route: /sys/ctrl/http-reboot
                    # Gracefully restarts the HTTP server.
                    #
                    # IMPORTANT - Order of operations matters here:
                    #   1. Send the response FIRST  → the browser gets confirmation
                    #   2. Close the output stream  → marks the response as complete
                    #   3. Set the reboot flag      → signals the post-loop code
                    #   4. Stop the listener        → exits the while-loop cleanly
                    #
                    # If we stopped the listener BEFORE sending the response,
                    # the browser would receive a connection error instead of
                    # a proper confirmation message. Always respond first!

                    # ------------------------------------------------------------------
                    # PART 1: Send the response BEFORE stopping the server
                    # ------------------------------------------------------------------
                    $rebootMessage = "Server reboot initiated. Restarting in 1 second..."
                    $rebootBytes   = [System.Text.Encoding]::UTF8.GetBytes($rebootMessage)

                    $context.Response.StatusCode        = 200
                    $context.Response.StatusDescription = "OK"
                    $context.Response.ContentType       = "text/plain; charset=utf-8"
                    $context.Response.ContentLength64   = $rebootBytes.Length
                    $context.Response.OutputStream.Write($rebootBytes, 0, $rebootBytes.Length)

                    # Close the stream now - this tells the browser the response
                    # is complete. The browser will display the message immediately.
                    # We can safely stop the server after this point.
                    $context.Response.OutputStream.Close()

                    # ------------------------------------------------------------------
                    # PART 2: Set the reboot flag and stop the listener
                    # ------------------------------------------------------------------
                    # Setting the flag BEFORE Stop() is important.
                    # Stop() is very fast - the post-loop code checks this flag
                    # immediately after the loop ends.
                    $script:shouldReboot = $true

                    # Stop the listener - this causes GetContext() to throw a
                    # HttpListenerException (ErrorCode 995) which breaks the while-loop.
                    $script:httpListener.Stop()
                    break
                }

                # Additional Router Check
                elseif ($isControlRoute) {
                    # Andere Steuerungsrouten: 200 OK + leere Antwort, kein Invoke-RequestHandler
                    $context.Response.StatusCode = 200
                    $context.Response.ContentLength64 = 0
                    $context.Response.OutputStream.Close()
                } elseif ($isSysCtrlPath) {
                    # ----------------------------------------------------------------
                    # Unknown /sys/ctrl/ route → HTTP 501 Not Implemented
                    # ----------------------------------------------------------------
                    # Semantics: The /sys/ctrl/ namespace exists and is valid,
                    # but this specific route is not implemented in the router.
                    # RFC 9110: 501 = "server does not support the functionality
                    # needed to fulfill the request." This is more precise than
                    # 404 (resource not found) for a known namespace with an
                    # unknown endpoint.
                    # ----------------------------------------------------------------

                    $context.Response.StatusCode        = 501
                    $context.Response.StatusDescription = "Not Implemented"

                    # Try to load custom 501 error page from $script:httpHost.error
                    $custom501Path = $null
                    $errorPages501 = $script:httpHost.error
                    if ($errorPages501 -is [hashtable] -and $errorPages501.ContainsKey('501')) {
                        if (-not [string]::IsNullOrEmpty($errorPages501['501'])) {
                            $custom501Path = $errorPages501['501']
                        }
                    }

                    if ($null -ne $custom501Path -and (Test-Path -Path $custom501Path -PathType Leaf)) {
                        # Custom error page found → serve it as HTML
                        $errorBytes = [System.IO.File]::ReadAllBytes($custom501Path)
                        $context.Response.ContentType     = "text/html; charset=utf-8"
                        $context.Response.ContentLength64 = $errorBytes.Length
                        $context.Response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
                    } else {
                        # No custom page → structured JSON fallback
                        # JSON is more appropriate here than plaintext because
                        # /sys/ctrl/ is an API-style namespace, not a web page.
                        $errorJson  = "{`"error`": 501, `"message`": `"Not Implemented`", `"route`": `"$urlPath`", `"hint`": `"Use /sys/ctrl/gethelp to list all available control routes.`"}"
                        $errorBytes = [System.Text.Encoding]::UTF8.GetBytes($errorJson)
                        $context.Response.ContentType     = "application/json; charset=utf-8"
                        $context.Response.ContentLength64 = $errorBytes.Length
                        $context.Response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
                    }

                    $context.Response.OutputStream.Close()
                } else {
                    # Normal file request
                    Invoke-RequestHandler -Context $context
                }

            }
            catch [System.Net.HttpListenerException] {
                # HttpListener was stopped (normal shutdown)
                if ($_.Exception.ErrorCode -eq 995) {
                    Write-Host "`n[INFO] Server shutdown initiated" -ForegroundColor Cyan
                    break
                }
                else {
                    Write-Error "HttpListener error: $($_.Exception.Message)"
                }
            }
            catch {
                Write-Error "Unexpected error in main server loop: $($_.Exception.Message)"
            }
            
        }

        # Post-loop reboot check.
        # If the reboot flag was set by the /sys/ctrl/http-reboot route,
        # we wait briefly for the OS to release the TCP port, then call
        # Start-HTTPserver again with the same parameters.
        #
        # Why Start-Sleep -Seconds 1?
        # When $listener.Stop() is called, the TCP port is not released
        # instantly by the operating system. If we try to bind to the same
        # port again immediately, $listener.Start() will throw:
        # "Only one usage of each socket address is permitted"
        # One second is enough for Windows to fully release the port.
        if ($script:shouldReboot -eq $true) {
            $script:shouldReboot = $false
            Write-Host "`n[INFO] Reboot requested - waiting 1 second for port release..." -ForegroundColor Yellow

            # The finally-block (below) will close and dispose the current listener.
            # We save Port and wwwRoot now because they are local variables
            # that will go out of scope once this function exits.
            $rebootPort    = $Port
            $rebootWwwRoot = $wwwRoot

            Start-Sleep -Seconds 1

            Write-Host "[INFO] Restarting server..." -ForegroundColor Yellow

            # Recursive call: Start-HTTPserver calls itself with the same parameters.
            # This creates a fresh listener, a fresh request counter and
            # a fresh start time - a true clean restart.
            Start-HTTPserver -Port $rebootPort -wwwRoot $rebootWwwRoot
        }

    }
    catch {
        Write-Error "Fatal error starting server: $($_.Exception.Message)"
    }
    finally {
        # ----------------------------------------------------------------
        # -> SECTION 5: Cleanup
        # ----------------------------------------------------------------
        # FIX: Only stop/close the listener if it still exists AND is still
        # listening. After a reboot the listener was already closed above
        # in the post-loop block - we must not try to close it again here.
        if ($null -ne $script:httpListener -and $script:httpListener.IsListening) {
            Write-Host "[INFO] Stopping HttpListener..." -ForegroundColor Cyan
            $script:httpListener.Stop()
            $script:httpListener.Close()
            Write-Host "[OK] HttpListener stopped" -ForegroundColor Green
        }
        
        Write-Host "`n[INFO] Server stopped. Total requests processed: $requestCount" -ForegroundColor Cyan
    }
}
