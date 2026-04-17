<#
.SYNOPSIS
    Demo-001 - Interactive step-by-step walkthrough of VPDLX v1.01.02

.DESCRIPTION
    This script provides an interactive, guided demonstration of the VPDLX module
    (Virtual PowerShell Data-Logger eXtension) using both the v1.01.02 Public Wrapper
    API (recommended) and the underlying class-based API.

    The demo pauses at the end of each section and waits for the user to press <Enter>
    before continuing. This gives you time to read the console output and understand
    what happened in each step.

    Sections covered:
        01 - Module import
        02 - Creating a log file via VPDLXnewlogfile (Public Wrapper)
        03 - Checking log file existence via VPDLXislogfile
        04 - Writing entries via VPDLXwritelogfile (all 8 levels)
        05 - Batch writing via the Logfile class Print() method (advanced)
        06 - Reading a single line via VPDLXreadlogfile
        07 - Reading all entries via GetAllEntries() (class API)
        08 - Filtering by level via FilterByLevel() (class API)
        09 - Guard helpers: IsEmpty(), HasEntries(), EntryCount()
        10 - Metadata inspection via GetDetails()
        11 - Multiple simultaneous log files
        12 - FileStorage access via VPDLXcore
        13 - Export to disk via VPDLXexportlogfile (all 4 formats)
        14 - Reset() - clear entries while preserving metadata
        15 - Destroying log files via VPDLXdroplogfile
        16 - Error handling examples

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.02
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Updated : 06.04.2026

    Run this script from any directory - the module path is resolved automatically
    via $PSScriptRoot. The demo creates temporary export files in $env:TEMP during
    the export demonstration and cleans them up at the end.

    Usage:
        .\VPDLX\Examples\Demo-001.ps1
        & 'C:\full\path\to\VPDLX\Examples\Demo-001.ps1'
#>

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

<#
.SYNOPSIS
    Displays a formatted section banner in the console.

.PARAMETER Step
    The step number (e.g. '01', '02' etc.)

.PARAMETER Title
    The section title to display.
#>
function Show-DemoStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Step,

        [Parameter(Mandatory = $true)]
        [string] $Title
    )
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor DarkCyan
    Write-Host "  [ STEP $Step ]  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor DarkCyan
    Write-Host ''
}

<#
.SYNOPSIS
    Displays a prompt and waits until the user presses <Enter> before continuing.
    This function is adapted from the WinISO.ScriptFXLib demo pattern.

.PARAMETER Message
    The message to display while waiting. Defaults to a standard continue prompt.

.PARAMETER Color
    The foreground color of the prompt text. Defaults to DarkGray.

.PARAMETER Block
    If set, wraps the prompt with empty lines above and below for visual clarity.
#>
function WaitForEnter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string] $Message = 'Press <Enter> to continue ...',

        [Parameter(Mandatory = $false)]
        [ConsoleColor] $Color = [ConsoleColor]::DarkGray,

        [Parameter(Mandatory = $false)]
        [switch] $Block
    )

    if ($Block.IsPresent) { Write-Host '' }
    do {
        Write-Host $Message -NoNewline -ForegroundColor $Color
        $key = Read-Host
    } while ($key -ne '')
    if ($Block.IsPresent) { Write-Host '' }
}


# ==============================================================================
# DEMO START - Welcome screen
# ==============================================================================
Clear-Host

$welcomeText = @"
========================================================================
  VPDLX - Virtual PowerShell Data-Logger eXtension
  Interactive Demo  //  Version 1.01.02
========================================================================

  Welcome! This demonstration walks you through the key features of
  VPDLX step by step. At the end of each section, you will be asked
  to press <Enter> before the next section begins.

  This gives you time to read and understand the output at your own
  pace before moving on.

========================================================================
"@
Write-Host $welcomeText -ForegroundColor DarkGray
WaitForEnter -Message 'Press <Enter> to start the demonstration ...' -Color DarkGray -Block


# ==============================================================================
# STEP 01 - Import the VPDLX module
# ==============================================================================
Show-DemoStep -Step '01' -Title 'Import the VPDLX module'

Write-Host '  The module is imported using Import-Module and the path resolved via' -ForegroundColor Gray
Write-Host '  $PSScriptRoot, so this demo works from any working directory.' -ForegroundColor Gray
Write-Host ''

