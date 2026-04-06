<#
.SYNOPSIS
    VPDLX Demo Script 001 — Basic Usage

.DESCRIPTION
    Demonstrates the core functionality of the VPDLX module:
      - Creating multiple virtual log file instances
      - Writing log entries with various log levels
      - Reading entries by line number (including auto-clamp behaviour)
      - Inspecting module-scope state via VPDLXcore
      - Resetting a virtual log file
      - Deleting a virtual log file instance

.NOTES
    Module  : VPDLX — Virtual PowerShell Data-Logger eXtension
    Version : 1.00.00
    Author  : Praetoriani
    Date    : 2026-04-05

    Run this script after importing the VPDLX module:
        Import-Module '.\VPDLX\VPDLX.psd1'
        .\VPDLX\demo-001.ps1
#>

#Requires -Version 5.1

# ---------------------------------------------------------------------------
# Helper: print a section separator with a title
# ---------------------------------------------------------------------------
function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Helper: evaluate a VPDLX return object and print a formatted result line
# ---------------------------------------------------------------------------
function Show-Result {
    param(
        [string]$Label,
        [PSCustomObject]$Result
    )
    if ($Result.code -eq 0) {
        Write-Host "  [OK]  $Label" -ForegroundColor Green
        Write-Host "        msg  : $($Result.msg)" -ForegroundColor DarkGreen
        if ($null -ne $Result.data) {
            Write-Host "        data : $($Result.data)" -ForegroundColor DarkGreen
        }
    } else {
        Write-Host "  [ERR] $Label" -ForegroundColor Red
        Write-Host "        msg  : $($Result.msg)" -ForegroundColor DarkRed
    }
}

# ---------------------------------------------------------------------------
# Guard: make sure the VPDLX module is loaded
# ---------------------------------------------------------------------------
if (-not (Get-Module -Name 'VPDLX')) {
    Write-Host "[DEMO] VPDLX module not loaded — attempting import ..." -ForegroundColor Yellow
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'VPDLX.psd1'
    if (Test-Path $manifestPath) {
        Import-Module $manifestPath -Verbose:$false
    } else {
        Write-Error "VPDLX module not found. Please import it manually before running this demo."
        exit 1
    }
}

Write-Host ""
Write-Host "  VPDLX — Virtual PowerShell Data-Logger eXtension" -ForegroundColor White
Write-Host "  Demo Script 001 — Basic Usage" -ForegroundColor Gray
Write-Host "  Module version: $((Get-Module VPDLX).Version)" -ForegroundColor Gray

# ===========================================================================
# SECTION 1 — Create virtual log files
# ===========================================================================
Write-Section 'SECTION 1 — CreateNewLogfile'

$r = CreateNewLogfile -FileName 'SetupLog'
Show-Result -Label 'CreateNewLogfile -FileName SetupLog' -Result $r

$r = CreateNewLogfile -FileName 'ErrorLog'
Show-Result -Label 'CreateNewLogfile -FileName ErrorLog' -Result $r

$r = CreateNewLogfile -FileName 'AuditLog'
Show-Result -Label 'CreateNewLogfile -FileName AuditLog' -Result $r

# Attempt to create a duplicate — should fail with code -1
$r = CreateNewLogfile -FileName 'SetupLog'
Show-Result -Label 'CreateNewLogfile -FileName SetupLog (duplicate — expected failure)' -Result $r

# Attempt with an invalid filename — should fail with code -1
$r = CreateNewLogfile -FileName 'My Log!'
Show-Result -Label "CreateNewLogfile -FileName 'My Log!' (invalid name — expected failure)" -Result $r

# ===========================================================================
# SECTION 2 — Write log entries
# ===========================================================================
Write-Section 'SECTION 2 — WriteLogfileEntry'

$entries = @(
    @{ File = 'SetupLog'; Level = 'INFO';     Msg = 'Installation phase 1 started' },
    @{ File = 'SetupLog'; Level = 'DEBUG';    Msg = 'Verifying prerequisite conditions' },
    @{ File = 'SetupLog'; Level = 'VERBOSE';  Msg = 'Checking registry key HKLM\SOFTWARE\Demo' },
    @{ File = 'SetupLog'; Level = 'INFO';     Msg = 'Prerequisite check passed' },
    @{ File = 'SetupLog'; Level = 'WARNING';  Msg = 'Disk space below recommended threshold (4 GB free)' },
    @{ File = 'SetupLog'; Level = 'INFO';     Msg = 'Installation phase 1 completed' },
    @{ File = 'ErrorLog'; Level = 'ERROR';    Msg = 'Failed to connect to update server' },
    @{ File = 'ErrorLog'; Level = 'ERROR';    Msg = 'Retry attempt 1 of 3 failed' },
    @{ File = 'ErrorLog'; Level = 'CRITICAL'; Msg = 'All retry attempts exhausted — aborting update' },
    @{ File = 'AuditLog'; Level = 'INFO';     Msg = 'User confirmed installation of package Demo-1.0.0' },
    @{ File = 'AuditLog'; Level = 'INFO';     Msg = 'Elevation accepted by user at 23:01:15' },
    @{ File = 'AuditLog'; Level = 'TRACE';    Msg = 'Token validation: OK' }
)

foreach ($e in $entries) {
    $r = WriteLogfileEntry -FileName $e.File -LogLevel $e.Level -Message $e.Msg
    Show-Result -Label "WriteLogfileEntry -> $($e.File) [$($e.Level)]" -Result $r
}

# Attempt with an invalid log level — should fail
$r = WriteLogfileEntry -FileName 'SetupLog' -LogLevel 'NOTICE' -Message 'This level does not exist'
Show-Result -Label 'WriteLogfileEntry -LogLevel NOTICE (invalid level — expected failure)' -Result $r

