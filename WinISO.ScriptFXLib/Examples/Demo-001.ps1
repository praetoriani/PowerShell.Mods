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
$appcore = WinISOcore -Scope 'env' -GlobalVar 'appcore' -Permission 'read' -Unwrap


Write-Host "You are using $($appinfo.AppName) v$($appinfo.AppVers)"
Write-Host ""
Write-Host "Current Root-Directory of your project: $($appenv.ISOroot)"
Write-Host 'Please make sure to put all required files in that directory'
Write-Host ""
Write-Host "This demo is using the following PowerShell Libraries:"
Write-Host "$($appcore.PSmod.WinISOmodlib)"
Write-Host "$($appcore.PSmod.PSAppCoreLib)"
Write-Host "PowerShell Modules are stored in: $($appcore.Root)"
Write-Host ""

Write-Host "Checking Requirements. Please wait ..."
Write-Host ""
# Let's check the requirements for using the WinISO ScriptFX Library
$CheckReq = CheckModuleRequirements -Export 1
if ( $CheckReq.code -eq 0) { Write-Host $CheckReq.msg } 
else { Write-Error $CheckReq.msg }
Write-Host ""
Write-Host "The Logfile is available at: $($appenv.LogfileDir)\$($appcore.ReqResLog)"
Write-Host ""

Write-Host "Trying to download oscdimg.exe from Github. Please wait ..."
$DownloadURL = "https://github.com/praetoriani/PowerShell.Mods/blob/main/WinISO.ScriptFXLib/Requirements/oscdimg.exe"
$Save2Folder = "$($appenv.Downloads)\oscdimg.exe"
$result = GitHubDownload `
    -URL    $DownloadURL `
    -SaveTo $Save2Folder
if ($result.code -eq 0) { Write-Host "Success: $($result.msg)" }
else { Write-Host "Failed: $($result.msg)" }
Write-Host ""

Write-Host "Time to download a UUP Dump for Windows 11 24H2 amd64. Please wait ..."
$result = DownloadUUPDump -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' `
                            -Target "$($appenv.Downloads)\Win11-24H2-amd64.zip"
if ($result.code -eq 0) { Write-Host "Downloaded: $($result.data)" }
Write-Host ""


Write-Host "Time to download latest PowerShell Installer for arch win-x64. Please wait ..."
$result = GetLatestPowerShellSetup `
-DownloadDir  "$($appenv.Downloads)" `
-Architecture "win-x64" `
-RunInstaller 0
if ($result.code -eq 0) { Write-Host "Downloaded: $($result.data)" }
else                    { Write-Host "Failed: $($result.msg)" }
Write-Host ""

Write-Host "Download latest PowerShell Installer (msixbundle). Please wait ..."
$result = GetLatestPowerShellSetup `
-DownloadDir  "$($appenv.Downloads)" `
-Architecture "win-msix" `
-RunInstaller 0
if ($result.code -eq 0) { Write-Host "Downloaded: $($result.data)" }
else                    { Write-Host "Failed: $($result.msg)" }
Write-Host ""
