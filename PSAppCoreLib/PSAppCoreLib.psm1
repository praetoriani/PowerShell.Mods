<#
.SYNOPSIS
    PSAppCoreLib - Collection of useful functions for PowerShell apps

.DESCRIPTION
    This PowerShell module provides a collection of utility functions for application development.
    It includes functions for logging, icon extraction, and other common tasks needed in
    PowerShell applications.

.NOTES
    Creation Date: 26.10.2025
    Last Update:   26.10.2025
    Version:       1.00.00
    Author:        Praetoriani (a.k.a. M.Sczepanski)
    Website:       https://github.com/praetoriani

    REQUIREMENTS & DEPENDENCIES:
    - PowerShell 5.1 or higher
    - .NET Framework 4.7.2 or higher (for Windows PowerShell)
    - System.Drawing assembly
    - System.Windows.Forms assembly
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
Write-Verbose "PSAppCoreLib module loaded successfully. Available functions: $(($PublicFunctions.BaseName) -join ', ')"
