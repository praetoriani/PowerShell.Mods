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
        [int]$Port = 8080,

        [Parameter(Mandatory = $false)]
        [string]$wwwRoot = "./wwwroot"
    )

    try {
        # ----------------------------------------------------------------
        # -> SECTION 1: System prechecks
        # ----------------------------------------------------------------
        Write-Host "[INFO] Performing system prechecks..." -ForegroundColor Cyan
        
        if (-not (Test-SystemPrecheck)) {
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
        $script:httpListener.Prefixes.Add("http://localhost:$Port/")
        
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
        Write-Host "  Listening on: http://localhost:$Port" -ForegroundColor Green
        Write-Host "  Press Ctrl+C to stop the server" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Green

        # Request counter for logging
        $requestCount = 0

        while ($script:httpListener.IsListening) {
            try {
                # Wait for incoming request (blocking call)
                $context = $script:httpListener.GetContext()
                $requestCount++
                
                $request = $context.Request

                # Log request
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Write-Host "[$timestamp] #$requestCount $($request.HttpMethod) $($request.RawUrl) from $($request.RemoteEndPoint)" -ForegroundColor White

                # Handle request using Invoke-RequestHandler
                Invoke-RequestHandler -Context $context

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

    }
    catch {
        Write-Error "Fatal error starting server: $($_.Exception.Message)"
    }
    finally {
        # ----------------------------------------------------------------
        # -> SECTION 5: Cleanup
        # ----------------------------------------------------------------
        if ($script:httpListener -and $script:httpListener.IsListening) {
            Write-Host "[INFO] Stopping HttpListener..." -ForegroundColor Cyan
            $script:httpListener.Stop()
            $script:httpListener.Close()
            Write-Host "[OK] HttpListener stopped" -ForegroundColor Green
        }
        
        Write-Host "`n[INFO] Server stopped. Total requests processed: $requestCount" -ForegroundColor Cyan
    }
}

# Export the function
Export-ModuleMember -Function Start-HTTPserver
