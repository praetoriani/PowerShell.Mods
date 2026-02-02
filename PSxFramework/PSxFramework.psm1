<#
.SYNOPSIS
    PSxFramework - Core framework for PSx Composer

.DESCRIPTION
    This PowerShell module provides the core functionality for PSx Composer, a tool for
    creating PowerShell executables. It includes functions for managing installation paths,
    verifying binaries, handling temporary data, and preparing SFX (Self-Extracting Archive)
    modules with custom configurations.

.NOTES
    Creation Date: 01.02.2026
    Last Update:   01.02.2026
    Version:       1.00.00
    Author:        Praetoriani (a.k.a. M.Sczepanski)
    Website:       https://github.com/praetoriani/PowerShell.Mods

    REQUIREMENTS & DEPENDENCIES:
    - PowerShell 5.1 or higher
    - .NET Framework 4.7.2 or higher (for Windows PowerShell)
    - Windows Registry access for installation directory detection
    - PSx Composer installation (for full functionality)
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
Write-Verbose "PSxFramework module loaded successfully. Available functions: $(($PublicFunctions.BaseName) -join ', ')"
