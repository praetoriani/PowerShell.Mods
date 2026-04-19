<#
___________________________________________________________________________
         POWERSHELL MODULE CONFIGURATION FILE FOR LOCAL.HTTPSERVER         
‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
THIS FILE IS USED TO STORE ALL THE CONFIGURATIONS FOR THE LOCAL.HTTPSERVER
___________________________________________________________________________

‼ DON'T TOUCH THIS FILE AS LONG AS YOU DON'T KNOW EXACTLY WHAT YOU'RE DOING ‼
___________________________________________________________________________

VERSION OF MODULE.CONFIG:       v1.00.00
SUPPORTED MODULE VERSION:       v1.00.xx
___________________________________________________________________________

#>

# _____________
# PLEASE NOTE ‼
# ‾‾‾‾‾‾‾‾‾‾‾‾‾
# The module.conf is the only source of truth! No other config-files are used or will be acceppted!
# → This file is loaded via local.httpserver.psm1. This means we can use $script:root

$httpCore = @{  # ← Stores infomations about the app itself and the environment
    
    app =   @{
        name    = "local.httpserver"
        version = "v1.00.00"
        devname = "Praetoriani"
        website = "https://github.com/praetoriani/"
        created  = "15.04.2026"
        updated  = "17.04.2026"
    }

    config =   @{
        # Internal Path Configuration
        xml  = Join-Path $script:root "include\ui.xml"
        png  = Join-Path $script:root "include\ui.png"
        lib  = Join-Path $script:root "lib"
        log  = Join-Path $script:root "logs"
    }

    dialog =   @{
        info  = "popup-info.xml"
        warn  = "popup-warn.xml"
        error = "popup-error.xml"
        exit  = "popup-exit.xml"
    }

    plugin =    @{
        OPSreturn   = @{
            src     = Join-Path $script:root "lib\OPSreturn\OPSreturn.psd1"
            name    = "OPSreturn"
            desc    = "The OPSreturn Module creates a consistent PSCustomObject for returning operation status information"
            vers    = "v1.00.00"
        }
        VPDLX       = @{
            src     = Join-Path $script:root "lib\VPDLX\VPDLX.psd1"
            name    = "VPDLX"
            desc    = "VPDLX provides a fully class-based virtual logging system for working with multiple in-memory log files simultaneously."
            vers    = "v1.02.06"
        }
    }
}

$httpHost = @{  # ← Stores important information for the HTTP Server
    domain      = "localhost"
    port        = 8080
    protocol    = "http"
    wwwroot     = Join-Path $script:root "wwwroot"
    homepage    = "index.html"
    logfile     = "local.httpserver"
    ssl         = $false
    error       = @{
        404     = Join-Path $script:root "wwwroot\sys\inc\404.html"
    }
}

$httpRouter = @{    # ← Defines the config-routes
    stop    = "/sys/ctrl/http-shutdown"
    restart = "/sys/ctrl/http-reboot"
    status  = "/sys/ctrl/http-getstatus"
    alive   = "/sys/ctrl/http-heartbeat"
    help    = "/sys/ctrl/gethelp"
    home    = "/sys/ctrl/gohome"
}

$mimeType   = @{    # ← Stores all available MimeTypes
    "default"       = "application/octet-stream"
    ".html"         = "text/html; charset=utf-8"
    ".htm"          = "text/html; charset=utf-8"
    ".css"          = "text/css; charset=utf-8"
    ".js"           = "application/javascript; charset=utf-8"
    ".mjs"          = "application/javascript; charset=utf-8"
    ".json"         = "application/json; charset=utf-8"
    ".map"          = "application/json; charset=utf-8"
    ".ts"           = "application/typescript; charset=utf-8"
    ".jsx"          = "application/javascript; charset=utf-8"
    ".tsx"          = "application/javascript; charset=utf-8"
    ".xml"          = "application/xml; charset=utf-8"
    ".wasm"          = "application/wasm"
    ".txt"          = "text/plain; charset=utf-8"
    ".csv"          = "text/csv; charset=utf-8"
    ".md"           = "text/markdown; charset=utf-8"
    ".pdf"          = "application/pdf"
    ".png"          = "image/png"
    ".jpg"          = "image/jpeg"
    ".jpeg"         = "image/jpeg"
    ".gif"          = "image/gif"
    ".webp"         = "image/webp"
    ".avif"         = "image/avif"
    ".ico"          = "image/x-icon"
    ".svg"          = "image/svg+xml; charset=utf-8"
    ".bmp"          = "image/bmp"
    ".tiff"         = "image/tiff"
    ".woff"         = "font/woff"
    ".woff2"        = "font/woff2"
    ".ttf"          = "font/ttf"
    ".otf"          = "font/otf"
    ".eot"          = "application/vnd.ms-fontobject"
    ".mp4"          = "video/mp4"
    ".webm"         = "video/webm"
    ".ogg"          = "video/ogg"
    ".mp3"          = "audio/mpeg"
    ".wav"          = "audio/wav"
    ".flac"         = "audio/flac"
    ".zip"          = "application/zip"
    ".gz"           = "application/gzip"
    ".tar"          = "application/x-tar"
}
