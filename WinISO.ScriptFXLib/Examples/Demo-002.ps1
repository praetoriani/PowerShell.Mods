<#
    .SYNOPSIS
        Demo-002.ps1 - A simple demonstration on how to use the WinISO ScriptFX Library in your own scripts.

    .DESCRIPTION
        The WinISO ScriptFX Library provides a set of functions designed to simplify and enhance the scripting experience
        for Windows administrators and developers. It includes utilities for file manipulation, system information retrieval,
        and other common tasks.

    .NOTES
        Creation Date: 03.04.2026
        Last Update:   03.04.2026
        Version:       1.00.00
#>

# For debugging purpose only
#Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1' -Force -Verbose
#Get-Command -Module WinISO.ScriptFXLib | Sort-Object Name
Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1'

# Import global vars using getter-functionallity
$appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read' -Unwrap
$appenv  = WinISOcore -Scope 'env' -GlobalVar 'appenv'  -Permission 'read' -Unwrap
$appcore = WinISOcore -Scope 'env' -GlobalVar 'appcore' -Permission 'read' -Unwrap

# We'll start wich a clean console window
Clear-Host
Write-Host "***************************************************************************" -ForegroundColor DarkGray
Write-Host "Welcome to Demo No.2 of $($appinfo.AppName) v$($appinfo.AppVers)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "This example will show you how the $($appinfo.AppName)-Framework works" -ForegroundColor DarkGray
Write-Host "and how you can use this PowerShell Module in your own scripts/projects." -ForegroundColor DarkGray
Write-Host ""
# Let the user start the demonstration whenever he is ready
do {
    Write-Host 'Please Press <enter> to start the demonstration ... ' -NoNewline -ForegroundColor DarkGray
    $input = Read-Host
} while ($input -ne '')
Write-Host ""
# Step 01: Let's check, if the user/machine fullfills all requirement
Write-Host "To make sure that everything will work as expected, we will first perform" -ForegroundColor DarkGray
Write-Host "a short system check. So please wait, while the verification is running ..." -ForegroundColor DarkGray
Write-Host ""
$CheckReq = CheckModuleRequirements -Export 1
if ( $CheckReq.code -eq 0) { Write-Host $CheckReq.msg -ForegroundColor DarkGreen }
else { Write-Error $CheckReq.msg -ForegroundColor DarkRed }
Write-Host ""
Write-Host "If you want to check the Logfile, it is available at:" -ForegroundColor DarkGray
Write-Host "$($appenv.LogfileDir)\$($appcore.ReqResLog)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "The second step should always be used to verify that the WinISO Environment" -ForegroundColor DarkGray
Write-Host "does exists and make sure that we have the correct environmental structure." -ForegroundColor DarkGray
Write-Host "You can do this, by using the InitializeEnvironment function." -ForegroundColor DarkGray
Write-Host "This function will automatically do the whole job for you :)" -ForegroundColor DarkGray
do {
    Write-Host 'Please Press <enter> to continue ... ' -NoNewline -ForegroundColor DarkGray
    $input = Read-Host
} while ($input -ne '')
Write-Host ""
$TMPresult = InitializeEnvironment
if ($TMPresult.code -eq 0) { Write-Host $TMPresult.msg -ForegroundColor DarkGreen }
else { Write-Host $TMPresult.data | Format-Table StepName, Status, Detail -AutoSize -ForegroundColor DarkRed }

# Let's clear the console and exit the demonstration
#Clear-Host
Exit 0