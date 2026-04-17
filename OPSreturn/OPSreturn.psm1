<#
.SYNOPSIS
    OPSreturn - Creates a standardized return object for operation status reporting.
.DESCRIPTION
    The OPSreturn Module creates a consistent PSCustomObject for returning operation
    status information across all module functions. It provides a uniform interface for
    success/failure reporting with optional data payload and other options/features.
.EXAMPLE
    I... TO BE DOCUMENTED ...
.REMARKS
    IMPORTANT NOTE: This module follows an Enterprise-Pattern with three simple steps
    → Import the local.httpserver-Module
    → Configure the server via SetCoreConfig
    → Start using the Module
    
.NOTES
    Creation Date : 17.04.2026
    Last Update   : 17.04.2026
    Version       : 1.00.00
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Website       : https://github.com/praetoriani

    REQUIREMENTS:
    - PowerShell 5.1 or higher
    - No external dependencies

#>

# ____________________________________________________________________________________________________
#  → SECTION 1: MODULE CONFIGURATION
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# In this section we're defining the absolute minimum configuration for local.httpserver to work.
# This configuration can be accessed/changed via the SetCoreCofing function and is stored in the
# $Script:Config variable.

$script:root = $PSScriptRoot # ← This is the root directory of the module, used for resolving relative paths in the config files

$script:conf = @{
    # please check below for a short description of the meaning
    timestamp   = $true
    verbosed    = $false
}

function SetCoreConfig {
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Set whether to use detailed timestamp or not", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "timestamp")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet($true,$false)]
    [string]$timestamp,

    [Parameter(Mandatory = $false, HelpMessage = "Set whether to activate verbose mode or not", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "verbosed")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet($true,$false)]
    [string]$verbosed
)

    # Only handover the params, which were really used by the user
    foreach ($key in $PSBoundParameters.Keys) {
        $Script:conf[$key] = $PSBoundParameters[$key]
    }
}


# ____________________________________________________________________________________________________
#  → SECTION X: 
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# PLACE ADDITIONAL CODE HERE

# ____________________________________________________________________________________________________
#  → FINAL SECTION: BOOTSTRAPING/DOT-SOURCING
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# Technically, it doesn't matter where in the psm1 file the bootstrapping/dot sourcing is performed.
# It's more a question of code design/architecture where you want or need to perform it.

# Get public and private function definition files
$PublicFunctions = @(Get-ChildItem -Path $script:root\Public\*.ps1 -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path $script:root\Private\*.ps1 -ErrorAction SilentlyContinue)

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

# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# ‼ NOTE: AS A PERSONAL DECISION, EXPORT-MODULEMEMBER ISN'T USED ANYMORE.
# EXPORT OF THE FUNCTIONS WILL FULLY BE HANDLED IN local.httpserver.psd1
# ____________________________________________________________________________________________________

# Export public functions only
#if ($PublicFunctions) {
#    Export-ModuleMember -Function ($PublicFunctions.BaseName)
#}
# Bootstraping finished.
# The code below this line has now access to the public and private functions of this module.
# ____________________________________________________________________________________________________


# Module initialization message
[string] $finalMessage = @(
"‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"
"OPSreturn module loaded successfully. Available functions:"
"$(($PublicFunctions.BaseName) -join ', ')"
"___________________________________________________________________________"
"Enjoy using local.httpserver :-)"
""
) -join "`n"
Write-Verbose $finalMessage
