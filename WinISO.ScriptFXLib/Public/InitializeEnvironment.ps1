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

        # create following directory: .\Downloads
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['Downloads'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['Downloads'] could not be created!")
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

        # create following directory: .\OEM
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['OEMfolder'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['OEMfolder'] could not be created!")
        }

        # create following sub-directory: .\OEM\root
        $OEMrootdir = Join-Path $EnvData['OEMfolder'] 'root'
        $makedir = New-Item -ItemType Directory -LiteralPath $OEMrootdir -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $OEMrootdir could not be created!")
        }

        # create following sub-directory: .\OEM\windir
        $OEMwindir = Join-Path $EnvData['OEMfolder'] 'windir'
        $makedir = New-Item -ItemType Directory -LiteralPath $OEMwindir -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $OEMwindir could not be created!")
        }

        # create following directory: .\Oscdimg
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['OscdimgDir'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['OscdimgDir'] could not be created!")
        }

        # create following directory: .\ScratchDir
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['ScratchDir'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['ScratchDir'] could not be created!")
        }

        # create following directory: .\temp
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['TempFolder'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['TempFolder'] could not be created!")
        }

        # create following directory: .\uupdump
        $makedir = New-Item -ItemType Directory -LiteralPath $EnvData['UUPDumpDir'] -Force -ErrorAction Stop
        if ($null -eq $makedir) {
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! $EnvData['UUPDumpDir'] could not be created!")
        }

        # let's try to download oscdimg.exe from our repository
        $DownloadResult = GitHubDownload -URL "https://github.com/praetoriani/PowerShell.Mods/raw/refs/heads/main/WinISO.ScriptFXLib/Requirements/oscdimg.exe" -SaveTo "$EnvData['OscdimgExe']"
        if ( $DownloadResult -ne 0) {
            # Download failed
            return (OPSreturn -Code -1 -Message "Function InitializeEnvironment failed! Error: $DownloadResult.msg")
        }
        
        # if we reached this point
        return (OPSreturn -Code 0 -Message "Function InitializeEnvironment successfully finished.")

    }
    catch {
        return (OPSreturn -Code -1 -Message "Error in $AppInfo['AppName']! Function InitializeEnvironment failed with the following error: $($_.Exception.Message)")
        # optional: $_.Exception.GetType().FullName für Typprüfung
    }
    
}
