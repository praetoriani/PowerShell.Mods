# VPDLX — Quick-Start Guide

> Get up and running with **VPDLX** (Virtual PowerShell Data-Logger eXtension) in under
> five minutes.

---

## 1. Installation

```powershell
# Clone the repository
git clone https://github.com/praetoriani/PowerShell.Mods.git

# Copy VPDLX to your personal module directory
Copy-Item -Path '.\PowerShell.Mods\VPDLX' `
          -Destination "$env:UserProfile\Documents\PowerShell\Modules\VPDLX" `
          -Recurse -Force

# Import and verify
Import-Module VPDLX -Verbose
Get-Module VPDLX | Select-Object Name, Version
```

---

## 2. Core Concept

VPDLX manages **virtual log file instances** entirely in memory.
Think of each instance as a named, structured text file that lives inside your
PowerShell session — no disk I/O until you decide to export.

Every public function follows the same return schema:

```powershell
$result = SomeVPDLXFunction -Param 'value'

if ($result.code -eq 0) {
    # Success — use $result.data
} else {
    # Failure — read $result.msg for the reason
}
```

| Field | Type | Meaning |
|---|---|---|
| `.code` | `int` | `0` = success · `-1` = failure |
| `.msg` | `string` | Human-readable status or error |
| `.data` | any | Return payload (`$null` on failure) |

---

## 3. Step-by-Step Walkthrough

### Step 1 — Create a virtual log file

```powershell
$r = CreateNewLogfile -FileName 'AppLog'

if ($r.code -eq 0) {
    Write-Host "[OK]  $($r.msg)"     # "Virtual log file 'AppLog' created successfully."
} else {
    Write-Error "[ERR] $($r.msg)"
}
```

**Filename rules:**
- Allowed characters: `a-z A-Z 0-9 _ - .`
- Minimum length: **3** characters
- Maximum length: **64** characters
- Names are **case-insensitive** internally (stored as lowercase key)

---

### Step 2 — Write log entries

```powershell
WriteLogfileEntry -FileName 'AppLog' -LogLevel 'INFO'    -Message 'Application started'
WriteLogfileEntry -FileName 'AppLog' -LogLevel 'DEBUG'   -Message 'Loading configuration file'
WriteLogfileEntry -FileName 'AppLog' -LogLevel 'WARNING' -Message 'Config value missing, using default'
WriteLogfileEntry -FileName 'AppLog' -LogLevel 'ERROR'   -Message 'Failed to connect to remote host'
```

**Available log levels:**

| Level | Typical use |
|---|---|
| `DEBUG` | Detailed diagnostic information |
| `INFO` | General operational messages |
| `VERBOSE` | Extended tracing output |
| `TRACE` | Granular step-by-step tracing |
| `WARNING` | Non-critical issues, degraded state |
| `ERROR` | Recoverable error conditions |
| `CRITICAL` | Severe errors, partial functionality loss |
| `FATAL` | Unrecoverable errors, immediate abort |

Each entry is stored in the format:
```
[yyyy-MM-dd HH:mm:ss] [LOGLEVEL] Message
```

---

### Step 3 — Read a specific entry

```powershell
# Read line 1 (first entry) — line numbers are 1-based
$r = ReadLogfileEntry -FileName 'AppLog' -Line 1
Write-Host $r.data
# Output: [2026-04-05 23:00:00] [INFO] Application started

# Line number exceeding entry count auto-clamps to the last entry
$r = ReadLogfileEntry -FileName 'AppLog' -Line 999
Write-Host $r.data   # Returns the last available entry, no error raised
```

---

### Step 4 — Inspect the registry

```powershell
# List all currently registered virtual log file names
$r = VPDLXcore -Scope 'storage' -GlobalVar 'filestorage' -Permission 'read'
Write-Host "Registered log files: $($r.data -join ', ')"

# Read the full instance data for 'AppLog'
$r = VPDLXcore -Scope 'instances' -GlobalVar 'loginstances' -Permission 'read'
$instance = $r.data['applog']   # Keys are always lowercase
Write-Host "Entries in AppLog: $($instance.info.entries)"
```

---

### Step 5 — Reset a log file

```powershell
# Clears all entries — the instance itself remains active and reusable
$r = ResetLogfile -FileName 'AppLog'
if ($r.code -eq 0) {
    Write-Host "[OK]  $($r.msg)"     # "Virtual log file 'AppLog' has been reset."
}
```

---

### Step 6 — Delete a log file instance

```powershell
# Removes the instance and unregisters it from filestorage
$r = DeleteLogfile -FileName 'AppLog'
if ($r.code -eq 0) {
    Write-Host "[OK]  $($r.msg)"     # "Virtual log file 'AppLog' has been deleted."
}
```

---

## 4. Working with Multiple Log Files

VPDLX is designed to manage **multiple simultaneous instances**.
A common pattern is to maintain separate logs for different concerns:

```powershell
CreateNewLogfile -FileName 'SetupLog'
CreateNewLogfile -FileName 'ErrorLog'
CreateNewLogfile -FileName 'AuditLog'

# Route entries to the appropriate log
WriteLogfileEntry -FileName 'SetupLog' -LogLevel 'INFO'  -Message 'Phase 1 complete'
WriteLogfileEntry -FileName 'ErrorLog' -LogLevel 'ERROR' -Message 'Registry write failed'
WriteLogfileEntry -FileName 'AuditLog' -LogLevel 'INFO'  -Message 'User action: install confirmed'

# Check all registered files at once
$r = VPDLXcore -Scope 'storage' -GlobalVar 'filestorage' -Permission 'read'
$r.data | ForEach-Object { Write-Host " - $_" }
```

---

## 5. Next Steps

| Resource | Description |
|---|---|
| **[demo-001.ps1](demo-001.ps1)** | Full working demonstration script |
| **[README.md](README.md)** | Complete module reference |
| **[CHANGELOG.md](CHANGELOG.md)** | Version history |

---

*VPDLX by [Praetoriani](https://github.com/praetoriani)*
