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
#Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1' -Force -Verbose
#Get-Command -Module WinISO.ScriptFXLib | Sort-Object Name
Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1'



# Import global vars using getter-functionallity
$appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read' -Unwrap
$appenv  = WinISOcore -Scope 'env' -GlobalVar 'appenv'  -Permission 'read' -Unwrap


Write-Host 'You are using '$appinfo.AppName' v'$appinfo.AppVers
Write-Host 'Current Root-Directory of your project: '$appenv.ISOroot
Write-Host 'Please make sure to put all required files in that directory'

# Let's check the requirements for using the WinISO ScriptFX Library
$CheckReq = CheckModuleRequirements -Export 1
if ( $CheckReq.code -eq 0) { Write-Host $CheckReq.msg } 
else { Write-Error $CheckReq.msg }
Write-Host 'The Logfile is available at: '$MyWinISO.appenv.LogfileDir