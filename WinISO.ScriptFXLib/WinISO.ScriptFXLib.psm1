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
    Export-ModuleMember -Function $PublicFunctions.BaseName
}

# Module initialization message
Write-Verbose "WinISOSciptFXLib module loaded successfully. Available functions: $(($PublicFunctions.BaseName) -join ', ')"
