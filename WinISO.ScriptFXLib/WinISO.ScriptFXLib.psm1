<#
.SYNOPSIS
    WinISO.ScriptFXLib - Powerfull Module for downloading, customizing and re-building bootable Windows 11 Pro Setup ISO Files

.DESCRIPTION
    This PowerShell Module was designed to provide powerfull functions to almost fully automate the process of
    downloading and generating Windows 11 Pro ISO Files (using uupdump.net), customizing install.wim images
    to fit your personal needs and necessary requirements (using DISM and other tools) and re-building a final
    version to an bootable ISO file based on your previously made customizations to the Windows Image.
    In simple words: With WinISO.ScriptFXLib you can create your own customized bootable Windows 11 Pro Setup ISO!

.NOTES
    Creation Date: 28.03.2026
    Last Update:   03.04.2026
    Version:       1.00.04
    Author:        Praetoriani (a.k.a. M.Sczepanski)
    Website:       https://github.com/praetoriani/PowerShell.Mods

    REQUIREMENTS & DEPENDENCIES:
    - PowerShell 5.1 or higher
    - .NET Framework 4.7.2 or higher (for Windows PowerShell)
    - Windows Registry access for installation directory detection
#>

# define vars on module-level (script scope = module scope)
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$script:appinfo = @{
    AppName     = 'WinISO.ScriptFXLib'
    AppVers     = '1.00.04'
    AppDevName  = 'Praetoriani'
    AppDevMail  = 'mr.praetoriani{at}gmail.com'
    AppWebsite  = 'https://github.com/praetoriani/PowerShell.Mods'
    DateCreate  = '28.03.2026'
    LastUpdate  = '03.04.2026'
}

# This var stores important paths and other important environment informations
$script:appenv = @{
    ISOroot    = 'C:\WinISO'
}
$script:appenv['ISOdata']    = Join-Path $script:appenv['ISOroot'] 'DATA'
$script:appenv['MountPoint'] = Join-Path $script:appenv['ISOroot'] 'MountPoint'
$script:appenv['installwim'] = Join-Path $script:appenv['ISOroot'] 'DATA\sources\install.wim'
$script:appenv['LogfileDir'] = Join-Path $script:appenv['ISOroot'] 'Logfiles'
$script:appenv['AppxBundle'] = Join-Path $script:appenv['ISOroot'] 'Appx'
$script:appenv['OEMDrivers'] = Join-Path $script:appenv['ISOroot'] 'Drivers'
$script:appenv['OEMfolder']  = Join-Path $script:appenv['ISOroot'] 'OEM'
$script:appenv['ScratchDir'] = Join-Path $script:appenv['ISOroot'] 'ScratchDir'
$script:appenv['TempFolder'] = Join-Path $script:appenv['ISOroot'] 'temp'
$script:appenv['Downloads']  = Join-Path $script:appenv['ISOroot'] 'Downloads'
$script:appenv['UUPDumpDir'] = Join-Path $script:appenv['ISOroot'] 'uupdump'
$script:appenv['OscdimgDir'] = Join-Path $script:appenv['ISOroot'] 'Oscdimg'
$script:appenv['OscdimgExe'] = Join-Path $script:appenv['ISOroot'] 'Oscdimg\oscdimg.exe'

# This var is very important, cause it stores core data for WinISO.ScriptFXLib
$script:appcore = @{
    Root    = Join-Path $script:appenv['ISOroot'] 'app.core'
    PSmod   = @{
        WinISOmodlib = Join-Path $script:appenv['ISOroot'] 'app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1'
        PSAppCoreLib = Join-Path $script:appenv['ISOroot'] 'app.core\PSAppCoreLib\PSAppCoreLib.psd1'
    }
    CoreLog   = "$($script:appinfo.AppName).$($script:appinfo.AppVers).log"
    ReqResLog = "$($script:appinfo.AppName).Requirements.Result.txt"
    util    = @{
        oscdimg  = "oscdimg.exe"
    }
    requirement = @{
        oscdimg  = "https://github.com/praetoriani/PowerShell.Mods/blob/main/WinISO.ScriptFXLib/Requirements/oscdimg.exe"
        dotnet48 = "https://github.com/praetoriani/PowerShell.Mods/raw/refs/heads/main/WinISO.ScriptFXLib/Requirements/NDP481-x86-x64-AllOS-ENU.exe"
    }
}