# $PSScriptRoot always points to the folder containing this script file,
# making the import path reliable regardless of where PowerShell was started.
# Script location : VPDLX\Examples\Demo-001.ps1
# Module manifest : VPDLX\VPDLX.psd1  (one directory up from Examples\)
$modulePath = Join-Path $PSScriptRoot '..\VPDLX.psd1'

if (-not (Test-Path $modulePath)) {
    Write-Host "  [ERROR] Module manifest not found at: $modulePath" -ForegroundColor Red
    Write-Host '  Please ensure the script is run from within the VPDLX\Examples\ folder.' -ForegroundColor Red
    exit -1
}

Import-Module $modulePath -Force

Write-Host '  [OK] Module imported successfully.' -ForegroundColor Green
Write-Host '  [OK] TypeAccelerators registered: [Logfile], [FileDetails], [FileStorage]' -ForegroundColor Green
Write-Host '  [OK] Public Wrapper functions exported and available in the current session.' -ForegroundColor Green

WaitForEnter -Block


# ==============================================================================
# STEP 02 - Create a new log file via VPDLXnewlogfile
# ==============================================================================
Show-DemoStep -Step '02' -Title 'Create a log file: VPDLXnewlogfile'

Write-Host '  VPDLXnewlogfile is the recommended way to create a new virtual log file.' -ForegroundColor Gray
Write-Host '  It validates the name, creates the instance, registers it in storage,' -ForegroundColor Gray
Write-Host '  and returns a standardised result object { code, msg, data }.' -ForegroundColor Gray
Write-Host ''

# Create the primary demo log via the Public Wrapper function.
# All wrapper functions return: PSCustomObject { code [int], msg [string], data [object] }
# code 0 = success, code -1 = failure
$r = VPDLXnewlogfile -Logfile 'DemoLog'

if ($r.code -eq 0) {
    Write-Host "  [OK] Log file created   : $($r.data)" -ForegroundColor Green
    Write-Host "  [OK] Result code        : $($r.code) (success)" -ForegroundColor Green
    Write-Host "  [OK] Result message     : $($r.msg)" -ForegroundColor Green
} else {
    Write-Host "  [FAILED] $($r.msg)" -ForegroundColor Red
    exit -1
}

WaitForEnter -Block


# ==============================================================================
# STEP 03 - Check log file existence via VPDLXislogfile
# ==============================================================================
Show-DemoStep -Step '03' -Title 'Check log file existence: VPDLXislogfile'

Write-Host '  VPDLXislogfile is the analog to the Contains() method on FileStorage.' -ForegroundColor Gray
Write-Host '  It returns a plain [bool] directly (no wrapper object).' -ForegroundColor Gray
Write-Host ''

# Check for an existing log file - should return $true
$existsDemo = VPDLXislogfile -Logfile 'DemoLog'
Write-Host "  VPDLXislogfile -Logfile 'DemoLog'    --> $existsDemo" -ForegroundColor Yellow

# Check for a non-existent log file - should return $false
$existsGhost = VPDLXislogfile -Logfile 'NonExistentLog'
Write-Host "  VPDLXislogfile -Logfile 'NonExistentLog' --> $existsGhost" -ForegroundColor Yellow

WaitForEnter -Block


# ==============================================================================
# STEP 04 - Write log entries via VPDLXwritelogfile
# ==============================================================================
Show-DemoStep -Step '04' -Title 'Write log entries: VPDLXwritelogfile'

Write-Host '  VPDLXwritelogfile appends a single formatted entry to the log file.' -ForegroundColor Gray
Write-Host '  It supports all 8 log levels and returns the new total entry count.' -ForegroundColor Gray
Write-Host '  The Level parameter supports tab-completion in the console and in editors.' -ForegroundColor Gray
Write-Host ''

# Write one entry per level to demonstrate all 8 supported levels.
# The Level values are case-insensitive: 'INFO', 'Info', 'info' all work.
$levels = @(
    @{ Level = 'info';     Message = 'Application started successfully.' },
    @{ Level = 'debug';    Message = 'Configuration loaded from default path.' },
    @{ Level = 'verbose';  Message = 'Entering function Initialize-DataStore.' },
    @{ Level = 'trace';    Message = 'Variable $count = 0 at checkpoint A.' },
    @{ Level = 'warning';  Message = 'Disk usage has exceeded 80 percent.' },
    @{ Level = 'error';    Message = 'HTTP request to api.example.com returned 503.' },
    @{ Level = 'critical'; Message = 'Primary database cluster is unreachable.' },
    @{ Level = 'fatal';    Message = 'Unrecoverable exception - process will terminate.' }
)

