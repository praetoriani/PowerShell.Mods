function GetMimeType {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    [hashtable]$mimeTypes = @{}

    # Load Configuration from JSON
    $mimeTypes = ReadJSON -Location $httpCore.config.mime
    # Exit on error
    if ($mimeTypes.code -ne 0) { Write-Error $mimeTypes.msg; exit 1 }
    # unwrap the data from the return object to obtain the plain deserialized JSON content
    $mimeTypes = $mimeTypes.data

    # Extract the file extension and look up the MIME type
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($mimeTypes.ContainsKey($ext)) {
        return $mimeTypes[$ext]
    }
    
    # Return application/octet-stream (default MIME type for unknown file types)
    return $mimeTypes['default']
}