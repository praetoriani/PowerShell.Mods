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

# Let's define some useful functions we can use during this demonstration
function WaitForEnter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false,  HelpMessage = "Sets the message that will be displayed to the user while waiting for the input.")]
        [ValidateNotNullOrEmpty()]
        [string]$Message = "Please Press <enter> to continue ...",

        [Parameter(Mandatory = $false, HelpMessage = "Text color for the prompt. Uses ConsoleColor enum.")]
        [ConsoleColor]$Color = [ConsoleColor]::White,

        [Parameter(Mandatory = $false, HelpMessage = "If set, the user input will be wrapped in empty lines.")]
        [switch]$Block
    )
    
    if ($Block.IsPresent) { Write-Host "" }
    do {
        Write-Host $Message -NoNewline -ForegroundColor $Color
        $input = Read-Host
    } while ($input -ne '')
    if ($Block.IsPresent) { Write-Host "" }

}


# For debugging purpose only
#Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1' -Force -Verbose
#Get-Command -Module WinISO.ScriptFXLib | Sort-Object Name
Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1'

# Import global vars using getter-functionallity
$appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read' -Unwrap
$appenv  = WinISOcore -Scope 'env' -GlobalVar 'appenv'  -Permission 'read' -Unwrap
$appcore = WinISOcore -Scope 'env' -GlobalVar 'appcore' -Permission 'read' -Unwrap


# INITIALIZATION
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# We'll start wich a clean console window
Clear-Host
$welcome = @"
***************************************************************************"
Welcome to Demo No.2 of $($appinfo.AppName) v$($appinfo.AppVers)

This example will show you how the $($appinfo.AppName)-Framework works
and how you can use this PowerShell Module in your own scripts/projects.
"@
Write-Host $welcome -ForegroundColor DarkGray
# Let the user start the demonstration whenever he is ready
WaitForEnter -Message "Please Press <enter> to start the demonstration ... " -Color DarkGray -Block

# Step 01: Let's check, if the user/machine fullfills all requirement
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$step1msg = @"
To make sure that everything will work as expected, we will first perform
a short system check. So please wait, while the verification is running ...

"@
Write-Host $step1msg -ForegroundColor DarkGray
$CheckReq = CheckModuleRequirements -Export 1
if ( $CheckReq.code -eq 0) { Write-Host $CheckReq.msg -ForegroundColor DarkGreen }
else { Write-Error $CheckReq.msg -ForegroundColor DarkRed }
$step1msg = @"

If you want to check the Logfile, it is available at:
$($appenv.LogfileDir)\$($appcore.ReqResLog)

"@
Write-Host $step1msg -ForegroundColor DarkGray

# Step 02: Let's initialize the WinISO Environment and check if everything is in place
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$step2msg = @"
The second step should always be used to verify that the WinISO Environment
does exists and make sure that we have the correct environmental structure.
You can do this, by using the InitializeEnvironment function.
This function will automatically do the whole job for you :)
"@
Write-Host $step2msg -ForegroundColor DarkGray
WaitForEnter -Message "Please Press <enter> to continue ... " -Color DarkGray
Write-Host ""
$TMPresult = InitializeEnvironment
if ($TMPresult.code -eq 0) { Write-Host $TMPresult.msg -ForegroundColor DarkGreen }
else {
    Write-Error -Message "Runtime Error in $($appinfo.AppName) while initializing WinISO Environment!" -ForegroundColor DarkRed
    Write-Error -Message ""
    Write-Error $TMPresult.data | Format-Table StepName, Status, Detail -AutoSize -ForegroundColor DarkRed
    Write-Error -Message ""
    Write-Error -Message "$($appinfo.AppName) cannot continue and has to be terminated!" -ForegroundColor DarkRed
    WaitForEnter -Message "Please Press <enter> to exit $($appinfo.AppName) ... " -Color DarkRed
    # Let's clear the console and exit the demonstration
    Clear-Host
    exit -1
}
WaitForEnter -Message "Please Press <enter> to continue ... " -Color DarkGray -Block

# Let's clear the console and exit the demonstration
#Clear-Host
Exit 0