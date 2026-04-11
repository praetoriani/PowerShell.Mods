# VPDLX — Quick Start Guide

> **Module version:** 1.02.03
> **Prerequisites:** PowerShell 5.1 or PowerShell 7.x

This guide takes you from zero to a fully working virtual log file in five minutes.
It covers both the recommended **Public Wrapper API** (introduced in v1.01.02) and
the underlying **class-based API** for advanced scenarios.

---

## Step 1 — Import the module

```powershell
Import-Module .\VPDLX.psd1
```

After import, three things are available in your session:

- **Type accelerators** — `[Logfile]`, `[FileDetails]`, `[FileStorage]` (no `using module` needed)
- **Public Wrapper functions** — `VPDLXnewlogfile`, `VPDLXislogfile`, `VPDLXdroplogfile`,
  `VPDLXreadlogfile`, `VPDLXwritelogfile`, `VPDLXexportlogfile`
- **Module accessor** — `VPDLXcore`

---

## Step 2 — Create a virtual log file

### Recommended — Public Wrapper

```powershell
$r = VPDLXnewlogfile -Logfile 'MyFirstLog'

# All wrapper functions return a standardised result object:
# $r.code  -1 = failure   0 = success
# $r.msg   Human-readable status message
# $r.data  Return payload (the log file name on success)

if ($r.code -eq 0) {
    Write-Host "Created: $($r.data)"
}
```

### Alternative — Class API (direct)

```powershell
$log = [Logfile]::new('MyFirstLog')
```

**Name rules (both approaches):**

- 3 – 64 characters
- Allowed characters: `a-z A-Z 0-9 _ - .`
- Names are case-insensitive for uniqueness (`MyLog` and `mylog` cannot coexist)

---

## Step 3 — Check whether a log file exists

```powershell
$exists = VPDLXislogfile -Logfile 'MyFirstLog'
# Returns $true or $false directly (not a result object)

if ($exists) {
    Write-Host 'Log file is registered and ready.'
}
```

---

## Step 4 — Write log entries

### Via Public Wrapper

```powershell
$r = VPDLXwritelogfile -Logfile 'MyFirstLog' -Level 'info' -Message 'Application started.'
# $r.data contains the new total entry count on success
```

### Via class shortcut methods

```powershell
# Obtain the instance from storage first
$store = (VPDLXcore -KeyID 'storage').data
$log   = $store.Get('MyFirstLog')

$log.Info('User authentication succeeded.')
$log.Debug('Token expiry: 3600 seconds.')
$log.Verbose('Entering function Initialize-DataStore.')
$log.Trace('Variable $count = 42 at line 87.')
$log.Warning('Disk usage has exceeded 80 percent.')
$log.Error('HTTP request returned status 503.')
$log.Critical('Primary database cluster is unreachable.')
$log.Fatal('Unrecoverable exception — process will terminate.')
```

### Via `Write()` (generic)

```powershell
$log.Write('info',    'Application started successfully.')
$log.Write('debug',   'Configuration file loaded from C:\App\config.json.')
$log.Write('warning', 'Retry limit is set to 0 — retries are disabled.')
$log.Write('error',   'Failed to connect to the database on first attempt.')
```

### Batch write — `Print()`

```powershell
$messages = @(
    'Service A initialised.',
    'Service B initialised.',
    'Service C initialised.'
)
$log.Print('info', $messages)
```

> All messages are validated **before** any are written.
> A validation failure on one message leaves the log unchanged (transactional).

### Supported log levels

| Level      | Shortcut method   | Output tag   |
|------------|-------------------|--------------|
| `info`     | `.Info()`         | `[INFO]`     |
| `debug`    | `.Debug()`        | `[DEBUG]`    |
| `verbose`  | `.Verbose()`      | `[VERBOSE]`  |
| `trace`    | `.Trace()`        | `[TRACE]`    |
| `warning`  | `.Warning()`      | `[WARNING]`  |
| `error`    | `.Error()`        | `[ERROR]`    |
| `critical` | `.Critical()`     | `[CRITICAL]` |
| `fatal`    | `.Fatal()`        | `[FATAL]`    |

Level identifiers are **case-insensitive** — `'INFO'`, `'Info'`, and `'info'` all work.

---

## Step 5 — Read log entries

### Read a specific line — `VPDLXreadlogfile` / `Read()`

```powershell
# Public Wrapper (1-based index; out-of-range values are clamped automatically)
$r = VPDLXreadlogfile -Logfile 'MyFirstLog' -Line 1
Write-Host $r.data

# Class API
$log.Read(1)
```

### Read everything — `GetAllEntries()`

```powershell
$allLines = $log.GetAllEntries()
$allLines | ForEach-Object { Write-Host $_ }
```

### Filter by level — `FilterByLevel()`

```powershell
$errors = $log.FilterByLevel('error')
$errors | ForEach-Object { Write-Host $_ }
```

> Note: the method is named `FilterByLevel()` because `Filter` is a reserved
> PowerShell keyword that cannot be used as a class method name.

### Guard helpers

```powershell
if ($log.HasEntries()) {
    Write-Host ('Total entries: ' + $log.EntryCount())
}

if ($log.IsEmpty()) {
    Write-Host 'Log is empty — nothing to display.'
}
```

---

## Step 6 — Export to disk

