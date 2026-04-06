# VPDLX — Virtual PowerShell Data-Logger eXtension

![Version](https://img.shields.io/badge/Version-1.01.00-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)

VPDLX is a PowerShell module that provides a fully class-based, **in-memory** virtual logging system. Instead of writing log entries to disk immediately, VPDLX keeps any number of named log instances alive in RAM for the duration of the current PowerShell session — enabling fast, structured, and reversible logging without any file-system I/O.

---

## Table of contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Architecture](#architecture)
4. [Class reference](#class-reference)
   - [Logfile](#logfile)
   - [FileDetails](#filedetails)
   - [FileStorage](#filestorage)
5. [VPDLXcore](#vpdlxcore)
6. [Log levels](#log-levels)
7. [Entry format](#entry-format)
8. [Quick examples](#quick-examples)
9. [Known limitations](#known-limitations)

---

## Requirements

| Requirement          | Value                          |
|----------------------|--------------------------------|
| PowerShell           | 5.1 (Desktop) or 7.x (Core)   |
| Compatible editions  | `Desktop`, `Core`              |
| External dependencies| None                           |
| Required privileges  | Standard user (no elevation)   |
| Platform             | Windows 10 / Windows 11        |

---

## Installation

Clone or copy the `VPDLX` folder to any location, then import:

```powershell
Import-Module .\VPDLX\VPDLX.psd1
```

After import, the three classes `[Logfile]`, `[FileDetails]`, and `[FileStorage]` are
registered as TypeAccelerators and are immediately usable — no `using module` required.

---

## Architecture

```
VPDLX/
├── VPDLX.psm1          # Root module: class loading, TypeAccelerators, module init
├── VPDLX.psd1          # Module manifest
├── CHANGELOG.md
├── QUICKSTART.md
├── README.md
│
├── Classes/
│   ├── FileDetails.ps1 # Metadata companion for each Logfile instance
│   ├── FileStorage.ps1 # Module-level singleton registry
│   └── Logfile.ps1     # Core user-facing class
│
├── Private/
│   └── VPDLXreturn.ps1 # Standardised return-object factory
│
├── Public/             # Reserved for future wrapper functions
│
└── Examples/
    └── Demo-001.ps1    # Annotated demonstration script
```

Classes are dot-sourced in strict dependency order: `FileDetails` → `FileStorage` → `Logfile`. A load-order guard in `VPDLX.psm1` verifies each file exists before dot-sourcing and aborts with a descriptive error if any file is missing.

---

## Class reference

### Logfile

The central, user-facing class. Each instance is one named virtual log file.

```powershell
$log = [Logfile]::new('MyAppLog')
```

**Name rules:** 3–64 characters; allowed: `a-z A-Z 0-9 _ - .`; case-insensitive uniqueness.

#### Write methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `Write` | `Write([string] $level, [string] $message)` | Appends a single entry |
| `Print` | `Print([string] $level, [string[]] $messages)` | Appends a batch; transactional pre-validation |
| `Info` | `Info([string] $message)` | Shortcut for `Write('info', ...)` |
| `Debug` | `Debug([string] $message)` | Shortcut for `Write('debug', ...)` |
| `Verbose` | `Verbose([string] $message)` | Shortcut for `Write('verbose', ...)` |
| `Trace` | `Trace([string] $message)` | Shortcut for `Write('trace', ...)` |
| `Warning` | `Warning([string] $message)` | Shortcut for `Write('warning', ...)` |
| `Error` | `Error([string] $message)` | Shortcut for `Write('error', ...)` |
| `Critical` | `Critical([string] $message)` | Shortcut for `Write('critical', ...)` |
| `Fatal` | `Fatal([string] $message)` | Shortcut for `Write('fatal', ...)` |

#### Read methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `Read` | `Read([int] $line) → string` | 1-based; auto-clamped to valid range |
| `SoakUp` | `SoakUp() → string[]` | Returns all entries as an array |
| `Filter` | `Filter([string] $level) → string[]` | Returns only entries matching the level |

#### Utility methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `IsEmpty` | `IsEmpty() → bool` | `$true` if no entries |
| `HasEntries` | `HasEntries() → bool` | `$true` if at least one entry |
| `EntryCount` | `EntryCount() → int` | Current entry count |
| `Reset` | `Reset() → void` | Clears all data (irreversible) |
| `Destroy` | `Destroy() → void` | Removes from registry, frees memory |
| `GetDetails` | `GetDetails() → [FileDetails]` | Returns the metadata companion |
| `ToString` | `ToString() → string` | One-line summary |

---

### FileDetails

Read-only metadata companion for each `[Logfile]` instance. Obtain via `$log.GetDetails()`.

#### Public getter methods

| Method | Returns | Description |
|--------|---------|-------------|
| `GetCreated()` | `string` | Timestamp of instance creation |
| `GetUpdated()` | `string` | Timestamp of last Write / Print / Reset |
| `GetLastAccessed()` | `string` | Timestamp of last Read / SoakUp / Filter |
| `GetLastAccessType()` | `string` | Type of the most recent interaction |
| `GetEntries()` | `int` | Current number of log entries |
| `GetAxcount()` | `int` | Total interactions since creation |
| `ToString()` | `string` | One-line summary of all fields |
| `ToHashtable()` | `OrderedDictionary` | All fields as ordered key-value pairs |

**Axcount** is never reset during the lifetime of the instance — only zeroed when `Destroy()` is called.

---

### FileStorage

Module-level singleton registry. Access via `VPDLXcore -KeyID 'storage'`.

| Method | Signature | Description |
|--------|-----------|-------------|
| `Contains` | `Contains([string] $name) → bool` | O(1) name lookup |
| `Get` | `Get([string] $name) → object` | Returns instance or `$null` |
| `Count` | `Count() → int` | Number of registered instances |
| `GetNames` | `GetNames() → string[]` | All names in insertion order |
| `ToString` | `ToString() → string` | Summary string |

---

## VPDLXcore

The only exported public function. Provides controlled read-only access to module-scope variables.

```powershell
VPDLXcore -KeyID 'appinfo'   # Module metadata hashtable
VPDLXcore -KeyID 'storage'   # [FileStorage] singleton
VPDLXcore -KeyID 'export'    # Export format definitions (reserved)
```

Return type: `PSCustomObject { code, msg, data }` where `code` is `0` (success) or `-1` (error).

---

## Log levels

| Identifier | Shortcut method | Output tag    | Typical use                            |
|------------|-----------------|---------------|----------------------------------------|
| `info`     | `.Info()`       | `[INFO]`      | General informational messages         |
| `debug`    | `.Debug()`      | `[DEBUG]`     | Developer diagnostics                  |
| `verbose`  | `.Verbose()`    | `[VERBOSE]`   | Detailed execution tracing             |
| `trace`    | `.Trace()`      | `[TRACE]`     | Fine-grained step-by-step tracing      |
| `warning`  | `.Warning()`    | `[WARNING]`   | Non-fatal unexpected conditions        |
| `error`    | `.Error()`      | `[ERROR]`     | Recoverable errors                     |
| `critical` | `.Critical()`   | `[CRITICAL]`  | Severe errors, degraded functionality  |
| `fatal`    | `.Fatal()`      | `[FATAL]`     | Unrecoverable errors, imminent failure |

Level identifiers are **case-insensitive**.

---

## Entry format

```
[dd.MM.yyyy | HH:mm:ss]  [LEVEL]     ->  MESSAGE
```

Example:

```
[06.04.2026 | 09:00:01]  [INFO]      ->  Application started.
[06.04.2026 | 09:00:02]  [DEBUG]     ->  Config loaded from C:\App\config.json.
[06.04.2026 | 09:00:03]  [WARNING]   ->  Disk usage at 81 percent.
[06.04.2026 | 09:00:04]  [ERROR]     ->  Database connection failed on attempt 1.
[06.04.2026 | 09:00:05]  [FATAL]     ->  Unrecoverable exception — terminating.
```

---

## Quick examples

```powershell
# ── Import ───────────────────────────────────────────────────────────
Import-Module .\VPDLX\VPDLX.psd1

# ── Create ───────────────────────────────────────────────────────────
$log = [Logfile]::new('AppLog')

# ── Write ────────────────────────────────────────────────────────────
$log.Info('Service started.')
$log.Debug('Reading configuration...')
$log.Verbose('Entering Initialize-DataStore.')
$log.Warning('Retry count is 0.')
$log.Error('Connection attempt 1 failed.')
$log.Fatal('Unrecoverable state — aborting.')

$log.Print('info', @('Step 1 complete.', 'Step 2 complete.', 'Step 3 complete.'))

# ── Read ─────────────────────────────────────────────────────────────
$log.Read(1)               # First entry
$log.SoakUp()              # All entries as string[]
$log.Filter('error')       # Only [ERROR] entries

# ── Guard helpers ────────────────────────────────────────────────────
if ($log.HasEntries()) {
    Write-Host "Entries: $($log.EntryCount())"
}

# ── Metadata ─────────────────────────────────────────────────────────
$d = $log.GetDetails()
Write-Host "Created : $($d.GetCreated())"
Write-Host "Updated : $($d.GetUpdated())"
Write-Host "AccType : $($d.GetLastAccessType())"
Write-Host "Axcount : $($d.GetAxcount())"

# ── Reset / Destroy ───────────────────────────────────────────────────
$log.Reset()
$log.Destroy()
$log = $null
```

---

## Known limitations

### No parallel execution support ⚠️

VPDLX is **not designed for parallel execution** and is **not thread-safe**.

The internal data structures (`List<string>` for log entries, `Dictionary` for the storage registry) are not synchronised. Using `[Logfile]` instances inside `ForEach-Object -Parallel`, `Start-ThreadJob`, or any other multi-runspace construct **without external synchronisation** may lead to:
- Race conditions on `_data.Add()` causing lost or corrupted entries
- Registry corruption in `FileStorage`
- Unpredictable `ObjectDisposedException` behaviour

This is a **known limitation** of the current version. For single-threaded, sequential PowerShell scripts VPDLX is fully reliable.

> If parallel logging is required, each parallel worker should maintain its own
> independent `[Logfile]` instance and the results should be merged after the
> parallel block completes.

### Other known limitations

| Limitation | Detail |
|------------|--------|
| `hidden` ≠ `private` | PowerShell does not enforce true access control. `hidden` suppresses IntelliSense/Get-Member visibility only. |
| No entry limit | Logs grow unboundedly in RAM. Very long-running scripts may consume significant memory. |
| String timestamps | Timestamps are stored as formatted strings. Direct time arithmetic requires additional parsing. |
| No export in v1.01.00 | Export to `.txt`, `.csv`, `.json`, `.log` is planned for a future version. Use `SoakUp()` as an interim workaround. |
| After `Destroy()` | Set the variable to `$null` manually. Subsequent calls on the old reference throw `ObjectDisposedException`. |
