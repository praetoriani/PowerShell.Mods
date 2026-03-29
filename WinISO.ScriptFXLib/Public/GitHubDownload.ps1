function GitHubDownload {
    <#
    .SYNOPSIS
        Downloades a single file from a public GitHub repository..

    .DESCRIPTION
        GitHubDownload downloads a file from a GitHub URL (or raw.githubusercontent.com URL)
        and saves it to the specified destination path. Its functionality includes:
        - Automatically converts github.com/tree/... URLs to raw.githubusercontent.com URLs
        - Checks the reachability of the source via an HTTP HEAD request
        - Ensures that the source and destination files have the same file extension
        - Downloads by byte – works for all file types (.exe, .ps1, .zip, etc.)
        - Verifies the download's completeness via content-length comparison
        - Returns standardized OPSreturn objects (code 0 = success, code -1 = failure)

    .PARAMETER URL
        The GitHub URL of the file to be downloaded.
        Supports both github.com/blob/... and raw.githubusercontent.com URLs.

    .PARAMETER SaveTo
        Full target path including filename, e.g. "C:\Tools\oscdimg.exe"

    .OUTPUTS
        PSCustomObject with the following fields:
        .code » 0 = Success | -1 = Error
        .msg » Description of the result
        .data » $null or additional data (e.g., saved path)

    .EXAMPLE
        $result = GitHubDownload `
            -URL    "https://github.com/praetoriani/PowerShell.Mods/blob/main/WinISO.ScriptFXLib/Requirements/oscdimg.exe" `
            -SaveTo "C:\Tools\oscdimg.exe"
        if ($result.code -eq 0) { Write-Host "Success: $($result.msg)" }
        else                     { Write-Host "Failed: $($result.msg)" }

    .NOTES
        Dependency: The private function OPSreturn must exist in the same module..
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "GitHub URL of the file to be downloaded")]
        [ValidateNotNullOrEmpty()]
        [string]$URL,

        [Parameter(Mandatory = $true, HelpMessage = "Full target path including filename")]
        [ValidateNotNullOrEmpty()]
        [string]$SaveTo
    )

    # -------------------------------------------------------------------------
    # STEP 1 » Convert GitHub browser URL → raw.githubusercontent.com
    # -------------------------------------------------------------------------
    try {
        $RawURL = $URL

        # github.com/.../blob/BRANCH/path  →  raw.githubusercontent.com/.../BRANCH/path
        if ($RawURL -match '^https://github\.com/([^/]+)/([^/]+)/blob/(.+)$') {
            $RawURL = "https://raw.githubusercontent.com/$($Matches[1])/$($Matches[2])/$($Matches[3])"
        }
        # github.com/.../tree/BRANCH/path  →  raw.githubusercontent.com/.../BRANCH/path
        elseif ($RawURL -match '^https://github\.com/([^/]+)/([^/]+)/tree/(.+)$') {
            $RawURL = "https://raw.githubusercontent.com/$($Matches[1])/$($Matches[2])/$($Matches[3])"
        }
        # Leave an existing raw URL or other direct URL unchanged.
    }
    catch {
        return (OPSreturn -Code -1 -Message "GitHubDownload failed! URL conversion failed: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 2 » Compare file extensions of source and destination
    # -------------------------------------------------------------------------
    try {
        $SourceExtension = [System.IO.Path]::GetExtension($RawURL).ToLower()
        $TargetExtension = [System.IO.Path]::GetExtension($SaveTo).ToLower()

        # Only check if both have an extension (e.g., .exe, .ps1, .zip)
        if (($SourceExtension -ne '') -and ($TargetExtension -ne '')) {
            if ($SourceExtension -ne $TargetExtension) {
                return (OPSreturn -Code -1 -Message "GitHubDownload failed! File extension does not match: Source='$SourceExtension' / Target='$TargetExtension'")
            }
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GitHubDownload failed! Error checking file extensions: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 3 » Create target directory (if it does not already exist)
    # -------------------------------------------------------------------------
    try {
        $TargetDir = [System.IO.Path]::GetDirectoryName($SaveTo)

        if ([string]::IsNullOrWhiteSpace($TargetDir)) {
            return (OPSreturn -Code -1 -Message "GitHubDownload failed! The target path '$SaveTo' does not contain a valid directory.")
        }

        if (-not (Test-Path -Path $TargetDir -PathType Container)) {
            $null = New-Item -Path $TargetDir -ItemType Directory -Force -ErrorAction Stop
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GitHubDownload failed! Target directory '$TargetDir' could not be created: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 4 » Check URL accessibility via HTTP HEAD request
    # -------------------------------------------------------------------------
    [long]$ExpectedBytes = 0

    try {
        $HttpRequest          = [System.Net.HttpWebRequest]::Create($RawURL)
        $HttpRequest.Method   = 'HEAD'
        $HttpRequest.Timeout  = 15000   # 15-second timeout

        $HttpResponse = $HttpRequest.GetResponse()
        $StatusCode   = [int]$HttpResponse.StatusCode

        if ($StatusCode -ne 200) {
            $HttpResponse.Close()
            return (OPSreturn -Code -1 -Message "GitHubDownload failed! Server responded with HTTP $StatusCode for URL: $RawURL")
        }

        # Save content length for later completeness check
        $ExpectedBytes = $HttpResponse.ContentLength
        $HttpResponse.Close()
    }
    catch [System.Net.WebException] {
        $StatusCode = [int]$_.Exception.Response.StatusCode
        return (OPSreturn -Code -1 -Message "GitHubDownload failed! Source not reachable (HTTP $StatusCode): $($_.Exception.Message)")
    }
    catch {
        return (OPSreturn -Code -1 -Message "GitHubDownload failed! Error checking download URL: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 5 » Perform binary download (WebClient / Stream-based)
    # -------------------------------------------------------------------------
    try {
        $WebClient                  = [System.Net.WebClient]::new()
        $WebClient.Headers['User-Agent'] = 'PowerShell-GitHubDownload/1.0'

        # Binary download to byte array (works for ALL file types)
        [byte[]]$FileBytes = $WebClient.DownloadData($RawURL)
        $WebClient.Dispose()

        if ($null -eq $FileBytes -or $FileBytes.Length -eq 0) {
            return (OPSreturn -Code -1 -Message "GitHubDownload failed! Download returned no data (0 bytes) for: $RawURL")
        }
    }
    catch [System.Net.WebException] {
        return (OPSreturn -Code -1 -Message "GitHubDownload failed! Network error during download: $($_.Exception.Message)")
    }
    catch {
        return (OPSreturn -Code -1 -Message "GitHubDownload failed! Unexpected error during download: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 6 » Check completeness (downloaded vs. expected bytes)
    # -------------------------------------------------------------------------
    try {
        # Content length was known (-1 = unknown/chunked → skip then)
        if ($ExpectedBytes -gt 0) {
            if ($FileBytes.Length -ne $ExpectedBytes) {
                return (OPSreturn -Code -1 -Message "GitHubDownload failed! Download incomplete: Expected=$ExpectedBytes bytes / Received=$($FileBytes.Length) bytes")
            }
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GitHubDownload failed! Error checking completeness: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 7 » Write file to disk in binary format
    # -------------------------------------------------------------------------
    try {
        [System.IO.File]::WriteAllBytes($SaveTo, $FileBytes)

        # Schreibvorgang verifizieren
        if (-not (Test-Path -Path $SaveTo -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "GitHubDownload failed! File was not written: '$SaveTo'")
        }

        $WrittenFileSize = (Get-Item -Path $SaveTo).Length

        if (($ExpectedBytes -gt 0) -and ($WrittenFileSize -ne $ExpectedBytes)) {
            return (OPSreturn -Code -1 -Message "GitHubDownload failed! Written file size ($WrittenFileSize Bytes) does not match expected value ($ExpectedBytes Bytes).")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GitHubDownload failed! Could not write file to '$SaveTo': $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # SUCCESS » Everything completed
    # -------------------------------------------------------------------------
    return (OPSreturn -Code 0 -Message "GitHubDownload successful! '$SaveTo' was downloaded ($WrittenFileSize Bytes)." -Data $SaveTo)
}