`VPDLXexportlogfile` writes a virtual log file as a physical file.
The target directory is created automatically if it does not exist.

```powershell
# Export as plain text
$r = VPDLXexportlogfile -Logfile 'MyFirstLog' -LogPath 'C:\Logs' -ExportAs 'txt'

# Export as .log file
$r = VPDLXexportlogfile -Logfile 'MyFirstLog' -LogPath 'C:\Logs' -ExportAs 'log'

# Export as CSV
$r = VPDLXexportlogfile -Logfile 'MyFirstLog' -LogPath 'C:\Logs' -ExportAs 'csv'

# Export as JSON
$r = VPDLXexportlogfile -Logfile 'MyFirstLog' -LogPath 'C:\Logs' -ExportAs 'json'

# Overwrite an existing file with -Override
$r = VPDLXexportlogfile -Logfile 'MyFirstLog' -LogPath 'C:\Logs' -ExportAs 'txt' -Override

# Check the result
if ($r.code -eq 0) {
    Write-Host "Exported to: $($r.data)"
} else {
    Write-Host "Export failed: $($r.msg)" -ForegroundColor Red
}
```

Supported export formats: `txt`, `log`, `csv`, `json`

---

## Step 7 — Inspect metadata

```powershell
$details = $log.GetDetails()

Write-Host ('Created      : ' + $details.GetCreated())
Write-Host ('Updated      : ' + $details.GetUpdated())
Write-Host ('Last access  : ' + $details.GetLastAccessed())
Write-Host ('Access type  : ' + $details.GetLastAccessType())
Write-Host ('Entry count  : ' + $details.GetEntries())
Write-Host ('Axcount      : ' + $details.GetAxcount())

# Or as an ordered hashtable:
$details.ToHashtable()
```

| Key       | Getter                  | Updated by                                      |
|-----------|-------------------------|-------------------------------------------------|
| `created` | `GetCreated()`          | Set once at construction                        |
| `updated` | `GetUpdated()`          | `Write`, `Print`, `Reset`                       |
| `lastacc` | `GetLastAccessed()`     | `Read`, `GetAllEntries`, `FilterByLevel`        |
| `acctype` | `GetLastAccessType()`   | Every interaction                               |
| `entries` | `GetEntries()`          | Every write or reset                            |
| `axcount` | `GetAxcount()`          | Every interaction (never reset unless Destroy)  |

---

## Additional operations

### Reset a log (clears entries, preserves metadata skeleton)

```powershell
$log.Reset()
# _data is now empty; _created and _axcount are preserved
```

### Destroy a log file

```powershell
# Public Wrapper (recommended)
$r = VPDLXdroplogfile -Logfile 'MyFirstLog'

# Class API (direct)
$log.Destroy()
$log = $null   # Always null the reference after Destroy()
```

### Access the module-level storage

```powershell
# Get the FileStorage instance
$store = (VPDLXcore -KeyID 'storage').data

# List all registered log file names
$store.GetNames()

# Count registered log files
$store.Count()

# Get a log file instance by name (returns [Logfile] directly, no cast needed)
$myLog = $store.Get('MyFirstLog')
$myLog.EntryCount()
```

### Destroy all log files at once

```powershell
# Option 1: Via VPDLXcore (recommended)
$r = VPDLXcore -KeyID 'destroyall'
Write-Host $r.msg   # "DestroyAll completed. 3 logfile instance(s) destroyed."

# Option 2: Via FileStorage directly
$store = (VPDLXcore -KeyID 'storage').data
$store.DestroyAll()
```

> `DestroyAll()` is also called automatically when the module is unloaded
> via `Remove-Module VPDLX`, ensuring no orphaned instances remain in memory.

### Retrieve module metadata

```powershell
$info = (VPDLXcore -KeyID 'appinfo').data
$info   # displays Name, Version, Author, ReleaseDate
```

---

## Entry format

Every line written by VPDLX uses this fixed format:

```
[dd.MM.yyyy | HH:mm:ss]  [LEVEL]     ->  MESSAGE
```

Example output:

```
[06.04.2026 | 10:15:42]  [INFO]      ->  Application started successfully.
[06.04.2026 | 10:15:43]  [WARNING]   ->  Retry limit is set to 0.
[06.04.2026 | 10:15:44]  [ERROR]     ->  Failed to connect to the database.
[06.04.2026 | 10:15:45]  [FATAL]     ->  Unrecoverable exception.
```

---

## Interactive demo

Run the included demo script to walk through all features step by step:

```powershell
.\VPDLX\Examples\Demo-001.ps1
```

The demo pauses at the end of each of its 16 sections and waits for you to
press `<Enter>` before continuing, so you can read each result at your own pace.

---

## Known limitations

- **No parallel execution support.** VPDLX is not thread-safe. Do not use `[Logfile]`
  instances inside `ForEach-Object -Parallel` or `Start-ThreadJob` without external
  synchronisation. See `README.md` for the full list of known limitations.
- After calling `.Destroy()` or `VPDLXdroplogfile`, always set the variable to `$null`.
  Subsequent method calls on a destroyed instance — including `ToString()` and
  implicit string interpolation — throw `ObjectDisposedException` (fixed in v1.02.03).
- There is no built-in entry limit. Very large logs accumulate in RAM for the duration
  of the PowerShell session.
