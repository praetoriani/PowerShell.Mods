function GetLatestPowerShellSetup {
    <#
    .SYNOPSIS
        Downloads the latest PowerShell release from GitHub and optionally installs it silently.

    .DESCRIPTION
        GetLatestPowerShellSetup queries the GitHub Releases API for the PowerShell/PowerShell
        repository to automatically detect and download the latest stable release of PowerShell.
        Its functionality includes:
        - Automatically resolves the latest stable release tag via the GitHub Releases API
        - Supports three architecture/package variants: win-x64 (.msi), win-arm64 (.msi), win-msix (.msixbundle)
        - Creates the full download directory hierarchy if it does not already exist
        - Deletes and re-downloads an already existing installer file (always fresh copy)
        - Downloads the installer as a binary stream (byte-exact, suitable for all file types)
        - Verifies download completeness via content-length comparison
        - Optionally runs the installer silently (no user interaction) after download
        - Optionally deletes the installer after successful silent installation
        - Returns standardized OPSreturn objects (code 0 = success, code -1 = failure)

    .PARAMETER DownloadDir
        Full path to the directory where the installer will be saved.
        The complete directory hierarchy is created automatically if it does not exist.

    .PARAMETER Architecture
        Specifies which PowerShell package variant to download.
        Valid values:
          'win-x64'    » Downloads the PowerShell-X.Y.Z-win-x64.msi installer   (default)
          'win-arm64'  » Downloads the PowerShell-X.Y.Z-win-arm64.msi installer
          'win-msix'   » Downloads the PowerShell-X.Y.Z-win-x64.msixbundle package

    .PARAMETER RunInstaller
        Controls whether the downloaded installer is executed after download.
          0 » Download only – no installation is performed                        (default)
          1 » Download, then run the installer silently (no user interaction)
          2 » Download, run the installer silently, then delete the installer file

    .OUTPUTS
        PSCustomObject with the following fields:
          .code  » 0 = Success | -1 = Error
          .msg   » Human-readable description of the result
          .data  » Full path to the downloaded installer (on success), or $null

    .EXAMPLE
        $result = GetLatestPowerShellSetup -DownloadDir "C:\WinISO\Downloads\PowerShell" -Architecture "win-x64"
        if ($result.code -eq 0) { Write-Host "Downloaded: $($result.data)" }
        else                    { Write-Host "Failed: $($result.msg)" }

    .EXAMPLE
        $result = GetLatestPowerShellSetup `
            -DownloadDir  "C:\WinISO\Downloads\PowerShell" `
            -Architecture "win-x64" `
            -RunInstaller 2
        if ($result.code -eq 0) { Write-Host "Installed and cleaned up successfully." }

    .NOTES
        Dependency: The private function OPSreturn must exist in the same module.
        The GitHub Releases API endpoint used:
            https://api.github.com/repos/PowerShell/PowerShell/releases/latest
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Full path to the download directory")]
        [ValidateNotNullOrEmpty()]
        [string]$DownloadDir,

        [Parameter(Mandatory = $true, HelpMessage = "Target architecture / package type: win-x64 | win-arm64 | win-msix")]
        [ValidateSet('win-x64', 'win-arm64', 'win-msix')]
        [string]$Architecture = 'win-x64',

        [Parameter(Mandatory = $false, HelpMessage = "0 = download only | 1 = download + install | 2 = download + install + delete")]
        [ValidateSet(0, 1, 2)]
        [int]$RunInstaller = 0
    )

    # -------------------------------------------------------------------------
    # STEP 1 » Create DownloadDir (including full hierarchy) if not present
    # -------------------------------------------------------------------------
    try {
        if (-not (Test-Path -Path $DownloadDir -PathType Container)) {
            $null = New-Item -Path $DownloadDir -ItemType Directory -Force -ErrorAction Stop
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Could not create download directory '$DownloadDir': $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 2 » Query GitHub Releases API for the latest stable PowerShell release
    # -------------------------------------------------------------------------
    [string]$LatestTag    = [string]::Empty
    [string]$DownloadURL  = [string]::Empty
    [string]$FileName     = [string]::Empty

    try {
        $ApiUrl     = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
        $WebClient  = [System.Net.WebClient]::new()
        $WebClient.Headers.Add('User-Agent',  'PowerShell-GetLatestPowerShellSetup/1.0')
        $WebClient.Headers.Add('Accept',      'application/vnd.github+json')

        $RawJson    = $WebClient.DownloadString($ApiUrl)
        $WebClient.Dispose()

        $ReleaseData = $RawJson | ConvertFrom-Json

        if ($null -eq $ReleaseData -or [string]::IsNullOrWhiteSpace($ReleaseData.tag_name)) {
            return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! GitHub API returned an empty or invalid response.")
        }

        $LatestTag = $ReleaseData.tag_name   # e.g. "v7.5.1"
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Could not query GitHub Releases API: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 3 » Resolve the correct asset URL based on the Architecture parameter
    # -------------------------------------------------------------------------
    try {
        # Build the expected asset name pattern based on requested architecture
        switch ($Architecture) {
            'win-x64'   {
                $AssetPattern = "*-win-x64.msi"
            }
            'win-arm64' {
                $AssetPattern = "*-win-arm64.msi"
            }
            'win-msix'  {
                $AssetPattern = "*.msixbundle"
            }
        }

        # Search assets for a matching file
        $MatchedAsset = $ReleaseData.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1

        if ($null -eq $MatchedAsset) {
            return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! No matching asset found for Architecture='$Architecture' in release '$LatestTag'. Pattern used: '$AssetPattern'")
        }

        $DownloadURL = $MatchedAsset.browser_download_url
        $FileName    = $MatchedAsset.name

        if ([string]::IsNullOrWhiteSpace($DownloadURL)) {
            return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Resolved asset '$($MatchedAsset.name)' has no valid download URL.")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Error resolving asset download URL: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 4 » Build full destination path; delete if already present
    # -------------------------------------------------------------------------
    [string]$DestinationPath = [string]::Empty

    try {
        $DestinationPath = Join-Path -Path $DownloadDir -ChildPath $FileName

        if (Test-Path -Path $DestinationPath -PathType Leaf) {
            Remove-Item -Path $DestinationPath -Force -ErrorAction Stop
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Could not delete existing file '$DestinationPath': $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 5 » Check URL accessibility via HTTP HEAD request
    # -------------------------------------------------------------------------
    [long]$ExpectedBytes = 0

    try {
        $HttpRequest         = [System.Net.HttpWebRequest]::Create($DownloadURL)
        $HttpRequest.Method  = 'HEAD'
        $HttpRequest.Timeout = 20000   # 20-second timeout

        $HttpResponse = $HttpRequest.GetResponse()
        $StatusCode   = [int]$HttpResponse.StatusCode

        if ($StatusCode -ne 200) {
            $HttpResponse.Close()
            return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Server responded with HTTP $StatusCode for: $DownloadURL")
        }

        $ExpectedBytes = $HttpResponse.ContentLength
        $HttpResponse.Close()
    }
    catch [System.Net.WebException] {
        $StatusCode = [int]$_.Exception.Response.StatusCode
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Download URL not reachable (HTTP $StatusCode): $($_.Exception.Message)")
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Error checking download URL reachability: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 6 » Perform binary download
    # -------------------------------------------------------------------------
    [byte[]]$FileBytes = $null

    try {
        $WebClient2 = [System.Net.WebClient]::new()
        $WebClient2.Headers.Add('User-Agent', 'PowerShell-GetLatestPowerShellSetup/1.0')

        $FileBytes = $WebClient2.DownloadData($DownloadURL)
        $WebClient2.Dispose()

        if ($null -eq $FileBytes -or $FileBytes.Length -eq 0) {
            return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Download returned 0 bytes for: $DownloadURL")
        }
    }
    catch [System.Net.WebException] {
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Network error during download: $($_.Exception.Message)")
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Unexpected error during download: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 7 » Verify completeness (downloaded vs. expected bytes)
    # -------------------------------------------------------------------------
    try {
        if ($ExpectedBytes -gt 0) {
            if ($FileBytes.Length -ne $ExpectedBytes) {
                return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Download incomplete: Expected=$ExpectedBytes bytes / Received=$($FileBytes.Length) bytes")
            }
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Error during completeness check: $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 8 » Write file to disk (binary, byte-exact)
    # -------------------------------------------------------------------------
    try {
        [System.IO.File]::WriteAllBytes($DestinationPath, $FileBytes)

        if (-not (Test-Path -Path $DestinationPath -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! File was not written to disk: '$DestinationPath'")
        }

        $WrittenSize = (Get-Item -Path $DestinationPath).Length

        if (($ExpectedBytes -gt 0) -and ($WrittenSize -ne $ExpectedBytes)) {
            return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Written file size ($WrittenSize bytes) does not match expected ($ExpectedBytes bytes).")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Could not write file to '$DestinationPath': $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # STEP 9 » Optional: Silent installation (RunInstaller 1 or 2)
    # -------------------------------------------------------------------------
    if ($RunInstaller -ge 1) {
        try {
            $Extension = [System.IO.Path]::GetExtension($DestinationPath).ToLower()

            if ($Extension -eq '.msi') {
                # Silent MSI installation via msiexec – no user interaction, no reboot prompt
                $MsiArgs    = @('/i', "`"$DestinationPath`"", '/quiet', '/norestart', 'ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1', 'ENABLE_PSREMOTING=0', 'REGISTER_MANIFEST=1')
                $MsiProcess = Start-Process -FilePath 'msiexec.exe' -ArgumentList $MsiArgs -Wait -PassThru -ErrorAction Stop

                if ($MsiProcess.ExitCode -ne 0) {
                    return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! msiexec.exe exited with code $($MsiProcess.ExitCode) for: '$DestinationPath'")
                }
            }
            elseif ($Extension -eq '.msixbundle') {
                # Silent MSIX installation via Add-AppxPackage
                Add-AppxPackage -Path $DestinationPath -ErrorAction Stop
            }
            else {
                return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Unknown installer extension '$Extension' – cannot run silent install.")
            }
        }
        catch {
            return (OPSreturn -Code -1 -Message "GetLatestPowerShellSetup failed! Silent installation error: $($_.Exception.Message)")
        }

        # ---------------------------------------------------------------------
        # STEP 10 » Optional: Delete installer after successful installation (RunInstaller 2)
        # ---------------------------------------------------------------------
        if ($RunInstaller -eq 2) {
            try {
                if (Test-Path -Path $DestinationPath -PathType Leaf) {
                    Remove-Item -Path $DestinationPath -Force -ErrorAction Stop
                }
            }
            catch {
                # Installation was successful - only warn, do not fail the overall operation
                return (OPSreturn -Code 0 -Message "GetLatestPowerShellSetup: Installation of '$FileName' ($LatestTag) completed successfully. WARNING: Installer file could not be deleted: $($_.Exception.Message)" -Data $DestinationPath)
            }

            return (OPSreturn -Code 0 -Message "GetLatestPowerShellSetup successful! '$FileName' ($LatestTag) installed silently and installer deleted." -Data $DestinationPath)
        }

        return (OPSreturn -Code 0 -Message "GetLatestPowerShellSetup successful! '$FileName' ($LatestTag) downloaded ($WrittenSize bytes) and installed silently." -Data $DestinationPath)
    }

    # -------------------------------------------------------------------------
    # SUCCESS » Download only (RunInstaller = 0)
    # -------------------------------------------------------------------------
    return (OPSreturn -Code 0 -Message "GetLatestPowerShellSetup successful! '$FileName' ($LatestTag) downloaded to '$DestinationPath' ($WrittenSize bytes)." -Data $DestinationPath)
}
