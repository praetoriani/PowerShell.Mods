<#
.SYNOPSIS
    Demo-001 - Annotated walkthrough of VPDLX v1.01.00

.DESCRIPTION
    This script demonstrates the core capabilities of the VPDLX module
    (Virtual PowerShell Data-Logger eXtension) using the v1.01.00 class-based API.

    Topics covered:
        1.  Importing the module
        2.  Creating a Logfile instance
        3.  Writing entries: Write(), Print(), and shortcut methods
        4.  All 8 supported log levels
        5.  Reading entries: Read(), SoakUp(), FilterByLevel()
        6.  Guard helpers: IsEmpty(), HasEntries(), EntryCount()
        7.  Metadata inspection via GetDetails() / FileDetails
        8.  Working with multiple simultaneous Logfile instances
        9.  Accessing the module-level FileStorage
        10. Reset() - clearing a log while preserving metadata
        11. Destroy() - permanent removal from storage
        12. Error handling examples

    BUGFIXES applied in this version (06.04.2026):
        - Module path now uses $PSScriptRoot for reliable resolution regardless
          of the caller's working directory.
        - All Filter() calls updated to FilterByLevel() to match the corrected
          class method name. 'filter' is a reserved PowerShell keyword and
          cannot be used as a class method name.
        - Fixed operator-precedence issue in Section 12 (Destroy) where
          -join was applied to the entire Write-Host expression instead of
          only to the names array.

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.00
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Updated : 06.04.2026

    Run this script from any directory — the module path is resolved
    automatically via $PSScriptRoot:
        .\VPDLX\Examples\Demo-001.ps1
        & 'C:\full\path\to\VPDLX\Examples\Demo-001.ps1'
#>

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# Helper: print a section banner to the console
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
function Show-Banner {
    param([string] $Title)
    Write-Host ''
    Write-Host ('-' * 70) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('-' * 70) -ForegroundColor DarkCyan
}


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 1. Import the VPDLX module
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '1. Import the VPDLX module'

# $PSScriptRoot always points to the directory containing THIS script file,
# regardless of where PowerShell was started from. This makes the demo
# runnable from any working directory without path errors.
#
# Script location : VPDLX\Examples\Demo-001.ps1
# Module manifest : VPDLX\VPDLX.psd1  (one level up from Examples\)
$modulePath = Join-Path $PSScriptRoot '..\VPDLX.psd1'

if (-not (Test-Path $modulePath)) {
    Write-Error "Module manifest not found at: $modulePath"
    exit -1
}

Import-Module $modulePath -Force
Write-Host 'Module imported. Classes [Logfile], [FileDetails], [FileStorage] are now available.' -ForegroundColor Green


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 2. Create a Logfile instance
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '2. Create a Logfile instance'

# The constructor validates the name, creates a [FileDetails] companion, and
# registers the instance in the module-level [FileStorage] singleton.
$appLog = [Logfile]::new('ApplicationLog')

Write-Host "Created : $appLog" -ForegroundColor Green
Write-Host "Type    : $($appLog.GetType().FullName)" -ForegroundColor Green


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 3. Write single entries with Write()
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '3. Write() - single entries'

$appLog.Write('info',    'Application started successfully.')
$appLog.Write('debug',   'Configuration loaded from default path.')
$appLog.Write('warning', 'No custom configuration file found - using defaults.')
$appLog.Write('error',   'Primary database connection failed on attempt 1.')

Write-Host "Entries after Write() calls: $($appLog.EntryCount())" -ForegroundColor Yellow


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 4. All 8 log levels via shortcut methods
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '4. All 8 log levels via shortcut methods'

$appLog.Info('INFO    - general informational message.')
$appLog.Debug('DEBUG   - developer diagnostics.')
$appLog.Verbose('VERBOSE - detailed execution tracing.')
$appLog.Trace('TRACE   - fine-grained step-by-step trace.')
$appLog.Warning('WARNING - non-fatal unexpected condition.')
$appLog.Error('ERROR   - recoverable error.')
$appLog.Critical('CRITICAL - severe error, degraded functionality.')
$appLog.Fatal('FATAL   - unrecoverable error, process will terminate.')

