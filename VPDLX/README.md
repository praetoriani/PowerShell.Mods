# VPDLX

> **Virtual PowerShell Data-Logger eXtension**
> A lightweight, purely in-memory PowerShell module for creating, managing, and exporting multiple virtual log files within a single script session.

[![Module Version](https://img.shields.io/badge/version-1.00.00-blue)](CHANGELOG.md)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-lightgrey)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/license-Personal%20%26%20Corporate%20Use-green)](LICENSE)

---

## Table of Contents

1. [Overview](#overview)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Module Architecture](#module-architecture)
5. [Public Functions](#public-functions)
6. [Private Helpers](#private-helpers)
7. [Module Scope Variables](#module-scope-variables)
8. [Return Value Convention](#return-value-convention)
9. [Typical Workflow](#typical-workflow)
10. [Further Reading](#further-reading)

---

## Overview

**VPDLX** (Virtual PowerShell Data-Logger eXtension) is a PowerShell module that provides
a purely in-memory virtual log file system. Instead of writing every log entry immediately
to disk, VPDLX lets you:

- **Create** multiple named virtual log file instances inside a running script session
- **Write** structured, timestamped log entries with configurable log levels into any instance
- **Read** individual entries from any instance by line number
- **Reset** the content of a virtual log file without destroying the instance
- **Delete** an instance entirely, including its removal from the central file registry
- **Export** virtual log files to real `.log` files on disk when you need persistence

All public functions return a uniform `PSCustomObject { .code, .msg, .data }` result so
VPDLX integrates cleanly into larger automation pipelines.

> For a quick hands-on introduction see **[QUICKSTART.md](QUICKSTART.md)**.
> For a full version history see **[CHANGELOG.md](CHANGELOG.md)**.
> For a working code example see **[demo-001.ps1](demo-001.ps1)**.

---

## Requirements

| Requirement | Details |
|---|---|
| **PowerShell** | 5.1 (Windows Desktop) or 7.x+ (Core) |
| **OS** | Windows 10 / Windows 11 |
| **.NET Framework** | 4.7.2+ (PS 5.x) — ships with Windows 10/11 |
| **Privileges** | Standard user — no elevation required |
| **External tools** | None — zero dependencies outside PowerShell itself |

---

## Installation

```powershell
# 1. Clone the repository
git clone https://github.com/praetoriani/PowerShell.Mods.git

# 2. Copy the VPDLX folder to a module path
Copy-Item -Path '.\PowerShell.Mods\VPDLX' `
          -Destination "$env:UserProfile\Documents\PowerShell\Modules\VPDLX" `
          -Recurse -Force

# 3. Import the module
Import-Module VPDLX -Verbose

# 4. Verify
Get-Module VPDLX | Select-Object Name, Version
```

> The module does **not** require administrator privileges and works equally well when
> dot-sourced directly from a script:
> ```powershell
> Import-Module '.\VPDLX\VPDLX.psd1'
> ```

---

## Module Architecture

```
VPDLX\
├── VPDLX.psm1                     <- Module root: scope initialisation + dot-source loader
├── VPDLX.psd1                     <- Module manifest (version, exports, file list)
├── CHANGELOG.md                   <- Full version history
├── QUICKSTART.md                  <- Hands-on quick-start guide
├── README.md                      <- This file
├── demo-001.ps1                   <- Working demonstration script
│
├── Public\                        <- All exported functions (one file per function)
│   ├── VPDLXcore.ps1              <- Type-safe read/write accessor for module-scope variables
│   ├── CreateNewLogfile.ps1       <- Create a new virtual log file instance
│   ├── WriteLogfileEntry.ps1      <- Write a log entry into a virtual log file
│   ├── ReadLogfileEntry.ps1       <- Read a single entry from a virtual log file
│   ├── ResetLogfile.ps1           <- Reset (clear) a virtual log file
│   └── DeleteLogfile.ps1          <- Delete a virtual log file instance entirely
│
└── Private\                       <- Internal helpers (not exported)
    └── VPDLXreturn.ps1            <- Standardised { .code, .msg, .data } return object factory
```

The `.psm1` dot-sources **all** `Public\*.ps1` and `Private\*.ps1` files automatically.
No edits to `.psm1` are needed when adding new functions — place the `.ps1` in the correct
subfolder and add the function name to `FunctionsToExport` in `.psd1`.

---

## Public Functions

### Core

| Function | Description |
|---|---|
| `VPDLXcore` | Type-safe read/write accessor for all module-scope variables (`loginstances`, `filestorage`, `loglevel`, `exit`) |

### Virtual Log File Management

| Function | Mandatory Parameters | Description |
|---|---|---|
| `CreateNewLogfile` | `-FileName` | Creates a new named virtual log file instance and registers it in `$script:filestorage` |
| `WriteLogfileEntry` | `-FileName`, `-LogLevel`, `-Message` | Appends a formatted, timestamped entry to the specified virtual log file |
| `ReadLogfileEntry` | `-FileName`, `-Line` | Returns a single entry by line number; auto-clamps to last entry when `Line` exceeds entry count |
| `ResetLogfile` | `-FileName` | Clears all entries from the specified virtual log file without removing the instance |
| `DeleteLogfile` | `-FileName` | Removes a virtual log file instance completely, including its entry in `$script:filestorage` |

---

## Private Helpers

| Function | Description |
|---|---|
| `VPDLXreturn` | Creates standardised `{ .code, .msg, .data }` return objects used by all public functions |

---

## Module Scope Variables

All module-scope variables are accessible read-only via `VPDLXcore` (Permission `'read'`)
and with type-safe write access via `VPDLXcore` (Permission `'write'`).

| Variable | Key(s) | Type | Purpose |
|---|---|---|---|
| `$script:loginstances` | `<normalizedName>` | `[hashtable]` | Dictionary of all active virtual log file instances, keyed by lowercase filename |
| `$script:filestorage` | — | `[array]` | Flat string array of all registered log file names; used for fast existence checks |
| `$script:loglevel` | — | `[array]` | Permitted log level strings (`DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`, `VERBOSE`, `TRACE`, `FATAL`) |
| `$script:exit` | `code`, `msg` | `[hashtable]` | Last module exit state |

### Log Instance Schema

Each entry in `$script:loginstances` is a hashtable with three keys:

```powershell
$script:loginstances['mylog'] = @{
    name = 'MyLog'                  # Original filename (preserves casing)
    data = [System.Collections.Generic.List[string]]::new()  # One string per log entry
    info = @{
        created = '2026-04-05 23:00:00'  # Timestamp of CreateNewLogfile call
        updated = '2026-04-05 23:05:00'  # Timestamp of last WriteLogfileEntry call
        entries = 0                       # Current entry count
    }
}
```

---

## Return Value Convention

Every public function returns a `PSCustomObject` with three fields:

| Field | Type | Meaning |
|---|---|---|
| `.code` | `int` | `0` = success, `-1` = failure |
| `.msg` | `string` | Human-readable result or error description |
| `.data` | any | Return payload — `$null` on failure |

```powershell
$r = CreateNewLogfile -FileName 'AppLog'
if ($r.code -eq 0) {
    Write-Host "Created: $($r.msg)"
} else {
    Write-Error "Failed:  $($r.msg)"
}
```

---

## Typical Workflow

```powershell
Import-Module VPDLX

# 1. Create two virtual log files
$r1 = CreateNewLogfile -FileName 'SetupLog'
$r2 = CreateNewLogfile -FileName 'ErrorLog'

# 2. Write entries
WriteLogfileEntry -FileName 'SetupLog' -LogLevel 'INFO'    -Message 'Installation started'
WriteLogfileEntry -FileName 'SetupLog' -LogLevel 'DEBUG'   -Message 'Verifying prerequisites'
WriteLogfileEntry -FileName 'ErrorLog' -LogLevel 'WARNING' -Message 'Disk space below threshold'

# 3. Read a specific entry (line 1 = first entry)
$entry = ReadLogfileEntry -FileName 'SetupLog' -Line 1
Write-Host $entry.data

# 4. List all registered log files
$files = VPDLXcore -Scope 'storage' -GlobalVar 'filestorage' -Permission 'read'
Write-Host "Active log files: $($files.data -join ', ')"

# 5. Reset a log file
ResetLogfile -FileName 'SetupLog'

# 6. Delete a log file instance
DeleteLogfile -FileName 'ErrorLog'
```

---

## Further Reading

| Resource | Link |
|---|---|
| **Quick-Start Guide** | [QUICKSTART.md](QUICKSTART.md) |
| **Changelog** | [CHANGELOG.md](CHANGELOG.md) |
| **Demo Script** | [demo-001.ps1](demo-001.ps1) |
| **PowerShell Releases** | [github.com/PowerShell/PowerShell/releases](https://github.com/PowerShell/PowerShell/releases) |
| **VPDLX on GitHub** | [github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX](https://github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX) |

---

*Module by [Praetoriani](https://github.com/praetoriani) — Licensed for personal and corporate use.*