foreach ($entry in $levels) {
    $r = VPDLXwritelogfile -Logfile 'DemoLog' -Level $entry.Level -Message $entry.Message
    if ($r.code -eq 0) {
        Write-Host "  [OK] [$($entry.Level.ToUpper().PadRight(8))]  Entry written. Total entries: $($r.data)" -ForegroundColor Green
    } else {
        Write-Host "  [FAILED] Level: $($entry.Level) - $($r.msg)" -ForegroundColor Red
    }
}

WaitForEnter -Block


# ==============================================================================
# STEP 05 - Batch write via class API Print()
# ==============================================================================
Show-DemoStep -Step '05' -Title 'Batch write: Logfile.Print() (class API)'

Write-Host '  For batch writes, the underlying [Logfile] class exposes a Print() method.' -ForegroundColor Gray
Write-Host '  Print() pre-validates all messages before writing any of them.' -ForegroundColor Gray
Write-Host '  If any single message fails validation, the log remains unchanged (transactional).' -ForegroundColor Gray
Write-Host ''

# Retrieve the [Logfile] instance from FileStorage to access class methods directly.
# VPDLXcore provides controlled read-only access to module-scope variables.
$storage = (VPDLXcore -KeyID 'storage').data
$demoLogInstance = $storage.Get('DemoLog')

$batchMessages = @(
    'Batch item 1 - Service A initialised.',
    'Batch item 2 - Service B initialised.',
    'Batch item 3 - Service C initialised.'
)

$demoLogInstance.Print('info', $batchMessages)

Write-Host "  [OK] Batch of $($batchMessages.Count) messages written via Print()." -ForegroundColor Green
Write-Host "  [OK] Total entries now: $($demoLogInstance.EntryCount())" -ForegroundColor Green

WaitForEnter -Block


# ==============================================================================
# STEP 06 - Read a single line via VPDLXreadlogfile
# ==============================================================================
Show-DemoStep -Step '06' -Title 'Read a specific line: VPDLXreadlogfile'

Write-Host '  VPDLXreadlogfile reads one entry by 1-based line index.' -ForegroundColor Gray
Write-Host '  Out-of-range values are clamped automatically (no exception thrown).' -ForegroundColor Gray
Write-Host ''

# Read line 1 (first entry)
$r = VPDLXreadlogfile -Logfile 'DemoLog' -Line 1
Write-Host '  Read(1) - First entry:' -ForegroundColor Cyan
Write-Host "  $($r.data)" -ForegroundColor White
Write-Host ''

# Read line 5
$r = VPDLXreadlogfile -Logfile 'DemoLog' -Line 5
Write-Host '  Read(5) - Fifth entry:' -ForegroundColor Cyan
Write-Host "  $($r.data)" -ForegroundColor White
Write-Host ''

# Read line 999 - will be clamped to the last available entry
$r = VPDLXreadlogfile -Logfile 'DemoLog' -Line 999
Write-Host '  Read(999) - Clamped to last entry:' -ForegroundColor Cyan
Write-Host "  $($r.data)" -ForegroundColor White

WaitForEnter -Block


# ==============================================================================
# STEP 07 - Read all entries via GetAllEntries()
# ==============================================================================
Show-DemoStep -Step '07' -Title 'Read all entries: GetAllEntries() (class API)'

Write-Host '  GetAllEntries() returns the entire log as a string[] array.' -ForegroundColor Gray
Write-Host '  Here we display only the first 5 entries to keep the output concise.' -ForegroundColor Gray
Write-Host ''

# GetAllEntries() returns string[] - all entries in write order
$allEntries = $demoLogInstance.GetAllEntries()
Write-Host "  Total entries in log  : $($allEntries.Count)" -ForegroundColor Yellow
Write-Host ''
Write-Host '  First 5 entries:' -ForegroundColor Cyan
$allEntries | Select-Object -First 5 | ForEach-Object {
    Write-Host "  $_" -ForegroundColor White
}

