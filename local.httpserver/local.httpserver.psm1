<#
.SYNOPSIS
    local.httpserver - A simple HTTP server module for PowerShell with SPA-Support.
.DESCRIPTION
    This module provides a lightweight HTTP server implementation in PowerShell, designed
    to serve static files and support Single Page Applications (SPAs) with client-side routing.
    It is ideal for local development, testing, and quick file sharing without the need
    for complex server setups.
.EXAMPLE
    Import-Module local.httpserver -ArgumentList 'C:\MyWebApp', 0, 'hidden', $false -Verbose
.NOTES
    Creation Date : 15.04.2026
    Last Update   : 16.04.2026
    Version       : 1.00.00
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Website       : https://github.com/praetoriani

    REQUIREMENTS:
    - PowerShell 5.1 or higher
    - No external dependencies

#>

# ____________________________________________________________________________________________________
#  → SECTION 1: Important Params for this module
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

[CmdletBinding()]
param(
    # The path to the directory that should be served by the HTTP server.
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$PathPointer,

    # If set to 1, the module will create a logfile during runtime
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet(0,1)]
    [int]$UseLogging = 0,

    # Set the operatin mode of the HTP-Server
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('hidden','systray','console','desktop')]
    [string]$Mode = 'hidden',

    # If used, a Pipe-Server will be created for IPC (Inter-Process Communication)
    # to allow external processes to send commands to the HTTP-Server.
    [Parameter(Mandatory = $false, Position = 3)]
    [switch]$UseIPC
)

# ____________________________________________________________________________________________________
#  → SECTION 2: Bootstrapping
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

$script:root = $PSScriptRoot # ← This is the root directory of the module, used for resolving relative paths in the config files

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

# Export public functions only
if ($PublicFunctions) {
    Export-ModuleMember -Function ($PublicFunctions.BaseName)
}
# Bootstraping finished.
# The code below this line has now access to the public and private functions of this module.
# ____________________________________________________________________________________________________


# ____________________________________________________________________________________________________
# SECTION 3: Load the core configuration files
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

# This is the module configuration file for local.httpserver.
$modConf = Join-Path $script:root "include\module.config"
# Try to load the module.conf into the current scope via dot-sourcing the file
if (Test-Path $modConf) {
    . $modConf   # Dot-Sourcing — alle Variablen sind jetzt im aktuellen Scope verfügbar
} else {
    Write-Error "File not found: $modConf"
    exit 1
}
<#  BACKUP OF THE ORIGINAL CONFIGURATION LOADING PROCESS BEFORE DOT-SOURCING THE MODULE.CONFIG
[hashtable]$httpCore = @{} # ← This will hold the deserialized content of config.httphost.json
[hashtable]$httpHost = @{} # ← This will hold the deserialized content of config.server.json
[hashtable]$mimetype = @{} # ← This will hold the deserialized content of config.mime.jsonscop

# This is the config file for the local.httpserver module.
$coreJSON = Join-Path $script:root 'include\config.httphost.json'
# Load config.httphost.json
$jsonContent = ReadJSON -Location $coreJSON
# Exit on error
if ($jsonContent.code -ne 0) { Write-Error $jsonContent.msg; exit 1 }
# pass the unwraped data from the return object to obtain the plain deserialized JSON content
$httpCore = $jsonContent.data

# Resolve relative paths in the core configuration to absolute paths based on the module directory
$httpCore.config.http = Join-Path $script:root $httpCore.config.http
$httpCore.config.mime = Join-Path $script:root $httpCore.config.mime
$httpCore.config.log = Join-Path $script:root $httpCore.config.log

# Load config.server.json
$jsonContent = ReadJSON -Location $httpCore.config.http
# Exit on error
if ($jsonContent.code -ne 0) { Write-Error $jsonContent.msg; exit 1 }
# pass the unwraped data from the return object to obtain the plain deserialized JSON content
$httpHost = $jsonContent.data

# Load config.mime.json
$jsonContent = ReadJSON -Location $httpCore.config.mime
# Exit on error
if ($jsonContent.code -ne 0) { Write-Error $jsonContent.msg; exit 1 }
# pass the unwraped data from the return object to obtain the plain deserialized JSON content
$mimetype = $jsonContent.data
#>

# Module initialization message
Write-Verbose "‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"
Write-Verbose "local.httpserver module loaded successfully. Available functions:"
Write-Verbose "$(($PublicFunctions.BaseName) -join ', ')"
Write-Verbose "___________________________________________________________________________"
Write-Verbose "Enjoy using local.httpserver :-)"
