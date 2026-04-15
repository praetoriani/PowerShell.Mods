<#
.SYNOPSIS
    httphost.serviceworker - A simple HTTP server module for PowerShell with SPA-Support.
.DESCRIPTION
    This module provides a lightweight HTTP server implementation in PowerShell, designed
    to serve static files and support Single Page Applications (SPAs) with client-side routing.
    It is ideal for local development, testing, and quick file sharing without the need
    for complex server setups.
.EXAMPLE
    Import-Module httphost.local -Verbose
    Import-Module httphost.local -Verbose -PathPointer 'C:\MyWebApp' -SystemTray -UseLogging 1
    Import-Module httphost.local -Verbose -SystemTray
.NOTES
    Creation Date : 15.04.2026
    Last Update   : 15.04.2026
    Version       : 1.00.00
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Website       : https://github.com/praetoriani

    REQUIREMENTS:
    - PowerShell 5.1 or higher
    - No external dependencies

#>

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# SECTION 1: Important Params for this module
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆

[CmdletBinding()]
param(
    # The path to the directory that should be served by the HTTP server.
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$PathPointer,
    # If used, a systray icon will be shown for the HTTP-Server.
    [Parameter(Mandatory = $false, Position = 1)]
    [switch]$SystemTray,
    # If set to 1, the module will create a logfile during runtime
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet(0,1)]
    [int]$UseLogging = 0
)

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# SECTION 2: Load the core configuration files
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆

$httpCore = @{} # ← This will hold the deserialized content of config.httphost.json
$httpHost = @{} # ← This will hold the deserialized content of config.server.json
$mimetype = @{} # ← This will hold the deserialized content of config.mime.json

# This is the config file for the httphost.serviceworker module.
$coreJSON = Join-Path $PSScriptRoot 'include\config.httphost.json'
# Load Configuration from JSON
if (Test-Path $coreJSON) {
    try {
        $httpCore = Get-Content $coreJSON -Raw | ConvertFrom-Json -ErrorAction Stop
        Write-Information "[INFO] Configuration successfully loaded from $coreJSON"
    }
    catch {
        Write-Error "[ERROR] Failed to load JSON: $($_.Exception.Message)"
        exit 1
    }
}
else {
    Write-Error "[ERROR] Configuration file not found: $coreJSON"
    exit 1
}

# Resolve relative paths in the core configuration to absolute paths based on the module directory
$httpCore.config.http = Join-Path $PSScriptRoot $httpCore.config.http
$httpCore.config.mime = Join-Path $PSScriptRoot $httpCore.config.mime
$httpCore.config.log = Join-Path $PSScriptRoot $httpCore.config.log

# Load the configuration for the HTTP-Server
$httpJSON = Join-Path $PSScriptRoot $httpCore.config.http
if (Test-Path $httpJSON) {
    try {
        $httpHost = Get-Content $httpJSON -Raw | ConvertFrom-Json -ErrorAction Stop
        Write-Information "[INFO] Configuration successfully loaded from $httpJSON"
    }
    catch {
        Write-Error "[ERROR] Failed to load JSON: $($_.Exception.Message)"
        exit 1
    }
}
else {
    Write-Error "[ERROR] Configuration file not found: $httpJSON"
    exit 1
}
# Load the Mime-Type Configuration
$mimeJSON = Join-Path $PSScriptRoot $httpCore.config.mime
if (Test-Path $mimeJSON) {
    try {
        $mimetype = Get-Content $mimeJSON -Raw | ConvertFrom-Json -ErrorAction Stop
        Write-Information "[INFO] Configuration successfully loaded from $mimeJSON"
    }
    catch {
        Write-Error "[ERROR] Failed to load JSON: $($_.Exception.Message)"
        exit 1
    }
}
else {
    Write-Error "[ERROR] Configuration file not found: $mimeJSON"
    exit 1
}


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# Get public and private function definition files
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
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
    Export-ModuleMember -Function ($PublicFunctions.BaseName)
}

# Module initialization message
Write-Verbose "httphost.daemon module loaded successfully. Available functions: $(($PublicFunctions.BaseName) -join ', ')"
