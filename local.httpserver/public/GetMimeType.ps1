function GetMimeType {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    # ___________________________________________________________________________
    # -> Use $mimeType hashtable from module.config (Single Source of Truth)
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # $mimeType is loaded into the module scope via dot-sourcing of module.config
    # in local.httpserver.psm1. No JSON file is read here.

    # Resolve the $mimeType hashtable from the current or script scope
    $resolvedMimeTypes = $null

    if (Get-Variable -Name 'mimeType' -Scope Script -ErrorAction SilentlyContinue) {
        $resolvedMimeTypes = $script:mimeType
    } elseif (Get-Variable -Name 'mimeType' -ErrorAction SilentlyContinue) {
        $resolvedMimeTypes = $script:mimeType
    }

    # Safety fallback: if $mimeType is somehow not available, use a minimal built-in table
    if ($null -eq $resolvedMimeTypes -or $resolvedMimeTypes.Count -eq 0) {
        Write-Warning "[GetMimeType] Warning: \$mimeType hashtable is not available in scope. Using built-in fallback."
        $resolvedMimeTypes = @{
            "default" = "application/octet-stream"
            ".html"   = "text/html; charset=utf-8"
            ".htm"    = "text/html; charset=utf-8"
            ".css"    = "text/css; charset=utf-8"
            ".js"     = "application/javascript; charset=utf-8"
            ".json"   = "application/json; charset=utf-8"
            ".png"    = "image/png"
            ".jpg"    = "image/jpeg"
            ".jpeg"   = "image/jpeg"
            ".gif"    = "image/gif"
            ".svg"    = "image/svg+xml; charset=utf-8"
            ".ico"    = "image/x-icon"
            ".txt"    = "text/plain; charset=utf-8"
            ".wasm"   = "application/wasm"
        }
    }

    # Extract the file extension and look up the MIME type
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($resolvedMimeTypes.ContainsKey($ext)) {
        return $resolvedMimeTypes[$ext]
    }

    # Return application/octet-stream (default MIME type for unknown file types)
    return $resolvedMimeTypes['default']
}
