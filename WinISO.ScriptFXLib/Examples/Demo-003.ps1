&#xFEFF;<#
    .SYNOPSIS
        Demo-003.ps1 - A comprehensive demonstration of the WinISO ScriptFX Library (v1.00.05).

    .DESCRIPTION
        This demonstration script provides an in-depth walkthrough of the WinISO.ScriptFXLib
        PowerShell module. It covers all major functional areas introduced up to version 1.00.05,
        including:

          - Module initialization and global variable access via WinISOcore
          - System requirement checks using CheckModuleRequirements
          - Working environment setup with InitializeEnvironment and VerifyEnvironment
          - Logging with WriteLogMessage
          - Downloading the latest PowerShell release with GetLatestPowerShellSetup
          - Downloading generic files from GitHub with GitHubDownload
          - Downloading and extracting UUP Dump packages (DownloadUUPDump / GetUUPDumpPackage)
          - Extracting, creating and renaming ISO files
          - Mounting and unmounting WIM images
          - Loading, querying and unloading offline registry hives
          - Managing provisioned Appx packages (GetAppxPackages / AppxPackageLookUp /
            RemAppxPackages / AddAppxPackages)
          - Reading and writing module-scope variables via the WinISOcore accessor

        Each step displays explanatory output to the console and waits for user input
        before continuing, keeping the demonstration interactive and easy to follow.

    .NOTES
        Creation Date: 04.04.2026
        Last Update:   04.04.2026
        Version:       1.00.00

        Designed for use with WinISO.ScriptFXLib v1.00.05 or later.
        Requires administrator privileges for environment setup, DISM, and registry operations.
#>

# ═══════════════════════════════════════════════════════════════════════════════
#  HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function WaitForEnter {
    <#
    .SYNOPSIS
        Displays a prompt and waits until the user presses &lt;Enter&gt;.

    .PARAMETER Message
        The prompt message displayed to the user.

    .PARAMETER Color
        ConsoleColor for the prompt text. Defaults to White.

    .PARAMETER Block
        When set, wraps the prompt in blank lines for visual separation.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Prompt message shown while waiting for input.")]
        [ValidateNotNullOrEmpty()]
        [string]$Message = "Please press &lt;Enter&gt; to continue ...",

        [Parameter(Mandatory = $false, HelpMessage = "Text color for the prompt. Uses ConsoleColor enum.")]
        [ConsoleColor]$Color = [ConsoleColor]::White,

        [Parameter(Mandatory = $false, HelpMessage = "If set, the prompt is wrapped in empty lines.")]
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
        Displays a formatted error message, waits for acknowledgement, then exits the script.

    .PARAMETER ErrorMessage
        The primary error message to display.

    .PARAMETER ErrorData
        Optional additional detail (e.g. a formatted table) shown below the error message.

    .PARAMETER Color
        Foreground color for all output lines. Defaults to White.

    .PARAMETER ExitCode
        Exit code passed to 'exit'. Defaults to -1.

    .PARAMETER Block
        If set, wraps the error output in empty lines.

    .PARAMETER CleanupAfterExit
        If set, clears the console before terminating.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,  HelpMessage = "Primary error message to display.")]
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

    Write-Host $ErrorMessage -ForegroundColor $Color

    if (-not [string]::IsNullOrWhiteSpace($ErrorData)) {
        Write-Host $ErrorData -ForegroundColor $Color
    }

    if ($Block.IsPresent) { Write-Host "" }
    Write-Host "$($appinfo.AppName) cannot continue and has to be terminated!" -ForegroundColor $Color

    WaitForEnter -Message "Please press &lt;Enter&gt; to exit $($appinfo.AppName) ... " -Color $Color

    if ($CleanupAfterExit.IsPresent) { Clear-Host }
    exit $ExitCode
}


function PrintSectionHeader {
    <#
    .SYNOPSIS
        Prints a visually distinct section header to the console.

    .PARAMETER Title
        The section title displayed inside the header box.

    .PARAMETER Color
        Foreground color for the header. Defaults to DarkCyan.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$Color = [ConsoleColor]::DarkCyan
    )

    $border = ([string][char]0x2500) * 73
    Write-Host ""
    Write-Host "$([char]0x250C)$border$([char]0x2510)" -ForegroundColor $Color
    Write-Host "$([char]0x2502)  $Title" -ForegroundColor $Color
    Write-Host "$([char]0x2514)$border$([char]0x2518)" -ForegroundColor $Color
    Write-Host ""
}


function PrintResult {
    <#
    .SYNOPSIS
        Prints a color-coded PASS/FAIL result line to the console.

    .PARAMETER Label
        Short label identifying the check or operation.

    .PARAMETER Result
        The OPSreturn-compatible object returned by a WinISO function.
        Must have a .code property: 0 = success, any other = failure.

    .PARAMETER SuccessText
        Text appended when the result is successful. Defaults to "OK".

    .PARAMETER FailText
        Text appended when the result indicates failure. Defaults to result .msg.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]  [string]$Label,
        [Parameter(Mandatory = $true)]  $Result,
        [Parameter(Mandatory = $false)] [string]$SuccessText = "OK",
        [Parameter(Mandatory = $false)] [string]$FailText    = ""
    )

    if ($Result.code -eq 0) {
        Write-Host "  [PASS] $Label : $SuccessText" -ForegroundColor DarkGreen
    }
    else {
        $detail = if ([string]::IsNullOrWhiteSpace($FailText)) { $Result.msg } else { $FailText }
        Write-Host "  [FAIL] $Label : $detail" -ForegroundColor DarkRed
    }
}


# ═══════════════════════════════════════════════════════════════════════════════
#  MODULE IMPORT
# ═══════════════════════════════════════════════════════════════════════════════

# For debugging: uncomment the next two lines to force-reload and list all exported functions
#Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1' -Force -Verbose
#Get-Command -Module WinISO.ScriptFXLib | Sort-Object Name
Import-Module 'C:\WinISO\app.core\WinISO.ScriptFXLib\WinISO.ScriptFXLib.psd1'