# Attempt with a message that is too short — should fail
$r = WriteLogfileEntry -FileName 'SetupLog' -LogLevel 'INFO' -Message 'Hi'
Show-Result -Label "WriteLogfileEntry -Message 'Hi' (too short — expected failure)" -Result $r

# ===========================================================================
# SECTION 3 — Read entries
# ===========================================================================
Write-Section 'SECTION 3 — ReadLogfileEntry'

# Read line 1 from SetupLog (first entry)
$r = ReadLogfileEntry -FileName 'SetupLog' -Line 1
Show-Result -Label 'ReadLogfileEntry -FileName SetupLog -Line 1' -Result $r

# Read line 3 from SetupLog
$r = ReadLogfileEntry -FileName 'SetupLog' -Line 3
Show-Result -Label 'ReadLogfileEntry -FileName SetupLog -Line 3' -Result $r

# Read a line that exceeds entry count — auto-clamp to last entry
$r = ReadLogfileEntry -FileName 'ErrorLog' -Line 999
Show-Result -Label 'ReadLogfileEntry -FileName ErrorLog -Line 999 (auto-clamp to last)' -Result $r

# Read from AuditLog line 2
$r = ReadLogfileEntry -FileName 'AuditLog' -Line 2
Show-Result -Label 'ReadLogfileEntry -FileName AuditLog -Line 2' -Result $r

# Attempt to read from a non-existent log file
$r = ReadLogfileEntry -FileName 'GhostLog' -Line 1
Show-Result -Label 'ReadLogfileEntry -FileName GhostLog (not found — expected failure)' -Result $r

# ===========================================================================
# SECTION 4 — Inspect module-scope state via VPDLXcore
# ===========================================================================
Write-Section 'SECTION 4 — VPDLXcore (read access)'

# List all registered log file names
$r = VPDLXcore -Scope 'storage' -GlobalVar 'filestorage' -Permission 'read'
if ($r.code -eq 0) {
    Write-Host "  Registered log files in filestorage:" -ForegroundColor Green
    $r.data | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGreen }
}

# Show entry counts for each registered log file
$r2 = VPDLXcore -Scope 'instances' -GlobalVar 'loginstances' -Permission 'read'
if ($r2.code -eq 0) {
    Write-Host "" 
    Write-Host "  Entry counts per log file:" -ForegroundColor Green
    foreach ($key in $r2.data.Keys) {
        $inst = $r2.data[$key]
        Write-Host "    $($inst.name): $($inst.info.entries) entries  (created: $($inst.info.created))" -ForegroundColor DarkGreen
    }
}

# Show available log levels
$r3 = VPDLXcore -Scope 'loglevel' -GlobalVar 'loglevel' -Permission 'read'
if ($r3.code -eq 0) {
    Write-Host ""
    Write-Host "  Available log levels: $($r3.data -join ' | ')" -ForegroundColor Green
}

# ===========================================================================
# SECTION 5 — Reset a log file
# ===========================================================================
Write-Section 'SECTION 5 — ResetLogfile'

Write-Host "  SetupLog entry count before reset: " -NoNewline -ForegroundColor Gray
$ri = VPDLXcore -Scope 'instances' -GlobalVar 'loginstances' -Permission 'read'
Write-Host $ri.data['setuplog'].info.entries -ForegroundColor Yellow

$r = ResetLogfile -FileName 'SetupLog'
Show-Result -Label 'ResetLogfile -FileName SetupLog' -Result $r

Write-Host "  SetupLog entry count after reset:  " -NoNewline -ForegroundColor Gray
$ri2 = VPDLXcore -Scope 'instances' -GlobalVar 'loginstances' -Permission 'read'
Write-Host $ri2.data['setuplog'].info.entries -ForegroundColor Yellow

# Attempt to read from a reset (empty) log file
$r = ReadLogfileEntry -FileName 'SetupLog' -Line 1
Show-Result -Label 'ReadLogfileEntry after reset (empty — expected failure)' -Result $r

# Attempt to reset a non-existent log file
$r = ResetLogfile -FileName 'NoSuchFile'
Show-Result -Label 'ResetLogfile -FileName NoSuchFile (not found — expected failure)' -Result $r

# ===========================================================================
# SECTION 6 — Delete a log file instance
# ===========================================================================
Write-Section 'SECTION 6 — DeleteLogfile'

Write-Host "  Registered files before delete: $((VPDLXcore -Scope 'storage' -GlobalVar 'filestorage' -Permission 'read').data -join ', ')" -ForegroundColor Gray

$r = DeleteLogfile -FileName 'AuditLog'
Show-Result -Label 'DeleteLogfile -FileName AuditLog' -Result $r

Write-Host "  Registered files after delete:  $((VPDLXcore -Scope 'storage' -GlobalVar 'filestorage' -Permission 'read').data -join ', ')" -ForegroundColor Gray

# Attempt to delete an already-deleted file
$r = DeleteLogfile -FileName 'AuditLog'
Show-Result -Label 'DeleteLogfile -FileName AuditLog (already deleted — expected failure)' -Result $r

# Attempt to delete a file that never existed
$r = DeleteLogfile -FileName 'Phantom'
Show-Result -Label 'DeleteLogfile -FileName Phantom (not found — expected failure)' -Result $r

# ===========================================================================
# DONE
# ===========================================================================
Write-Section 'DEMO COMPLETE'
Write-Host "  All VPDLX v1.00.00 base functions demonstrated." -ForegroundColor White
Write-Host "  See README.md and QUICKSTART.md for full documentation." -ForegroundColor Gray
Write-Host ""
