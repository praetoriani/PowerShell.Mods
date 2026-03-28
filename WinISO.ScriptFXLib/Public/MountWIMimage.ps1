function MountWIMimage {
    <#
    .SYNOPSIS
    MountWIMimage - tries to mount the install.wim file
    
    .DESCRIPTION
    ... to be documented ...
    
    .EXAMPLE
    ... to be documented ...
    #>

    # Import global vars using getter-functionallity
    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData = AppScope -KeyID 'appenv'
    # Sample Usage: $EnvData['ISOroot'] will be 'C:\WinISO' (as defined and exported via psm1 file)

    try {
        #dism /Mount-Image /ImageFile:$EnvData['installwim'] /Index:1 /MountDir:$EnvData['MountPoint']

        # Use Native PowerShell DISM-Cmdlet to mount the install.wim from our environment
        Mount-WindowsImage -ImagePath $EnvData['installwim'] -Index 1 -Path $EnvData['MountPoint'] -ErrorAction Stop

        # Verify if the image could be mounted.
        $MountedWIM = Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $EnvData['MountPoint'] }
        
        # Handle the current mount-state
        if ( $MountedWIM -and $MountedWIM.MountStatus.ToLower() -eq 'ok' ) {
            return (OPSreturn -Code 0 -Message "Image $EnvData['installwim'] successfully mounted at $EnvData['MountPoint']")
        }
        else {
            return (OPSreturn -Code -1 -Message "Image $EnvData['installwim'] mounted but with errors. Mount-Status: $MountedWIM.MountStatus")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Error in $AppInfo['AppName']! Function MountWIMimage failed while trying to mount $EnvData['installwim'] to Mountpoint $EnvData['MountPoint']! $($_.Exception.Message)")
    }
    
}
