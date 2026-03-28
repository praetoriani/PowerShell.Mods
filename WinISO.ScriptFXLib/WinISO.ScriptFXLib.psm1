<#
.SYNOPSIS
    WinISOSciptFXLib - Powerfull Module for downloading, customizing and re-building bootable Windows 11 Pro Setup ISO Files

.DESCRIPTION
    This PowerShell Module was designed to provide powerfull functions to almost fully automate the process of
    downloading and generating Windows 11 Pro ISO Files (using uupdump.net), customizing install.wim images
    to fit your personal needs and necessary requirements (using DISM and other tools) and re-building a final
    version to an bootable ISO file based on your previously made customizations to the Windows Image.
    In simple words: With WinISOSciptFXLib you can create your own customized bootable Windows 11 Pro Setup ISO!

.NOTES
    Creation Date: 28.03.2026
    Last Update:   28.03.2026
    Version:       1.00.00
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
    AppName     = 'WinISOSciptFXLib'
    AppVers     = '1.00.00'
    AppDevName  = 'Praetoriani'
    AppWebsite  = 'https://github.com/praetoriani/PowerShell.Mods'
    DateCreate  = '28.03.2026'
    LastUpdate  = '28.03.2026'
}

$script:appenv = @{
    ISOroot    = 'C:\WinISO'
}
$script:appenv['ISOdata']    = Join-Path $script:appenv['ISOroot'] "DATA"
$script:appenv['MountPoint'] = Join-Path $script:appenv['ISOroot'] "MountPoint"
$script:appenv['installwim'] = Join-Path $script:appenv['ISOroot'] "DATA\sources\install.wim"
$script:appenv['AppxBundle'] = Join-Path $script:appenv['ISOroot'] "Appx"
$script:appenv['OEMDrivers'] = Join-Path $script:appenv['ISOroot'] "Drivers"
$script:appenv['OEMfolder']  = Join-Path $script:appenv['ISOroot'] 'OEM'
$script:appenv['ScratchDir'] = Join-Path $script:appenv['ISOroot'] 'ScratchDir'
$script:appenv['TempFolder'] = Join-Path $script:appenv['ISOroot'] 'TEMPDIR'
$script:appenv['Downloads']  = Join-Path $script:appenv['ISOroot'] 'TEMPDIR\Downloads'
$script:appenv['UUPDumpDir'] = Join-Path $script:appenv['ISOroot'] 'TEMPDIR\uupdump'
$script:appenv['OscdimgDir'] = Join-Path $script:appenv['ISOroot'] 'Oscdimg'
$script:appenv['OscdimgExe'] = Join-Path $script:appenv['ISOroot'] 'Oscdimg\oscdimg.exe'

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
                default     {
                    $script:exit['code'] = -1
                    $script:exit['text'] = "Parameter 'KeyID' can only be 'appinfo'  or  'appenv'."
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
Write-Verbose "WinISOSciptFXLib module loaded successfully. Available functions: $(($PublicFunctions.BaseName) -join ', ')"