WaitForEnter -Block


# ==============================================================================
# STEP 08 - Filter by level via FilterByLevel()
# ==============================================================================
Show-DemoStep -Step '08' -Title 'Filter by level: FilterByLevel() (class API)'

Write-Host '  FilterByLevel() returns only entries matching a specific log level.' -ForegroundColor Gray
Write-Host '  Note: the method is named FilterByLevel() because "filter" is a reserved' -ForegroundColor Gray
Write-Host '  PowerShell keyword and cannot be used as a class method name.' -ForegroundColor Gray
Write-Host ''

# Filter for 'error' entries
$errorEntries = $demoLogInstance.FilterByLevel('error')
Write-Host '  FilterByLevel("error"):' -ForegroundColor Cyan
if ($errorEntries.Count -gt 0) {
    $errorEntries | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
} else {
    Write-Host '  (no entries found for this level)' -ForegroundColor DarkGray
}
Write-Host ''

# Filter for 'fatal' entries
$fatalEntries = $demoLogInstance.FilterByLevel('fatal')
Write-Host '  FilterByLevel("fatal"):' -ForegroundColor Cyan
if ($fatalEntries.Count -gt 0) {
    $fatalEntries | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
} else {
    Write-Host '  (no entries found for this level)' -ForegroundColor DarkGray
}
Write-Host ''

# Filter for 'info' entries
$infoEntries = $demoLogInstance.FilterByLevel('info')
Write-Host "  FilterByLevel(\"info\") - entry count: $($infoEntries.Count)" -ForegroundColor Cyan

WaitForEnter -Block


# ==============================================================================
# STEP 09 - Guard helpers: IsEmpty(), HasEntries(), EntryCount()
# ==============================================================================
Show-DemoStep -Step '09' -Title 'Guard helpers: IsEmpty(), HasEntries(), EntryCount()'

Write-Host '  These three methods let you safely check the state of a log' -ForegroundColor Gray
Write-Host '  before attempting to read from it.' -ForegroundColor Gray
Write-Host ''

Write-Host "  HasEntries()  --> $($demoLogInstance.HasEntries())" -ForegroundColor Yellow
Write-Host "  IsEmpty()     --> $($demoLogInstance.IsEmpty())" -ForegroundColor Yellow
Write-Host "  EntryCount()  --> $($demoLogInstance.EntryCount())" -ForegroundColor Yellow
Write-Host ''

# Demonstrate a typical guard pattern used before reading
if ($demoLogInstance.HasEntries()) {
    Write-Host '  Guard check passed - safe to read from DemoLog.' -ForegroundColor Green
}

WaitForEnter -Block


# ==============================================================================
# STEP 10 - Metadata inspection via GetDetails()
# ==============================================================================
Show-DemoStep -Step '10' -Title 'Metadata inspection: GetDetails() / FileDetails'

Write-Host '  Every Logfile instance has a [FileDetails] companion that tracks' -ForegroundColor Gray
Write-Host '  creation time, last update, last access type, and interaction count (axcount).' -ForegroundColor Gray
Write-Host ''

$details = $demoLogInstance.GetDetails()

Write-Host '  Individual getters:' -ForegroundColor Cyan
Write-Host "  Created          : $($details.GetCreated())" -ForegroundColor White
Write-Host "  Updated          : $($details.GetUpdated())" -ForegroundColor White
Write-Host "  Last accessed    : $($details.GetLastAccessed())" -ForegroundColor White
Write-Host "  Last access type : $($details.GetLastAccessType())" -ForegroundColor White
Write-Host "  Entry count      : $($details.GetEntries())" -ForegroundColor White
Write-Host "  Axcount          : $($details.GetAxcount())" -ForegroundColor White
Write-Host ''

Write-Host '  ToHashtable() output:' -ForegroundColor Cyan
$details.ToHashtable() | Format-List

WaitForEnter -Block


# ==============================================================================
# STEP 11 - Multiple simultaneous log files
# ==============================================================================
Show-DemoStep -Step '11' -Title 'Multiple simultaneous log files'

