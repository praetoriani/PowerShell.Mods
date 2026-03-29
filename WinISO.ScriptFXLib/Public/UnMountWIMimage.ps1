function UnMountWIMimage {
    <#
    .SYNOPSIS
        Dismounts a currently active WIM image from a DISM mount point.

    .DESCRIPTION
        UnMountWIMimage dismounts a Windows image that was previously mounted with
        MountWIMimage (or directly via Mount-WindowsImage / DISM). Steps:

        1. Validates the mount-point directory exists.
        2. Verifies the mount-point is actively in use via Get-WindowsImage -Mounted
           (with a fallback to 'dism.exe /Get-MountedWimInfo' for robustness).
        3. Performs Dismount-WindowsImage with -Save (commit) or -Discard.
        4. Verifies the mount is fully gone by re-querying mounted images.

        A failed post-dismount verification emits a warning rather than a hard error,
        because Dismount-WindowsImage may have succeeded even if the subsequent query
        is unreliable. The caller should run 'dism /Cleanup-Wim' if issues persist.

    .PARAMETER MountPoint
        Full path to the active WIM mount-point. Must exist and must be actively mounted.

    .PARAMETER Action
        'commit'  = save all changes back into the WIM file
        'discard' = discard all changes (revert to original WIM content)

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = $MountPoint on success, $null on failure.

    .EXAMPLE
        $r = UnMountWIMimage -MountPoint 'C:\WinISO\MountPoint' -Action 'commit'

    .EXAMPLE
        $r = UnMountWIMimage -MountPoint 'C:\WinISO\MountPoint' -Action 'discard'

    .NOTES
        Requires: DISM PowerShell module, dism.exe, OPSreturn, administrator privileges.
        If dismount state is inconsistent run: dism /Cleanup-Wim
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Full path to the active WIM mount-point.")]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint,

        [Parameter(Mandatory = $true, HelpMessage = "Action: 'commit' (save changes) | 'discard' (revert changes).")]
        [ValidateNotNullOrEmpty()]
        [string]$Action
    )

    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData  = AppScope -KeyID 'appenv'

    # Normalise Action
    $ActionNorm = $Action.Trim().ToLower()

    # -- Validate Action --
    if ($ActionNorm -notin @('commit', 'discard')) {
        return (OPSreturn -Code -1 -Message "UnMountWIMimage failed! Invalid Action '$Action'. Allowed: 'commit' | 'discard'.")
    }

    # -- Validate mount-point directory --
    try {
        if (-not (Test-Path -Path $MountPoint -PathType Container)) {
            return (OPSreturn -Code -1 -Message "UnMountWIMimage failed! Mount-point does not exist: '$MountPoint'")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "UnMountWIMimage failed! Error checking mount-point: $($_.Exception.Message)")
    }

    # -- Verify mount-point is actively mounted --
    $IsActiveMount = $false

    try {
        $MountedList = Get-WindowsImage -Mounted -ErrorAction Stop
        $ActiveEntry = $MountedList | Where-Object { $_.Path -eq $MountPoint }
        if ($null -ne $ActiveEntry) { $IsActiveMount = $true }
    }
    catch {
        Write-Verbose "UnMountWIMimage: Get-WindowsImage -Mounted failed - trying dism.exe fallback: $($_.Exception.Message)"
    }

    # Fallback: dism.exe /Get-MountedWimInfo
    if (-not $IsActiveMount) {
        try {
            $DismOut   = & "$env:SystemRoot\System32\dism.exe" /Get-MountedWimInfo 2>&1
            $DismText  = ($DismOut | Out-String)
            $MPnorm    = $MountPoint.TrimEnd('\').ToLower()
            if ($DismText -match [regex]::Escape($MPnorm)) { $IsActiveMount = $true }
        }
        catch {
            Write-Verbose "UnMountWIMimage: dism.exe fallback failed: $($_.Exception.Message)"
        }
    }

    if (-not $IsActiveMount) {
        return (OPSreturn -Code -1 -Message "UnMountWIMimage failed! No active WIM mount found at '$MountPoint'. Use 'dism /Get-MountedWimInfo' to list active mounts.")
    }

    # -- Perform dismount --
    try {
        if ($ActionNorm -eq 'commit') {
            Dismount-WindowsImage -Path $MountPoint -Save    -ErrorAction Stop
        } else {
            Dismount-WindowsImage -Path $MountPoint -Discard -ErrorAction Stop
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "UnMountWIMimage failed! Dismount-WindowsImage ($ActionNorm) error at '$MountPoint': $($_.Exception.Message)")
    }

    # -- Verify dismount --
    try {
        $PostCheck = Get-WindowsImage -Mounted -ErrorAction Stop | Where-Object { $_.Path -eq $MountPoint }
        if ($null -ne $PostCheck) {
            Write-Warning "UnMountWIMimage: Dismount completed but '$MountPoint' still appears in mounted images list. Consider running: dism /Cleanup-Wim"
        }
    }
    catch {
        Write-Warning "UnMountWIMimage: Post-dismount verification query failed: $($_.Exception.Message). Assuming dismount succeeded."
    }

    $ActionLabel = if ($ActionNorm -eq 'commit') { 'committed (changes saved)' } else { 'discarded (changes not saved)' }
    return (OPSreturn -Code 0 -Message "UnMountWIMimage successful! WIM at '$MountPoint' dismounted — changes $ActionLabel." -Data $MountPoint)
}
