<#
    .SYNOPSIS
        A simple HTTP server implemented in PowerShell.
    .DESCRIPTION
        This module provides a lightweight HTTP server that can serve static files and support Single Page Applications (SPAs) with client-side routing. It is ideal for local development, testing, and quick file sharing without the need for complex server setups.
    .EXAMPLE
        .\local.httpserver.ps1
        .\local.httpserver.ps1 -Port 9090 -wwwRoot 'C:\MyWebsite'
    .NOTES
        Creation Date : 15.04.2026
        Last Update   : 18.04.2026
        Version       : 1.00.00
        Author        : Praetoriani (a.k.a. M.Sczepanski)
        Website       : https://github.com/praetoriani/PowerShell.Mods
    .REQUIREMENTS
        - PowerShell 5.1 or higher
        - No external dependencies
#>
param (
    [Parameter(Mandatory = $false)]
    [int]$Port = 8080,

    [Parameter(Mandatory = $false)]
    [string]$wwwRoot = (Join-Path $PSScriptRoot 'wwwroot')
)

# Remember the 3-Step-Enterprise-Pattern??

# 1st Step: ... load the module
Import-Module (Join-Path $PSScriptRoot 'local.httpserver.psd1') -Force

# 2nd Step: ... configure the module
SetCoreConfig -PathPointer $wwwRoot -UseLogging 0 -Mode 'console' -UseIPC $false

# 3rd Step: ... start the server
Start-LocalHttpServer -Port $Port -wwwRoot $wwwRoot
