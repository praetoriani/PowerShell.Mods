function InitializeEnvironment {
    <#
    .SYNOPSIS
    InitializeEnvironment - Core function that creates our WinISO-Environment
    
    .DESCRIPTION
    This function is a mandatory function. It is used to fully create the WinISO-Environment
    and verifies that we have everything we need, to operate (almost) fully automated.
    IMPORTANT:
    This function assumes that the environment does not yet exist and must be created from scratch!
    
    .EXAMPLE
    InitializeEnvironment
    #>

    # Import global vars using getter-functionallity
    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData = AppScope -KeyID 'appenv'
    # Sample Usage: $EnvData['ISOroot'] will be 'C:\WinISO' (as defined and exported via psm1 file)

    try {
        # create the root directory of our environment
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['ISOroot'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['ISOroot'] could not be created!")
        }
        # create following directory: .\Appx
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['AppxBundle'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['AppxBundle'] could not be created!")
        }
        # create following directory: .\DATA
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['ISOdata'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['ISOdata'] could not be created!")
        }
        # create following directory: .\Drivers
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['OEMDrivers'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['OEMDrivers'] could not be created!")
        }
        # create following directory: .\MountPoint
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['MountPoint'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['MountPoint'] could not be created!")
        }

    }
    catch {
        return (OPSreturn -Code -1 -Message "Error in $AppInfo['AppName']! Function InitializeEnvironment failed with the following error: $($_.Exception.Message)")
        # optional: $_.Exception.GetType().FullName für Typprüfung
    }
    
}