Write-Host "Entries after shortcut calls: $($appLog.EntryCount())" -ForegroundColor Yellow


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 5. Batch write with Print()
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '5. Print() - batch write'

# All messages are pre-validated before any are written (transactional).
# A failure on any single message leaves the log unchanged.
$batchMessages = @(
    'Initialisation step 1 of 3 completed.',
    'Initialisation step 2 of 3 completed.',
    'Initialisation step 3 of 3 completed.'
)

$appLog.Print('info', $batchMessages)
Write-Host "Entries after Print() batch: $($appLog.EntryCount())" -ForegroundColor Yellow


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 6. Read entries
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '6. Read(), SoakUp(), FilterByLevel()'

# Read() - 1-based index; out-of-range values are clamped automatically.
Write-Host 'Read(1):' -ForegroundColor Cyan
Write-Host $appLog.Read(1)

Write-Host ''
Write-Host 'Read(999) - clamped to last entry:' -ForegroundColor Cyan
Write-Host $appLog.Read(999)

# SoakUp() - returns the entire log as string[].
Write-Host ''
Write-Host 'SoakUp() - first 5 lines:' -ForegroundColor Cyan
$allLines = $appLog.SoakUp()
$allLines | Select-Object -First 5 | ForEach-Object { Write-Host $_ }

# FilterByLevel() - returns only lines whose level tag matches.
# NOTE: The method is named FilterByLevel() (not Filter()) because 'filter'
# is a reserved keyword in PowerShell and cannot be used as a method name.
Write-Host ''
Write-Host 'FilterByLevel("error"):' -ForegroundColor Cyan
$errorLines = $appLog.FilterByLevel('error')
$errorLines | ForEach-Object { Write-Host $_ }

Write-Host ''
Write-Host 'FilterByLevel("fatal"):' -ForegroundColor Cyan
$fatalLines = $appLog.FilterByLevel('fatal')
$fatalLines | ForEach-Object { Write-Host $_ }


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 7. Guard helpers
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '7. IsEmpty(), HasEntries(), EntryCount()'

if ($appLog.HasEntries()) {
    Write-Host ("HasEntries() = true - entry count: " + $appLog.EntryCount()) -ForegroundColor Green
}

if (-not $appLog.IsEmpty()) {
    Write-Host 'IsEmpty() = false' -ForegroundColor Green
}


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 8. Inspect metadata with GetDetails()
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '8. Metadata via GetDetails()'

$details = $appLog.GetDetails()

Write-Host ("Created   : " + $details.GetCreated())         -ForegroundColor White
Write-Host ("Updated   : " + $details.GetUpdated())         -ForegroundColor White
Write-Host ("Last acc  : " + $details.GetLastAccessed())    -ForegroundColor White
Write-Host ("Acc type  : " + $details.GetLastAccessType())  -ForegroundColor White
Write-Host ("Entries   : " + $details.GetEntries())         -ForegroundColor White
Write-Host ("Axcount   : " + $details.GetAxcount())         -ForegroundColor White

Write-Host ''
Write-Host 'ToHashtable():' -ForegroundColor Cyan
$details.ToHashtable() | Format-List


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 9. Multiple simultaneous Logfile instances
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '9. Multiple simultaneous Logfile instances'

$authLog = [Logfile]::new('AuthLog')
$perfLog = [Logfile]::new('PerfLog')

$authLog.Info('User admin logged in.')
$authLog.Warning('Failed login attempt for user guest.')

$perfLog.Debug('CPU usage: 12 percent.')
$perfLog.Debug('Memory usage: 48 percent.')
$perfLog.Warning('Response time exceeded 500 ms threshold.')

Write-Host "ApplicationLog entries : $($appLog.EntryCount())" -ForegroundColor Yellow
Write-Host "AuthLog entries        : $($authLog.EntryCount())" -ForegroundColor Yellow
Write-Host "PerfLog entries        : $($perfLog.EntryCount())" -ForegroundColor Yellow


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 10. Access the FileStorage singleton
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '10. FileStorage via VPDLXcore'

$store = VPDLXcore -KeyID 'storage'

Write-Host ("Registered logfiles   : " + $store.Count())
Write-Host ("Registered names      : " + ($store.GetNames() -join ', '))

