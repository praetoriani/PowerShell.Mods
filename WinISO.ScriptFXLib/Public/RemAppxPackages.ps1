function RemAppxPackages {
    <#
    .SYNOPSIS
        Removes provisioned Appx packages from a mounted WIM image using DISM.

    .DESCRIPTION
        Iterates over all package entries stored in $script:appx['remove'] and invokes
        DISM /Remove-ProvisionedAppxPackage for each entry against the mounted image at
        the specified mount point.

        Supported package file types include .appx, .appxbundle, .msix, .msixbundle and
        any provisioned package identified by its full PackageName string.

        Monitoring / self-cleaning:
        After each successful removal, the corresponding entry is removed from
        $script:appx['remove'] in the module scope. This means that after the function
        completes, $script:appx['remove'] contains ONLY the packages that could NOT be
        removed (either DISM reported an error or the package was not found in the image).
        An empty 'remove' array at the end signals a fully clean run.

        Each entry in $script:appx['remove'] must be a PSCustomObject or hashtable with
        at least a 'PackageName' property (the full provisioned package name string as
        returned by GetAppxPackages / DISM).

    .PARAMETER MountPoint
        Full path to the directory where the WIM image is currently mounted.
        Defaults to $script:appenv['MountPoint'] when not provided.

    .PARAMETER ContinueOnError
        Switch. If set, the function continues removing remaining packages even when one
        DISM call fails. Without this switch, the first failure aborts the entire operation.
        Default: not set (abort on first failure).

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [hashtable] @{ Succeeded=[array]; Failed=[array] } on completion.
        .code = 0  if all packages were removed successfully.
        .code = -1 if one or more removals failed (or $script:appx['remove'] was empty).

    .EXAMPLE
        # Populate the remove list first
        $r = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
                        -VarKeyID 'remove' -SetNewVal @(
                            [PSCustomObject]@{ PackageName = 'Microsoft.BingWeather_...' }
                        )
        # Then remove
        $r = RemAppxPackages
        if ($r.code -eq 0) { Write-Host "All packages removed." }

    .EXAMPLE
        # Remove with error-continuation and custom mount point
        $r = RemAppxPackages -MountPoint 'D:\WIM\MountPoint' -ContinueOnError

    .NOTES
        Version:    1.00.05
        Written by: Praetoriani (a.k.a. M.Sczepanski)
        Requires:   DISM.exe on PATH, administrator privileges, OPSreturn, AppScope, WinISOcore
        The 'remove' key in $script:appx is modified in-place during execution:
        successfully removed entries are deleted; failed entries remain.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Full path to the mounted WIM image directory.")]
        [string]$MountPoint = '',

        [Parameter(Mandatory = $false, HelpMessage = "Continue removing remaining packages even if one DISM call fails.")]
        [switch]$ContinueOnError
    )

    # ── Resolve mount point ──────────────────────────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($MountPoint)) {
        $EnvData = AppScope -KeyID 'appenv'
        if ($EnvData -is [PSCustomObject] -and $EnvData.PSObject.Properties['code']) {
            return (OPSreturn -Code -1 -Message "RemAppxPackages failed! Could not read module env: $($EnvData.msg)")
        }
        $MountPoint = $EnvData['MountPoint']
    }

    if ([string]::IsNullOrWhiteSpace($MountPoint)) {
        return (OPSreturn -Code -1 -Message "RemAppxPackages failed! Parameter 'MountPoint' is required and could not be resolved from module scope.")
    }

    # ── Validate mount point ─────────────────────────────────────────────────────
    if (-not (Test-Path -Path $MountPoint -PathType Container)) {
        return (OPSreturn -Code -1 -Message "RemAppxPackages failed! Mount point directory does not exist: '$MountPoint'")
    }

    $MountedImages = $null
    try {
        $MountedImages = Get-WindowsImage -Mounted -ErrorAction Stop |
                         Where-Object { $_.Path -eq $MountPoint }
    }
    catch {
        return (OPSreturn -Code -1 -Message "RemAppxPackages failed! Error querying mounted images: $($_.Exception.Message)")
    }

    if ($null -eq $MountedImages) {
        return (OPSreturn -Code -1 -Message "RemAppxPackages failed! No mounted WIM image found at '$MountPoint'. Mount the image first using MountWIMimage.")
    }

    # ── Read $script:appx['remove'] ──────────────────────────────────────────────
    $AppxData = AppScope -KeyID 'appx'
    if ($AppxData -is [PSCustomObject] -and $AppxData.PSObject.Properties['code']) {
        return (OPSreturn -Code -1 -Message "RemAppxPackages failed! Could not access `$script:appx: $($AppxData.msg)")
    }

    $RemoveList = $AppxData['remove']
    if ($null -eq $RemoveList -or $RemoveList.Count -eq 0) {
        return (OPSreturn -Code -1 -Message "RemAppxPackages failed! `$script:appx['remove'] is empty. Add package entries before calling RemAppxPackages.")
    }

    # ── Process each package ─────────────────────────────────────────────────────
    $Succeeded  = [System.Collections.Generic.List[object]]::new()
    $Failed     = [System.Collections.Generic.List[object]]::new()
    $Remaining  = [System.Collections.Generic.List[object]]::new($RemoveList)

    foreach ($pkg in $RemoveList) {
        # Resolve PackageName – support both PSCustomObject and hashtable entries
        $PkgName = $null
        if ($pkg -is [System.Collections.Hashtable] -or $pkg -is [System.Collections.Specialized.OrderedDictionary]) {
            $PkgName = [string]$pkg['PackageName']
        }
        elseif ($pkg -is [PSCustomObject]) {
            $PkgName = [string]$pkg.PackageName
        }
        else {
            $PkgName = [string]$pkg
        }

        if ([string]::IsNullOrWhiteSpace($PkgName)) {
            $Failed.Add($pkg)
            if (-not $ContinueOnError) {
                break
            }
            continue
        }

        # ── Invoke DISM ──────────────────────────────────────────────────────────
        $DismArgs  = "/Image:`"$MountPoint`" /Remove-ProvisionedAppxPackage /PackageName:`"$PkgName`""
        $DismProc  = $null
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
            # Remove from remaining list (monitoring: only failed entries stay)
            $Remaining.Remove($pkg) | Out-Null
        }
        else {
            $Failed.Add($pkg)
            if (-not $ContinueOnError) {
                break
            }
        }
    }

    # ── Write back remaining (= failed) entries to module scope ───────────────────
    $RemainingArray = @($Remaining)
    $WriteResult = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
                              -VarKeyID 'remove' -SetNewVal $RemainingArray
    if ($WriteResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "RemAppxPackages: DISM processing done, but failed to update `$script:appx['remove']: $($WriteResult.msg)")
    }

    # ── Build result summary ─────────────────────────────────────────────────────
    $ResultData = @{
        Succeeded = @($Succeeded)
        Failed    = @($Failed)
    }

    if ($Failed.Count -eq 0) {
        return (OPSreturn -Code 0 `
            -Message "RemAppxPackages completed. $($Succeeded.Count) package(s) removed successfully. `$script:appx['remove'] is now empty." `
            -Data $ResultData)
    }
    else {
        return (OPSreturn -Code -1 `
            -Message "RemAppxPackages completed with errors. Succeeded: $($Succeeded.Count) | Failed: $($Failed.Count). Failed package(s) remain in `$script:appx['remove']." `
            -Data $ResultData)
    }
}
