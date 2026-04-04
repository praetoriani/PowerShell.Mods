function GetAppxPackages {
    <#
    .SYNOPSIS
        Lists all provisioned Appx packages from a mounted WIM image.

    .DESCRIPTION
        Uses Get-AppxProvisionedPackage (DISM PowerShell module) to enumerate all
        provisioned Appx packages from a mounted Windows image at the specified
        mount point.

        The result is always stored in the module-scope variable $script:appx['listed']
        as an array of PSCustomObjects. Each entry contains the most relevant package
        properties (DisplayName, PackageName, Version, Architecture, PublisherId) so
        that downstream functions (RemAppxPackages, AppxPackageLookUp) can process them
        without re-querying DISM.

        Optionally the list can be exported to a file in one of three formats:
          - TXT  : human-readable Format-List output (UTF-8)
          - CSV  : comma-separated with headers
          - JSON : formatted JSON array

    .PARAMETER MountPoint
        Full path to the directory where the WIM image is currently mounted.
        Defaults to $script:appenv['MountPoint'] when not provided.

    .PARAMETER ExportFile
        Optional. Full path (including filename and extension) for the export file.
        If omitted, no file is written. The extension does NOT need to match the
        Format parameter — it is purely cosmetic; the Format parameter controls
        the actual output structure.

    .PARAMETER Format
        Export file format. Valid values: TXT | CSV | JSON
        Only evaluated when -ExportFile is provided.
        Default: TXT

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [array] of PSCustomObjects on success, $null on failure.
        Each object has: DisplayName, PackageName, Version, Architecture, PublisherId

    .EXAMPLE
        # Virtual only – results stored in $script:appx['listed']
        $r = GetAppxPackages
        if ($r.code -eq 0) { $r.data | ForEach-Object { Write-Host $_.DisplayName } }

    .EXAMPLE
        # Virtual + export as CSV
        $r = GetAppxPackages -ExportFile 'C:\WinISO\Appx-Packages.csv' -Format CSV

    .EXAMPLE
        # Custom mount point, export as JSON
        $r = GetAppxPackages -MountPoint 'D:\WIM\MountPoint' `
                             -ExportFile 'C:\WinISO\Appx-Packages.json' `
                             -Format JSON

    .NOTES
        Version:    1.00.05
        Written by: Praetoriani (a.k.a. M.Sczepanski)
        Requires:   DISM PowerShell module, administrator privileges, OPSreturn, AppScope, WinISOcore
        After a successful run, $script:appx['listed'] is replaced with the new result array.
        On failure, $script:appx['listed'] is left unchanged.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Full path to the mounted WIM image directory.")]
        [string]$MountPoint = '',

        [Parameter(Mandatory = $false, HelpMessage = "Optional full path (incl. filename) for the export file.")]
        [string]$ExportFile = '',

        [Parameter(Mandatory = $false, HelpMessage = "Export format: TXT | CSV | JSON. Only used when -ExportFile is provided.")]
        [ValidateSet('TXT', 'CSV', 'JSON', IgnoreCase = $true)]
        [string]$Format = 'TXT'
    )

    # ── Resolve mount point ──────────────────────────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($MountPoint)) {
        $EnvData = AppScope -KeyID 'appenv'
        if ($EnvData -is [PSCustomObject] -and $EnvData.PSObject.Properties['code']) {
            return (OPSreturn -Code -1 -Message "GetAppxPackages failed! Could not read module env: $($EnvData.msg)")
        }
        $MountPoint = $EnvData['MountPoint']
    }

    if ([string]::IsNullOrWhiteSpace($MountPoint)) {
        return (OPSreturn -Code -1 -Message "GetAppxPackages failed! Parameter 'MountPoint' is required and could not be resolved from module scope.")
    }

    # ── Validate mount point ─────────────────────────────────────────────────────
    if (-not (Test-Path -Path $MountPoint -PathType Container)) {
        return (OPSreturn -Code -1 -Message "GetAppxPackages failed! Mount point directory does not exist: '$MountPoint'")
    }

    $MountedImages = $null
    try {
        $MountedImages = Get-WindowsImage -Mounted -ErrorAction Stop |
                         Where-Object { $_.Path -eq $MountPoint }
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetAppxPackages failed! Error querying mounted images: $($_.Exception.Message)")
    }

    if ($null -eq $MountedImages) {
        return (OPSreturn -Code -1 -Message "GetAppxPackages failed! No mounted WIM image found at '$MountPoint'. Mount the image first using MountWIMimage.")
    }

    # ── Query provisioned Appx packages ─────────────────────────────────────────
    $RawPackages = $null
    try {
        $RawPackages = Get-AppxProvisionedPackage -Path $MountPoint -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code -1 -Message "GetAppxPackages failed! Get-AppxProvisionedPackage error at '$MountPoint': $($_.Exception.Message)")
    }

    if ($null -eq $RawPackages -or ($RawPackages | Measure-Object).Count -eq 0) {
        return (OPSreturn -Code -1 -Message "GetAppxPackages failed! No provisioned Appx packages found at '$MountPoint'. The image may be empty or the mount is incomplete.")
    }

    # ── Build normalized list ────────────────────────────────────────────────────
    $PackageList = @()
    foreach ($pkg in $RawPackages) {
        $PackageList += [PSCustomObject]@{
            DisplayName  = [string]$pkg.DisplayName
            PackageName  = [string]$pkg.PackageName
            Version      = [string]$pkg.Version
            Architecture = [string]$pkg.Architecture
            PublisherId  = [string]$pkg.PublisherId
        }
    }

    # ── Write to module scope via WinISOcore ─────────────────────────────────────
    $WriteResult = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
                              -VarKeyID 'listed' -SetNewVal $PackageList
    if ($WriteResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "GetAppxPackages failed! Could not write to `$script:appx['listed']: $($WriteResult.msg)")
    }

    # ── Optional file export ─────────────────────────────────────────────────────
    if (-not [string]::IsNullOrWhiteSpace($ExportFile)) {
        $FormatNorm = $Format.ToUpper()
        try {
            # Ensure export directory exists
            $ExportDir = Split-Path -Path $ExportFile -Parent
            if ($ExportDir -and -not (Test-Path -Path $ExportDir)) {
                New-Item -ItemType Directory -Path $ExportDir -Force | Out-Null
            }

            switch ($FormatNorm) {
                'TXT' {
                    $PackageList | Format-List * | Out-File -FilePath $ExportFile -Encoding UTF8 -Force
                }
                'CSV' {
                    $PackageList | Export-Csv -Path $ExportFile -Encoding UTF8 -NoTypeInformation -Force
                }
                'JSON' {
                    $PackageList | ConvertTo-Json -Depth 4 |
                        Out-File -FilePath $ExportFile -Encoding UTF8 -Force
                }
            }
        }
        catch {
            # Export failure is non-fatal – data is already stored in module scope
            return (OPSreturn -Code 0 `
                -Message "GetAppxPackages completed. $($PackageList.Count) package(s) stored in `$script:appx['listed']. WARNING: Export to '$ExportFile' failed: $($_.Exception.Message)" `
                -Data $PackageList)
        }

        return (OPSreturn -Code 0 `
            -Message "GetAppxPackages completed. $($PackageList.Count) package(s) stored in `$script:appx['listed'] and exported to '$ExportFile' ($FormatNorm)." `
            -Data $PackageList)
    }

    # ── Virtual-only success ─────────────────────────────────────────────────────
    return (OPSreturn -Code 0 `
        -Message "GetAppxPackages completed. $($PackageList.Count) provisioned package(s) stored in `$script:appx['listed']." `
        -Data $PackageList)
}
