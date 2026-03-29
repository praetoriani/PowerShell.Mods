<#
    .SYNOPSIS
        Demo 001 - A simple demonstration on how to use the WinISO ScriptFX Library in your own scripts.
    
    .DESCRIPTION
        The WinISO ScriptFX Library provides a set of functions designed to simplify and enhance the scripting experience for Windows administrators and developers. It includes utilities for file manipulation, system information retrieval, and other common tasks.
    
    .NOTES
        Creation Date: 29.03.2026
        Last Update:   29.03.2026
        Version:       1.00.02
#>

#Import-Module -Name 'C:\WinISO\app.core\PSAppCoreLib\PSAppCoreLib.psd1' -Force -Verbose
Import-Module -Name 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1' -Force -Verbose


# Import global vars using getter-functionallity
$MyWinISO = @{
    appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read'
    appenv  = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'read'
#    appcore = WinISOcore -Scope 'env' -GlobalVar 'appcore' -Permission 'read'
}

Write-Host $MyWinISO.appinfo.data.AppName   # >> WinISOSciptFXLib