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
    [string]$Homepage = $script:httpHost.Get_Item("homepage"),

    [Parameter(Mandatory = $false)]
    [hashtable]$ErrorPages = $script:httpHost.error
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
    $headersSent = $false
<#
    # Secure error page cache – everything gathered centrally here.
    $ErrorPages = @{}

    try {
        if ($null -ne (Get-Variable -Name 'httpHost' -Scope Script -ErrorAction SilentlyContinue)) {
            $rawError = $script:httpHost.error
            if ($rawError -is [hashtable]) {
                $ErrorPages = $rawError
            } elseif ($rawError -is [System.Collections.IDictionary]) {
                $ErrorPages = @{}
                foreach ($key in $rawError.Keys) {
                    $ErrorPages[$key] = $rawError[$key]
                }
            }
        }
    } catch {
        # If the configuration is unreachable for any reason,
        # we simply stick with an empty hashtable.
        $ErrorPages = @{}
    }
    
    # Secure access to error pages — $ErrorPages comes as a parameter,
    # therefore it is evaluated in the scope of the caller (where $script:httpHost is visible)
    $resolvedErrorPages = if ($null -ne $ErrorPages) { $ErrorPages } else { @{} }
    
#>
    try {


        # ___________________________________________________________________________
        # -> SECTION 2: HTTP Method validation (Whitelist: GET, HEAD)
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        $allowedMethods = @('GET', 'HEAD')
        if ($request.HttpMethod -notin $allowedMethods) {

            $response.StatusCode        = 405
            $response.StatusDescription = "Method Not Allowed"

            # RFC 9110 requires an "Allow" header listing the accepted methods.
            # This is MANDATORY for a spec-compliant 405 response —
            # without it, clients cannot know which methods are valid.
            $response.Headers.Add("Allow", ($allowedMethods -join ', '))

            # Try to load custom 405 error page (same pattern as 404/500)
            $custom405Path = $null
            if ($ErrorPages -is [hashtable] -and $ErrorPages.ContainsKey('405')) {
                if (-not [string]::IsNullOrEmpty($ErrorPages['405'])) {
                    $custom405Path = $ErrorPages['405']
                }
            }

            if ($null -ne $custom405Path -and (Test-Path -Path $custom405Path -PathType Leaf)) {
                # Custom error page found → serve as HTML
                # We use ReadAllBytes and set ContentType manually because
                # GetMimeType is not yet called at this point in the pipeline.
                $responseBytes = [System.IO.File]::ReadAllBytes($custom405Path)
                $response.ContentType       = "text/html; charset=utf-8"
                $response.ContentLength64   = $responseBytes.Length
                $headersSent = $true
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            } else {
                # No custom page → plaintext fallback
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes(
                    "405 Method Not Allowed. Accepted methods: $($allowedMethods -join ', ')"
                )
                $response.ContentType       = "text/plain; charset=utf-8"
                $response.ContentLength64   = $responseBytes.Length
                $headersSent = $true
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            }

            return
        }

        # ___________________________________________________________________________
        # -> SECTION 2b: URL Validation (400 Bad Request)
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        # Checks if the URL contains invalid characters or an incorrect encoding.
        # Such requests are rejected with a 400 Bad Request before they reach the
        # path mapping code.
        try {
            # [System.Uri]::UnescapeDataString wirft eine Exception bei
            # fehlerhaftem Percent-Encoding (z.B. %GG oder abgeschnittenes %2)
            $null = [System.Uri]::UnescapeDataString($request.RawUrl)
        }
        catch {
            $response.StatusCode        = 400
            $response.StatusDescription = "Bad Request"

            # Load custom 400 error page (same pattern as 404)
            $custom400Path = $null
            if ($ErrorPages -is [hashtable] -and $ErrorPages.ContainsKey('400')) {
                if (-not [string]::IsNullOrEmpty($ErrorPages['400'])) {
                    $custom400Path = $ErrorPages['400']
                }
            }

            if ($null -ne $custom400Path -and (Test-Path -Path $custom400Path -PathType Leaf)) {
                # Custom error page found → resolved. Path redirected, code continues to Section 7-9.
                $resolvedPath = $custom400Path
            }
            else {
                # No Custom Errorpage found → Send Plaintext as fallback
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("400 Bad Request: $($request.RawUrl)")
                $response.ContentLength64 = $responseBytes.Length
                $headersSent = $true
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
                return
            }
        }

        # ___________________________________________________________________________
        # -> SECTION 2c: Request-URI Length Limit (413 Content Too Large)
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        # Rejects requests with excessively long URLs before any filesystem
        # operations are performed.
        #
        # WHY THIS MATTERS FOR A STATIC FILE SERVER:
        # Even with a GET-only whitelist, an attacker can send requests with
        # extremely long URLs (e.g. '/' + 50,000 chars). These reach
        # [System.IO.Path]::GetFullPath() and can cause performance degradation.
        # Checking the length here is cheap, early, and unambiguous.
        #
        # LIMIT RATIONALE:
        # - 2083 chars: historical IE/Edge limit, de-facto browser maximum
        # - 4096 chars: common web server default (Apache, nginx)
        # - We use 4096 as a generous but reasonable upper bound.
        #   Any URL longer than this from a browser is either a bug or malicious.
        #
        # RFC NOTE:
        # RFC 9110 §15.5.15 defines 414 (URI Too Long) for this exact case.
        # We use 413 here because it is already configured in module.config.ps1
        # and our ErrorPages hashtable. The user experience is identical —
        # both codes signal "your request is too big, try again."
        # If you prefer strict RFC compliance, change 413 → 414 and add
        # '414' to the error hashtable in module.config.ps1.

        # get max. URL-Length from module.config.ps1
        $maxUrlLength = if ($script:httpHost.ContainsKey('maxUrlLength') -and $script:httpHost['maxUrlLength'] -gt 0) {
            $script:httpHost['maxUrlLength']
        } else {
            4096  # Safe fallback if not configured in module.consig.ps1
        }
        if ($request.RawUrl.Length -gt $maxUrlLength) {

            Write-Warning "[Invoke-RequestHandler] URI too long ($($request.RawUrl.Length) chars), blocked: $($request.RawUrl.Substring(0, [Math]::Min(100, $request.RawUrl.Length)))..."

            $response.StatusCode        = 413
            $response.StatusDescription = "Content Too Large"

            # Try to load custom 413 error page
            $custom413Path = $null
            if ($ErrorPages -is [hashtable] -and $ErrorPages.ContainsKey('413')) {
                if (-not [string]::IsNullOrEmpty($ErrorPages['413'])) {
                    $custom413Path = $ErrorPages['413']
                }
            }

            if ($null -ne $custom413Path -and (Test-Path -Path $custom413Path -PathType Leaf)) {
                # Custom error page found → send directly
                $responseBytes              = [System.IO.File]::ReadAllBytes($custom413Path)
                $response.ContentType       = "text/html; charset=utf-8"
                $response.ContentLength64   = $responseBytes.Length
                $headersSent = $true
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            } else {
                # No custom page → plaintext fallback
                # Same reasoning as 403: do NOT reflect the (potentially huge) URL back.
                $responseBytes              = [System.Text.Encoding]::UTF8.GetBytes("413 Content Too Large: Request URI exceeds maximum allowed length.")
                $response.ContentType       = "text/plain; charset=utf-8"
                $response.ContentLength64   = $responseBytes.Length
                $headersSent = $true
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            }

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
        # CRITICAL SECURITY: Ensure resolved path is within wwwroot.
        #
        # NOTE ON PATTERN CHOICE:
        # Unlike 404/400 (where $resolvedPath is redirected to the error page and
        # the pipeline continues normally), we use the direct-send pattern here.
        # Reason: $resolvedPath currently holds the attacker-controlled path that
        # escaped wwwroot. Reusing it — even redirected — in the downstream pipeline
        # would be confusing and fragile. A clean early-exit is safer and clearer
        # for a security-critical code path.

        $resolvedPath    = [System.IO.Path]::GetFullPath($fullPath)
        $resolvedWwwRoot = [System.IO.Path]::GetFullPath($WwwRoot)

        if (-not $resolvedPath.StartsWith($resolvedWwwRoot, [System.StringComparison]::OrdinalIgnoreCase)) {

            Write-Warning "[Invoke-RequestHandler] Path traversal attempt blocked: $urlPath"

            $response.StatusCode        = 403
            $response.StatusDescription = "Forbidden"

            # Try to load custom 403 error page (same pattern as 405/500)
            $custom403Path = $null
            if ($ErrorPages -is [hashtable] -and $ErrorPages.ContainsKey('403')) {
                if (-not [string]::IsNullOrEmpty($ErrorPages['403'])) {
                    $custom403Path = $ErrorPages['403']
                }
            }

            if ($null -ne $custom403Path -and (Test-Path -Path $custom403Path -PathType Leaf)) {
                # Custom error page found → read and send directly.
                # ContentType is set manually because GetMimeType (Section 7)
                # is never reached on this early-exit path.
                $responseBytes              = [System.IO.File]::ReadAllBytes($custom403Path)
                $response.ContentType       = "text/html; charset=utf-8"
                $response.ContentLength64   = $responseBytes.Length
                $headersSent = $true
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            } else {
                # No custom page → plaintext fallback
                # Intentionally vague: we do NOT echo $urlPath back in the response.
                # Reflecting attacker-controlled input in an error message is an
                # information disclosure risk (and potential XSS vector if ever
                # switched to HTML). A static message is always safer here.
                $responseBytes              = [System.Text.Encoding]::UTF8.GetBytes("403 Forbidden")
                $response.ContentType       = "text/plain; charset=utf-8"
                $response.ContentLength64   = $responseBytes.Length
                $headersSent = $true
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
            }

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

            $response.StatusCode        = 404
            $response.StatusDescription = "Not Found"

            # Try to load Custom-Errorpage
            # Custom 404 errors are only attempted if we have a hashtable and a 404 entry.
            $custom404Path = $null
            if ($ErrorPages -is [hashtable] -and $ErrorPages.ContainsKey('404')) {
                if (-not [string]::IsNullOrEmpty($ErrorPages['404'])) {
                    $custom404Path = $ErrorPages['404']
                }
            }

            if ($null -ne $custom404Path -and (Test-Path -Path $custom404Path -PathType Leaf)) {
                # Custom-Errorpage found → Set as resolvedPath, Code will continue till Section 9
                $resolvedPath = $custom404Path
            } else {
                # No Custom Errorpage found → Send Plaintext as fallback
                $responseBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $urlPath")
                $response.ContentLength64 = $responseBytes.Length
                $headersSent = $true
                $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
                return # OutputStream will closed inside finally
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

        # --- Existing headers (unchanged) ---
        $response.Headers.Add("X-Content-Type-Options", "nosniff")
        $response.Headers.Add("X-Frame-Options", "DENY")
        $response.Headers.Add("Cache-Control", "no-cache")

        # --- NEW: Content-Security-Policy ---
        # Restricts which resources the browser is allowed to load.
        # 'self' = only resources from the same origin (same domain + port).
        # This is the most important XSS-mitigation header a server can send.
        # For a local static file server, "default-src 'self'" is the correct
        # and sufficient default. If your web app loads fonts or scripts from
        # external CDNs (e.g. Google Fonts), you would need to extend this —
        # but that is a per-app customization, not a server default.
        $response.Headers.Add("Content-Security-Policy", "default-src 'self'")

        # --- NEW: Referrer-Policy ---
        # Controls how much referrer information is included with requests.
        # "no-referrer" means: the browser sends NO Referer header at all
        # when navigating away from this server. This prevents leaking the
        # local URL structure (e.g. "http://localhost:8080/admin/config.html")
        # to any external resource that might be loaded by a page.
        $response.Headers.Add("Referrer-Policy", "no-referrer")

        # --- NEW: Permissions-Policy ---
        # Disables browser APIs that a static file server has no legitimate
        # use for. This prevents any loaded page from accidentally (or
        # maliciously) requesting geolocation, camera or microphone access.
        # Format: feature=(allowlist) — empty () means "disabled for all origins".
        $response.Headers.Add("Permissions-Policy", "geolocation=(), camera=(), microphone=()")

        # Remove or neutralize Server header
        # (prevents fingerprinting of the server technology)
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

        # Only set 200 if no previous error has been set
        if ($response.StatusCode -eq 200) { $response.StatusDescription = "OK" }
        
        # For HEAD requests, don't send body
        if ($request.HttpMethod -eq 'GET') {
            $headersSent = $true
            $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
        }

    } catch {
        # ___________________________________________________________________________
        # -> SECTION 10: Error Handling
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        
        Write-Error "[Invoke-RequestHandler] Error processing request: $($_.Exception.Message)"
        # Only try to send 500 if the stream hasn't startet
        try {

            if (-not $headersSent) {
                $response.StatusCode        = 500
                $response.StatusDescription = "Internal Server Error"

                $custom500Path = $null
                if ($ErrorPages -is [hashtable] -and $ErrorPages.ContainsKey('500')) {
                    if (-not [string]::IsNullOrEmpty($ErrorPages['500'])) {
                        $custom500Path = $ErrorPages['500']
                    }
                }

                if ($null -ne $custom500Path -and (Test-Path -Path $custom500Path -PathType Leaf)) {
                    $errorBytes = [System.IO.File]::ReadAllBytes($custom500Path)
                    $response.ContentType = "text/html; charset=utf-8"
                } else {
                    $errorBytes = [System.Text.Encoding]::UTF8.GetBytes("500 Internal Server Error")
                    $response.ContentType = "text/plain; charset=utf-8"
                }

                $response.ContentLength64 = $errorBytes.Length
                $headersSent = $true
                $response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
            }
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
