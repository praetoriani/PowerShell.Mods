function AppxPackageLookUp {
    <#
    .SYNOPSIS
        Checks whether one or more Appx/MSIX packages exist in a mounted WIM image
        or verifies a given package file can be injected from the Appx source directory.

    .DESCRIPTION
        AppxPackageLookUp serves as the verification layer for AppxPackage operations.
        It supports two independent but complementary lookup modes:

        Mode 1 – IMAGE (default)
        ────────────────────────
        Queries the provisioned Appx packages currently in the mounted WIM image
        (via Get-AppxProvisionedPackage) and checks whether a given search string
        matches any package. The search is performed as a case-insensitive substring
        match against both DisplayName and PackageName.

        If $script:appx['listed'] is already populated (e.g. by a prior call to
        GetAppxPackages), the cached list is used instead of re-querying DISM —
        pass -ForceRefresh to bypass the cache and query DISM directly.

        Mode 2 – FILE
        ─────────────
        Checks whether a given package file (.appx, .appxbundle, .msix, .msixbundle)
        physically exists in the configured Appx source directory
        ($script:appenv['AppxBundle'] or the -AppxSourceDir override).

        Both modes can be combined in a single call.

    .PARAMETER SearchTerm
        The package name, display name fragment, or file name to search for.
        Used as a case-insensitive substring match in IMAGE mode and as an exact
        file name match (with extension) in FILE mode.
        At least one of -SearchTerm or -PackageFile must be provided.

    .PARAMETER PackageFile
        File name (with extension) of the package to check for in FILE mode.
        Supported extensions: .appx, .appxbundle, .msix, .msixbundle
        If provided, a physical file existence check is performed in -AppxSourceDir.

    .PARAMETER MountPoint
        Full path to the directory where the WIM image is currently mounted.
        Defaults to $script:appenv['MountPoint'] when not provided.
        Only required when checking the image (Mode 1).

    .PARAMETER AppxSourceDir
        Full path to the directory containing Appx/MSIX package files.
        Defaults to $script:appenv['AppxBundle'] when not provided.
        Only required when -PackageFile is specified (Mode 2).

    .PARAMETER ForceRefresh
        Switch. Forces a fresh DISM query even when $script:appx['listed'] is already
        populated. The refreshed data is also written back to $script:appx['listed'].

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [hashtable] with the following keys:
            ImageMatches  [array]   – list of matching provisioned package objects found in image
                                      (each: DisplayName, PackageName, Version, Architecture, PublisherId)
            FileExists    [bool]    – $true if -PackageFile was found in AppxSourceDir; $false otherwise.
                                      $null when -PackageFile was not specified.
            SearchTerm    [string]  – the search term used (or empty string if not provided)
            PackageFile   [string]  – the package file name checked (or empty string if not provided)
        .code = 0  if the lookup executed without errors (even if no matches were found).
        .code = -1 if a required parameter is missing, a directory is invalid, or DISM fails.

    .EXAMPLE
        # Check if 'BingWeather' exists in the mounted image
        $r = AppxPackageLookUp -SearchTerm 'BingWeather'
        if ($r.code -eq 0 -and $r.data.ImageMatches.Count -gt 0) {
            Write-Host "Found: $($r.data.ImageMatches[0].PackageName)"
        }

    .EXAMPLE
        # Check if a package file exists in the Appx source directory
        $r = AppxPackageLookUp -PackageFile 'MyApp.msixbundle'
        if ($r.data.FileExists) { Write-Host "Package file is ready to inject." }

    .EXAMPLE
        # Combined: check both image presence and file availability
        $r = AppxPackageLookUp -SearchTerm 'MyApp' -PackageFile 'MyApp.msixbundle' -ForceRefresh

    .EXAMPLE
        # Use with custom paths
        $r = AppxPackageLookUp -SearchTerm 'Calculator' `
                               -MountPoint 'D:\WIM\MountPoint' `
                               -AppxSourceDir 'D:\MyAppxFiles'

    .NOTES
        Version:    1.00.05
        Written by: Praetoriani (a.k.a. M.Sczepanski)
        Requires:   DISM PowerShell module (for image mode), OPSreturn, AppScope, WinISOcore
        A .code = 0 result with an empty ImageMatches array means the search ran
        successfully but the package was NOT found in the image.
        Supported file extensions for FILE mode: .appx | .appxbundle | .msix | .msixbundle
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Case-insensitive substring to search in DisplayName and PackageName.")]
        [string]$SearchTerm = '',

        [Parameter(Mandatory = $false, HelpMessage = "Package file name (with extension) to check in AppxSourceDir.")]
        [string]$PackageFile = '',

        [Parameter(Mandatory = $false, HelpMessage = "Full path to the mounted WIM image directory.")]
        [string]$MountPoint = '',

        [Parameter(Mandatory = $false, HelpMessage = "Directory containing the Appx/MSIX package files.")]
        [string]$AppxSourceDir = '',

        [Parameter(Mandatory = $false, HelpMessage = "Force fresh DISM query even if script:appx['listed'] is already populated.")]
        [switch]$ForceRefresh
    )

    # ── Valid package extensions ───────────────────────────────────────────────────
    $ValidExtensions = @('.appx', '.appxbundle', '.msix', '.msixbundle')

    # ── At least one mode must be active ──────────────────────────────────────────
    $DoImageLookup = -not [string]::IsNullOrWhiteSpace($SearchTerm)
    $DoFileLookup  = -not [string]::IsNullOrWhiteSpace($PackageFile)

    if (-not $DoImageLookup -and -not $DoFileLookup) {
        return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! At least one of -SearchTerm or -PackageFile must be provided.")
    }

    # ── Resolve env paths ───────────────────────────────────────────────────────
    $EnvData = AppScope -KeyID 'appenv'
    if ($EnvData -is [PSCustomObject] -and $EnvData.PSObject.Properties['code']) {
        return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! Could not read module env: $($EnvData.msg)")
    }

    if ([string]::IsNullOrWhiteSpace($MountPoint))    { $MountPoint    = $EnvData['MountPoint']  }
    if ([string]::IsNullOrWhiteSpace($AppxSourceDir)) { $AppxSourceDir = $EnvData['AppxBundle']  }

    # ── Initialize result object ───────────────────────────────────────────────────
    $ResultData = @{
        ImageMatches = @()
        FileExists   = $null
        SearchTerm   = $SearchTerm
        PackageFile  = $PackageFile
    }

    # ══════════════════════════════════════════════════════════════════════════════
    # MODE 1 – IMAGE LOOKUP
    # ══════════════════════════════════════════════════════════════════════════════
    if ($DoImageLookup) {
        # Validate mount point
        if ([string]::IsNullOrWhiteSpace($MountPoint)) {
            return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! 'MountPoint' is required for image lookup and could not be resolved from module scope.")
        }

        if (-not (Test-Path -Path $MountPoint -PathType Container)) {
            return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! Mount point directory does not exist: '$MountPoint'")
        }

        # Determine whether to use cached list or re-query DISM
        $PackageSource = @()

        $AppxData = AppScope -KeyID 'appx'
        $CachedList = if ($AppxData -isnot [PSCustomObject] -or -not $AppxData.PSObject.Properties['code']) {
            $AppxData['listed']
        }
        else { @() }

        $UseCache = (-not $ForceRefresh) -and ($null -ne $CachedList) -and ($CachedList.Count -gt 0)

        if ($UseCache) {
            $PackageSource = $CachedList
        }
        else {
            # Validate that a WIM is actually mounted
            $MountedImages = $null
            try {
                $MountedImages = Get-WindowsImage -Mounted -ErrorAction Stop |
                                 Where-Object { $_.Path -eq $MountPoint }
            }
            catch {
                return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! Error querying mounted images: $($_.Exception.Message)")
            }

            if ($null -eq $MountedImages) {
                return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! No mounted WIM image found at '$MountPoint'. Mount the image first using MountWIMimage.")
            }

            # Fresh DISM query
            $RawPackages = $null
            try {
                $RawPackages = Get-AppxProvisionedPackage -Path $MountPoint -ErrorAction Stop
            }
            catch {
                return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! Get-AppxProvisionedPackage error at '$MountPoint': $($_.Exception.Message)")
            }

            if ($null -ne $RawPackages -and ($RawPackages | Measure-Object).Count -gt 0) {
                foreach ($p in $RawPackages) {
                    $PackageSource += [PSCustomObject]@{
                        DisplayName  = [string]$p.DisplayName
                        PackageName  = [string]$p.PackageName
                        Version      = [string]$p.Version
                        Architecture = [string]$p.Architecture
                        PublisherId  = [string]$p.PublisherId
                    }
                }

                # Update cache
                WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
                           -VarKeyID 'listed' -SetNewVal $PackageSource | Out-Null
            }
        }

        # Perform substring search against DisplayName and PackageName
        $SearchLower  = $SearchTerm.ToLower()
        $ImageMatches = @($PackageSource | Where-Object {
            $_.DisplayName.ToLower()  -like "*$SearchLower*" -or
            $_.PackageName.ToLower()  -like "*$SearchLower*"
        })

        $ResultData['ImageMatches'] = $ImageMatches
    }

    # ══════════════════════════════════════════════════════════════════════════════
    # MODE 2 – FILE LOOKUP
    # ══════════════════════════════════════════════════════════════════════════════
    if ($DoFileLookup) {
        # Validate extension
        $FileExt = [System.IO.Path]::GetExtension($PackageFile).ToLower()
        if ($FileExt -notin $ValidExtensions) {
            return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! '$PackageFile' has unsupported extension '$FileExt'. Allowed: $($ValidExtensions -join ', ')")
        }

        if ([string]::IsNullOrWhiteSpace($AppxSourceDir)) {
            return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! 'AppxSourceDir' is required for file lookup and could not be resolved from module scope.")
        }

        if (-not (Test-Path -Path $AppxSourceDir -PathType Container)) {
            return (OPSreturn -Code -1 -Message "AppxPackageLookUp failed! Appx source directory does not exist: '$AppxSourceDir'")
        }

        $FullFilePath = Join-Path $AppxSourceDir $PackageFile
        $ResultData['FileExists'] = (Test-Path -Path $FullFilePath -PathType Leaf)
    }

    # ── Build result message ─────────────────────────────────────────────────────
    $MsgParts = @()

    if ($DoImageLookup) {
        $MatchCount = $ResultData['ImageMatches'].Count
        if ($MatchCount -gt 0) {
            $MsgParts += "Image lookup: $MatchCount match(es) found for '$SearchTerm'."
        }
        else {
            $MsgParts += "Image lookup: No matches found for '$SearchTerm'."
        }
    }

    if ($DoFileLookup) {
        if ($ResultData['FileExists']) {
            $MsgParts += "File lookup: '$PackageFile' found in '$AppxSourceDir'."
        }
        else {
            $MsgParts += "File lookup: '$PackageFile' NOT found in '$AppxSourceDir'."
        }
    }

    $SummaryMsg = "AppxPackageLookUp completed. " + ($MsgParts -join ' ')

    return (OPSreturn -Code 0 -Message $SummaryMsg -Data $ResultData)
}