Write-Host '  VPDLX supports any number of named log file instances in parallel.' -ForegroundColor Gray
Write-Host '  Each instance is independent and lives in the shared FileStorage registry.' -ForegroundColor Gray
Write-Host ''

# Create two additional log files alongside the already existing DemoLog
$rAuth = VPDLXnewlogfile -Logfile 'AuthLog'
$rPerf = VPDLXnewlogfile -Logfile 'PerfLog'

Write-Host "  [OK] Created: $($rAuth.data)" -ForegroundColor Green
Write-Host "  [OK] Created: $($rPerf.data)" -ForegroundColor Green
Write-Host ''

# Write to each log independently
$authInstance = $storage.Get('AuthLog')
$authInstance.Info('User admin logged in successfully.')
$authInstance.Warning('Failed login attempt for user guest.')
$authInstance.Error('Account lockout triggered for user testuser.')

$perfInstance = $storage.Get('PerfLog')
$perfInstance.Debug('CPU usage: 12 percent.')
$perfInstance.Debug('Memory usage: 48 percent.')
$perfInstance.Warning('Response time exceeded 500 ms threshold.')

Write-Host '  Entry counts per log file:' -ForegroundColor Cyan
Write-Host "  DemoLog  : $($demoLogInstance.EntryCount()) entries" -ForegroundColor Yellow
Write-Host "  AuthLog  : $($authInstance.EntryCount()) entries" -ForegroundColor Yellow
Write-Host "  PerfLog  : $($perfInstance.EntryCount()) entries" -ForegroundColor Yellow

WaitForEnter -Block


# ==============================================================================
# STEP 12 - FileStorage access via VPDLXcore
# ==============================================================================
Show-DemoStep -Step '12' -Title 'FileStorage access: VPDLXcore'

Write-Host '  VPDLXcore provides controlled read-only access to module-scope variables.' -ForegroundColor Gray
Write-Host '  The FileStorage singleton tracks all registered Logfile instances.' -ForegroundColor Gray
Write-Host ''

$storeResult = VPDLXcore -KeyID 'storage'
$store = $storeResult.data

Write-Host "  Registered log files   : $($store.Count())" -ForegroundColor Yellow
Write-Host "  Registered names       : $($store.GetNames() -join ', ')" -ForegroundColor Yellow
Write-Host ''

# Retrieve a specific log file by name from the registry
$retrieved = $store.Get('AuthLog')
Write-Host "  store.Get('AuthLog') -> EntryCount: $($retrieved.EntryCount())" -ForegroundColor White
Write-Host ''

# Show module metadata
$metaResult = VPDLXcore -KeyID 'appinfo'
Write-Host '  Module metadata (appinfo):' -ForegroundColor Cyan
$metaResult.data | Format-List

WaitForEnter -Block


# ==============================================================================
# STEP 13 - Export to disk via VPDLXexportlogfile
# ==============================================================================
Show-DemoStep -Step '13' -Title 'Export to disk: VPDLXexportlogfile'

Write-Host '  VPDLXexportlogfile writes a virtual log file to a physical file on disk.' -ForegroundColor Gray
Write-Host '  It supports four formats: txt, log, csv, json.' -ForegroundColor Gray
Write-Host '  The target directory is created automatically if it does not exist.' -ForegroundColor Gray
Write-Host '  The -Override switch overwrites an existing file at the target path.' -ForegroundColor Gray
Write-Host ''

# Use $env:TEMP for the demo exports - no system pollution
$exportPath = Join-Path $env:TEMP 'VPDLX_Demo'

Write-Host "  Export target directory: $exportPath" -ForegroundColor Gray
Write-Host ''

# Export as TXT
$r = VPDLXexportlogfile -Logfile 'DemoLog' -LogPath $exportPath -ExportAs 'txt'
if ($r.code -eq 0) { Write-Host "  [OK] TXT  -> $($r.data)" -ForegroundColor Green }
else               { Write-Host "  [FAILED] TXT: $($r.msg)" -ForegroundColor Red }

# Export as LOG
$r = VPDLXexportlogfile -Logfile 'DemoLog' -LogPath $exportPath -ExportAs 'log'
if ($r.code -eq 0) { Write-Host "  [OK] LOG  -> $($r.data)" -ForegroundColor Green }
else               { Write-Host "  [FAILED] LOG: $($r.msg)" -ForegroundColor Red }

