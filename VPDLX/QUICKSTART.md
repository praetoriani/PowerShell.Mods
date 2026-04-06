# VPDLX — Quick Start Guide

> **Module version:** 1.01.00  
> **Prerequisites:** PowerShell 5.1 or PowerShell 7.x

This guide takes you from zero to a working virtual log file in five steps.

---

## Step 1 — Import the module

```powershell
Import-Module .\VPDLX.psd1
```

After import, the three classes `[Logfile]`, `[FileDetails]`, and `[FileStorage]` are
available as type accelerators — no `using module` statement required.

---

## Step 2 — Create a virtual log file

```powershell
$log = [Logfile]::new('MyFirstLog')
```

Name rules:
- 3–64 characters
- Allowed characters: `a-z A-Z 0-9 _ - .`
- Names are case-insensitive for uniqueness (you cannot have both `MyLog` and `mylog`)

---

## Step 3 — Write log entries

### Single entry — `Write()`

```powershell
$log.Write('info',    'Application started successfully.')
$log.Write('debug',   'Configuration file loaded from C:\App\config.json.')
$log.Write('warning', 'Retry limit is set to 0 — retries are disabled.')
$log.Write('error',   'Failed to connect to the database on first attempt.')
```

### Shortcut methods — one method per level

```powershell
$log.Info('User authentication succeeded.')
$log.Debug('Token expiry: 3600 seconds.')
$log.Verbose('Entering function Initialize-DataStore.')
$log.Trace('Variable $count = 42 at line 87.')
$log.Warning('Disk usage has exceeded 80 percent.')
$log.Error('HTTP request returned status 503.')
$log.Critical('Primary database cluster is unreachable.')
$log.Fatal('Unrecoverable exception — process will terminate.')
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
> A validation failure on one message leaves the log unchanged.

### Supported log levels

| Level      | Shortcut          | Output tag    |
|------------|-------------------|---------------|
| `info`     | `.Info()`         | `[INFO]`      |
| `debug`    | `.Debug()`        | `[DEBUG]`     |
| `verbose`  | `.Verbose()`      | `[VERBOSE]`   |
| `trace`    | `.Trace()`        | `[TRACE]`     |
| `warning`  | `.Warning()`      | `[WARNING]`   |
| `error`    | `.Error()`        | `[ERROR]`     |
| `critical` | `.Critical()`     | `[CRITICAL]`  |
| `fatal`    | `.Fatal()`        | `[FATAL]`     |

Level identifiers are **case-insensitive** (`'INFO'`, `'Info'`, `'info'` all work).

---

## Step 4 — Read log entries

### Read a specific line — `Read()`

```powershell
# Read line 1 (1-based index; out-of-range values are clamped automatically)
$log.Read(1)
```

### Read everything — `SoakUp()`

```powershell
$allLines = $log.SoakUp()
$allLines | ForEach-Object { Write-Host $_ }
```

### Filter by level — `Filter()`

```powershell
$errors = $log.Filter('error')
$errors | ForEach-Object { Write-Host $_ }
```

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

## Step 5 — Inspect metadata

```powershell
$details = $log.GetDetails()

Write-Host ('Created   : ' + $details.GetCreated())
Write-Host ('Updated   : ' + $details.GetUpdated())
Write-Host ('Last acc  : ' + $details.GetLastAccessed())
Write-Host ('Acc type  : ' + $details.GetLastAccessType())
Write-Host ('Entries   : ' + $details.GetEntries())
Write-Host ('Axcount   : ' + $details.GetAxcount())

# Or as an ordered dictionary:
$details.ToHashtable()
```

Field reference:

| Key       | Getter                  | Updated by                     |
|-----------|-------------------------|--------------------------------|
| `created` | `GetCreated()`          | Set once at construction       |
| `updated` | `GetUpdated()`          | `Write`, `Print`, `Reset`      |
| `lastacc` | `GetLastAccessed()`     | `Read`, `SoakUp`, `Filter`     |
| `acctype` | `GetLastAccessType()`   | Every interaction              |
| `entries` | `GetEntries()`          | Every write or reset           |
| `axcount` | `GetAxcount()`          | Every interaction (never reset unless Destroy) |

---

## Additional operations

### Reset a log (clears data, keeps metadata skeleton)

```powershell
$log.Reset()
# _data is now empty; _created and _axcount are preserved
```

### Destroy a log (removes from registry, frees memory)

```powershell
$log.Destroy()
$log = $null   # Always set the variable to $null after Destroy()
```

### Access the module-level storage

```powershell
# List all registered logfile names
$store = VPDLXcore -KeyID 'storage'
$store.GetNames()

# Get a logfile by name
$myLog = $store.Get('MyFirstLog')
$myLog.EntryCount()
```

### Retrieve module info

```powershell
$info = VPDLXcore -KeyID 'appinfo'
$info   # displays Name, Version, Author, ReleaseDate
```

---

## Entry format

Every log line written by VPDLX follows this fixed format:

```
[dd.MM.yyyy | HH:mm:ss]  [LEVEL]     ->  MESSAGE
```

Example output:

```
[06.04.2026 | 10:15:42]  [INFO]      ->  Application started successfully.
[06.04.2026 | 10:15:43]  [WARNING]   ->  Retry limit is set to 0.
[06.04.2026 | 10:15:44]  [ERROR]     ->  Failed to connect to the database.
```

---

## Known limitations

- **No parallel execution support.** VPDLX is not thread-safe. Do not use `[Logfile]` instances inside `ForEach-Object -Parallel` or `Start-ThreadJob` without external synchronisation. See README.md for the full list of known limitations.
- After calling `.Destroy()`, always set the variable to `$null`. Subsequent method calls on a destroyed instance throw `ObjectDisposedException`.
- There is no built-in entry limit. Very large logs accumulate in RAM for the duration of the session.
