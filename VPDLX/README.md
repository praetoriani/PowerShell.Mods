<div align="center">
  <img src="VPDLX.Logo.v1.svg" alt="VPDLX Logo" width="480" />
</div>

<br />

<div align="center">

![Version](https://img.shields.io/badge/Version-1.02.06-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)

</div>

---

**VPDLX** (Virtual PowerShell Data-Logger eXtension) is a PowerShell module that provides a fully class-based, **in-memory** virtual logging system. Instead of writing log entries to disk immediately, VPDLX keeps any number of named log instances alive in RAM for the duration of the current PowerShell session — enabling fast, structured, and flexible logging without immediate file-system I/O.

When you are ready to persist a log, the built-in export function writes it to disk in your choice of format with a single command.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Architecture](#architecture)
4. [Public Wrapper Functions](#public-wrapper-functions)
   - [VPDLXnewlogfile](#vpdlxnewlogfile)
   - [VPDLXislogfile](#vpdlxislogfile)
   - [VPDLXdroplogfile](#vpdlxdroplogfile)
   - [VPDLXreadlogfile](#vpdlxreadlogfile)
   - [VPDLXwritelogfile](#vpdlxwritelogfile)
   - [VPDLXexportlogfile](#vpdlxexportlogfile)
   - [VPDLXgetalllogfiles](#vpdlxgetalllogfiles)
   - [VPDLXresetlogfile](#vpdlxresetlogfile)
   - [VPDLXfilterlogfile](#vpdlxfilterlogfile)
5. [Class Reference](#class-reference)
   - [Logfile](#logfile)
   - [FileDetails](#filedetails)
   - [FileStorage](#filestorage)
6. [VPDLXcore](#vpdlxcore)
7. [Log Levels](#log-levels)
8. [Entry Format](#entry-format)
9. [Quick Examples](#quick-examples)
10. [Known Limitations](#known-limitations)

---

## Requirements

| Requirement | Value |
|---|---|
| PowerShell | 5.1 (Desktop) or 7.x (Core) |
| Compatible editions | `Desktop`, `Core` |
| External dependencies | None |
| Required privileges | Standard user (no elevation required) |
| Platform | Windows 10 / Windows 11 |

---

## Installation

Clone or copy the `VPDLX` folder to any location, then import the module:

```powershell
Import-Module .\VPDLX\VPDLX.psd1
```

After import:
- The three classes `[Logfile]`, `[FileDetails]`, and `[FileStorage]` are registered as **TypeAccelerators** and are immediately usable — no `using module` syntax required.
- All **Public Wrapper functions** (`VPDLXnewlogfile`, `VPDLXislogfile`, etc.) are exported and available in your session.

To unload the module and clean up all TypeAccelerators:

```powershell
Remove-Module VPDLX
```

---

## Architecture

```
VPDLX/
├── VPDLX.psm1              # Root module: class loading, TypeAccelerators, VPDLXcore
├── VPDLX.psd1              # Module manifest
├── VPDLX.Precheck.ps1      # Pre-import validation (PS version check)
├── CHANGELOG.md
├── QUICKSTART.md
├── README.md
├── VPDLX.Logo.v1.svg       # Module logo
│
├── Classes/
│   └── VPDLXClasses.ps1    # All three classes: FileDetails, FileStorage, Logfile
│
├── Private/
│   └── VPDLXreturn.ps1     # Standardised return-object factory { code, msg, data }
│
├── Public/
│   ├── VPDLXnewlogfile.ps1
│   ├── VPDLXislogfile.ps1
│   ├── VPDLXdroplogfile.ps1
│   ├── VPDLXreadlogfile.ps1
│   ├── VPDLXwritelogfile.ps1
│   ├── VPDLXexportlogfile.ps1
│   ├── VPDLXgetalllogfiles.ps1   # NEW v1.02.05
│   ├── VPDLXresetlogfile.ps1     # NEW v1.02.05
│   └── VPDLXfilterlogfile.ps1    # NEW v1.02.05
│
└── Examples/
    └── Demo-001.ps1        # Interactive step-by-step demonstration script
```

All three classes are defined in a single file (`VPDLXClasses.ps1`) in dependency order: `FileDetails` → `FileStorage` → `Logfile`. This resolves the PowerShell 5.1 forward-reference limitation and enables full type safety throughout.
Public wrapper functions are dot-sourced automatically from `Public\*.ps1` by the module loader.

---

## Public Wrapper Functions

The Public Wrapper Layer is the recommended way to interact with VPDLX. Each wrapper function follows a consistent defensive pipeline and always returns a standardised `[PSCustomObject]` with three properties:

| Property | Type | Description |
|---|---|---|
| `code` | `int` | `0` = success, `-1` = failure |
| `msg` | `string` | Human-readable status or error description |
| `data` | `object` | Return value on success; `$null` on failure |

> **Exception:** `VPDLXislogfile` returns a plain `[bool]` directly.

---

### VPDLXnewlogfile

Creates a new named virtual log file.

```powershell
VPDLXnewlogfile -Logfile <string>
```

| Parameter | Type | Mandatory | Description |
|---|---|---|---|
| `Logfile` | `string` | yes | Name of the new log file (3–64 chars; `a-z A-Z 0-9 _ - .`) |

**Returns:** `code 0` + new instance name in `.data` on success.

```powershell
$result = VPDLXnewlogfile -Logfile 'AppLog'
if ($result.code -eq 0) { Write-Host "Created: $($result.data)" }
```

---

### VPDLXislogfile

Checks whether a named log file currently exists in the module storage.

```powershell
VPDLXislogfile -Logfile <string>
```

**Returns:** `$true` if the log file exists, `$false` otherwise.

```powershell
if (VPDLXislogfile -Logfile 'AppLog') {
    Write-Host 'Log file exists.'
}
```

---

### VPDLXdroplogfile

Permanently destroys a virtual log file and removes it from storage. This action is **irreversible**.

```powershell
VPDLXdroplogfile -Logfile <string>
```

**Returns:** `code 0` + removed log file name in `.data` on success.

```powershell
$result = VPDLXdroplogfile -Logfile 'AppLog'
if ($result.code -eq 0) { Write-Host "Dropped: $($result.data)" }
```

---

### VPDLXreadlogfile

Reads a single entry from an existing log file by its 1-based line index.

```powershell
VPDLXreadlogfile -Logfile <string> -Line <int>
```

| Parameter | Type | Mandatory | Description |
|---|---|---|---|
| `Logfile` | `string` | yes | Name of the log file to read from |
| `Line` | `int` | yes | 1-based line index (auto-clamped to valid range) |

**Clamping behaviour:** values below `1` are treated as `1`; values above the total entry count are treated as the last entry. No range exception is ever thrown for integer inputs.

**Returns:** `code 0` + the log line as `string` in `.data` on success.

```powershell
$result = VPDLXreadlogfile -Logfile 'AppLog' -Line 3
if ($result.code -eq 0) { Write-Host $result.data }
```

---

### VPDLXwritelogfile

Appends a new formatted entry to an existing log file.

```powershell
VPDLXwritelogfile -Logfile <string> -Level <string> -Message <string>
```

| Parameter | Type | Mandatory | Description |
|---|---|---|---|
| `Logfile` | `string` | yes | Name of the log file to write to |
| `Level` | `string` | yes | Log level — see [Log Levels](#log-levels) for valid values |
| `Message` | `string` | yes | Log message (min. 3 non-whitespace chars; no newlines) |

**Returns:** `code 0` + new total entry count as `int` in `.data` on success.

```powershell
$result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Service started.'
if ($result.code -eq 0) { Write-Host "Total entries: $($result.data)" }
```

> The `Level` parameter supports **tab-completion** in the console and in editors.

---

### VPDLXexportlogfile

Exports a virtual log file to a physical file on disk. This is the primary way to persist in-memory log data.

```powershell
VPDLXexportlogfile -Logfile <string> -LogPath <string> -ExportAs <string> [-Override] [-NoBOM]
```

| Parameter | Type | Mandatory | Description |
|---|---|---|---|
| `Logfile` | `string` | yes | Name of the virtual log file to export |
| `LogPath` | `string` | yes | Full path to the target directory (created automatically if it does not exist) |
| `ExportAs` | `string` | yes | Target format: `txt` \| `csv` \| `json` \| `log` \| `html` \| `ndjson` |
| `Override` | `switch` | no | When set, overwrites an existing file at the target path |
| `NoBOM` | `switch` | no | Forces BOM-free UTF-8 output (important for Unix tools, JSON parsers, and log aggregators; see below) |

**Supported formats:**

| Value | Extension | Output |
|---|---|---|
| `txt` | `.txt` | Plain text — each log line written as-is |
| `log` | `.log` | Same as `txt`, with `.log` extension |
| `csv` | `.csv` | RFC 4180-compliant with header `"Timestamp","Level","Message"` |
| `json` | `.json` | JSON object `{ LogFile, ExportedAt, EntryCount, Entries[] }` |
| `html` | `.html` | Self-contained HTML document with embedded CSS, level-coloured rows (v1.02.06) |
| `ndjson` | `.ndjson` | Newline-Delimited JSON — one compact JSON object per line (v1.02.06) |

**Output file naming:** `<LogPath>\<Logfile><extension>` — e.g. `C:\Logs\AppLog.csv`

**Returns:** `code 0` + full path to the created file as `string` in `.data` on success.

```powershell
# Export as CSV — creates directory if missing
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'csv'
if ($result.code -eq 0) { Write-Host "Saved to: $($result.data)" }

# Export as JSON and overwrite if file exists
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json' -Override

# Export with BOM-free UTF-8 (recommended for Unix tools and log aggregators)
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json' -NoBOM

# Export as HTML — opens in any browser (v1.02.06)
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'html'
if ($result.code -eq 0) { Start-Process $result.data }

# Export as NDJSON — one JSON object per line, ideal for log pipelines (v1.02.06)
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM
```

> **Encoding note:** By default, Windows PowerShell 5.1 writes a UTF-8 BOM (Byte Order Mark) at the start of exported files. The `-NoBOM` switch suppresses this 3-byte prefix, ensuring clean interoperability with Unix-based log aggregators (Filebeat, Fluentd), JSON parsers, and web APIs. On PowerShell 7.x, `-NoBOM` is a no-op (PS 7 is BOM-free by default), but using it makes the encoding intent explicit across PS editions.

> **HTML export note (v1.02.06):** The HTML format generates a self-contained document with embedded CSS. Log entries are displayed in a styled table with level-specific row colouring (green for INFO, blue for DEBUG, orange background for WARNING, red background for ERROR/CRITICAL/FATAL). All message content is HTML-encoded for XSS safety. The document is print-friendly.

> **NDJSON export note (v1.02.06):** NDJSON (Newline-Delimited JSON) writes one compact JSON object per line — no root wrapper or array. This format is the standard for streaming log data into Elasticsearch, Logstash, Kafka, AWS Kinesis, and Grafana Loki. Each line is independently parseable, making it ideal for `jq` processing: `cat log.ndjson | jq .Level`.

---

### VPDLXgetalllogfiles

Lists all active virtual log files with their metadata. No parameters required.

```powershell
VPDLXgetalllogfiles
```

**Returns:** `code 0` + `[PSCustomObject[]]` in `.data` with one entry per log file.

Each entry contains:

| Property       | Type     | Description                                   |
|----------------|----------|-----------------------------------------------|
| `Name`         | `string` | Log file name (case-preserved)                |
| `EntryCount`   | `int`    | Current number of stored entries               |
| `Created`      | `string` | Creation timestamp                            |
| `Updated`      | `string` | Last write/reset timestamp                    |
| `LastAccessed` | `string` | Last read/filter timestamp                    |
| `AccessCount`  | `int`    | Total interaction count since creation        |

```powershell
# List all logs as a table
$result = VPDLXgetalllogfiles
if ($result.code -eq 0) {
    $result.data | Format-Table -AutoSize
}

# Find the log with the most entries
$largest = $result.data | Sort-Object -Property EntryCount -Descending | Select-Object -First 1
Write-Host "Largest: $($largest.Name) with $($largest.EntryCount) entries"
```

> **Note:** This is a read-only operation. It does **not** increment `axcount` or update `lastacc` on any log file.

---

### VPDLXresetlogfile

Clears all entries from a virtual log file without destroying it. The log file
remains registered and can immediately accept new entries.

```powershell
VPDLXresetlogfile -Logfile <string>
```

| Parameter   | Type     | Required | Description                        |
|-------------|----------|----------|------------------------------------|
| `-Logfile`  | `string` | Yes      | Name of the log file to reset      |

**Returns:** `code 0` + entry count before the reset (`int`) in `.data`.

```powershell
# Basic reset
$result = VPDLXresetlogfile -Logfile 'AppLog'
if ($result.code -eq 0) {
    Write-Host "Cleared $($result.data) entries."
}

# Log rotation pattern: export then reset
$export = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json'
if ($export.code -eq 0) {
    $reset = VPDLXresetlogfile -Logfile 'AppLog'
    Write-Host "Exported and cleared $($reset.data) entries."
}
```

> **Difference from VPDLXdroplogfile:**
> - `VPDLXresetlogfile` — clears the data, keeps the log file alive and reusable.
> - `VPDLXdroplogfile` — destroys the entire log file permanently (data + metadata + registration).

---

### VPDLXfilterlogfile

Filters the entries of a virtual log file by log level. Returns the matching
entries as a structured result object.

```powershell
VPDLXfilterlogfile -Logfile <string> -Level <string>
```

| Parameter   | Type     | Required | Description                                     |
|-------------|----------|----------|-------------------------------------------------|
| `-Logfile`  | `string` | Yes      | Name of the log file to filter                  |
| `-Level`    | `string` | Yes      | Log level to filter for (tab-completion enabled)|

Accepted levels: `info`, `debug`, `verbose`, `trace`, `warning`, `error`, `critical`, `fatal`

**Returns:** `code 0` + `[PSCustomObject]` in `.data` containing:

| Property  | Type       | Description                        |
|-----------|------------|------------------------------------|
| `Entries` | `string[]` | Matching log lines (or empty `@()`)|
| `Count`   | `int`      | Number of matches                  |
| `Level`   | `string`   | The level that was filtered        |

```powershell
# Filter for error entries
$result = VPDLXfilterlogfile -Logfile 'AppLog' -Level 'error'
if ($result.code -eq 0 -and $result.data.Count -gt 0) {
    Write-Host "Found $($result.data.Count) error(s):"
    $result.data.Entries | ForEach-Object { Write-Host "  $_" }
}

# Alert on critical entries
$criticals = VPDLXfilterlogfile -Logfile 'ProdLog' -Level 'critical'
if ($criticals.data.Count -gt 0) {
    Write-Warning "CRITICAL entries detected — exporting log."
    VPDLXexportlogfile -Logfile 'ProdLog' -LogPath 'C:\Logs' -ExportAs 'json'
}
```

---

## Class Reference

The classes below are the underlying engine of VPDLX. For most use cases the
[Public Wrapper Functions](#public-wrapper-functions) above are sufficient. Direct
class access is useful for advanced scenarios, scripted loops, or when integrating
VPDLX into a larger module.

---

### Logfile

The central user-facing class. Each instance represents one named virtual log file.

```powershell
# Standard constructor — all log levels accepted
$log = [Logfile]::new('MyAppLog')

# Constructor with minimum log level (v1.02.06) — entries below the threshold are silently discarded
$prodLog = [Logfile]::new('ProdLog', 'warning')
```

**Name rules:** 3–64 characters; allowed characters: `a-z A-Z 0-9 _ - .`; uniqueness is case-insensitive.

**Minimum log level (v1.02.06):** When a minimum level is specified, `Write()` and `Print()` silently discard entries whose severity is below the threshold. No exception is thrown — the call simply returns without side effects. Severity ranking (low → high): `trace(0)` < `debug(1)` < `verbose(2)` < `info(3)` < `warning(4)` < `error(5)` < `critical(6)` < `fatal(7)`.

#### Write Methods

| Method | Signature | Description |
|---|---|---|
| `Write` | `Write([string] $level, [string] $message)` | Appends a single formatted entry |
| `Print` | `Print([string] $level, [string[]] $messages)` | Batch write; transactional — all entries are pre-validated before any are written |
| `Info` | `Info([string] $message)` | Shortcut for `Write('info', ...)` |
| `Debug` | `Debug([string] $message)` | Shortcut for `Write('debug', ...)` |
| `Verbose` | `Verbose([string] $message)` | Shortcut for `Write('verbose', ...)` |
| `Trace` | `Trace([string] $message)` | Shortcut for `Write('trace', ...)` |
| `Warning` | `Warning([string] $message)` | Shortcut for `Write('warning', ...)` |
| `Error` | `Error([string] $message)` | Shortcut for `Write('error', ...)` |
| `Critical` | `Critical([string] $message)` | Shortcut for `Write('critical', ...)` |
| `Fatal` | `Fatal([string] $message)` | Shortcut for `Write('fatal', ...)` |

#### Read Methods

| Method | Signature | Description |
|---|---|---|
| `Read` | `Read([int] $line) → string` | 1-based index; auto-clamped to valid range |
| `GetAllEntries` | `GetAllEntries() → string[]` | Returns all entries as a string array |
| `FilterByLevel` | `FilterByLevel([string] $level) → string[]` | Returns only entries matching the given level |

#### Utility Methods

| Method | Signature | Description |
|---|---|---|
| `IsEmpty` | `IsEmpty() → bool` | `$true` if the log has no entries |
| `HasEntries` | `HasEntries() → bool` | `$true` if at least one entry exists |
| `EntryCount` | `EntryCount() → int` | Current number of entries |
| `Reset` | `Reset() → void` | Clears all entries (irreversible; preserves metadata timestamps) |
| `Destroy` | `Destroy() → void` | Removes instance from storage and frees all data; subsequent calls throw `ObjectDisposedException` |
| `GetDetails` | `GetDetails() → [FileDetails]` | Returns the metadata companion |
| `ToString` | `ToString() → string` | One-line summary (includes `MinLevel` when configured) |
| `GetMinLogLevel` | `GetMinLogLevel() → string` | Returns the configured minimum level name, or `'none'` if no filter is active (v1.02.06) |

#### Static Properties

| Property | Type | Description |
|---|---|---|
| `MaxMessageLength` | `int` | Maximum allowed message length (default: 8192; configurable at runtime) |
| `LevelSeverity` | `hashtable` | Maps level names to severity indices: trace=0, debug=1, ..., fatal=7 (v1.02.06) |

---

### FileDetails

Read-only metadata companion for each `[Logfile]` instance. Obtain via `$log.GetDetails()`.

| Method | Returns | Description |
|---|---|---|
| `GetCreated()` | `string` | Timestamp of instance creation |
| `GetUpdated()` | `string` | Timestamp of last `Write` / `Print` / `Reset` |
| `GetLastAccessed()` | `string` | Timestamp of last `Read` / `GetAllEntries()` / `FilterByLevel()` |
| `GetLastAccessType()` | `string` | Type of the most recent interaction |
| `GetEntries()` | `int` | Current number of log entries |
| `GetAxcount()` | `int` | Total number of interactions since creation |
| `ToString()` | `string` | One-line summary of all fields |
| `ToHashtable()` | `OrderedDictionary` | All fields as ordered key-value pairs |

**Axcount** increments on every interaction and is only zeroed by `Destroy()`.

---

### FileStorage

Module-level singleton registry. Not typically called directly — use `VPDLXcore -KeyID 'storage'` to access it.

| Method | Signature | Description |
|---|---|---|
| `Contains` | `Contains([string] $name) → bool` | O(1) existence check |
| `Get` | `Get([string] $name) → Logfile` | Returns the `[Logfile]` instance or `$null` |
| `DestroyAll` | `DestroyAll() → void` | Destroys all registered instances and clears the registry |
| `Count` | `Count() → int` | Number of currently registered instances |
| `GetNames` | `GetNames() → string[]` | All registered names in insertion order |
| `ToString` | `ToString() → string` | One-line summary |

---

## VPDLXcore

A controlled read-only accessor for module-scope variables. Used internally by all
Public Wrapper functions and available for advanced callers who need direct access
to module internals.

```powershell
$meta    = VPDLXcore -KeyID 'appinfo'      # Module metadata hashtable
$storage = VPDLXcore -KeyID 'storage'      # [FileStorage] singleton
$formats = VPDLXcore -KeyID 'export'       # Export format definitions (txt, csv, json, log, html, ndjson)
VPDLXcore -KeyID 'destroyall'              # Destroys all active logfile instances
$stats   = VPDLXcore -KeyID 'stats'        # Module-wide statistics (v1.02.05)
```

The `stats` key (new in v1.02.05) returns a `[PSCustomObject]` with:

| Property          | Type     | Description                                 |
|-------------------|----------|---------------------------------------------|
| `ActiveLogfiles`  | `int`    | Number of currently registered log files     |
| `TotalEntries`    | `int`    | Sum of all entries across all log files       |
| `MaxEntries`      | `int`    | Highest entry count among all log files       |
| `MaxEntriesLog`   | `string` | Name of the log file with the most entries    |
| `MinEntries`      | `int`    | Lowest entry count among all log files        |
| `MinEntriesLog`   | `string` | Name of the log file with the fewest entries  |
| `ModuleVersion`   | `string` | Current VPDLX module version                  |

```powershell
$stats = (VPDLXcore -KeyID 'stats').data
Write-Host "Active: $($stats.ActiveLogfiles) logs, $($stats.TotalEntries) total entries"
Write-Host "Largest: $($stats.MaxEntriesLog) ($($stats.MaxEntries) entries)"
```

**Return type on error:** `PSCustomObject { code = -1, msg = <description>, data = $null }`

---

## Log Levels

| Identifier | Shortcut method | Output tag | Typical use |
|---|---|---|---|
| `info` | `.Info()` | `[INFO]` | General informational messages |
| `debug` | `.Debug()` | `[DEBUG]` | Developer diagnostics |
| `verbose` | `.Verbose()` | `[VERBOSE]` | Detailed execution tracing |
| `trace` | `.Trace()` | `[TRACE]` | Fine-grained step-by-step tracing |
| `warning` | `.Warning()` | `[WARNING]` | Non-fatal unexpected conditions |
| `error` | `.Error()` | `[ERROR]` | Recoverable errors |
| `critical` | `.Critical()` | `[CRITICAL]` | Severe errors, degraded functionality |
| `fatal` | `.Fatal()` | `[FATAL]` | Unrecoverable errors, imminent failure |

Level identifiers are **case-insensitive** in all wrapper functions and class methods.

---

## Entry Format

Every log entry follows this fixed format:

```
[dd.MM.yyyy | HH:mm:ss]  [LEVEL]     ->  MESSAGE
```

Example output:

```
[06.04.2026 | 09:00:01]  [INFO]      ->  Application started.
[06.04.2026 | 09:00:02]  [DEBUG]     ->  Config loaded from C:\App\config.json.
[06.04.2026 | 09:00:03]  [WARNING]   ->  Disk usage at 81 percent.
[06.04.2026 | 09:00:04]  [ERROR]     ->  Database connection failed on attempt 1.
[06.04.2026 | 09:00:05]  [FATAL]     ->  Unrecoverable exception — terminating.
```

The timestamp is captured at the moment each entry is written. Messages may not contain newline characters (`\r` or `\n`) — this is enforced to prevent log injection in exported files.

---

## Quick Examples

### Using the Public Wrapper Functions (recommended)

```powershell
Import-Module .\VPDLX\VPDLX.psd1

# Create a new log file
$r = VPDLXnewlogfile -Logfile 'AppLog'

# Write entries
VPDLXwritelogfile -Logfile 'AppLog' -Level 'info'    -Message 'Service started.'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'warning' -Message 'Retry count is 0.'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'error'   -Message 'Connection attempt failed.'

# Check existence
if (VPDLXislogfile -Logfile 'AppLog') {
    Write-Host 'Log file is active.'
}

# Read a specific line
$r = VPDLXreadlogfile -Logfile 'AppLog' -Line 1
Write-Host $r.data

# Export to disk as CSV (creates C:\Logs if it doesn't exist)
$r = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'csv'
Write-Host "Exported to: $($r.data)"

# Export as JSON, overwrite if file exists
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json' -Override

# Export as styled HTML report (v1.02.06)
$r = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'html'
if ($r.code -eq 0) { Start-Process $r.data }   # opens in browser

# Export as NDJSON for log pipelines (v1.02.06)
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM

# List all active log files (v1.02.05)
$all = VPDLXgetalllogfiles
$all.data | Format-Table -AutoSize

# Filter for error entries only (v1.02.05)
$errors = VPDLXfilterlogfile -Logfile 'AppLog' -Level 'error'
Write-Host "Found $($errors.data.Count) error(s)."

# Log rotation: export, then clear entries (v1.02.05)
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json' -NoBOM
$reset = VPDLXresetlogfile -Logfile 'AppLog'
Write-Host "Cleared $($reset.data) entries."

# Module statistics (v1.02.05)
$stats = (VPDLXcore -KeyID 'stats').data
Write-Host "$($stats.ActiveLogfiles) active log(s), $($stats.TotalEntries) total entries."

# Remove the log file from memory
VPDLXdroplogfile -Logfile 'AppLog'
```

### Using the Minimum Log Level (v1.02.06)

```powershell
Import-Module .\VPDLX\VPDLX.psd1

# Create a production log that only records warnings and above
$prodLog = [Logfile]::new('ProdLog', 'warning')

$prodLog.Info('Ignored — below minimum level.')    # silently discarded
$prodLog.Warning('Disk usage at 85 percent.')        # recorded
$prodLog.Error('Connection timeout.')                # recorded

$prodLog.EntryCount()       # → 2
$prodLog.GetMinLogLevel()   # → 'warning'

# Severity ranking is available as a static property
[Logfile]::LevelSeverity
# → @{ trace = 0; debug = 1; verbose = 2; info = 3; warning = 4; error = 5; critical = 6; fatal = 7 }

# Export the filtered log
VPDLXexportlogfile -Logfile 'ProdLog' -LogPath 'C:\Logs' -ExportAs 'html'

$prodLog.Destroy()
$prodLog = $null
```

### Using the Classes Directly (advanced)

```powershell
Import-Module .\VPDLX\VPDLX.psd1

$log = [Logfile]::new('AppLog')

$log.Info('Service started.')
$log.Warning('Retry count is 0.')
$log.Error('Connection attempt failed.')

# Batch write
$log.Print('info', @('Step 1 complete.', 'Step 2 complete.', 'Step 3 complete.'))

# Read
$log.Read(1)                      # First entry
$log.GetAllEntries()              # All entries as string[]
$log.FilterByLevel('error')       # Only [ERROR] entries

# Metadata
$d = $log.GetDetails()
Write-Host "Created : $($d.GetCreated())"
Write-Host "Updated : $($d.GetUpdated())"
Write-Host "Axcount : $($d.GetAxcount())"

# Cleanup
$log.Destroy()
$log = $null
```

---

## Known Limitations

### No Parallel Execution Support ⚠️

VPDLX is **not designed for parallel execution** and is **not thread-safe**.

The internal data structures (`List<string>` for log entries, `Dictionary` for the
storage registry) are not synchronised. Using `[Logfile]` instances inside
`ForEach-Object -Parallel`, `Start-ThreadJob`, or any other multi-runspace construct
**without external synchronisation** may lead to:
- Race conditions on `_data.Add()` causing lost or corrupted entries
- Registry corruption in `FileStorage`
- Unpredictable `ObjectDisposedException` behaviour

> If parallel logging is required, each parallel worker should maintain its own
> independent `[Logfile]` instance and the results should be merged after the
> parallel block completes.

### Message Length Limit

Since v1.02.04, `ValidateMessage()` enforces a configurable maximum message length (default: **8192 characters**). Messages exceeding the limit are rejected with a descriptive error. This protects against accidental memory flooding from extremely long strings.

To adjust the limit at runtime:

```powershell
[Logfile]::MaxMessageLength = 16384   # double the default
[Logfile]::MaxMessageLength = 1024    # stricter limit for production
```

### Other Limitations

| Limitation | Detail |
|---|---|
| `hidden` ≠ `private` | PowerShell does not enforce true access control. `hidden` suppresses IntelliSense / `Get-Member` visibility only. Disciplined callers should use the documented public methods. |
| String timestamps | Timestamps are stored as formatted strings. Direct time arithmetic requires additional parsing via `[datetime]::ParseExact()`. |
| After `Destroy()` | The PowerShell variable is not automatically set to `$null`. Always assign `$log = $null` after calling `Destroy()` to prevent stale reference errors. |
| After `Destroy()` + `ToString()` | Calling `ToString()` on a destroyed instance (explicitly or via string interpolation) throws `ObjectDisposedException`. This is consistent with all other public methods since v1.02.03. |