# Export as CSV
$r = VPDLXexportlogfile -Logfile 'DemoLog' -LogPath $exportPath -ExportAs 'csv'
if ($r.code -eq 0) { Write-Host "  [OK] CSV  -> $($r.data)" -ForegroundColor Green }
else               { Write-Host "  [FAILED] CSV: $($r.msg)" -ForegroundColor Red }

# Export as JSON
$r = VPDLXexportlogfile -Logfile 'DemoLog' -LogPath $exportPath -ExportAs 'json'
if ($r.code -eq 0) { Write-Host "  [OK] JSON -> $($r.data)" -ForegroundColor Green }
else               { Write-Host "  [FAILED] JSON: $($r.msg)" -ForegroundColor Red }

Write-Host ''
Write-Host '  Exporting AuthLog as CSV with -Override to demonstrate overwrite behaviour:' -ForegroundColor Gray
$r = VPDLXexportlogfile -Logfile 'AuthLog' -LogPath $exportPath -ExportAs 'csv'
if ($r.code -eq 0) { Write-Host "  [OK] CSV  -> $($r.data)" -ForegroundColor Green }

# Show that -Override allows overwriting an existing file
$r = VPDLXexportlogfile -Logfile 'AuthLog' -LogPath $exportPath -ExportAs 'csv' -Override
if ($r.code -eq 0) { Write-Host "  [OK] CSV  -> $($r.data) (overwritten with -Override)" -ForegroundColor Green }

WaitForEnter -Block


# ==============================================================================
# STEP 14 - Reset() - clear entries while preserving metadata
# ==============================================================================
Show-DemoStep -Step '14' -Title 'Reset entries: Logfile.Reset() (class API)'

Write-Host '  Reset() clears all log entries from memory.' -ForegroundColor Gray
Write-Host '  The creation timestamp and the axcount are preserved - only _data is cleared.' -ForegroundColor Gray
Write-Host ''

$beforeCount   = $demoLogInstance.EntryCount()
$createdBefore = $demoLogInstance.GetDetails().GetCreated()
$axBefore      = $demoLogInstance.GetDetails().GetAxcount()

$demoLogInstance.Reset()

Write-Host "  Entries before Reset() : $beforeCount" -ForegroundColor White
Write-Host "  Entries after  Reset() : $($demoLogInstance.EntryCount())" -ForegroundColor Green
Write-Host "  Created (preserved)    : $createdBefore" -ForegroundColor White
Write-Host "  Axcount before Reset() : $axBefore" -ForegroundColor White
Write-Host "  Axcount after  Reset() : $($demoLogInstance.GetDetails().GetAxcount())" -ForegroundColor Yellow
Write-Host "  Last access type       : $($demoLogInstance.GetDetails().GetLastAccessType())" -ForegroundColor Yellow

WaitForEnter -Block


# ==============================================================================
# STEP 15 - Destroy log files via VPDLXdroplogfile
# ==============================================================================
Show-DemoStep -Step '15' -Title 'Destroy log files: VPDLXdroplogfile'

Write-Host '  VPDLXdroplogfile permanently removes a log file from storage.' -ForegroundColor Gray
Write-Host '  This action is irreversible - the instance and all its data are freed.' -ForegroundColor Gray
Write-Host ''

Write-Host "  Registered before cleanup: $($store.GetNames() -join ', ')" -ForegroundColor White
Write-Host ''

# Drop all three demo log files via the Public Wrapper
foreach ($logName in @('DemoLog', 'AuthLog', 'PerfLog')) {
    $r = VPDLXdroplogfile -Logfile $logName
    if ($r.code -eq 0) {
        Write-Host "  [OK] Dropped: $($r.data)" -ForegroundColor Green
    } else {
        Write-Host "  [FAILED] $logName - $($r.msg)" -ForegroundColor Red
    }
}

# Clear local references - always null variables after dropping
$demoLogInstance = $null
$authInstance    = $null
$perfInstance    = $null

Write-Host ''
Write-Host "  Registered after cleanup : $($store.Count()) instance(s)" -ForegroundColor Green

WaitForEnter -Block


# ==============================================================================
# STEP 16 - Error handling examples
# ==============================================================================
Show-DemoStep -Step '16' -Title 'Error handling examples'