$script:appverify = @{
    checkosversion  = ""
    checkpowershell = ""
    checkdotnet     = ""
    checkisadmin    = ""
    checkdismpath   = ""
    checkdismmods   = ""
    checkrobocopy   = ""
    checkcmd        = ""
    checkoscdimg    = ""
    checkenvdirs    = ""
    checkinternet   = ""
    result          = @{
        pass        = 0
        fail        = 0
        info        = 0
        warn        = 0
    }
}

# Runtime state tracker for offline registry hives loaded via LoadRegistryHive.
# Stores: HiveName (e.g. 'SOFTWARE') -> RegMountKey (e.g. 'HKLM\WinISO_SOFTWARE')
# Written by: LoadRegistryHive  (adds entries on successful reg.exe LOAD)
# Read by:    UnloadRegistryHive, RegistryHiveAdd, RegistryHiveRem,
#             RegistryHiveImport, RegistryHiveExport, RegistryHiveQuery
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$script:LoadedHives = @{}

# Runtime state tracker for UUPDump Downloads
# Stores: ostype, osvers, osarch, buildno, zipname (after successful download)
# Written by: DownloadUUPDump
$script:uupdump = @{
    ostype          = "Windows11"               # can be Windows11 only
    edition         = "Professional"            # can be Home | Professional (only important for DownloadUUPDump-Function)
    multiedition    = "Professional;Education"  # only importand if GetUUPDumpPackage is used. This defines the editions to be included
    osvers          = "24H2"                    # can be 24H2 | 25H2 | 26H1
    osarch          = "amd64"                   # can be amd64 | arm64
    buildno         = ""                        # can be any official build number (e.g. 22621.1600)
    kbsize          = ""                        # will be used to store the Filesize in KB of the donwnloaded ZIP-File
    zipname         = ""                        # after successfull download, this will be set to a filename like "Windows11-Pro-24H2-amd64-Build-22621.1600.zip"
}

# Runtime state tracker for Appx-Interactions (listing, removing, adding Appx-Packages)
$script:appx = @{
    # This scope is reserved for Appx-Package related data and variables
    listed = @() # This array will be used to store the list of Appx-Packages that are currently in the image
    remove = @() # This array is reserved for data about Appx-Packages that should be removed from the image
    inject = @() # This array is reserved for data about Appx-Packages that should be added from $script:appenv['AppxBundle'] into the image)
}

$script:exit = @{
    code    = -1
    text    = [string]::Empty
}


# Getter functions so dot-sourced scripts can access script-scope vars :)
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
function AppScope {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $KeyID
    )

    # Initialize status object (as per App Development Guidelines)
    $script:exit['code'] = -1
    $script:exit['text'] = [string]::Empty

    try {
        # Validate the KeyID-Param
        if ([string]::IsNullOrWhiteSpace($KeyID)) {
            $script:exit['code'] = -1
            $script:exit['text'] = "Parameter 'KeyID' is required and must not be null, empty or whitespace-only."
        }
        # KeyID-Param seems to be valid
        else {
            # Normalize the KeyID for case-insensitive comparison
            $KeyID = $KeyID.ToLower()
            switch ($KeyID) {
                'appinfo'   { return $script:appinfo }
                'appenv'    { return $script:appenv }
                'reghive'   { return $script:LoadedHives }
                default     {
                    $script:exit['code'] = -1
                    $script:exit['text'] = "Parameter 'KeyID' can only be 'appinfo'  or  'appenv' or 'reghive'."
                }
            }
        }
    }
    catch {
        <#Do this if a terminating exception happens#>
        $script:exit['code'] = -1
        $script:exit['text'] = "Error in AppScope: $($_.Exception.Message)"
    }

    # final return
    return $script:exit
}

# Get public and private function definition files
$PublicFunctions = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)

# Import all functions
foreach ($ImportFile in @($PublicFunctions + $PrivateFunctions)) {
    try {
        Write-Verbose "Importing function from file: $($ImportFile.FullName)"
        . $ImportFile.FullName
    }
    catch {
        Write-Error "Failed to import function $($ImportFile.FullName): $($_.Exception.Message)"
    }
}

# Export public functions only
if ($PublicFunctions) {
    Export-ModuleMember -Function ($PublicFunctions.BaseName + @('AppScope'))
}

# Module initialization message
Write-Verbose "WinISOScriptFXLib module loaded successfully. Available functions: $(($PublicFunctions.BaseName) -join ', ')"
