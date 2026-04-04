function AddAppxPackages {
    <#
    .SYNOPSIS
        Injects provisioned Appx packages into a mounted WIM image using DISM.

    .DESCRIPTION
        Iterates over all package entries stored in $script:appx['inject'] and invokes
        DISM /Add-ProvisionedAppxPackage for each entry against the mounted image at the
        specified mount point.

        Supported package file types: .appx, .appxbundle, .msix, .msixbundle

        Source resolution:
        Each entry in $script:appx['inject'] must be a PSCustomObject or hashtable with
        at least a 'PackageFile' property pointing to the package file name (without path).
        The function resolves the full path by looking for the file inside
        $script:appenv['AppxBundle'] (default: C:\WinISO\Appx).

        Optionally a 'LicenseFile' property (filename only) can be provided per entry.
        The function searches for it in the same AppxBundle directory.
        If no license file is found, the /SkipLicense switch is used automatically.

        Monitoring / self-cleaning:
        After each successful injection, the corresponding entry is removed from
        $script:appx['inject'] in the module scope. This means that after the function
        completes, $script:appx['inject'] contains ONLY the packages that could NOT be
        injected. An empty 'inject' array at the end signals a fully clean run.

    .PARAMETER MountPoint
        Full path to the directory where the WIM image is currently mounted.
        Defaults to $script:appenv['MountPoint'] when not provided.

    .PARAMETER AppxSourceDir
        Full path to the directory containing the .appx/.msix package files to inject.
        Defaults to $script:appenv['AppxBundle'] when not provided.

    .PARAMETER ContinueOnError
        Switch. If set, the function continues injecting remaining packages even when one
        DISM call fails. Without this switch, the first failure aborts the entire operation.
        Default: not set (abort on first failure).

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [hashtable] @{ Succeeded=[array]; Failed=[array] } on completion.
        .code = 0  if all packages were injected successfully.
        .code = -1 if one or more injections failed (or $script:appx['inject'] was empty).

    .EXAMPLE
        # Populate the inject list first
        $r = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
                        -VarKeyID 'inject' -SetNewVal @(
                            [PSCustomObject]@{ PackageFile = 'MyApp.msixbundle'; LicenseFile = 'MyApp_License.xml' }
                            [PSCustomObject]@{ PackageFile = 'AnotherApp.appx' }
                        )
        # Then inject
        $r = AddAppxPackages
        if ($r.code -eq 0) { Write-Host "All packages injected." }

    .EXAMPLE
        # Inject with custom source directory and error-continuation
        $r = AddAppxPackages -AppxSourceDir 'D:\MyAppxPackages' -ContinueOnError

    .NOTES
        Version:    1.00.05
        Written by: Praetoriani (a.k.a. M.Sczepanski)
        Requires:   DISM.exe on PATH, administrator privileges, OPSreturn, AppScope, WinISOcore
        The 'inject' key in $script:appx is modified in-place during execution:
        successfully injected entries are deleted; failed entries remain.
        Supported extensions: .appx | .appxbundle | .msix | .msixbundle
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Full path to the mounted WIM image directory.")]
        [string]$MountPoint = '',

        [Parameter(Mandatory = $false, HelpMessage = "Directory containing the Appx/MSIX package files.")]
        [string]$AppxSourceDir = '',

        [Parameter(Mandatory = $false, HelpMessage = "Continue injecting remaining packages even if one DISM call fails.")]
        [switch]$ContinueOnError
    )

    # ── Valid package extensions ───────────────────────────────────────────────────
    $ValidExtensions = @('.appx', '.appxbundle', '.msix', '.msixbundle')

    # ── Resolve mount point ──────────────────────────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($MountPoint)) {
        $EnvData = AppScope -KeyID 'appenv'
        if ($EnvData -is [PSCustomObject] -and $EnvData.PSObject.Properties['code']) {
            return (OPSreturn -Code -1 -Message "AddAppxPackages failed! Could not read module env: $($EnvData.msg)")
        }
        $MountPoint = $EnvData['MountPoint']
    }

    if ([string]::IsNullOrWhiteSpace($MountPoint)) {
        return (OPSreturn -Code -1 -Message "AddAppxPackages failed! Parameter 'MountPoint' is required and could not be resolved from module scope.")
    }

    # ── Resolve AppxBundle source directory ───────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($AppxSourceDir)) {
        $EnvData2 = AppScope -KeyID 'appenv'
        if ($EnvData2 -is [PSCustomObject] -and $EnvData2.PSObject.Properties['code']) {
            return (OPSreturn -Code -1 -Message "AddAppxPackages failed! Could not read module env for AppxBundle: $($EnvData2.msg)")
        }
        $AppxSourceDir = $EnvData2['AppxBundle']
    }

    if ([string]::IsNullOrWhiteSpace($AppxSourceDir)) {
        return (OPSreturn -Code -1 -Message "AddAppxPackages failed! Parameter 'AppxSourceDir' is required and could not be resolved from module scope.")
    }

    # ── Validate directories ─────────────────────────────────────────────────────
    if (-not (Test-Path -Path $MountPoint -PathType Container)) {
        return (OPSreturn -Code -1 -Message "AddAppxPackages failed! Mount point directory does not exist: '$MountPoint'")
    }

    if (-not (Test-Path -Path $AppxSourceDir -PathType Container)) {
        return (OPSreturn -Code -1 -Message "AddAppxPackages failed! Appx source directory does not exist: '$AppxSourceDir'")
    }

    $MountedImages = $null
    try {
        $MountedImages = Get-WindowsImage -Mounted -ErrorAction Stop |
                         Where-Object { $_.Path -eq $MountPoint }
    }
    catch {
        return (OPSreturn -Code -1 -Message "AddAppxPackages failed! Error querying mounted images: $($_.Exception.Message)")
    }

    if ($null -eq $MountedImages) {
        return (OPSreturn -Code -1 -Message "AddAppxPackages failed! No mounted WIM image found at '$MountPoint'. Mount the image first using MountWIMimage.")
    }

    # ── Read $script:appx['inject'] ──────────────────────────────────────────────
    $AppxData = AppScope -KeyID 'appx'
    if ($AppxData -is [PSCustomObject] -and $AppxData.PSObject.Properties['code']) {
        return (OPSreturn -Code -1 -Message "AddAppxPackages failed! Could not access `$script:appx: $($AppxData.msg)")
    }

    $InjectList = $AppxData['inject']
    if ($null -eq $InjectList -or $InjectList.Count -eq 0) {
        return (OPSreturn -Code -1 -Message "AddAppxPackages failed! `$script:appx['inject'] is empty. Add package entries before calling AddAppxPackages.")
    }

    # ── Process each package ─────────────────────────────────────────────────────
    $Succeeded = [System.Collections.Generic.List[object]]::new()
    $Failed    = [System.Collections.Generic.List[object]]::new()
    $Remaining = [System.Collections.Generic.List[object]]::new($InjectList)

    foreach ($pkg in $InjectList) {
        # Resolve PackageFile and LicenseFile properties
        $PkgFile     = $null
        $LicenseFile = $null

        if ($pkg -is [System.Collections.Hashtable] -or $pkg -is [System.Collections.Specialized.OrderedDictionary]) {
            $PkgFile     = [string]$pkg['PackageFile']
            $LicenseFile = [string]$pkg['LicenseFile']
        }
        elseif ($pkg -is [PSCustomObject]) {
            $PkgFile     = [string]$pkg.PackageFile
            $LicenseFile = if ($pkg.PSObject.Properties['LicenseFile']) { [string]$pkg.LicenseFile } else { '' }
        }
        else {
            $PkgFile = [string]$pkg
        }

        if ([string]::IsNullOrWhiteSpace($PkgFile)) {
            $Failed.Add($pkg)
            if (-not $ContinueOnError) { break }
            continue
        }

        # ── Validate extension ────────────────────────────────────────────────────
        $PkgExt = [System.IO.Path]::GetExtension($PkgFile).ToLower()
        if ($PkgExt -notin $ValidExtensions) {
            $Failed.Add($pkg)
            if (-not $ContinueOnError) { break }
            continue
        }

        # ── Resolve full paths ──────────────────────────────────────────────────────
        $FullPkgPath = Join-Path $AppxSourceDir $PkgFile
        if (-not (Test-Path -Path $FullPkgPath -PathType Leaf)) {
            $Failed.Add($pkg)
            if (-not $ContinueOnError) { break }
            continue
        }

        # ── Build DISM arguments ─────────────────────────────────────────────────────
        $DismArgs = "/Image:`"$MountPoint`" /Add-ProvisionedAppxPackage /PackagePath:`"$FullPkgPath`""

        # Try to resolve optional license file
        $UseLicense = $false
        if (-not [string]::IsNullOrWhiteSpace($LicenseFile)) {
            $FullLicPath = Join-Path $AppxSourceDir $LicenseFile
            if (Test-Path -Path $FullLicPath -PathType Leaf) {
                $DismArgs  += " /LicensePath:`"$FullLicPath`""
                $UseLicense = $true
            }
        }
        if (-not $UseLicense) {
            $DismArgs += ' /SkipLicense'
        }

        # ── Invoke DISM ───────────────────────────────────────────────────────────
        $DismExitCode = -1
        try {
            $DismProc = Start-Process -FilePath 'DISM.exe' -ArgumentList $DismArgs `
                        -Wait -PassThru -NoNewWindow -ErrorAction Stop
            $DismExitCode = $DismProc.ExitCode
        }
        catch {
            $DismExitCode = -1
        }

        if ($DismExitCode -eq 0) {
            $Succeeded.Add($pkg)
            $Remaining.Remove($pkg) | Out-Null
        }
        else {
            $Failed.Add($pkg)
            if (-not $ContinueOnError) { break }
        }
    }

    # ── Write back remaining (= failed) entries to module scope ─────────────────
    $RemainingArray = @($Remaining)
    $WriteResult = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
                              -VarKeyID 'inject' -SetNewVal $RemainingArray
    if ($WriteResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "AddAppxPackages: DISM processing done, but failed to update `$script:appx['inject']: $($WriteResult.msg)")
    }

    # ── Build result summary ─────────────────────────────────────────────────────
    $ResultData = @{
        Succeeded = @($Succeeded)
        Failed    = @($Failed)
    }

    if ($Failed.Count -eq 0) {
        return (OPSreturn -Code 0 `
            -Message "AddAppxPackages completed. $($Succeeded.Count) package(s) injected successfully. `$script:appx['inject'] is now empty." `
            -Data $ResultData)
    }
    else {
        return (OPSreturn -Code -1 `
            -Message "AddAppxPackages completed with errors. Succeeded: $($Succeeded.Count) | Failed: $($Failed.Count). Failed package(s) remain in `$script:appx['inject']." `
            -Data $ResultData)
    }
}
