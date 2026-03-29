function MountWIMimage {
    <#
    .SYNOPSIS
        Mounts a specific image index from a WIM file to a mount-point directory.

    .DESCRIPTION
        Uses Mount-WindowsImage (DISM) to mount the specified image index.
        After mounting, the result is verified via Get-WindowsImage -Mounted.

        If the mount fails or verification fails, a defensive Dismount-WindowsImage -Discard
        is attempted to ensure no partially mounted images remain.

    .PARAMETER WIMimage
        Full path to the .wim file (must exist).

    .PARAMETER IndexNo
        ImageIndex of the edition to mount (must exist in the WIM file).
        Use ImageIndexLookup to resolve an edition name to its index.

    .PARAMETER MountPoint
        Full path to the mount-point directory. Must exist AND be completely empty.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = $MountPoint path on success, $null on failure.

    .EXAMPLE
        $r = MountWIMimage -WIMimage 'C:\WinISO\DATA\sources\install.wim' `
                           -IndexNo 6 `
                           -MountPoint 'C:\WinISO\MountPoint'

    .NOTES
        Requires: DISM PowerShell module, OPSreturn, administrator privileges.
        On failure, a defensive dismount (-Discard) is attempted automatically.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true,  HelpMessage = "Full path to the .wim file (must exist).")]
        [ValidateNotNullOrEmpty()]
        [string]$WIMimage,

        [Parameter(Mandatory = $true,  HelpMessage = "ImageIndex to mount (must exist in WIM).")]
        [ValidateRange(1, 9999)]
        [int]$IndexNo,

        [Parameter(Mandatory = $true,  HelpMessage = "Full path to the mount-point directory (must exist and be empty).")]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint
    )

    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData  = AppScope -KeyID 'appenv'

    # -- Validate WIM file --
    try {
        if ([System.IO.Path]::GetExtension($WIMimage).ToLower() -ne '.wim') {
            return (OPSreturn -Code -1 -Message "MountWIMimage failed! 'WIMimage' must be a .wim file. Provided: '$WIMimage'")
        }
        if (-not (Test-Path -Path $WIMimage -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "MountWIMimage failed! WIM file not found: '$WIMimage'")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "MountWIMimage failed! Error validating WIM path: $($_.Exception.Message)")
    }

    # -- Validate mount-point (must exist and be empty) --
    try {
        if (-not (Test-Path -Path $MountPoint -PathType Container)) {
            return (OPSreturn -Code -1 -Message "MountWIMimage failed! Mount-point does not exist: '$MountPoint'")
        }
        $MPcontent = Get-ChildItem -Path $MountPoint -Force -ErrorAction SilentlyContinue
        if ($MPcontent -and $MPcontent.Count -gt 0) {
            return (OPSreturn -Code -1 -Message "MountWIMimage failed! Mount-point is not empty: '$MountPoint'. The directory must be empty before mounting.")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "MountWIMimage failed! Error validating mount-point: $($_.Exception.Message)")
    }

    # -- Validate IndexNo exists in the WIM --
    $IndexEntry = $null
    try {
        $AllWIMimages = Get-WindowsImage -ImagePath $WIMimage -ErrorAction Stop
        $IndexEntry   = $AllWIMimages | Where-Object { [int]$_.ImageIndex -eq $IndexNo }
        if (-not $IndexEntry) {
            $ValidList = ($AllWIMimages | ForEach-Object { "[$($_.ImageIndex)] $($_.ImageName)" }) -join ', '
            return (OPSreturn -Code -1 -Message "MountWIMimage failed! Index $IndexNo does not exist in '$WIMimage'. Available: $ValidList")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "MountWIMimage failed! Error querying WIM indices: $($_.Exception.Message)")
    }

    # -- Mount --
    try {
        Mount-WindowsImage -ImagePath $WIMimage -Index $IndexNo -Path $MountPoint -ErrorAction Stop
    }
    catch {
        # Defensive dismount to prevent corrupted mount state
        try { Dismount-WindowsImage -Path $MountPoint -Discard -ErrorAction SilentlyContinue } catch { }
        return (OPSreturn -Code -1 -Message "MountWIMimage failed! Mount-WindowsImage error (Index $IndexNo at '$MountPoint'): $($_.Exception.Message)")
    }

    # -- Verify mount --
    try {
        $MountedEntry = Get-WindowsImage -Mounted -ErrorAction Stop |
                        Where-Object { $_.Path -eq $MountPoint }

        if ($null -eq $MountedEntry) {
            try { Dismount-WindowsImage -Path $MountPoint -Discard -ErrorAction SilentlyContinue } catch { }
            return (OPSreturn -Code -1 -Message "MountWIMimage failed! DISM reports no active mount at '$MountPoint' after Mount-WindowsImage completed.")
        }

        $StatusLower = ([string]$MountedEntry.MountStatus).ToLower()
        if ($StatusLower -notin @('ok', '0')) {
            try { Dismount-WindowsImage -Path $MountPoint -Discard -ErrorAction SilentlyContinue } catch { }
            return (OPSreturn -Code -1 -Message "MountWIMimage failed! DISM reports non-OK mount status '$($MountedEntry.MountStatus)' at '$MountPoint'.")
        }
    }
    catch {
        try { Dismount-WindowsImage -Path $MountPoint -Discard -ErrorAction SilentlyContinue } catch { }
        return (OPSreturn -Code -1 -Message "MountWIMimage failed! Error during post-mount verification: $($_.Exception.Message)")
    }

    $EditionName = if ($null -ne $IndexEntry) { $IndexEntry.ImageName } else { "Index $IndexNo" }
    return (OPSreturn -Code 0 -Message "MountWIMimage successful! '$EditionName' (Index $IndexNo) mounted at '$MountPoint'." -Data $MountPoint)
}
