<#
    .SYNOPSIS
        A simple HTTP server implemented in PowerShell.
        Launcher script for local.httpserver (Runspace mode).
    .DESCRIPTION
        This module provides a lightweight HTTP server that can serve static files and support Single Page Applications (SPAs) with client-side routing. It is ideal for local development, testing, and quick file sharing without the need for complex server setups.
        Implements the 3-Step-Enterprise-Pattern:
            1. Import-Module   — loads local.httpserver.psm1 with all functions
            2. SetCoreConfig   — configures port, wwwRoot and mode
            3. Start-HTTPserver — starts the server in a background Runspace

        In 'console' mode the launcher keeps the process alive by looping
        until the Runspace exits or the user presses Ctrl+C.
        In 'hidden' mode no wait-loop is needed — the window is hidden and
        the process stays alive as long as the Runspace is running.
    .EXAMPLE
        .\local.httpserver.ps1
        .\local.httpserver.ps1 -Port 9090 -wwwRoot 'C:\MyWebsite'
    .NOTES
        Creation Date : 15.04.2026
        Last Update   : 26.04.2026
        Version       : 1.01.00
        Author        : Praetoriani (a.k.a. M.Sczepanski)
        Website       : https://github.com/praetoriani/PowerShell.Mods
    .REQUIREMENTS
        - PowerShell 5.1 or higher
        - No external dependencies
#>

# Remember the 3-Step-Enterprise-Pattern??

# ____________________________________________________________________________________________________
# 1st STEP: ... LOAD/IMPORT THE MODULE
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
Import-Module (Join-Path $PSScriptRoot 'local.httpserver.psd1') -Force -Verbose


# ____________________________________________________________________________________________________
# 2nd STEP: ... CONFIGURE THE MODULE/SERVER
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# Available modes: 'console', 'hidden', 'systray', 'desktop'
#   console  — server runs in the background, this console window stays open
#   hidden   — server runs in the background, console window is hidden
#
# Uncomment and adjust the line that fits your use case:
# 
# --------------------------------------------------------------------------------
# 
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
SetCoreConfig -PathPointer (Join-Path $PSScriptRoot 'wwwroot') -Port 8080 -UseLogging 0 -Mode 'console'



# ____________________________________________________________________________________________________
# 3rd STEP: ... START THE SERVER (NON-BLOCKING - RETURNS IMMEDIATELY)
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
Start-HTTPserver


# ____________________________________________________________________________________________________
# 4th STEP: ... THE KEEP-ALIVE LOOP (CNOSOLE MODE ONLY)
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# Start-HTTPserver returns immediately — the server runs in a background Runspace.
# In 'console' mode we must keep the PowerShell process alive, otherwise the
# process exits and takes the Runspace with it.
#
# The loop checks Test-RunspaceExists every 2 seconds:
#   - If the Runspace is still running → sleep and loop again
#   - If the Runspace has exited (e.g. fatal error in Start-HttpRunspace) → exit
#
# Ctrl+C triggers the 'finally' block → Stop-LocalHttpServer → clean shutdown.
#
# In 'hidden' mode this loop is skipped — the process stays alive as a
# background process and can only be stopped via Stop-LocalHttpServer,
# the /sys/ctrl/http-stop route, or by killing the process externally.

if ((Get-ServerConfig -Section 'mode') -eq 'console') {

    Write-Host "[INFO] Server is running. Press Ctrl+C to stop." -ForegroundColor Yellow
    Write-Host "       Use 'Get-LocalHttpServerStatus' to see live stats." -ForegroundColor Gray
    Write-Host ""

    try {
        # Keep the process alive while the Runspace is running
        while (Test-RunspaceExists -RunspaceName 'http') {
            Start-Sleep -Seconds 2
        }
        # If we reach here, the Runspace exited on its own (e.g. fatal error)
        # Exit loop without Ctrl+C → Runspace exited automatically
        Write-Host "[WARN] Server Runspace exited unexpectedly." -ForegroundColor Yellow
    }
    finally {
        # Ctrl+C or any terminating error → ensure clean shutdown
        Write-Host "[INFO] Shutdown signal received. Stopping server..." -ForegroundColor Cyan
        Stop-LocalHttpServer -TimeoutMs 5000
    }
}


