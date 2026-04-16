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
.REMARKS
    IMPORTANT NOTE: This module follows an Enterprise-Pattern with three simple steps
    → Import the local.httpserver-Module
    → Configure the server via SetCoreConfig
    → Start using the Module
    That means: 
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
#  → SECTION 1: Module Configuration
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# In this section we're defining the absolute minimum configuration for local.httpserver to work.
# This configuration can be accessed/changed via the SetCoreCofing function and is stored in the
# $Script:Config variable.

$script:root = $PSScriptRoot # ← This is the root directory of the module, used for resolving relative paths in the config files

$Script:Config = @{
    # please check below for a short description of the meaning
    PathPointer = $null                 # ← Defaults to $httpHost.wwwroot on error
    ServerName  = "local.httpserver"
    UseLogging  = 0
    Mode        = 'console'
    UseIPC      = $false
}

function SetCoreConfig {
[CmdletBinding()]
param(
    # The path to the directory that should be served by the HTTP server.
    [Parameter(Mandatory = $true, HelpMessage = "Set the path to the directory that should be served by the HTTP server.", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "PathPointer")]
    [ValidateNotNullOrEmpty()]
    [string]$PathPointer,

    # Give your HTTP-Server a Name :-)
    [Parameter(Mandatory = $false, HelpMessage = "The name of your own local.httpserver.", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "ServerName")]
    [ValidateNotNullOrEmpty()]
    [string]$ServerName,

    # If set to 1, the module will create a logfile during runtime
    [Parameter(Mandatory = $false, HelpMessage = "Specify whether or not logging should be used.", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "UseLogging")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet(0,1)]
    [int]$UseLogging,

    # Set the operatin mode of the HTP-Server
    [Parameter(Mandatory = $false, HelpMessage = "Set the Mode local.hhtpserver should use", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "Mode")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('hidden','systray','console','desktop')]
    # hidden    → local.httpserver runs completely (hidden) in the background
    # systray   → local.httpserver can be accessed via an icon in the system tray
    # console   → local.httpserver will show the original console window containing its process
    # desktop   → local.httpserver as a full WPF/XML-Based PowerShell UI
    [string]$Mode,

    # If used, a Pipe-Server will be created for IPC (Inter-Process Communication)
    # to allow external processes to send commands to the HTTP-Server.
    [Parameter(Mandatory = $false, HelpMessage = "Activates IPC to use named pipes for communicaating with local.httpserver", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "UseIPC")]
    [switch]$UseIPC
)

    # Only handover the params, which were really used by the user
    foreach ($key in $PSBoundParameters.Keys) {
        $Script:Config[$key] = $PSBoundParameters[$key]
    }
}


# ____________________________________________________________________________________________________
# SECTION 2: Load the core configuration file
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



# ____________________________________________________________________________________________________
#  → SECTION 3: Bootstrapping
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# The Reason, why we do the dot-sourcing at the beginnging of the module is, that we have access to
# all public and private functions of this module during the runtime of local.httpserver.psm1.

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
Write-Verbose "‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"
Write-Verbose "local.httpserver module loaded successfully. Available functions:"
Write-Verbose "$(($PublicFunctions.BaseName) -join ', ')"
Write-Verbose "___________________________________________________________________________"
Write-Verbose "Enjoy using local.httpserver :-)"
