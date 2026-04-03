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
    # This function will display a message to the current user and wait till the <enter> key is pressed
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

function ThrowInternalError {
    <#
    .SYNOPSIS
        Displays a formatted error message to the user, waits for acknowledgement,
        then terminates the script with the specified exit code.

    .PARAMETER ErrorMessage
        The primary error message to display.

    .PARAMETER ErrorData
        Optional additional data (e.g. a formatted table) to display below the
        primary error message.

    .PARAMETER Color
        Foreground color for all output lines. Defaults to White.

    .PARAMETER ExitCode
        Exit code passed to 'exit'. Defaults to -1.

    .PARAMETER Block
        If set, adds an empty line before and after the error output.

    .PARAMETER CleanupAfterExit
        If set, clears the console before terminating.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Primary error message to display.")]
        [ValidateNotNullOrEmpty()]
        [string]$ErrorMessage,

        [Parameter(Mandatory = $false, HelpMessage = "Optional additional data to display.")]
        [string]$ErrorData,

        [Parameter(Mandatory = $false, HelpMessage = "Text color for all output. Uses ConsoleColor enum.")]
        [ConsoleColor]$Color = [ConsoleColor]::White,

        [Parameter(Mandatory = $false, HelpMessage = "Exit code for the script.")]
        [int]$ExitCode = -1,

        [Parameter(Mandatory = $false, HelpMessage = "If set, wraps output in empty lines.")]
        [switch]$Block,

        [Parameter(Mandatory = $false, HelpMessage = "If set, clears the console before exit.")]
        [switch]$CleanupAfterExit
    )

    if ($Block.IsPresent) { Write-Host "" }

    # Print the primary error message
    Write-Host $ErrorMessage -ForegroundColor $Color

    # Print optional additional data (e.g. table output from Format-Table | Out-String)
    if (-not [string]::IsNullOrWhiteSpace($ErrorData)) {
        Write-Host $ErrorData -ForegroundColor $Color
    }

    if ($Block.IsPresent) { Write-Host "" }
    Write-Host "$($appinfo.AppName) cannot continue and has to be terminated!" -ForegroundColor $Color

    WaitForEnter -Message "Please Press <enter> to exit $($appinfo.AppName) ... " -Color $Color
    
    # Let's clear the console (if requested) and exit the demonstration with the provided exit code
    if ($CleanupAfterExit.IsPresent) { Clear-Host }
    exit $ExitCode
}


# For debugging purpose only
#Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1' -Force -Verbose
#Get-Command -Module WinISO.ScriptFXLib | Sort-Object Name
Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1'

# Import global vars using getter-functionallity
$appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read' -Unwrap
$appenv  = WinISOcore -Scope 'env' -GlobalVar 'appenv'  -Permission 'read' -Unwrap
$appcore = WinISOcore -Scope 'env' -GlobalVar 'appcore' -Permission 'read' -Unwrap
$uupdump = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap


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
else { Write-Host $CheckReq.msg -ForegroundColor DarkRed }
$step1msg = @"

If you want to check the Logfile, it is available at:
$($appenv.LogfileDir)\$($appcore.ReqResLog)

"@
Write-Host $step1msg -ForegroundColor DarkGray

# Step 02: Let's initialize the WinISO Environment and check if everything is in place
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$step2msg = @"
The 2nd step should always be used to verify that the WinISO Environment
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
$errormsg = @"
Runtime Error in $($appinfo.AppName) while initializing WinISO Environment!
$($TMPresult.msg)

"@
ThrowInternalError -ErrorMessage $errormsg `
                    -ErrorData $TMPresult.data `
                    -Color DarkRed -ExitCode -1 -Block -CleanupAfterExit
}
WaitForEnter -Message "Please Press <enter> to continue ... " -Color DarkGray -Block

# Step 03: Let's try do download and unzip a uupdump package from uupdump.net
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$step3msg = @"
In this 3rd step, we're going to download a ZIP-File from uupdump.net and extract its
whole content so we can create a bootable ISO file out of the uupdump package.
For this demo we're going to use the latest $($uupdump.ostype) Pro $($uupdump.osvers) (Arch: $($uupdump.osarch))
"@
# Write new value to uupdump-scope
$r = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'write' `
                -VarKeyID 'zipname' -SetNewVal "$($uupdump.ostype)-Pro-$($uupdump.osvers)-$($uupdump.osarch)-latest.zip"
#if ($r.code -eq 0) { Write-Host "Updated." }
# re-fresh the local variable with the latest values from the module-scope
$uupdump = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap

Write-Host $step3msg -ForegroundColor DarkGray
WaitForEnter -Message "Please Press <enter> to continue ... " -Color DarkGray
$UUPDresult = DownloadUUPDump -OStype $($uupdump.ostype) -OSvers $($uupdump.osvers) -OSarch $($uupdump.osarch) `
                            -Target "$($appenv.Downloads)\$($uupdump.zipname)"
if ($UUPDresult.code -eq 0) { Write-Host "Download successfully finished." -ForegroundColor DarkGreen }
else {
$errormsg = @"
Runtime Error in $($appinfo.AppName) while downloading UUPDump!

"@
ThrowInternalError -ErrorMessage $errormsg `
                    -ErrorData ($UUPDresult.data | Out-String) `
                    -Color DarkRed -ExitCode -1 -Block -CleanupAfterExit
}
# Extract, verify and delete ZIP afterwards
$ExtractResult = ExtractUUPDump -ZIPfile "$($appenv.Downloads)\$($uupdump.zipname)" `
                                -Target  "$($appenv.UUPDumpDir)" `
                                -Verify  1 `
                                -Cleanup 1
if ($ExtractResult.code -eq 0) { Write-Host "Extraction completed successfully." -ForegroundColor DarkGreen }
else {
$errormsg = @"
Runtime Error in $($appinfo.AppName) while extracting $($uupdump.zipname)!

"@
ThrowInternalError -ErrorMessage $errormsg `
                    -ErrorData ($ExtractResult.data | Out-String) `
                    -Color DarkRed -ExitCode -1 -Block -CleanupAfterExit
}

# Let's clear the console and exit the demonstration
WaitForEnter -Message "We're done. Please Press <enter> to exit ... " -Color DarkGray -Block
Clear-Host
Exit 0