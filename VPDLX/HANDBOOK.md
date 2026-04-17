# VPDLX API Reference

**Virtual PowerShell Data-Logger eXtension** — Complete Function Reference and Developer Documentation

**Version:** 1.02.06  
**Author:** Praetoriani (M.Sczepanski)  
**Repository:** https://github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Core Concepts](#core-concepts)
4. [Standardized Return Values](#standardized-return-values)
5. [Log Levels](#log-levels)
6. [Log Format](#log-format)
7. [Public Functions](#public-functions)
8. [Export Formats](#export-formats)
9. [Class Architecture](#class-architecture)
10. [Error Handling](#error-handling)
11. [Best Practices](#best-practices)

---

## Overview

**VPDLX** (Virtual PowerShell Data-Logger eXtension) is a high-performance in-memory logging module for PowerShell. It stores log entries entirely in RAM, enabling lightning-fast write operations without disk I/O latency.

### Key Features

- **In-Memory Logging**: All data stored in `[Logfile]` instances in RAM
- **Structured Log Format**: Fixed format `[Timestamp] [Level] -> Message`
- **Multi-Format Export**: TXT, LOG, CSV, JSON, NDJSON, HTML
- **8 Log Levels**: info, debug, verbose, trace, warning, error, critical, fatal
- **Standardized API**: All functions return `[PSCustomObject]` with `.code`, `.msg`, `.data`
- **No Exceptions**: Error handling via return codes, no try/catch required
- **Filter Functions**: Filter log entries by level
- **UTF-8 Support**: BOM-free UTF-8 output for maximum compatibility

---

## Installation

```powershell
# Import the module
Import-Module .\VPDLX.psd1

# List available functions
Get-Command -Module VPDLX
```

---

## Core Concepts

### Virtual Log Files

A virtual log file is a **named object** in memory:

- **Name**: 3-64 characters, alphanumeric + `_`, `-`, `.`
- **Uniqueness**: Case-insensitive ("AppLog" = "applog")
- **Lifetime**: Session-bound (lost on module unload)
- **Storage**: `$script:storage` ([FileStorage] singleton)

### Naming Conventions

All public functions follow the **VPDLX prefix schema** (not Verb-Noun pattern):

```
VPDLX + <Verb> + logfile
```

Examples:
- `VPDLXnewlogfile` (create)
- `VPDLXislogfile` (check)
- `VPDLXwritelogfile` (write)

---

## Standardized Return Values

**All public functions** (except `VPDLXislogfile`) return a `[PSCustomObject]`:

```powershell
@{
    code = [int]     # 0 = Success, -1 = Error
    msg  = [string]  # Human-readable description
    data = [object]  # Payload data (success) or $null (error)
}
```

### Usage

```powershell
$result = VPDLXnewlogfile -Logfile 'AppLog'

if ($result.code -eq 0) {
    # Success
    $log = $result.data  # [Logfile] instance
    Write-Host $result.msg
} else {
    # Error
    Write-Warning $result.msg
}
```

**Advantage**: No try/catch blocks required, simple if/else pattern.

---

## Log Levels

VPDLX supports **8 log levels** (case-insensitive):

| Level | Description | Usage |
|-------|-------------|-------|
| `info` | Informational | Normal program flow |
| `debug` | Debug | Developer diagnostic info |
| `verbose` | Verbose | Detailed flow information |
| `trace` | Trace | Very detailed debug info |
| `warning` | Warning | Potential problems |
| `error` | Error | Error conditions |
| `critical` | Critical | Critical errors requiring immediate action |
| `fatal` | Fatal | Severe errors, program termination |

**Severity Order** (ascending):

```
trace < verbose < debug < info < warning < error < critical < fatal
```

---

## Log Format

Every log entry follows this **fixed format**:

```
[dd.MM.yyyy | HH:mm:ss] [LEVEL] -> Message
```

### Example

```
[17.04.2026 | 14:32:15] [INFO] -> Application started successfully
[17.04.2026 | 14:32:18] [WARNING] -> Disk space below 10%
[17.04.2026 | 14:32:22] [ERROR] -> Database connection failed
[17.04.2026 | 14:32:25] [FATAL] -> Unrecoverable error, shutting down
```

**Properties**:
- **Timestamp**: Exact time of the `Write()` call
- **Level**: Uppercase (INFO, WARNING, ERROR, ...)
- **Message**: User-defined, min. 3 characters, no newlines

---

## Public Functions

VPDLX exports **9 public functions** via `Export-ModuleMember`:

### Overview

| Function | Purpose | Return Type |
|----------|---------|-------------|
| [VPDLXnewlogfile](#vpdlxnewlogfile) | Create new log file | PSCustomObject |
| [VPDLXislogfile](#vpdlxislogfile) | Existence check | bool |
| [VPDLXdroplogfile](#vpdlxdroplogfile) | Delete log file | PSCustomObject |
| [VPDLXwritelogfile](#vpdlxwritelogfile) | Write entry | PSCustomObject |
| [VPDLXreadlogfile](#vpdlxreadlogfile) | Read entry | PSCustomObject |
| [VPDLXfilterlogfile](#vpdlxfilterlogfile) | Filter by level | PSCustomObject |
| [VPDLXexportlogfile](#vpdlxexportlogfile) | Export to file | PSCustomObject |
| [VPDLXresetlogfile](#vpdlxresetlogfile) | Clear all entries | PSCustomObject |
| [VPDLXgetalllogfiles](#vpdlxgetalllogfiles) | List all log files | PSCustomObject |

---

### VPDLXnewlogfile

**Creates a new virtual log file.**

#### Syntax

```powershell
VPDLXnewlogfile -Logfile <string>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Logfile` | `string` | Yes | Log file name (3-64 chars, alphanumeric + `_-.`) |

#### Return Value

```powershell
@{
    code = 0        # Success
    msg  = "..."
    data = [Logfile] # The new log file instance
}
# or
@{
    code = -1       # Error
    msg  = "..."
    data = $null
}
```

#### Errors

- **Name too short/long**: "must be between 3 and 64 characters"
- **Invalid characters**: "may only contain alphanumeric characters plus underscore, hyphen, and dot"
- **Duplicate**: "already exists in the current session"

#### Examples

```powershell
# Create new log file
$result = VPDLXnewlogfile -Logfile 'AppLog'

if ($result.code -eq 0) {
    $log = $result.data
    Write-Host "Log file created: $($log.Name)"
} else {
    Write-Warning $result.msg
}

# Error case: Duplicate
$r1 = VPDLXnewlogfile -Logfile 'MyLog'  # code 0
$r2 = VPDLXnewlogfile -Logfile 'MyLog'  # code -1, "already exists"
```

---

### VPDLXislogfile

**Checks whether a virtual log file exists.**

#### Syntax

```powershell
VPDLXislogfile -Logfile <string>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Logfile` | `string` | Yes | Name of the log file to check |

#### Return Value

**Type**: `bool`

- `$true`: Log file exists
- `$false`: Log file not found or name null/empty

**Special Note**: This function returns a direct `bool`, NOT a `[PSCustomObject]`.

#### Examples

```powershell
# Check existence before write access
if (VPDLXislogfile -Logfile 'AppLog') {
    $result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Ready'
} else {
    $result = VPDLXnewlogfile -Logfile 'AppLog'
}

# Guard pattern
if (-not (VPDLXislogfile 'DiagLog')) {
    VPDLXnewlogfile 'DiagLog'
}
```

---

### VPDLXdroplogfile

**Permanently deletes a virtual log file from memory.**

#### Syntax

```powershell
VPDLXdroplogfile -Logfile <string>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Logfile` | `string` | Yes | Name of the log file to delete |

#### Return Value

```powershell
@{
    code = 0
    msg  = "..."
    data = $null   # Always $null (deleted instance has no payload)
}
# or
@{
    code = -1
    msg  = "...
    data = $null
}
```

#### Warning

> **DESTRUCTIVE OPERATION**: This action is **irreversible**. All log data is permanently lost. Use `VPDLXexportlogfile` before calling if data preservation is needed.

#### Errors

- **Not found**: "does not exist in the current session"
- **Module not initialized**: Error accessing internal storage

#### Examples

```powershell
# Delete log file
$result = VPDLXdroplogfile -Logfile 'AppLog'

if ($result.code -eq 0) {
    Write-Host 'Log file deleted successfully'
} else {
    Write-Warning $result.msg
}

# Safe pattern: Check existence before delete
if (VPDLXislogfile -Logfile 'TempLog') {
    $result = VPDLXdroplogfile -Logfile 'TempLog'
}

# Error case: Log file doesn't exist
$result = VPDLXdroplogfile -Logfile 'Ghost'  # code -1
```

---

### VPDLXwritelogfile

**Writes a new entry to a virtual log file.**

#### Syntax

```powershell
VPDLXwritelogfile -Logfile <string> -Level <string> -Message <string>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Logfile` | `string` | Yes | Name of target log file |
| `Level` | `string` | Yes | Log level (info/debug/verbose/trace/warning/error/critical/fatal) |
| `Message` | `string` | Yes | Log message (min. 3 non-whitespace chars, no newlines) |

#### Parameter Details: Level

- **Validation**: `[ValidateSet]` at PowerShell binding layer (early rejection)
- **Case-insensitive**: `INFO`, `info`, `Info` are equivalent
- **Tab-Completion**: Fully supported in ISE and VS Code

**Valid values**: `info` | `debug` | `verbose` | `trace` | `warning` | `error` | `critical` | `fatal`

#### Parameter Details: Message

- Cannot be null, empty, or whitespace-only
- Must contain **at least 3 non-whitespace characters**
- Must **not contain newlines** (CR or LF) — prevents log injection

#### Return Value

```powershell
@{
    code = 0
    msg  = "..."
    data = [int]    # New total entry count
}
# or
@{
    code = -1
    msg  = "..."
    data = $null
}
```

#### Errors

- **Log file not found**: "does not exist in the current session"
- **Invalid level**: "Cannot validate argument on parameter 'Level'"
- **Message too short**: "must contain at least 3 non-whitespace characters"
- **Newline in message**: "must not contain newline characters"

#### Examples

```powershell
# Write simple entry
$result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Application started'

if ($result.code -eq 0) {
    Write-Host "Entry written. Total: $($result.data)"
}

# Different log levels
VPDLXwritelogfile -Logfile 'AppLog' -Level 'warning' -Message 'Disk space below 10%'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'error'   -Message 'Connection to DB failed'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'critical' -Message 'Service unavailable'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'fatal'   -Message 'Unrecoverable error'

# Error case: Invalid level (rejected at binding layer)
VPDLXwritelogfile -Logfile 'AppLog' -Level 'notice' -Message 'Test'
# Error: "Cannot validate argument on parameter 'Level'..."

# Error case: Message with newline
$result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message "Line1`nLine2"
# $result.code -> -1
```

---

### VPDLXreadlogfile

**Reads a single entry from a virtual log file.**

#### Syntax

```powershell
VPDLXreadlogfile -Logfile <string> -Line <int>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Logfile` | `string` | Yes | Name of log file |
| `Line` | `int` | Yes | 1-based line number |

#### Parameter Details: Line

- **1-based**: First line = 1
- **Auto-Clamping**: Values outside valid range are automatically clamped:
  - Value < 1 → becomes 1 (first entry)
  - Value > entry count → becomes last entry
- **No out-of-range error** for integer inputs

#### Return Value

```powershell
@{
    code = 0
    msg  = "...read line X of Y..."
    data = [string]    # The log entry (complete formatted string)
}
# or
@{
    code = -1
    msg  = "..."
    data = $null
}
```

#### Errors

- **Log file not found**: "does not exist"
- **Empty log file**: "contains no entries"

#### Examples

```powershell
# Read line 3
$result = VPDLXreadlogfile -Logfile 'AppLog' -Line 3

if ($result.code -eq 0) {
    Write-Host "Line 3: $($result.data)"
}

# Iterate all entries
$r = VPDLXgetalllogfiles
$log = ($r.data.Files | Where-Object { $_.Name -eq 'AppLog' })
$count = $log.EntryCount

for ($i = 1; $i -le $count; $i++) {
    $entry = VPDLXreadlogfile -Logfile 'AppLog' -Line $i
    Write-Host $entry.data
}

# Clamping in action: Log has 5 entries
$r = VPDLXreadlogfile -Logfile 'AppLog' -Line 0   # Reads entry #1
$r = VPDLXreadlogfile -Logfile 'AppLog' -Line 99  # Reads entry #5 (last)
```

---

### VPDLXfilterlogfile

**Filters log entries by a specific level.**

#### Syntax

```powershell
VPDLXfilterlogfile -Logfile <string> -Level <string>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Logfile` | `string` | Yes | Name of log file |
| `Level` | `string` | Yes | Level to filter by |

**Valid values for Level**: `info` | `debug` | `verbose` | `trace` | `warning` | `error` | `critical` | `fatal`

#### Return Value

```powershell
@{
    code = 0
    msg  = "..."
    data = [PSCustomObject]@{
        Entries = [string[]]    # Array of found entries
        Count   = [int]         # Number of matches
        Level   = [string]      # Filtered level
    }
}
# or
@{
    code = -1
    msg  = "..."
    data = $null
}
```

**Note**: With code 0, `data.Count` can also be 0 if no entries with the level were found.

#### Errors

- **Log file not found**: "does not exist"
- **Invalid level**: At binding layer (ValidateSet)

#### Examples

```powershell
# Filter all error entries
$result = VPDLXfilterlogfile -Logfile 'AppLog' -Level 'error'

if ($result.code -eq 0) {
    Write-Host "$($result.data.Count) error entries found:"
    $result.data.Entries | ForEach-Object { Write-Host $_ }
}

# Show only warnings
$r = VPDLXfilterlogfile -Logfile 'AppLog' -Level 'warning'
if ($r.code -eq 0 -and $r.data.Count -gt 0) {
    $r.data.Entries | ForEach-Object { Write-Host $_ }
}
```

---

### VPDLXexportlogfile

**Exports a virtual log file to a physical file on disk.**

#### Syntax

```powershell
VPDLXexportlogfile -Logfile <string> -LogPath <string> -ExportAs <string> [-Override] [-NoBOM]
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Logfile` | `string` | Yes | Name of log file |
| `LogPath` | `string` | Yes | Target directory (auto-created if missing) |
| `ExportAs` | `string` | Yes | Export format (txt/log/csv/json/html/ndjson) |
| `Override` | `switch` | No | Overwrite existing file |
| `NoBOM` | `switch` | No | Force UTF-8 without BOM (important for PS 5.1 + Unix tools) |

#### Parameter Details: ExportAs

| Value | Extension | Description |
|-------|-----------|-------------|
| `txt` | `.txt` | Plain text, one entry per line |
| `log` | `.log` | Identical to txt, different extension |
| `csv` | `.csv` | Comma-Separated Values with header |
| `json` | `.json` | JSON array wrapped in root object |
| `html` | `.html` | Complete HTML report with CSS styling (**NEW v1.02.06**) |
| `ndjson` | `.ndjson` | Newline-Delimited JSON (**NEW v1.02.06**) |

#### File Naming

Filename is derived from: `<Logfile-Name>.<Extension>`

```
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'csv'
-> C:\Logs\AppLog.csv
```

#### Export Formats in Detail

**CSV Format** (`csv`):
```csv
"Timestamp","Level","Message"
"17.04.2026 | 14:32:15","INFO","Application started"
```

**JSON Format** (`json`):
```json
{
  "LogFile": "AppLog",
  "ExportedAt": "17.04.2026 | 14:32:00",
  "EntryCount": 3,
  "Entries": [
    { "Timestamp": "17.04.2026 | 14:32:15", "Level": "INFO", "Message": "Application started" }
  ]
}
```

**NDJSON Format** (`ndjson`) — one JSON object per line:
```
{"Timestamp":"17.04.2026 | 14:32:15","Level":"INFO","Message":"Application started"}
{"Timestamp":"17.04.2026 | 14:32:18","Level":"WARNING","Message":"Disk space low"}
```

**HTML Format** (`html`) — Self-contained HTML report:
- Header with log name, export timestamp, and entry count
- Table with Timestamp/Level/Message columns
- Level-specific row coloring (Red=ERROR/FATAL, Orange=WARNING/CRITICAL, Green=INFO, Blue=DEBUG/VERBOSE/TRACE)
- Responsive layout, print-ready

#### -Override Behavior

| Situation | Without -Override | With -Override |
|-----------|-------------------|----------------|
| File doesn't exist | File is created | File is created |
| File exists | code -1 (error) | Old file deleted, new created |

#### -NoBOM Behavior

| PowerShell Version | Without -NoBOM | With -NoBOM |
|-------------------|----------------|-------------|
| Windows PS 5.1 | UTF-8 **with** BOM (EF BB BF) | UTF-8 without BOM |
| PowerShell 7.x | UTF-8 without BOM | UTF-8 without BOM (no difference) |

**Recommendation**: Always use `-NoBOM` when working with Unix tools, Filebeat, Fluentd, Grafana Loki, JSON parsers.

#### Return Value

```powershell
@{
    code = 0
    msg  = "..."
    data = [string]    # Full path to created file
}
# or
@{
    code = -1
    msg  = "..."
    data = $null
}
```

#### Errors

- **Unknown format**: "is not a supported export format"
- **Log file not found**: "does not exist"
- **Empty log file**: "contains no entries"
- **File exists + no -Override**: "already exists. Use -Override to overwrite"
- **Directory creation failed**: "Failed to create target directory"

#### Examples

```powershell
# Simple text export
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'txt'
if ($result.code -eq 0) {
    Write-Host "Exported to: $($result.data)"
}

# CSV export with auto-directory creation
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\NewDir\Sub' -ExportAs 'csv'

# JSON export with override and BOM-free
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json' -Override -NoBOM

# HTML report (v1.02.06)
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Reports' -ExportAs 'html'

# NDJSON for log streaming pipeline (v1.02.06)
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM
```

---

### VPDLXresetlogfile

**Clears all entries from a log file while keeping the log file itself.**

#### Syntax

```powershell
VPDLXresetlogfile -Logfile <string>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Logfile` | `string` | Yes | Name of log file to reset |

#### Difference to VPDLXdroplogfile

| Action | VPDLXresetlogfile | VPDLXdroplogfile |
|--------|-------------------|------------------|
| Entries deleted | Yes | Yes |
| Log file deleted | **No** (stays registered) | **Yes** (completely removed) |

#### Return Value

```powershell
@{
    code = 0
    msg  = "..."
    data = $null
}
# or
@{
    code = -1
    msg  = "..."
    data = $null
}
```

#### Errors

- **Log file not found**: "does not exist"

#### Examples

```powershell
# Reset log (delete entries, keep object)
$result = VPDLXresetlogfile -Logfile 'AppLog'

if ($result.code -eq 0) {
    Write-Host 'Log file reset'
    # Log still registered, ready for new entries
    VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'New session started'
}

# Pattern: Export log, then reset
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Archive' -ExportAs 'json'
VPDLXresetlogfile  -Logfile 'AppLog'
```

---

### VPDLXgetalllogfiles

**Returns an overview of all registered virtual log files.**

#### Syntax

```powershell
VPDLXgetalllogfiles
```

#### Parameters

None.

#### Return Value

```powershell
@{
    code = 0
    msg  = "..."
    data = [PSCustomObject]@{
        Count = [int]             # Number of registered log files
        Files = [PSCustomObject[]] # Array with info for each log file
        # Each Files object:
        # @{
        #     Name       = [string]
        #     EntryCount = [int]
        # }
    }
}
# or
@{
    code = -1
    msg  = "..."
    data = $null
}
```

**Note**: With code 0, `data.Count` can also be 0 if no log files are registered.

#### Errors

- Module not initialized: Error accessing internal storage

#### Examples

```powershell
# List all log files
$result = VPDLXgetalllogfiles

if ($result.code -eq 0) {
    Write-Host "$($result.data.Count) log files registered:"
    $result.data.Files | ForEach-Object {
        Write-Host "  - $($_.Name) ($($_.EntryCount) entries)"
    }
}

# Export all log files
$allLogs = VPDLXgetalllogfiles
if ($allLogs.code -eq 0) {
    $allLogs.data.Files | ForEach-Object {
        VPDLXexportlogfile -Logfile $_.Name -LogPath 'C:\Logs' -ExportAs 'json' -Override
    }
}
```

---

## Export Formats

VPDLX supports **6 export formats** via `VPDLXexportlogfile -ExportAs`:

### Format Comparison

| Format | Extension | Structure | Usage |
|--------|-----------|-----------|-------|
| **txt** | `.txt` | Plain text | Simple text viewing |
| **log** | `.log` | Plain text | Tools expecting .log files |
| **csv** | `.csv` | Structured, header row | Excel, SQL import, data analysis |
| **json** | `.json` | JSON array, root object | REST APIs, web apps, archiving |
| **ndjson** | `.ndjson` | JSON, 1 object per line | Filebeat, Fluentd, Logstash, Grafana Loki |
| **html** | `.html` | HTML table + CSS | Browser viewing, email, printing |

### When to Use Which Format?

- **txt/log**: Simple reading in text editors, grepping
- **csv**: Import to Excel, SQL databases, PowerBI
- **json**: REST APIs, long-term archiving, structured analysis
- **ndjson**: Log streaming pipelines (ELK Stack, Splunk, Grafana)
- **html**: Management reports, email attachments, browser display

---

## Class Architecture

VPDLX is based on **3 core classes** in `Classes/`:

### [Logfile]

**Main class** for virtual log files.

**Properties**:
- `Name` (string, read-only): Log file name
- `LogLevels` (Hashtable, static): Mapping of all 8 levels

**Methods**:
- `Write(level, message)`: Add entry
- `Read(line)`: Read 1-based entry (auto-clamping)
- `FilterByLevel(level)`: Filter entries by level
- `GetAllEntries()`: All entries as `string[]`
- `EntryCount()`: Number of entries
- `IsEmpty()`: Check if empty
- `Reset()`: Delete all entries
- `Destroy()`: Destroy instance (destructor pattern)

### [FileStorage]

**Singleton** for central log file management.

**Properties**:
- `_files` (Dictionary<string, Logfile>): Internal storage

**Methods**:
- `Add(logfile)`: Register log file
- `Get(name)`: Retrieve log file
- `Contains(name)`: Existence check
- `Remove(name)`: Deregister log file
- `GetAll()`: All log files as array
- `Count()`: Number of registered log files

**Module Usage**:
```powershell
$script:storage = [FileStorage]::new()  # Singleton in VPDLX.psm1
```

### [FileDetails]

**Metadata companion** for `[Logfile]`.

**Properties**:
- `Created` (DateTime): Creation time
- `LastUpdated` (DateTime): Last modification
- `LastAccessed` (DateTime): Last access
- `LastAccessType` (string): Type of last access (Write/Read/Filter)
- `AccessCount` (int): Total access count
- `EntryCount` (int): Entry count (redundant with Logfile._data.Count)

**Methods**:
- `RecordWrite()`: Log write access
- `RecordRead()`: Log read access
- `RecordFilter()`: Log filter access

---

## Error Handling

### No Exceptions!

VPDLX **never throws exceptions** in normal error situations. All errors are returned as `code -1`.

**Advantages**:
- No try/catch required
- Simple if/else pattern
- Predictable program flow

**Pattern**:
```powershell
$result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Test'

if ($result.code -ne 0) {
    Write-Warning "Log error: $($result.msg)"
    # Error handling
}
```

### Error Types

| Error Type | code | data | Example msg |
|------------|------|------|-------------|
| Not found | -1 | $null | "does not exist in the current session" |
| Duplicate | -1 | $null | "already exists" |
| Validation | -1 | $null | "must be between 3 and 64 characters" |
| Empty | -1 | $null | "contains no entries" |
| Module error | -1 | $null | "VPDLXcore did not return a valid..." |

---

## Best Practices

### 1. Always Check Return Values

```powershell
# ✓ GOOD
$result = VPDLXnewlogfile -Logfile 'AppLog'
if ($result.code -eq 0) {
    # Continue with $result.data
}

# ✗ BAD (ignores errors)
VPDLXnewlogfile -Logfile 'AppLog'
```

### 2. Existence Check Before Access

```powershell
# ✓ GOOD
if (-not (VPDLXislogfile 'AppLog')) {
    VPDLXnewlogfile 'AppLog'
}
VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Test'

# ✗ BAD (throws code -1 if doesn't exist)
VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Test'
```

### 3. Export Before Destroy/Reset

```powershell
# ✓ GOOD: Backup data
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Archive' -ExportAs 'json'
VPDLXdroplogfile -Logfile 'AppLog'

# ✗ BAD: Data irreversibly lost
VPDLXdroplogfile -Logfile 'AppLog'
```

### 4. Use -NoBOM with Unix Tools/Pipelines

```powershell
# ✓ GOOD: BOM-free for Filebeat/Fluentd
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM

# ✗ Problematic: PS 5.1 writes BOM, JSON parsers may fail
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json'
```

### 5. Structured Logging Pattern

```powershell
# ✓ Consistent structured logging
function Log-Action {
    param(
        [string]$Action,
        [string]$Level = 'info',
        [hashtable]$Data
    )
    
    $msg = "$Action | $($Data.Keys | ForEach-Object { "$_=$($Data[$_])" } | Join-String -Separator ' | ')"
    VPDLXwritelogfile -Logfile 'AppLog' -Level $Level -Message $msg
}

Log-Action -Action 'UserLogin' -Data @{ User='Admin'; IP='192.168.1.1' }
Log-Action -Action 'FileProcessed' -Data @{ File='data.csv'; Rows=1500 }
```

### 6. Log Rotation with Reset

```powershell
# Daily log export and reset
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
VPDLXexportlogfile -Logfile 'AppLog' -LogPath "C:\Logs\Archive\AppLog_$timestamp" -ExportAs 'json'
VPDLXresetlogfile -Logfile 'AppLog'
```

### 7. Export All Logs on Script Exit

```powershell
try {
    # Main script
    VPDLXnewlogfile 'AppLog'
    # ... Your logic ...
} finally {
    # Cleanup: Export all logs
    $allLogs = VPDLXgetalllogfiles
    if ($allLogs.code -eq 0) {
        $allLogs.data.Files | ForEach-Object {
            VPDLXexportlogfile -Logfile $_.Name -LogPath 'C:\Logs' -ExportAs 'json' -Override -NoBOM
        }
    }
}
```

---

## Complete Example

```powershell
# Load VPDLX module
Import-Module .\VPDLX.psd1

# Create log
$r = VPDLXnewlogfile -Logfile 'DeploymentLog'
if ($r.code -ne 0) {
    Write-Error "Could not create log: $($r.msg)"
    exit 1
}

# Write entries
VPDLXwritelogfile -Logfile 'DeploymentLog' -Level 'info'     -Message 'Deployment started'
VPDLXwritelogfile -Logfile 'DeploymentLog' -Level 'verbose' -Message 'Connecting to server'
VPDLXwritelogfile -Logfile 'DeploymentLog' -Level 'warning' -Message 'Server latency high'
VPDLXwritelogfile -Logfile 'DeploymentLog' -Level 'info'    -Message 'Files deployed successfully'

# Filter entries
$warnings = VPDLXfilterlogfile -Logfile 'DeploymentLog' -Level 'warning'
if ($warnings.code -eq 0 -and $warnings.data.Count -gt 0) {
    Write-Host "$($warnings.data.Count) warnings found"
}

# Export as HTML (for management report)
VPDLXexportlogfile -Logfile 'DeploymentLog' -LogPath 'C:\Reports' -ExportAs 'html'

# Export as NDJSON (for Grafana Loki)
VPDLXexportlogfile -Logfile 'DeploymentLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM

# Cleanup
VPDLXdroplogfile -Logfile 'DeploymentLog'
```

---

## Support & Contributing

**Repository**: https://github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX  
**Issues**: https://github.com/praetoriani/PowerShell.Mods/issues  
**Author**: Praetoriani (M.Sczepanski)

---

*Last updated: April 17, 2026 (v1.02.06)*
