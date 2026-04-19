function Invoke-RequestHandler {
<#
.SYNOPSIS
    Core HTTP request handler for local.httpserver
.DESCRIPTION
    This function processes incoming HTTP requests, maps URL paths to filesystem paths,
    serves static files with appropriate MIME types, and implements security measures
    including path traversal protection and security response headers.
.PARAMETER Context
    The HttpListenerContext object containing the request and response
.PARAMETER WwwRoot
    The root directory for serving files (defaults to $httpHost.wwwroot)
.PARAMETER Homepage
    The default file to serve for directory requests (defaults to $httpHost.homepage)
.EXAMPLE
    Invoke-RequestHandler -Context $context
.NOTES
    Version:        v1.00.00
    Author:         Praetoriani
    Date Created:   18.04.2026
    Last Updated:   18.04.2026
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [System.Net.HttpListenerContext]$Context,

    [Parameter(Mandatory = $false)]
    [string]$WwwRoot = $script:httpHost.Get_Item("wwwroot"),

    [Parameter(Mandatory = $false)]
    [string]$Homepage = $script:httpHost.Get_Item("homepage")
)

    # ___________________________________________________________________________
    # -> SECTION 1: Initialize and validate parameters
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    # Resolve wwwroot from $httpHost if not provided
    if ([string]::IsNullOrEmpty($WwwRoot)) {
        if ($null -ne (Get-Variable -Name 'httpHost' -Scope Script -ErrorAction SilentlyContinue)) {
            $WwwRoot = $script:httpHost.wwwroot
        } else {
            Write-Error "[Invoke-RequestHandler] wwwroot not specified and \$script:httpHost not available"
            return
        }
    }

    # Resolve homepage from $httpHost if using default
    if ($Homepage -eq "index.html" -and $null -ne (Get-Variable -Name 'httpHost' -Scope Script -ErrorAction SilentlyContinue)) {
        if (-not [string]::IsNullOrEmpty($script:httpHost.homepage)) {
            $Homepage = $script:httpHost.homepage
        }
    }

    $request = $Context.Request
    $response = $Context.Response

    try {
        # ___________________________________________________________________________
        # -> SECTION 2: HTTP Method validation (Whitelist: GET, HEAD)
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        $allowedMethods = @('GET', 'HEAD')
        if ($request.HttpMethod -notin $allowedMethods) {
            $response.StatusCode = 405
            $response.StatusDescription = "Method Not Allowed"
            $response.Headers.Add("Allow", ($allowedMethods -join ', '))
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("405 Method Not Allowed")
            $response.ContentLength64 = $responseBytes.Length
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            return
        }

        # ___________________________________________________________________________
        # -> SECTION 3: URL to Filesystem Path Mapping
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        # Get the requested URL path and decode it
        $urlPath = [System.Uri]::UnescapeDataString($request.Url.LocalPath)

        # Remove leading slash and normalize path separators
        $relativePath = $urlPath.TrimStart('/')
        if ([string]::IsNullOrEmpty($relativePath)) {
            $relativePath = $Homepage
        }

        # Construct the full filesystem path
        $fullPath = Join-Path $WwwRoot $relativePath

        # ___________________________________________________________________________
        # -> SECTION 4: Path Traversal Protection
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        # CRITICAL SECURITY: Ensure resolved path is within wwwroot

        $resolvedPath = [System.IO.Path]::GetFullPath($fullPath)
        $resolvedWwwRoot = [System.IO.Path]::GetFullPath($WwwRoot)

        # Check if resolved path starts with wwwroot (case-insensitive for Windows)
        if (-not $resolvedPath.StartsWith($resolvedWwwRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "[Invoke-RequestHandler] Path traversal attempt blocked: $urlPath"
            $response.StatusCode = 403
            $response.StatusDescription = "Forbidden"
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("403 Forbidden")
            $response.ContentLength64 = $responseBytes.Length
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            return
        }

        # ___________________________________________________________________________
        # -> SECTION 5: Directory to index.html mapping
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        if (Test-Path -Path $resolvedPath -PathType Container) {
            if ([string]::IsNullOrEmpty($Homepage)) {
                # Fallback
                $Homepage = "index.html"
            }
            $resolvedPath = Join-Path $resolvedPath $Homepage
        }

        # ___________________________________________________________________________
        # -> SECTION 6: File existence check and 404 handling
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        if (-not (Test-Path -Path $resolvedPath -PathType Leaf)) {
            # Try custom 404.html if it exists
            $custom404 = $script:httpHost.error['404']
            if (Test-Path -Path $custom404 -PathType Leaf) {
                $resolvedPath = $custom404
                $response.StatusCode = 404
                $response.StatusDescription = "Not Found"
            } else {
                # Default 404 response
                $response.StatusCode = 404
                $response.StatusDescription = "Not Found"
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $urlPath")
                $response.ContentLength64 = $responseBytes.Length
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
                return
            }
        }

        # ___________________________________________________________________________
        # -> SECTION 7: MIME Type detection
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        $detectedMime = "application/octet-stream"
        try {
            $detectedMime = GetMimeType -FilePath $resolvedPath
        } catch {
            Write-Warning "[Invoke-RequestHandler] Failed to get MIME type for $resolvedPath : $($_.Exception.Message)"
        }

        # ___________________________________________________________________________
        # -> SECTION 8: Security Response Headers
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        $response.Headers.Add("X-Content-Type-Options", "nosniff")
        $response.Headers.Add("X-Frame-Options", "DENY")
        $response.Headers.Add("Cache-Control", "no-cache")
        
        # Remove or neutralize Server header
        try {
            $response.Headers.Remove("Server")
        } catch {
            # Header might not be set yet, ignore
        }

        # ___________________________________________________________________________
        # -> SECTION 9: Read and send file content
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        $fileBytes = [System.IO.File]::ReadAllBytes($resolvedPath)
        
        $response.ContentType = $detectedMime
        $response.ContentLength64 = $fileBytes.Length
        $response.StatusCode = 200
        $response.StatusDescription = "OK"

        # For HEAD requests, don't send body
        if ($request.HttpMethod -eq 'GET') {
            $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
        }

    } catch {
        # ___________________________________________________________________________
        # -> SECTION 10: Error Handling
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        
        Write-Error "[Invoke-RequestHandler] Error processing request: $($_.Exception.Message)"
        try {
            $response.StatusCode = 500
            $response.StatusDescription = "Internal Server Error"
            $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("500 Internal Server Error")
            $response.ContentLength64 = $responseBytes.Length
            $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
        } catch {
            # If we can't even send error response, just log it
            Write-Error "[Invoke-RequestHandler] Failed to send error response: $($_.Exception.Message)"
        }
    } finally {
        # ___________________________________________________________________________
        # -> SECTION 11: Cleanup
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        
        try {
            $response.OutputStream.Close()
        } catch {
            # Stream might already be closed
        }
    }
}