# ═══════════════════════════════════════════════════════════════════════════════
#  GLOBAL VARIABLE RETRIEVAL
#  All module-scope variables are accessed via the type-safe WinISOcore accessor.
#  Never read $script:* variables directly from outside the module -- always use
#  WinISOcore with Permission='read' and the -Unwrap switch to get a live
#  reference to the underlying hashtable.
# ═══════════════════════════════════════════════════════════════════════════════

$appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read' -Unwrap
$appenv  = WinISOcore -Scope 'env' -GlobalVar 'appenv'  -Permission 'read' -Unwrap
$appcore = WinISOcore -Scope 'env' -GlobalVar 'appcore' -Permission 'read' -Unwrap
$uupdump = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap


# ═══════════════════════════════════════════════════════════════════════════════
#  WELCOME SCREEN
# ═══════════════════════════════════════════════════════════════════════════════
Clear-Host
$welcomeText = @"
*******************************************************************************
  Welcome to Demo No.3 of $($appinfo.AppName) v$($appinfo.AppVers)
*******************************************************************************

  This comprehensive demo walks you through ALL major capabilities of the
  $($appinfo.AppName) framework as of version $($appinfo.AppVers).

  Topics covered:
    01. Module global variables and WinISOcore accessor
    02. System requirements check (CheckModuleRequirements)
    03. Working environment setup (InitializeEnvironment / VerifyEnvironment)
    04. Logging with WriteLogMessage
    05. Downloading the latest PowerShell MSI (GetLatestPowerShellSetup)
    06. Generic GitHub file download (GitHubDownload)
    07. Downloading a UUP Dump package (DownloadUUPDump)
    08. Multi-edition ISO download (GetUUPDumpPackage)
    09. Extracting and creating ISO files
    10. Mounting / unmounting WIM images
    11. Offline registry hive operations
    12. Appx package management
    13. Reading and writing module-scope variables via WinISOcore

  NOTE: Steps that require admin rights, network access or an actual
        Windows ISO are shown with a [DEMO] prefix and will display the
        expected behavior without executing potentially long-running tasks.

*******************************************************************************
"@
Write-Host $welcomeText -ForegroundColor DarkGray
WaitForEnter -Message "Press &lt;Enter&gt; to start the demonstration ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 01 -- MODULE GLOBAL VARIABLES AND WINISOCORE ACCESSOR
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 01 -- Module Global Variables and WinISOcore Accessor"

$step01msg = @"
WinISO.ScriptFXLib manages its state through a set of module-scope hashtable
variables defined in WinISO.ScriptFXLib.psm1. These variables are NEVER
directly accessible from outside the module -- the correct, type-safe way to
read or write them is always through the WinISOcore function.

Syntax:
  READ  : WinISOcore -Scope 'env' -GlobalVar '<var>' -Permission 'read' [-Unwrap]
  WRITE : WinISOcore -Scope 'env' -GlobalVar '<var>' -Permission 'write'
                     -VarKeyID '<key>' -SetNewVal <value>

Available GlobalVar identifiers:
  appinfo    -- module metadata  (AppName, AppVers, AppDevName, ...)
  appenv     -- file system paths (ISOroot, MountPoint, Downloads, ...)
  appcore    -- read-only core config (PSmod paths, log file names, ...)
  uupdump    -- UUP Dump download state  (ostype, osvers, osarch, zipname, ...)
  appverify  -- requirement check results per check key (PASS/FAIL/INFO/WARN)
  appx       -- Appx package state arrays (listed, remove, inject)
  loadedhives-- tracking of offline registry hives currently mounted

The -Unwrap switch returns the raw hashtable directly instead of the
OPSreturn wrapper { .code, .msg, .data }, which is useful in calling code
where you just want to read values:

  `$appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read' -Unwrap

Current module metadata:
"@
Write-Host $step01msg -ForegroundColor DarkGray

# Display all appinfo fields
$appinfo.GetEnumerator() | Sort-Object Key | ForEach-Object {
    Write-Host ("  {0,-12}: {1}" -f $_.Key, $_.Value) -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "  Key environment paths (appenv):" -ForegroundColor DarkGray
$appenv.GetEnumerator() | Sort-Object Key | ForEach-Object {
    Write-Host ("  {0,-14}: {1}" -f $_.Key, $_.Value) -ForegroundColor DarkYellow
}

# Demonstrate a WinISOcore WRITE operation
Write-Host ""
Write-Host "  Demonstrating a WinISOcore WRITE operation ..." -ForegroundColor DarkGray
$writeResult = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'write' `
                          -VarKeyID 'zipname' -SetNewVal "Windows11-Pro-24H2-amd64-latest.zip"
PrintResult -Label "WinISOcore WRITE (uupdump.zipname)" -Result $writeResult `
            -SuccessText $writeResult.msg

# Re-read the updated value to confirm
$uupdump = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap
Write-Host "  Confirmed new value  -> uupdump.zipname = '$($uupdump.zipname)'" -ForegroundColor DarkYellow

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 02 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 02 -- SYSTEM REQUIREMENTS CHECK
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 02 -- System Requirements Check (CheckModuleRequirements)"

$step02msg = @"
Before performing any ISO-related work it is good practice to verify that
the current machine fulfils all prerequisites. CheckModuleRequirements
performs a comprehensive audit and reports each check with one of four status
codes:

  PASS -- requirement fully met
  INFO -- requirement not yet met but can be fixed automatically (e.g. by
         calling InitializeEnvironment)
  WARN -- requirement not met and needs manual user action (e.g. run elevated)
  FAIL -- hard system component missing, no automated fix available

The optional -Export 1 parameter writes a plain-text report to:
  $($appenv.LogfileDir)\$($appcore.ReqResLog)

Running the check now. Please wait ...
"@
Write-Host $step02msg -ForegroundColor DarkGray

$checkResult = CheckModuleRequirements -Export 1
if ($checkResult.code -eq 0) {
    Write-Host $checkResult.msg -ForegroundColor DarkGreen
}
else {
    Write-Host $checkResult.msg -ForegroundColor DarkRed
}

# Show per-check detail table
Write-Host ""
Write-Host "  Per-check breakdown:" -ForegroundColor DarkGray
$appverify = WinISOcore -Scope 'env' -GlobalVar 'appverify' -Permission 'read' -Unwrap
$appverify.GetEnumerator() | Where-Object { $_.Key -ne 'result' } | Sort-Object Key | ForEach-Object {
    $color = switch ($_.Value) {
        'PASS' { [ConsoleColor]::DarkGreen  }
        'INFO' { [ConsoleColor]::DarkYellow }
        'WARN' { [ConsoleColor]::Yellow     }
        'FAIL' { [ConsoleColor]::DarkRed    }
        default { [ConsoleColor]::DarkGray  }
    }
    Write-Host ("  {0,-22}: {1}" -f $_.Key, $_.Value) -ForegroundColor $color
}

Write-Host ""
$res = $appverify['result']
Write-Host "  Summary  ->  PASS: $($res.pass)  |  INFO: $($res.info)  |  WARN: $($res.warn)  |  FAIL: $($res.fail)" `
      -ForegroundColor DarkGray

