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

# Remember the 3-Step-Enterprise-Pattern??

# 1st Step: ... load the module
Import-Module (Join-Path $PSScriptRoot 'local.httpserver.psd1') -Verbose

# 2nd Step: ... configure the module
# Here are some examples on how to use the SetCoreConfig-Method
# 
# Sets a wwwwroot-Directory and activates logging
# SetCoreConfig -PathPointer "C:\local.httpserver\wwwroot" -UseLogging 1
# 
# With this line, you can use it more portable ;)
# If no port is specified, the system falls back to module.config.ps1 (port 8080).
# SetCoreConfig -PathPointer (Join-Path $PSScriptRoot 'wwwroot') -UseLogging 0
# 
# You can set a explicit port
# SetCoreConfig -PathPointer (Join-Path $PSScriptRoot 'wwwroot') -Port 8085 -UseLogging 1
# 
# You can give your server a name :)
# SetCoreConfig -PathPointer (Join-Path $PSScriptRoot 'wwwroot') -Port 8085 -UseLogging 1 -ServerName 'MyLocalServer'
# 
# Aaaaand ... you can set a mode, how local.httpserver will behave
# You can use one of the following modes: 'hidden','systray','console','desktop'
# SetCoreConfig -PathPointer (Join-Path $PSScriptRoot 'wwwroot') -Port 8085 -UseLogging 1 -ServerName 'MyLocalServer' -Mode 'consle'
# 
SetCoreConfig -PathPointer (Join-Path $PSScriptRoot 'wwwroot') -Port 8080 -UseLogging 0



# 3rd Step: ... start the server
Start-HTTPserver