# Retrieve a specific log by name from the registry.
$retrieved = $store.Get('AuthLog')
Write-Host ("Retrieved AuthLog - entries: " + $retrieved.EntryCount())


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 11. Reset() - clear data while preserving creation time and axcount
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '11. Reset()'

$beforeReset   = $appLog.EntryCount()
$createdBefore = $appLog.GetDetails().GetCreated()
$axcountBefore = $appLog.GetDetails().GetAxcount()

$appLog.Reset()

Write-Host ("Entries before reset  : $beforeReset")                                    -ForegroundColor White
Write-Host ("Entries after reset   : " + $appLog.EntryCount())                         -ForegroundColor Green
Write-Host ("Created (preserved)   : $createdBefore")                                  -ForegroundColor White
Write-Host ("Axcount before reset  : $axcountBefore")                                  -ForegroundColor White
Write-Host ("Axcount after reset   : " + $appLog.GetDetails().GetAxcount())             -ForegroundColor Yellow
Write-Host ("Acc type after reset  : " + $appLog.GetDetails().GetLastAccessType())      -ForegroundColor Yellow


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 12. Destroy() - remove from registry, free memory
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '12. Destroy()'

# BUGFIX: The original code had an operator-precedence issue:
#   Write-Host ("text" + $store.GetNames() -join ', ') -ForegroundColor White
# The -join operator was applied to the entire Write-Host expression instead
# of only to the GetNames() array. Fixed by evaluating the join in a
# sub-expression first: ($store.GetNames() -join ', ')
Write-Host ("Registered before destroy: " + ($store.GetNames() -join ', ')) -ForegroundColor White

$appLog.Destroy()
$appLog = $null   # Always null the variable after Destroy()

$authLog.Destroy()
$authLog = $null

$perfLog.Destroy()
$perfLog = $null

Write-Host ("Registered after destroy : " + $store.Count() + " instance(s)") -ForegroundColor Green


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# 13. Error handling examples
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Show-Banner '13. Error handling'

# 13a - Invalid name (too short)
try {
    $bad = [Logfile]::new('AB')   # only 2 characters
} catch [System.ArgumentException] {
    Write-Host ("Caught (name too short) : " + $_.Exception.Message) -ForegroundColor Red
}

# 13b - Duplicate name
try {
    $dup1 = [Logfile]::new('DuplicateTest')
    $dup2 = [Logfile]::new('DuplicateTest')   # duplicate
} catch [System.InvalidOperationException] {
    Write-Host ("Caught (duplicate name) : " + $_.Exception.Message) -ForegroundColor Red
    $dup1.Destroy()
    $dup1 = $null
}

# 13c - Unknown log level
try {
    $tmp = [Logfile]::new('TempLog')
    $tmp.Write('notice', 'This level does not exist.')   # 'notice' is not valid
} catch [System.ArgumentException] {
    Write-Host ("Caught (unknown level)  : " + $_.Exception.Message) -ForegroundColor Red
    $tmp.Destroy()
    $tmp = $null
}

# 13d - Reading from an empty log
try {
    $empty = [Logfile]::new('EmptyLog')
    $empty.Read(1)
} catch [System.InvalidOperationException] {
    Write-Host ("Caught (empty log)      : " + $_.Exception.Message) -ForegroundColor Red
    $empty.Destroy()
    $empty = $null
}

# 13e - Call after Destroy()
try {
    $ghost = [Logfile]::new('GhostLog')
    $ghost.Destroy()
    $ghost.Info('This will throw.')
} catch [System.ObjectDisposedException] {
    Write-Host ("Caught (after destroy)  : " + $_.Exception.Message) -ForegroundColor Red
    $ghost = $null
}

# 13f - Message containing a newline (log-injection attempt)
try {
    $inj = [Logfile]::new('InjectionTest')
    $inj.Write('info', "Normal message`nFake entry injected")
} catch [System.ArgumentException] {
    Write-Host ("Caught (newline in msg) : " + $_.Exception.Message) -ForegroundColor Red
    $inj.Destroy()
    $inj = $null
}


# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# Done
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
Write-Host ''
Write-Host ('-' * 70) -ForegroundColor DarkGreen
Write-Host '  Demo-001 completed successfully.' -ForegroundColor Green
Write-Host ('-' * 70) -ForegroundColor DarkGreen
Write-Host ''