Write-Host ""
Write-Host "  If you want to inspect the full report file, look here:" -ForegroundColor DarkGray
Write-Host "  $($appenv.LogfileDir)\$($appcore.ReqResLog)" -ForegroundColor DarkYellow

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 03 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 03 -- ENVIRONMENT SETUP AND VERIFICATION
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 03 -- Environment Setup and Verification"

$step03msg = @"
InitializeEnvironment ensures that the complete WinISO directory structure
exists and that oscdimg.exe is present. It creates any missing directories,
including two important OEM sub-directories (OEM\root and OEM\windir), and
downloads oscdimg.exe from the GitHub repository if it is absent.

The function collects all results without aborting on the first failure and
returns a single structured status object at the end. This makes it easy to
see exactly which steps succeeded and which (if any) failed.

After InitializeEnvironment you can use VerifyEnvironment to perform spot
checks on individual files, directories or configuration objects:

  VerifyEnvironment -type 'file' -path 'C:\WinISO\Oscdimg\oscdimg.exe'
  VerifyEnvironment -type 'dir'  -path 'C:\WinISO\Downloads'

Running InitializeEnvironment now ...
"@
Write-Host $step03msg -ForegroundColor DarkGray

$initResult = InitializeEnvironment
if ($initResult.code -eq 0) {
    Write-Host $initResult.msg -ForegroundColor DarkGreen
}
else {
    $errMsg = @"
Runtime Error in $($appinfo.AppName) while initializing the WinISO Environment!
$($initResult.msg)
"@
    ThrowInternalError -ErrorMessage $errMsg `
                       -ErrorData ($initResult.data | Format-Table StepName, Status, Detail -AutoSize | Out-String) `
                       -Color DarkRed -ExitCode -1 -Block -CleanupAfterExit
}

# Show per-step detail table
Write-Host ""
Write-Host "  Per-step detail:" -ForegroundColor DarkGray
$initResult.data | Format-Table StepName, Status, Detail -AutoSize | Out-String |
    ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }

# Spot-check one file and one directory via VerifyEnvironment
$verifFile = VerifyEnvironment -type 'file' -path $appenv['OscdimgExe']
$verifDir  = VerifyEnvironment -type 'dir'  -path $appenv['Downloads']

# VerifyEnvironment returns code 1 when the item exists, code 0 when it does not
if ($verifFile.code -eq 1) {
    Write-Host "  [PASS] oscdimg.exe exists at: $($appenv['OscdimgExe'])" -ForegroundColor DarkGreen
}
else {
    Write-Host "  [WARN] oscdimg.exe NOT found at: $($appenv['OscdimgExe'])" -ForegroundColor Yellow
}

if ($verifDir.code -eq 1) {
    Write-Host "  [PASS] Downloads directory exists at: $($appenv['Downloads'])" -ForegroundColor DarkGreen
}
else {
    Write-Host "  [WARN] Downloads directory NOT found at: $($appenv['Downloads'])" -ForegroundColor Yellow
}

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 04 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 04 -- LOGGING WITH WRITELOGMESSAGE
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 04 -- Logging with WriteLogMessage"

$step04msg = @"
WriteLogMessage writes structured, timestamped log entries to a UTF-8 text
file. Each entry is formatted as:

  [yyyy.MM.dd ; HH:mm:ss] [FLAG] Your message here

Supported severity flags:
  INFO  -- informational messages
  DEBUG -- detailed debug output (default when -Flag is omitted)
  WARN  -- warning conditions
  ERROR -- error conditions

Parameters:
  -Logfile  : full path including filename (directory is created automatically)
  -Message  : the log text
  -Flag     : INFO | DEBUG | WARN | ERROR  (default: DEBUG)
  -Override : 0 = append (default) | 1 = overwrite / create new file

The function returns a standard OPSreturn object:
  .code  0 = success | -1 = failure
  .msg   description of the result

Writing four sample log entries now ...
"@
Write-Host $step04msg -ForegroundColor DarkGray

$demoLogFile = Join-Path $appenv['LogfileDir'] "Demo-003.demo.log"

# Entry 1 -- create new log file (Override=1)
$r1 = WriteLogMessage -Logfile $demoLogFile -Message "Demo-003 started." -Flag "INFO" -Override 1
PrintResult -Label "WriteLogMessage (INFO  / new file)" -Result $r1 -SuccessText "Entry written."

# Entry 2 -- append DEBUG
$r2 = WriteLogMessage -Logfile $demoLogFile -Message "Performing environment setup..." -Flag "DEBUG"
PrintResult -Label "WriteLogMessage (DEBUG / append  )" -Result $r2 -SuccessText "Entry written."

