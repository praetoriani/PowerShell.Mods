function Invoke-RouteHandler {
<#
.SYNOPSIS
    Handles all /sys/ctrl/ control route requests for local.httpserver
.DESCRIPTION
    This function processes all defined control routes from $script:httpRouter.
    It is called by Start-HTTPserver after the IP guard has confirmed the
    request originates from localhost. Each route is handled as a distinct
    elseif branch. Unknown routes within the /sys/ctrl/ namespace receive
    HTTP 501 Not Implemented.
.PARAMETER Context
    The HttpListenerContext object containing the request and response
.PARAMETER UrlPath
    The normalized URL path (query string already stripped)
.EXAMPLE
    Invoke-RouteHandler -Context $context -UrlPath "/sys/ctrl/http-getstatus"
.NOTES
    Version:        v1.00.00
    Author:         Praetoriani
    Date Created:   25.04.2026
    Last Updated:   25.04.2026
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$UrlPath
    )

    # Shortcuts - same pattern as Invoke-RequestHandler
    $response = $Context.Response

    # ----------------------------------------------------------------
    # Shutdown
    # ----------------------------------------------------------------
    if ($UrlPath -eq $script:httpRouter['stop']) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Server stopping...")
        $response.StatusCode        = 200
        $response.ContentType       = "text/plain; charset=utf-8"
        $response.ContentLength64   = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.OutputStream.Close()
        $script:httpListener.Stop()

    # ----------------------------------------------------------------
    # Reboot
    # ----------------------------------------------------------------
    } elseif ($UrlPath -eq $script:httpRouter['restart']) {
        $rebootMessage = "Server reboot initiated. Restarting in 1 second..."
        $rebootBytes   = [System.Text.Encoding]::UTF8.GetBytes($rebootMessage)
        $response.StatusCode        = 200
        $response.StatusDescription = "OK"
        $response.ContentType       = "text/plain; charset=utf-8"
        $response.ContentLength64   = $rebootBytes.Length
        $response.OutputStream.Write($rebootBytes, 0, $rebootBytes.Length)
        $response.OutputStream.Close()
        $script:shouldReboot = $true
        $script:httpListener.Stop()

    # ----------------------------------------------------------------
    # Status
    # ----------------------------------------------------------------
    } elseif ($UrlPath -eq $script:httpRouter['status']) {
        $uptimeString = "unknown"
        if ($null -ne $script:serverStartTime) {
            $uptime       = (Get-Date) - $script:serverStartTime
            $uptimeString = "{0}d {1:D2}h {2:D2}m {3:D2}s" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds
        }
        $statusData = @{
            server     = @{ name = $script:httpCore.app.name; version = $script:httpCore.app.version; status = "running"; startTime = $script:serverStartTime.ToString("yyyy-MM-dd HH:mm:ss"); uptime = $uptimeString }
            network    = @{ protocol = $script:httpHost['protocol']; domain = $script:httpHost['domain']; port = $script:httpHost['port']; url = "$($script:httpHost['protocol'])://$($script:httpHost['domain']):$($script:httpHost['port'])/" }
            filesystem = @{ wwwroot = $script:httpHost['wwwroot']; homepage = $script:httpHost['homepage']; logfile = $script:httpHost['logfile'] }
            routes     = $script:httpRouter
        }
        $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(($statusData | ConvertTo-Json -Depth 3))
        $response.StatusCode        = 200
        $response.ContentType       = "application/json; charset=utf-8"
        $response.ContentLength64   = $jsonBytes.Length
        $response.OutputStream.Write($jsonBytes, 0, $jsonBytes.Length)
        $response.OutputStream.Close()

    # ----------------------------------------------------------------
    # Heartbeat
    # ----------------------------------------------------------------
    } elseif ($UrlPath -eq $script:httpRouter['alive']) {
        $hbJson  = "{`"alive`": true, `"timestamp`": `"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`"}"
        $hbBytes = [System.Text.Encoding]::UTF8.GetBytes($hbJson)
        $response.StatusCode        = 200
        $response.ContentType       = "application/json; charset=utf-8"
        $response.ContentLength64   = $hbBytes.Length
        $response.OutputStream.Write($hbBytes, 0, $hbBytes.Length)
        $response.OutputStream.Close()

    # ----------------------------------------------------------------
    # Help
    # ----------------------------------------------------------------
    } elseif ($UrlPath -eq $script:httpRouter['help']) {
        $helpData = @{
            namespace   = "/sys/ctrl/"
            description = "Control routes for local.httpserver. GET only. Localhost access only."
            routes      = @(
                @{ path = $script:httpRouter['stop'];    method = "GET"; description = "Gracefully shuts down the HTTP server." }
                @{ path = $script:httpRouter['restart']; method = "GET"; description = "Restarts the server (same port and wwwroot)." }
                @{ path = $script:httpRouter['status'];  method = "GET"; description = "Returns uptime, port, wwwroot and request stats as JSON." }
                @{ path = $script:httpRouter['alive'];   method = "GET"; description = "Minimal health check - returns {alive: true, timestamp}." }
                @{ path = $script:httpRouter['help'];    method = "GET"; description = "Returns this help document." }
                @{ path = $script:httpRouter['home'];    method = "GET"; description = "Redirects (302) to the configured homepage." }
            )
        }
        $helpBytes = [System.Text.Encoding]::UTF8.GetBytes(($helpData | ConvertTo-Json -Depth 3))
        $response.StatusCode        = 200
        $response.ContentType       = "application/json; charset=utf-8"
        $response.ContentLength64   = $helpBytes.Length
        $response.OutputStream.Write($helpBytes, 0, $helpBytes.Length)
        $response.OutputStream.Close()

    # ----------------------------------------------------------------
    # GoHome
    # ----------------------------------------------------------------
    } elseif ($UrlPath -eq $script:httpRouter['home']) {
        $homeUrl = "$($script:httpHost['protocol'])://$($script:httpHost['domain']):$($script:httpHost['port'])/"
        $response.StatusCode        = 302
        $response.StatusDescription = "Found"
        $response.Headers.Add("Location", $homeUrl)
        $response.ContentLength64   = 0
        $response.OutputStream.Close()

    # ----------------------------------------------------------------
    # Unknown /sys/ctrl/ route → 501 Not Implemented
    # ----------------------------------------------------------------
    } else {
        $errorPages = $script:httpHost.error
        $custom501Path = $null
        if ($errorPages -is [hashtable] -and $errorPages.ContainsKey('501')) {
            if (-not [string]::IsNullOrEmpty($errorPages['501'])) {
                $custom501Path = $errorPages['501']
            }
        }
        if ($null -ne $custom501Path -and (Test-Path -Path $custom501Path -PathType Leaf)) {
            $errorBytes = [System.IO.File]::ReadAllBytes($custom501Path)
            $response.ContentType = "text/html; charset=utf-8"
        } else {
            $errorJson  = "{`"error`": 501, `"message`": `"Not Implemented`", `"route`": `"$UrlPath`", `"hint`": `"Use /sys/ctrl/gethelp to list all available control routes.`"}"
            $errorBytes = [System.Text.Encoding]::UTF8.GetBytes($errorJson)
            $response.ContentType = "application/json; charset=utf-8"
        }
        $response.StatusCode        = 501
        $response.StatusDescription = "Not Implemented"
        $response.ContentLength64   = $errorBytes.Length
        $response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
        $response.OutputStream.Close()
    }
}
