function GetMimeType {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    # Load Configuration from JSON
    if (Test-Path $httpCore.config.mime) {
        try {
            $mimeTypes = Get-Content $httpCore.config.mime -Raw | ConvertFrom-Json -ErrorAction Stop
            Write-Information "[INFO] Configuration successfully loaded from $($httpCore.config.mime)"
        }
        catch {
            Write-Error "[ERROR] Failed to load JSON: $($_.Exception.Message)"
            exit 1
        }
    }
    else {
        Write-Error "[ERROR] Configuration file not found: $coreJSON"
        exit 1
    }
    # Extract the file extension and look up the MIME type
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($mimeTypes.ContainsKey($ext)) {
        return $mimeTypes[$ext]
    }
    
    # Return application/octet-stream (default MIME type for unknown file types)
    return $mimeTypes['default']
}