# Entry 3 -- append WARN
$r3 = WriteLogMessage -Logfile $demoLogFile -Message "Optional component not present, will attempt download." -Flag "WARN"
PrintResult -Label "WriteLogMessage (WARN  / append  )" -Result $r3 -SuccessText "Entry written."

# Entry 4 -- append ERROR
$r4 = WriteLogMessage -Logfile $demoLogFile -Message "This is a simulated ERROR entry for demonstration purposes." -Flag "ERROR"
PrintResult -Label "WriteLogMessage (ERROR / append  )" -Result $r4 -SuccessText "Entry written."

Write-Host ""
Write-Host "  Log file written to: $demoLogFile" -ForegroundColor DarkYellow
Write-Host "  Content preview:" -ForegroundColor DarkGray
if (Test-Path $demoLogFile) {
    Get-Content $demoLogFile | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 05 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 05 -- DOWNLOADING THE LATEST POWERSHELL RELEASE
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 05 -- GetLatestPowerShellSetup"

$step05msg = @"
GetLatestPowerShellSetup queries the GitHub Releases API for the PowerShell
repository to automatically detect and download the latest stable release.

Key features:
  - Automatically resolves the latest stable tag via the GitHub Releases API
  - Supports three architecture variants:
      win-x64    -> PowerShell-X.Y.Z-win-x64.msi      (default)
      win-arm64  -> PowerShell-X.Y.Z-win-arm64.msi
      win-msix   -> PowerShell-X.Y.Z-win-x64.msixbundle
  - Verifies download completeness via HTTP Content-Length comparison
  - Optional silent installation (-RunInstaller 1) and post-install cleanup (-RunInstaller 2)
  - Always downloads a fresh copy (deletes any pre-existing file first)

Parameters:
  -DownloadDir   : target directory  (created automatically if missing)
  -Architecture  : win-x64 | win-arm64 | win-msix
  -RunInstaller  : 0 = download only (default) | 1 = download+install | 2 = download+install+delete

[DEMO] This step demonstrates the DOWNLOAD ONLY variant (RunInstaller=0).
       The download target is: $($appenv['Downloads'])\PowerShell

Running GetLatestPowerShellSetup now ...
"@
Write-Host $step05msg -ForegroundColor DarkGray
WaitForEnter -Message "Press &lt;Enter&gt; to start the download ... " -Color DarkGray

$psDownloadDir = Join-Path $appenv['Downloads'] 'PowerShell'
$psResult = GetLatestPowerShellSetup -DownloadDir $psDownloadDir -Architecture 'win-x64' -RunInstaller 0

if ($psResult.code -eq 0) {
    Write-Host ""
    Write-Host "  [PASS] Download successful!" -ForegroundColor DarkGreen
    Write-Host "  File saved to: $($psResult.data)" -ForegroundColor DarkYellow
    Write-Host "  $($psResult.msg)" -ForegroundColor DarkGray
}
else {
    Write-Host ""
    Write-Host "  [FAIL] Download failed: $($psResult.msg)" -ForegroundColor DarkRed
    Write-Host "         This is non-critical for the demo -- continuing ..." -ForegroundColor DarkGray
}

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 06 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 06 -- GENERIC GITHUB FILE DOWNLOAD
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 06 -- GitHubDownload"

$step06msg = @"
GitHubDownload downloads a single file from any public GitHub repository.
It is the generic building block used internally by InitializeEnvironment to
fetch oscdimg.exe and can be called directly in your own scripts.

Key features:
  - Automatically converts github.com/blob/... and /tree/... URLs to their
    raw.githubusercontent.com equivalent
  - Performs a HEAD request to verify URL accessibility before downloading
  - Validates that source and destination share the same file extension
  - Downloads the file as a binary byte stream (works for ALL file types)
  - Verifies completeness via HTTP Content-Length
  - Creates the target directory hierarchy automatically if it does not exist

Parameters:
  -URL    : GitHub URL (blob/tree/raw format all accepted)
  -SaveTo : full destination path including filename

[DEMO] We'll re-download oscdimg.exe from the module requirements to a
       temporary location to demonstrate the function.
       Source URL : $($appcore['requirement']['oscdimg'])
       Destination: $($appenv['TempFolder'])\oscdimg_demo.exe
"@
Write-Host $step06msg -ForegroundColor DarkGray
WaitForEnter -Message "Press &lt;Enter&gt; to start the download ... " -Color DarkGray

$ghTarget = Join-Path $appenv['TempFolder'] 'oscdimg_demo.exe'
$ghResult = GitHubDownload -URL $appcore['requirement']['oscdimg'] -SaveTo $ghTarget

if ($ghResult.code -eq 0) {
    Write-Host ""
    Write-Host "  [PASS] $($ghResult.msg)" -ForegroundColor DarkGreen
    Write-Host "  File saved to: $($ghResult.data)" -ForegroundColor DarkYellow
}
else {
    Write-Host ""
    Write-Host "  [FAIL] $($ghResult.msg)" -ForegroundColor DarkRed
    Write-Host "         Continuing demo ..." -ForegroundColor DarkGray
}

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 07 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 07 -- DOWNLOADING A UUP DUMP PACKAGE (SINGLE EDITION)
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 07 -- DownloadUUPDump (Single-Edition)"

$step07msg = @"
DownloadUUPDump downloads a pre-configured ZIP package from uupdump.net
that contains all scripts and data required to build a Windows 11 ISO.

This function is designed for single-edition downloads:
  - Windows 11 Pro
  - Windows 11 Home

Key features:
  - Automatic build discovery via the UUP Dump API (no manual UUID lookup)
  - Optional build-number pinning via -BuildNo (format: '00000.0000')
  - Supports -Edition 'Pro' or 'Home'
  - New in v1.00.05: -ExcludeNetFX / -IncludeNetFX switches (default: include)
  - New in v1.00.05: -UseESD switch to request install.esd instead of install.wim
  - Completeness check via HTTP Content-Length comparison
  - On success, all download metadata is written back into `$script:uupdump
    via WinISOcore (ostype, osvers, osarch, buildno, kbsize, zipname)

Parameters:
  -OStype  : 'Windows11'  (only supported value)
  -OSvers  : '24H2' | '25H2' | '26H1'
  -OSarch  : 'amd64' | 'arm64'
  -Edition : 'Pro' | 'Home'
  -Target  : full path to the destination .zip file

Current uupdump module state BEFORE the download:
  ostype  = $($uupdump.ostype)
  osvers  = $($uupdump.osvers)
  osarch  = $($uupdump.osarch)
  zipname = $($uupdump.zipname)

NOTE: This downloads several hundred MB. Press &lt;Enter&gt; to start or
      skip by reading the expected behavior description above.
"@
Write-Host $step07msg -ForegroundColor DarkGray
WaitForEnter -Message "Press &lt;Enter&gt; to start the UUP Dump download ... " -Color DarkGray

$uupdResult = DownloadUUPDump -OStype $uupdump.ostype `
                               -OSvers $uupdump.osvers `
                               -OSarch $uupdump.osarch `
                               -Edition 'Pro' `
                               -Target "$($appenv['Downloads'])\$($uupdump.zipname)"

if ($uupdResult.code -eq 0) {
    Write-Host ""
    Write-Host "  [PASS] Download successfully finished." -ForegroundColor DarkGreen

    # Refresh local variable after successful write-back by DownloadUUPDump
    $uupdump = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap

    Write-Host "  Updated uupdump module state AFTER the download:" -ForegroundColor DarkGray
    Write-Host "    ostype  = $($uupdump.ostype)"     -ForegroundColor DarkYellow
    Write-Host "    osvers  = $($uupdump.osvers)"     -ForegroundColor DarkYellow
    Write-Host "    osarch  = $($uupdump.osarch)"     -ForegroundColor DarkYellow
    Write-Host "    buildno = $($uupdump.buildno)"    -ForegroundColor DarkYellow
    Write-Host "    kbsize  = $($uupdump.kbsize) KB"  -ForegroundColor DarkYellow
    Write-Host "    zipname = $($uupdump.zipname)"    -ForegroundColor DarkYellow
}
else {
    Write-Host ""
    Write-Host "  [FAIL] Download failed: $($uupdResult.msg)" -ForegroundColor DarkRed
    Write-Host "         Continuing demo ..." -ForegroundColor DarkGray
}

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 08 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 08 -- MULTI-EDITION ISO DOWNLOAD (GETUUPDUMPPACKAGE)
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 08 -- GetUUPDumpPackage (Multi-Edition)"

$step08msg = @"
GetUUPDumpPackage is the advanced counterpart to DownloadUUPDump and uses
the UUP Dump Virtual Editions feature (autodl=3) to build an ISO that
contains multiple Windows editions in a single file.

Supported extra editions (one or more, combinable):
  ProWorkstations  -- Windows Pro for Workstations
  ProEducation     -- Windows Pro Education
  Education        -- Windows Education
  Enterprise       -- Windows Enterprise
  IoTEnterprise    -- Windows IoT Enterprise

Key differences from DownloadUUPDump:
  - -Editions parameter accepts an array of edition names
  - `$script:uupdump['multiedition'] stores the semicolon-joined display names
  - `$script:uupdump['edition'] is left empty for multi-edition packages
  - -ExcludeNetFX switch: exclude .NET 3.5 from the conversion package
  - -UseESD switch: produce install.esd instead of install.wim

Example calls:

  # Enterprise only
  `$r = GetUUPDumpPackage -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' ``
                          -Editions @('Enterprise') ``
                          -Target 'C:\WinISO\Downloads\Win11_Ent_24H2.zip'

  # Multi-edition: Enterprise + Education + Pro for Workstations
  `$r = GetUUPDumpPackage -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' ``
                          -Editions @('Enterprise','Education','ProWorkstations') ``
                          -Target 'C:\WinISO\Downloads\Win11_Multi_24H2.zip'

  # Enterprise 25H2 without .NET FX 3.5, using ESD format
  `$r = GetUUPDumpPackage -OStype 'Windows11' -OSvers '25H2' -OSarch 'amd64' ``
                          -Editions @('Enterprise','IoTEnterprise') ``
                          -ExcludeNetFX -UseESD ``
                          -Target 'C:\WinISO\Downloads\Win11_Ent_IoT_25H2_ESD.zip'

[DEMO] This step shows the call syntax and expected behavior.
       The actual download (several hundred MB) is NOT triggered automatically.
       Uncomment the lines below in the script to run the real download.
"@
Write-Host $step08msg -ForegroundColor DarkGray

# --- DEMO ONLY: The following block is commented out intentionally ---
# Uncomment to perform the actual multi-edition download:
#
# $multiTarget = "$($appenv['Downloads'])\Win11_Enterprise_Education_24H2.zip"
# $multiResult = GetUUPDumpPackage -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' `
#                                   -Editions @('Enterprise','Education') `
#                                   -Target $multiTarget
# if ($multiResult.code -eq 0) {
#     Write-Host "  [PASS] Multi-edition package downloaded: $($multiResult.data)" -ForegroundColor DarkGreen
#     $uupdump = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap
#     Write-Host "  multiedition = $($uupdump.multiedition)" -ForegroundColor DarkYellow
# }
# else { Write-Host "  [FAIL] $($multiResult.msg)" -ForegroundColor DarkRed }
# --- END DEMO ONLY ---

Write-Host "  [DEMO] Skipping live download. See inline comments to enable." -ForegroundColor DarkYellow

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 09 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 09 -- EXTRACTING, CREATING AND RENAMING ISO FILES
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 09 -- Extract, Create and Rename ISO Files"

$step09msg = @"
After a successful DownloadUUPDump or GetUUPDumpPackage call, the downloaded
ZIP file contains everything needed to build a bootable ISO. The following
functions orchestrate this process:

  ExtractUUPDump   -- Extracts the ZIP file to the UUPDumpDir working folder.
                     Parameters: -ZIPfile, -Target, -Verify (0|1), -Cleanup (0|1)
                     -Verify 1  : checks that all extracted files are readable
                     -Cleanup 1 : deletes the ZIP file after successful extraction

  CreateUUPDiso    -- Runs the UUP Dump conversion scripts inside UUPDumpDir
                     and produces a bootable ISO.
                     Parameters: -UUPDdir, -CleanUp (0|1), -ISOname, ...
                     The function monitors the conversion process in real time with
                     configurable idle timeouts (-SoftIdleMinutes, -HardIdleMinutes,
                     -GlobalTimeoutMinutes, -PollSeconds) for robustness.

  ExtractUUPDiso   -- Mounts the finished ISO via Mount-DiskImage, copies its entire
                     content to ISOdata using robocopy, then dismounts it.
                     This populates the DATA folder required for WIM image work.

  RenameUUPDiso    -- Renames the single ISO found in UUPDumpDir to a canonical name.
                     Fails gracefully if zero or more than one ISO is present.
                     Parameters: -UUPDdir, -NewName

  CleanupUUPDump   -- Removes all non-ISO files from UUPDumpDir after the ISO has
                     been created, keeping only the final .iso file.
                     Parameters: -UUPDdir

Typical workflow:
  1. DownloadUUPDump   -> downloads the ZIP
  2. ExtractUUPDump    -> unzips it to UUPDumpDir
  3. CreateUUPDiso     -> runs uup_download_windows.cmd -> produces .iso
  4. RenameUUPDiso     -> gives the ISO a meaningful name
  5. ExtractUUPDiso    -> mounts the ISO and copies contents to ISOdata
  6. CleanupUUPDump    -> removes temporary files

[DEMO] Showing call syntax and parameters only -- no live execution.
       Uncomment the blocks below to run the full pipeline after downloading.
"@
Write-Host $step09msg -ForegroundColor DarkGray

# --- DEMO ONLY: Commented out to avoid triggering a long-running conversion ---
# $extractResult = ExtractUUPDump -ZIPfile "$($appenv['Downloads'])\$($uupdump.zipname)" `
#                                  -Target  $appenv['UUPDumpDir'] `
#                                  -Verify  1 `
#                                  -Cleanup 1
# if ($extractResult.code -eq 0) { Write-Host "  [PASS] Extraction completed." -ForegroundColor DarkGreen }
# else { ThrowInternalError -ErrorMessage "Extraction failed: $($extractResult.msg)" -Color DarkRed -ExitCode -1 -Block }
#
# $isoName    = "Windows11-Pro-$($uupdump.osvers)-$($uupdump.osarch)-Build-$($uupdump.buildno).iso"
# $createResult = CreateUUPDiso -UUPDdir $appenv['UUPDumpDir'] -CleanUp 1 -ISOname $isoName
# if ($createResult.code -eq 0) { Write-Host "  [PASS] ISO created: $isoName" -ForegroundColor DarkGreen }
# else { ThrowInternalError -ErrorMessage "ISO creation failed: $($createResult.msg)" -Color DarkRed -ExitCode -1 -Block }
#
# $extractISOresult = ExtractUUPDiso -ISOfile "$($appenv['UUPDumpDir'])\$isoName" `
#                                     -Target  $appenv['ISOdata']
# if ($extractISOresult.code -eq 0) { Write-Host "  [PASS] ISO contents extracted." -ForegroundColor DarkGreen }
# else { ThrowInternalError -ErrorMessage "ISO extraction failed: $($extractISOresult.msg)" -Color DarkRed -ExitCode -1 -Block }
# --- END DEMO ONLY ---

Write-Host "  [DEMO] See inline comments to enable the full ISO pipeline." -ForegroundColor DarkYellow

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 10 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 10 -- MOUNTING AND UNMOUNTING WIM IMAGES
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 10 -- Mounting and Unmounting WIM Images"

$step10msg = @"
Once you have extracted the ISO contents to ISOdata, the install.wim file
(located at ISOdata\sources\install.wim) can be mounted to a local directory
using DISM. WinISO.ScriptFXLib provides two dedicated functions:

  ImageIndexLookup  -- Resolves a human-readable edition name to the integer
                      image index required by MountWIMimage.
                      Example: ImageIndexLookup -Name 'Professional' -> 6

  MountWIMimage     -- Mounts the specified WIM image index to MountPoint using
                      DISM /Mount-Image. Performs post-mount verification and
                      auto-dismounts on failure (defensive error handling).
                      Parameters:
                        -WIMfile   : path to install.wim (defaults to appenv['installwim'])
                        -ImageIndex: integer index returned by ImageIndexLookup
                        -MountDir  : mount directory    (defaults to appenv['MountPoint'])

  UnMountWIMimage   -- Dismounts the currently mounted WIM image.
                      Parameters:
                        -MountDir  : the mount directory that was used for mounting
                        -Action    : 'commit'  -> save changes back into the WIM
                                     'discard' -> discard all changes (default)
                      Always performs pre- and post-dismount verification.

Typical WIM workflow:
  1. ImageIndexLookup  -> find the correct index
  2. MountWIMimage     -> mount it
  3. (make changes to the mounted image)
  4. UnMountWIMimage   -> commit or discard, then unmount

[DEMO] Showing call syntax and parameters -- live mount requires admin rights
       and a valid install.wim in $($appenv['installwim']).

Example (uncomment to run):
  `$idx = ImageIndexLookup -Name 'Professional'
  if (`$idx -gt 0) {
      `$mountResult = MountWIMimage -ImageIndex `$idx
      if (`$mountResult.code -eq 0) {
          Write-Host "WIM mounted at $($appenv.MountPoint)"
      }
  }
"@
Write-Host $step10msg -ForegroundColor DarkGray

# --- DEMO ONLY ---
# $idx = ImageIndexLookup -Name 'Professional'
# if ($idx -gt 0) {
#     $mountResult = MountWIMimage -ImageIndex $idx
#     PrintResult -Label "MountWIMimage (Professional)" -Result $mountResult -SuccessText "Mounted at $($appenv['MountPoint'])"
# }
# --- END DEMO ONLY ---

Write-Host "  [DEMO] Mount/unmount skipped. See inline comments to enable." -ForegroundColor DarkYellow

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 11 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 11 -- OFFLINE REGISTRY HIVE OPERATIONS
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 11 -- Offline Registry Hive Operations"

$step11msg = @"
After mounting the WIM image, you can load its offline registry hives into
the live registry, modify them, export/import keys, and then unload them
before unmounting the image.

Available registry hives and their source locations inside the mount point:
  SOFTWARE  -> Windows\System32\config\SOFTWARE
  SYSTEM    -> Windows\System32\config\SYSTEM
  DEFAULT   -> Windows\System32\config\DEFAULT
  NTUSER    -> Users\Default\NTUSER.DAT

All hives are mounted under the HKLM\WinISO_&lt;HiveName&gt; prefix to avoid
collisions with system hives.

IMPORTANT: Always call UnloadRegistryHive BEFORE UnMountWIMimage to prevent
           open registry handles that would block the WIM dismount.

Function overview:

  LoadRegistryHive   -- Loads one or all hives. -HiveID 'ALL' loads all four.
                       Tracks each loaded hive in `$script:LoadedHives via WinISOcore.

  UnloadRegistryHive -- Unloads one or all hives. Flushes the live registry first.

  RegistryHiveAdd    -- Adds a key and/or value to a loaded hive.
                       Supported types: REG_SZ, REG_DWORD, REG_QWORD,
                       REG_EXPAND_SZ, REG_BINARY, REG_MULTI_SZ

  RegistryHiveRem    -- Removes a key and/or value. Use -RemoveKey to delete the
                       entire key tree.

  RegistryHiveQuery  -- Queries keys/values from a loaded hive. Returns structured
                       PSCustomObject entries per value.

  RegistryHiveExport -- Exports a registry branch to a .reg file.

  RegistryHiveImport -- Imports a validated .reg file into a loaded hive.

Example (requires a mounted WIM image -- see Step 10):

  # Load SOFTWARE hive only
  `$lr = LoadRegistryHive -HiveID 'SOFTWARE'
  `$lr.data | Format-Table HiveName, Status, RegMountKey -AutoSize

  # Add a DWORD value under HKLM:\WinISO_SOFTWARE\...
  RegistryHiveAdd -HiveID 'SOFTWARE' ``
                  -RegKey 'Microsoft\Windows NT\CurrentVersion' ``
                  -ValueName 'DemoValue' -ValueType 'REG_DWORD' -ValueData '1'

  # Query the value back
  RegistryHiveQuery -HiveID 'SOFTWARE' ``
                    -RegKey 'Microsoft\Windows NT\CurrentVersion' ``
                    -ValueName 'DemoValue'

  # Always unload before dismounting!
  UnloadRegistryHive -HiveID 'ALL'

[DEMO] Registry operations skipped (require a mounted WIM image).
       See inline comments to enable.
"@
Write-Host $step11msg -ForegroundColor DarkGray

# Show current LoadedHives state (will be empty in this demo)
$loadedHives = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'read' -Unwrap
$hiveCount = if ($null -ne $loadedHives) { $loadedHives.Count } else { 0 }
Write-Host "  Currently tracked loaded hives: $hiveCount" -ForegroundColor DarkYellow

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 12 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 12 -- APPX PACKAGE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 12 -- Appx Package Management"

$step12msg = @"
WinISO.ScriptFXLib v1.00.05 introduces four new functions for managing
provisioned Appx packages inside a mounted WIM image:

  GetAppxPackages    -- Lists all provisioned Appx packages from the mounted WIM.
                       Results are stored in `$script:appx['listed'] as an array of
                       PSCustomObjects (DisplayName, PackageName, Version, ...).
                       Optional file export via -ExportFile and -Format (TXT|CSV|JSON).

  AppxPackageLookUp  -- Dual-mode lookup function:
                       IMAGE mode : substring search in `$script:appx['listed']
                                   (use -ForceRefresh to bypass the cache)
                       FILE mode  : checks if a package file exists in AppxBundle dir
                       Both modes can be combined in a single call.

  RemAppxPackages    -- Removes packages listed in `$script:appx['remove'] using
                       DISM /Remove-ProvisionedAppxPackage.
                       Self-cleaning: successfully removed entries are deleted from
                       `$script:appx['remove']. Only failed entries remain.
                       Use -ContinueOnError to process all entries despite failures.

  AddAppxPackages    -- Injects packages listed in `$script:appx['inject'] into the
                       mounted WIM using DISM /Add-ProvisionedAppxPackage.
                       Resolves package files from AppxBundle directory.
                       Self-cleaning and -ContinueOnError work identically to Remove.

Typical Appx workflow:
  1. GetAppxPackages        -> list and cache all current packages
  2. AppxPackageLookUp      -> find specific packages by name
  3. Populate `$script:appx['remove'] via WinISOcore writes
  4. RemAppxPackages        -> remove unwanted packages
  5. Populate `$script:appx['inject'] via WinISOcore writes
  6. AddAppxPackages        -> inject new packages

WinISOcore write example for populating the remove list:
  `$toRemove = @(
      [PSCustomObject]@{ PackageName = 'Microsoft.BingWeather'   },
      [PSCustomObject]@{ PackageName = 'Microsoft.WindowsMaps'   },
      [PSCustomObject]@{ PackageName = 'Microsoft.MicrosoftSolitaireCollection' }
  )
  WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' ``
             -VarKeyID 'remove' -SetNewVal `$toRemove

[DEMO] GetAppxPackages and AppxPackageLookUp both require a mounted WIM image.
       Showing current `$script:appx state and usage examples only.
"@
Write-Host $step12msg -ForegroundColor DarkGray

# Show current appx state
$appxState = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'read' -Unwrap
Write-Host "  Current `$script:appx state:" -ForegroundColor DarkGray
Write-Host "    appx['listed'] : $($appxState['listed'].Count) package(s)" -ForegroundColor DarkYellow
Write-Host "    appx['remove'] : $($appxState['remove'].Count) package(s)" -ForegroundColor DarkYellow
Write-Host "    appx['inject'] : $($appxState['inject'].Count) package(s)" -ForegroundColor DarkYellow

# Demonstrate writing to appx['remove'] via WinISOcore
Write-Host ""
Write-Host "  Demonstrating WinISOcore write to appx['remove'] ..." -ForegroundColor DarkGray
$demoRemoveList = @(
    [PSCustomObject]@{ PackageName = 'Microsoft.BingWeather'                  },
    [PSCustomObject]@{ PackageName = 'Microsoft.WindowsMaps'                  },
    [PSCustomObject]@{ PackageName = 'Microsoft.MicrosoftSolitaireCollection' }
)
$writeAppxResult = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
                               -VarKeyID 'remove' -SetNewVal $demoRemoveList

PrintResult -Label "WinISOcore WRITE (appx.remove)" -Result $writeAppxResult `
            -SuccessText "3 package name(s) written to appx['remove']."

# Confirm by re-reading
$appxState = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'read' -Unwrap
Write-Host "  Confirmed  ->  appx['remove'] now contains $($appxState['remove'].Count) entry(s):" -ForegroundColor DarkYellow
$appxState['remove'] | ForEach-Object { Write-Host "    - $($_.PackageName)" -ForegroundColor DarkGray }

# Reset demo data
$null = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' -VarKeyID 'remove' -SetNewVal $null
Write-Host "  (Demo data cleared from appx['remove'] after display)" -ForegroundColor DarkGray

WaitForEnter -Message "Press &lt;Enter&gt; to continue to Step 13 ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 13 -- ADVANCED WINISOCORE USAGE
# ═══════════════════════════════════════════════════════════════════════════════
PrintSectionHeader -Title "STEP 13 -- Advanced WinISOcore Usage"

$step13msg = @"
This final step summarises the full WinISOcore API with advanced usage patterns.

Read Operations:
  # Wrapped -- returns OPSreturn { .code, .msg, .data }
  `$r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'read'
  Write-Host `$r.data['ISOroot']                               # C:\WinISO

  # Unwrapped -- returns the hashtable directly (recommended for most cases)
  `$appenv = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'read' -Unwrap
  Write-Host `$appenv['MountPoint']                            # C:\WinISO\MountPoint

Write Operations (with type enforcement):
  # Update a string key in appenv
  WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' ``
             -VarKeyID 'MountPoint' -SetNewVal 'D:\WIMmount'

  # Write a check status into appverify
  WinISOcore -Scope 'env' -GlobalVar 'appverify' -Permission 'write' ``
             -VarKeyID 'checkoscdimg' -SetNewVal 'PASS'

  # Replace the result counters sub-hashtable
  WinISOcore -Scope 'env' -GlobalVar 'appverify' -Permission 'write' ``
             -VarKeyID 'result' -SetNewVal @{ pass=8; fail=0; info=2; warn=1 }

  # Replace the appx 'listed' array
  WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' ``
             -VarKeyID 'listed' -SetNewVal `$packageList

  # Add a LoadedHives entry (after successful LoadRegistryHive)
  WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'write' ``
             -VarKeyID 'SOFTWARE' -SetNewVal 'HKLM\WinISO_SOFTWARE'

  # Remove a LoadedHives entry (pass `$null)
  WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'write' ``
             -VarKeyID 'SOFTWARE' -SetNewVal `$null

Read-only variables (write access is denied by WinISOcore):
  appcore, exit / appexit

Type safety:
  WinISOcore enforces that the new value matches the existing key's type.
  If types differ, an implicit conversion is attempted. If that fails, the
  write is rejected and the original value remains unchanged -- you will receive
  a structured OPSreturn error with code -1 and a descriptive message.

OPSreturn return object:
  Every WinISO public function returns a PSCustomObject with three fields:
    .code  >> 0 = success | -1 = error
    .msg   >> human-readable description
    .data  >> function-specific result data (hashtable, array, path string, ...)

Always check .code before consuming .data -- this prevents null-reference
errors and makes error handling explicit and consistent throughout your script.
"@
Write-Host $step13msg -ForegroundColor DarkGray

# Live demonstration: round-trip read-write-read for uupdump
Write-Host "  Live round-trip demonstration on `$script:uupdump ..." -ForegroundColor DarkGray

$before = (WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap)['osvers']
Write-Host "  Before write  ->  uupdump.osvers = '$before'" -ForegroundColor DarkYellow

$null = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'write' `
                   -VarKeyID 'osvers' -SetNewVal '25H2'

$after = (WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap)['osvers']
Write-Host "  After  write  ->  uupdump.osvers = '$after'" -ForegroundColor DarkYellow

# Restore original value
$null = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'write' `
                   -VarKeyID 'osvers' -SetNewVal '24H2'
$restored = (WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap)['osvers']
Write-Host "  Restored      ->  uupdump.osvers = '$restored'" -ForegroundColor DarkYellow

WaitForEnter -Message "Press &lt;Enter&gt; to finish the demonstration ... " -Color DarkGray -Block


# ═══════════════════════════════════════════════════════════════════════════════
#  WRAP-UP
# ═══════════════════════════════════════════════════════════════════════════════
Clear-Host
$byeText = @"
*******************************************************************************
  Demo-003.ps1 completed successfully.

  You have seen all major capabilities of $($appinfo.AppName) v$($appinfo.AppVers).

  For the full developer reference, consult DEVGUIDE.md in the repository:
  https://github.com/praetoriani/PowerShell.Mods/tree/main/WinISO.ScriptFXLib

  Thank you for using $($appinfo.AppName)!
  -- $($appinfo.AppDevName)
*******************************************************************************
"@
Write-Host $byeText -ForegroundColor DarkGray

Exit 0