Write-Host '  VPDLX throws typed exceptions for all invalid operations.' -ForegroundColor Gray
Write-Host '  The examples below demonstrate each error category.' -ForegroundColor Gray
Write-Host ''

# 16a - Invalid name (too short - minimum is 3 characters)
Write-Host '  [16a] Invalid name (too short):' -ForegroundColor Cyan
try {
    $bad = [Logfile]::new('AB')   # only 2 characters - must be >= 3
} catch [System.ArgumentException] {
    Write-Host "  Caught ArgumentException: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''

# 16b - Duplicate name (case-insensitive uniqueness is enforced)
Write-Host '  [16b] Duplicate name:' -ForegroundColor Cyan
try {
    $dup1 = [Logfile]::new('DuplicateTest')
    $dup2 = [Logfile]::new('DuplicateTest')   # same name - not allowed
} catch [System.InvalidOperationException] {
    Write-Host "  Caught InvalidOperationException: $($_.Exception.Message)" -ForegroundColor Red
    $dup1.Destroy()
    $dup1 = $null
}
Write-Host ''

# 16c - Unknown log level
Write-Host '  [16c] Unknown log level:' -ForegroundColor Cyan
try {
    $tmp = [Logfile]::new('TempLog')
    $tmp.Write('notice', 'This level does not exist.')   # 'notice' is not a valid level
} catch [System.ArgumentException] {
    Write-Host "  Caught ArgumentException: $($_.Exception.Message)" -ForegroundColor Red
    $tmp.Destroy()
    $tmp = $null
}
Write-Host ''

# 16d - Reading from an empty log
Write-Host '  [16d] Reading from an empty log:' -ForegroundColor Cyan
try {
    $empty = [Logfile]::new('EmptyLog')
    $empty.Read(1)   # log has no entries - cannot read
} catch [System.InvalidOperationException] {
    Write-Host "  Caught InvalidOperationException: $($_.Exception.Message)" -ForegroundColor Red
    $empty.Destroy()
    $empty = $null
}
Write-Host ''

# 16e - Method call after Destroy()
Write-Host '  [16e] Call after Destroy():' -ForegroundColor Cyan
try {
    $ghost = [Logfile]::new('GhostLog')
    $ghost.Destroy()
    $ghost.Info('This will throw ObjectDisposedException.')   # instance is destroyed
} catch [System.ObjectDisposedException] {
    Write-Host "  Caught ObjectDisposedException: $($_.Exception.Message)" -ForegroundColor Red
    $ghost = $null
}
Write-Host ''

# 16f - Newline injection attempt in message
Write-Host '  [16f] Newline character in message (log injection guard):' -ForegroundColor Cyan
try {
    $inj = [Logfile]::new('InjectionTest')
    $inj.Write('info', "Legit message`nFake injected entry")   # newlines are forbidden
} catch [System.ArgumentException] {
    Write-Host "  Caught ArgumentException: $($_.Exception.Message)" -ForegroundColor Red
    $inj.Destroy()
    $inj = $null
}
Write-Host ''

# 16g - Wrapper function error path: log file does not exist
Write-Host '  [16g] Wrapper error path - log file not found:' -ForegroundColor Cyan
$rErr = VPDLXwritelogfile -Logfile 'DoesNotExist' -Level 'info' -Message 'This should fail.'
Write-Host "  Result code : $($rErr.code) (expected: -1)" -ForegroundColor Yellow
Write-Host "  Result msg  : $($rErr.msg)" -ForegroundColor Yellow

WaitForEnter -Block


# ==============================================================================
# CLEANUP - Remove temporary export files
# ==============================================================================
$exportPath = Join-Path $env:TEMP 'VPDLX_Demo'
if (Test-Path $exportPath) {
    Remove-Item -Path $exportPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '  [OK] Temporary export files cleaned up.' -ForegroundColor DarkGray
}


# ==============================================================================
# DONE
# ==============================================================================
Write-Host ''
Write-Host ('=' * 70) -ForegroundColor DarkGreen
Write-Host '  Demo-001 completed successfully.' -ForegroundColor Green
Write-Host '  All 16 steps walked through. Thank you for exploring VPDLX!' -ForegroundColor Green
Write-Host ('=' * 70) -ForegroundColor DarkGreen
Write-Host ''
