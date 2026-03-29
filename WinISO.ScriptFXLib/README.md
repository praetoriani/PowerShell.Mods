# WinISO.ScriptFXLib

> **PowerShell module for fully automated Windows 11 ISO creation, customisation, and rebuilding**
> Using [UUP Dump](https://uupdump.net), DISM, and oscdimg.

---

## Table of Contents

1. [Overview](#overview)
2. [Requirements & Dependencies](#requirements--dependencies)
3. [Installation](#installation)
4. [Module Architecture](#module-architecture)
5. [Public Functions – Reference](#public-functions--reference)
   - Core & Infrastructure
   - UUP Dump Workflow
   - WIM Image Operations
6. [Private Functions](#private-functions)
7. [Global Variables (Module Scope)](#global-variables-module-scope)
8. [Typical Workflow](#typical-workflow)
9. [Return Value Convention](#return-value-convention)
10. [Official Download Sources](#official-download-sources)

---

## Overview

**WinISO.ScriptFXLib** is a PowerShell module that provides a complete, automatable
pipeline for:

- Downloading the latest Windows 11 build package from **UUP Dump**
- Extracting and converting the package into a bootable ISO using `uup_download_windows.cmd`
- Mounting and customising the `install.wim` image (drivers, Appx packages, OEM settings, …)
- Rebuilding a final, bootable Windows 11 Setup ISO using `oscdimg.exe`

The module is designed for both home-lab use and corporate IT automation. All functions
return structured `PSCustomObject` results (`code`, `msg`, `data`) for easy integration
into larger scripts.

---

## Requirements & Dependencies

### Mandatory – Software

| Dependency | Minimum Version | Where to Get |
|---|---|---|
| **Windows OS** | Windows 10 / Windows 11 | — |
| **PowerShell** | 5.1 (Windows PowerShell) or 7.x+ | [PowerShell GitHub](https://github.com/PowerShell/PowerShell/releases) |
| **.NET Framework** | 4.7.2 (Desktop/PS 5.x) | [Microsoft .NET download](https://dotnet.microsoft.com/en-us/download/dotnet-framework/net472) |
| **DISM** (built-in) | Windows 10 1809+ | Built into Windows — `%SystemRoot%\System32\dism.exe` |
| **DISM PowerShell module** | (built-in) | `Import-Module Dism` — ships with Windows |
| **robocopy.exe** | (built-in) | `%SystemRoot%\System32\robocopy.exe` — ships with Windows |
| **cmd.exe** | (built-in) | `%SystemRoot%\System32\cmd.exe` — ships with Windows |
| **oscdimg.exe** | ADK component | See [Official Download Sources](#official-download-sources) |

### Mandatory – Privileges

All functions that interact with DISM (`Mount-WindowsImage`, `Dismount-WindowsImage`,
`Get-WindowsImage`), ISO mounting (`Mount-DiskImage`), and the UUP build process
(`uup_download_windows.cmd`) **require administrator privileges**.

Add `#requires -RunAsAdministrator` to any calling script.

### oscdimg.exe

`oscdimg.exe` is part of the **Windows Assessment and Deployment Kit (Windows ADK)**.
The expected path inside the WinISO environment is:

```
C:\WinISO\Oscdimg\oscdimg.exe
```

This path is stored in `$script:appenv['OscdimgExe']` and is populated by the
`InitializeEnvironment` function (which downloads oscdimg via `GitHubDownload`).

---

## Installation

```powershell
# 1. Clone or download the repository
git clone https://github.com/praetoriani/PowerShell.Mods.git

# 2. Copy WinISO.ScriptFXLib to a module path
Copy-Item -Path '.\PowerShell.Mods\WinISO.ScriptFXLib' `
          -Destination "$env:ProgramFiles\WindowsPowerShell\Modules\WinISO.ScriptFXLib" `
          -Recurse -Force

# 3. Import the module
Import-Module WinISO.ScriptFXLib -Verbose

# 4. Verify requirements
$r = CheckModuleRequirements -Export 1
$r.data | Format-Table CheckName, Status, Detail -AutoSize
```

---

## Module Architecture

```
WinISO.ScriptFXLib\
├── WinISO.ScriptFXLib.psm1        ← Module root: scope variables + AppScope getter + dot-source loader
├── WinISO.ScriptFXLib.psd1        ← Module manifest
├── Public\                        ← All exported functions (one file per function)
│   ├── InitializeEnvironment.ps1
│   ├── VerifyEnvironment.ps1
│   ├── CheckModuleRequirements.ps1
│   ├── WinISOcore.ps1
│   ├── WriteLogMessage.ps1
│   ├── GitHubDownload.ps1
│   ├── DownloadUUPDump.ps1
│   ├── ExtractUUPDump.ps1
│   ├── CreateUUPDiso.ps1
│   ├── CleanupUUPDump.ps1
│   ├── RenameUUPDiso.ps1
│   ├── ExtractUUPDiso.ps1
│   ├── ImageIndexLookup.ps1
│   ├── MountWIMimage.ps1
│   └── UnMountWIMimage.ps1
├── Private\                       ← Internal helper functions (not exported)
│   ├── OPSreturn.ps1
│   ├── Invoke-UUPRuntimeLog.ps1
│   ├── Get-UUPLogTail.ps1
│   ├── Test-UUPConversionPhase.ps1
│   ├── Invoke-UUPProcessKill.ps1
│   └── Get-UUPNewestISO.ps1
└── Requirements\
    └── oscdimg.exe                ← Placed here by InitializeEnvironment
```

The `.psm1` dot-sources **all** `Public\*.ps1` and `Private\*.ps1` files automatically.
No edits to `.psm1` are needed when adding new functions — just place the `.ps1` file in
the correct subfolder and update `FunctionsToExport` in `.psd1`.

---

## Public Functions – Reference

### Core & Infrastructure

---

#### `InitializeEnvironment`

Creates the full WinISO directory structure under `C:\WinISO` and downloads `oscdimg.exe`.
**Must be run once** before using any other functions.

```powershell
$r = InitializeEnvironment
if ($r.code -eq 0) { Write-Host "Environment ready." }
```

---

#### `VerifyEnvironment`

Checks that the WinISO directory structure is intact and all required files are present.
Returns a structured result with details about any missing items.

```powershell
$r = VerifyEnvironment
if ($r.code -ne 0) { Write-Warning $r.msg }
```

---

#### `CheckModuleRequirements`

Performs a full system dependency audit (OS, PowerShell version, .NET, DISM, robocopy,
oscdimg, environment directories, internet connectivity). Optionally exports results to a
text file.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `Export` | `int` | No | `0` | `1` = write results to `<LogfileDir>\WinISO.ScriptFXLib.Requirements.Result.txt` |

```powershell
$r = CheckModuleRequirements -Export 1
$r.data | Format-Table CheckName, Status, Detail -AutoSize
```

**Return `.data`**: `List[PSCustomObject]` with `CheckName`, `Status` (PASS/FAIL/WARNING), `Detail`.

---

#### `WinISOcore`

Type-safe read/write accessor for module-scope (`$script:`) variables.

> **Background:** `AppScope` returns a live hashtable reference (read). `WinISOcore` adds
> explicit, type-validated write access and a formal interface for future scope extensions.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `Scope` | `string` | **Yes** | — | `'env'` (only supported scope currently) |
| `GlobalVar` | `string` | No | `''` | `'appinfo'` \| `'appenv'` \| `'appexit'` |
| `Permission` | `string` | **Yes** | `'read'` | `'read'` \| `'write'` |
| `VarKeyID` | `string` | No | `''` | Key to update (write only; key must exist) |
| `SetNewVal` | any | No | `$null` | New value (write only; type must match existing value) |

```powershell
# Read
$env = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'read'
Write-Host $env.data['ISOroot']   # → C:\WinISO

# Write (type-safe)
$r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' `
                -VarKeyID 'MountPoint' -SetNewVal 'D:\WIMmount'

# Type mismatch → fails gracefully, original value unchanged
$r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' `
                -VarKeyID 'MountPoint' -SetNewVal 42    # $r.code -eq -1
```

---

#### `WriteLogMessage`

Writes a formatted log entry to the WinISO log file (`$EnvData['LogfileDir']`).

```powershell
WriteLogMessage -Level 'INFO' -Message 'ISO creation started.'
```

---

### UUP Dump Workflow

---

#### `DownloadUUPDump`

Downloads a UUP Dump package ZIP from `uupdump.net` for the specified Windows 11 build.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `OStype` | `string` | **Yes** | `'Windows11'` (only supported value) |
| `OSvers` | `string` | **Yes** | `'24H2'` or `'25H2'` |
| `OSarch` | `string` | **Yes** | `'amd64'` or `'arm64'` |
| `BuildNo` | `string` | No | Specific build in format `'00000.0000'` (e.g. `'26100.2161'`) |
| `Target` | `string` | **Yes** | Full path to the target ZIP file (incl. filename) |

```powershell
$r = DownloadUUPDump -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' `
                     -Target 'C:\WinISO\uupdump\Win11_24H2.zip'
```

---

#### `ExtractUUPDump`

Extracts a UUP Dump ZIP archive to the target directory.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `ZIPfile` | `string` | **Yes** | — | Full path to the ZIP file (must exist) |
| `Target` | `string` | **Yes** | — | Destination directory (created if not present) |
| `Verify` | `int` | **Yes** | `1` | `1` = verify entry count after extraction |
| `Cleanup` | `int` | **Yes** | `0` | `1` = delete ZIP after successful extraction |

```powershell
$r = ExtractUUPDump -ZIPfile 'C:\WinISO\uupdump\Win11_24H2.zip' `
                    -Target 'C:\WinISO\uupdump' -Verify 1 -Cleanup 1
```

---

#### `CreateUUPDiso`

**The central ISO creation function.** Runs `uup_download_windows.cmd` and monitors the
full conversion process until the ISO file appears on disk.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `UUPDdir` | `string` | **Yes** | — | UUPDump working directory (must exist, non-empty, **no spaces in path**) |
| `CleanUp` | `int` | No | `1` | `1` = delete all except ISO after creation |
| `ISOname` | `string` | No | `''` | New base name for the ISO (`.iso` extension auto-handled) |
| `SoftIdleMinutes` | `int` | No | `3` | Minutes before soft-idle warning |
| `HardIdleMinutes` | `int` | No | `30` | Minutes before hard-idle event |
| `GlobalTimeoutMinutes` | `int` | No | `360` | Absolute timeout (6 hours) |
| `PollSeconds` | `int` | No | `2` | Monitoring poll interval |
| `KillOnHardIdle` | `switch` | No | — | Kill process tree on hard-idle |

**Monitoring layers:**
1. Runtime log `LastWriteTime` (primary heartbeat)
2. `aria2_download.log` size (download phase)
3. **ISO-presence watch** — detects the ISO appearing on disk (improvement over original script)
4. Conversion-phase detection (WIM/ESD files, oscdimg keywords)
5. Auto-send `0` to stdin when completion prompt appears
6. Soft-idle warning / hard-idle kill
7. Global timeout safety net

> ⚠️ `UUPDdir` **must not contain spaces**. `uup_download_windows.cmd` cannot handle
> paths with spaces. Pre-existing `.iso` files in `UUPDdir` will cause the function to
> abort (required for clean ISO-presence monitoring).

```powershell
$r = CreateUUPDiso -UUPDdir 'C:\WinISO\uupdump' -CleanUp 1 -ISOname 'Win11_24H2_Pro'
if ($r.code -eq 0) { Write-Host "ISO: $($r.data)" }
```

---

#### `CleanupUUPDump`

Deletes all files and subdirectories from the UUPDump directory, keeping only `.iso` files.

```powershell
$r = CleanupUUPDump -UUPDdir 'C:\WinISO\uupdump'
```

---

#### `RenameUUPDiso`

Renames the single `.iso` file found in `UUPDdir`. Automatically handles `.iso` extension
in `ISOname`. Fails if 0 or more than 1 ISO file is found.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `UUPDdir` | `string` | **Yes** | UUPDump directory (must exist) |
| `ISOname` | `string` | **Yes** | New base name (without `.iso`; extension is auto-added) |

```powershell
$r = RenameUUPDiso -UUPDdir 'C:\WinISO\uupdump' -ISOname 'Win11_24H2_Pro_Custom'
```

---

#### `ExtractUUPDiso`

Mounts a UUPDump ISO and copies its entire contents to the target directory using
`robocopy /E /COPYALL`. Dismounts the ISO in a `finally` block (always, even on error).

| Parameter | Type | Required | Description |
|---|---|---|---|
| `UUPDiso` | `string` | **Yes** | Full path to the `.iso` file (must exist) |
| `Target` | `string` | **Yes** | Target directory (created if not present) |

```powershell
$r = ExtractUUPDiso -UUPDiso 'C:\WinISO\uupdump\Win11_24H2_Pro_Custom.iso' `
                    -Target 'C:\WinISO\DATA'
```

---

#### `GitHubDownload`

Downloads a single file from a public GitHub repository. Used internally by
`InitializeEnvironment` to download `oscdimg.exe`.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `URL` | `string` | **Yes** | GitHub URL (`github.com/blob/...` or `raw.githubusercontent.com`) |
| `SaveTo` | `string` | **Yes** | Full target path including filename |

---

### WIM Image Operations

---

#### `ImageIndexLookup`

Searches a WIM file for a Windows edition by name and returns its unique `ImageIndex`.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `WIMimage` | `string` | **Yes** | Full path to the `.wim` file (must exist) |
| `ImageLookup` | `string` | **Yes** | Case-insensitive edition name (e.g. `'Pro'`, `'Home'`) |

Fails with a descriptive error listing all available editions if the search is ambiguous
(multiple matches) or returns no results.

```powershell
$r = ImageIndexLookup -WIMimage 'C:\WinISO\DATA\sources\install.wim' -ImageLookup 'Pro'
if ($r.code -eq 0) { Write-Host "Pro edition index: $($r.data)" }
# On multiple matches: narrow down, e.g. -ImageLookup 'Windows 11 Pro'
```

---

#### `MountWIMimage`

Mounts a specific image index from a WIM file to a mount-point directory. Performs
post-mount verification via `Get-WindowsImage -Mounted`. Automatically attempts a
defensive `Dismount-WindowsImage -Discard` on any failure.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `WIMimage` | `string` | **Yes** | Full path to `.wim` file (must exist) |
| `IndexNo` | `int` | **Yes** | ImageIndex to mount (must exist in WIM) |
| `MountPoint` | `string` | **Yes** | Mount-point directory (must exist **and be empty**) |

```powershell
$r = MountWIMimage -WIMimage 'C:\WinISO\DATA\sources\install.wim' `
                   -IndexNo 6 -MountPoint 'C:\WinISO\MountPoint'
```

---

#### `UnMountWIMimage`

Dismounts an active WIM mount point with either `commit` (save changes) or `discard`
(revert changes). Verifies the mount-point is actually active before dismounting (via
`Get-WindowsImage -Mounted` + `dism.exe /Get-MountedWimInfo` fallback). Verifies full
dismount after completion.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `MountPoint` | `string` | **Yes** | Full path to active mount-point (must be mounted) |
| `Action` | `string` | **Yes** | `'commit'` \| `'discard'` |

```powershell
# Commit changes
$r = UnMountWIMimage -MountPoint 'C:\WinISO\MountPoint' -Action 'commit'

# Discard changes (e.g. after failed customisation)
$r = UnMountWIMimage -MountPoint 'C:\WinISO\MountPoint' -Action 'discard'
```

> If the dismount leaves the system in an inconsistent state, run:
> `dism /Cleanup-Wim`

---

## Private Functions

These functions are not exported and are only available within the module scope.

| Function | Description |
|---|---|
| `OPSreturn` | Creates standardised `PSCustomObject` return values (`code`, `msg`, `data`) |
| `Invoke-UUPRuntimeLog` | Creates/rotates the runtime log for `uup_download_windows.cmd` |
| `Get-UUPLogTail` | Efficiently reads the last N lines of a large log file |
| `Test-UUPConversionPhase` | Detects transition from download → conversion phase |
| `Invoke-UUPProcessKill` | Kills a process and its entire child tree via WMI |
| `Get-UUPNewestISO` | Finds the newest `.iso` file in a UUPDump working directory |

---

## Global Variables (Module Scope)

All variables live in `$script:` scope (module scope) and are accessible via `AppScope` or `WinISOcore`.

### `$script:appinfo`

```powershell
AppScope -KeyID 'appinfo'
# Returns hashtable:
@{
    AppName    = 'WinISOSciptFXLib'
    AppVers    = '1.02.00'
    AppDevName = 'Praetoriani'
    AppWebsite = 'https://github.com/praetoriani/PowerShell.Mods'
    DateCreate = '28.03.2026'
    LastUpdate = '29.03.2026'
}
```

### `$script:appenv`

```powershell
AppScope -KeyID 'appenv'
# Returns hashtable:
@{
    ISOroot    = 'C:\WinISO'
    ISOdata    = 'C:\WinISO\DATA'
    MountPoint = 'C:\WinISO\MountPoint'
    installwim = 'C:\WinISO\DATA\sources\install.wim'
    LogfileDir = 'C:\WinISO\Logfiles'
    AppxBundle = 'C:\WinISO\Appx'
    OEMDrivers = 'C:\WinISO\Drivers'
    OEMfolder  = 'C:\WinISO\OEM'
    ScratchDir = 'C:\WinISO\ScratchDir'
    TempFolder = 'C:\WinISO\temp'
    Downloads  = 'C:\WinISO\Downloads'
    UUPDumpDir = 'C:\WinISO\uupdump'
    OscdimgDir = 'C:\WinISO\Oscdimg'
    OscdimgExe = 'C:\WinISO\Oscdimg\oscdimg.exe'
}
```

> **Read-only access**: `AppScope -KeyID 'appenv'`
> **Type-safe write access**: `WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' -VarKeyID '<key>' -SetNewVal '<value>'`

---

## Typical Workflow

```powershell
#requires -RunAsAdministrator
Import-Module WinISO.ScriptFXLib

# 1. First-time setup: create directories and download oscdimg
InitializeEnvironment

# 2. Verify system requirements
$req = CheckModuleRequirements -Export 1
if ($req.code -ne 0) { throw "Requirements not met! See: $($req.msg)" }

# 3. Download the latest Win11 24H2 Pro UUP package
$dl = DownloadUUPDump -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' `
                      -Target 'C:\WinISO\uupdump\Win11_24H2.zip'

# 4. Extract the package
$ex = ExtractUUPDump -ZIPfile $dl.data -Target 'C:\WinISO\uupdump' -Verify 1 -Cleanup 1

# 5. Build the ISO (monitoring runs until ISO is complete)
$iso = CreateUUPDiso -UUPDdir 'C:\WinISO\uupdump' `
                     -CleanUp 1 -ISOname 'Win11_24H2_Pro_Custom'

# 6. Extract ISO contents to DATA directory
$ext = ExtractUUPDiso -UUPDiso $iso.data -Target 'C:\WinISO\DATA'

# 7. Find the 'Pro' edition index in install.wim
$idx = ImageIndexLookup -WIMimage 'C:\WinISO\DATA\sources\install.wim' -ImageLookup 'Pro'

# 8. Mount the WIM for customisation
$mnt = MountWIMimage -WIMimage 'C:\WinISO\DATA\sources\install.wim' `
                     -IndexNo $idx.data -MountPoint 'C:\WinISO\MountPoint'

# 9. ... perform customisations (DISM add-driver, add-package, etc.) ...

# 10. Commit changes and unmount
$unm = UnMountWIMimage -MountPoint 'C:\WinISO\MountPoint' -Action 'commit'
```

---

## Return Value Convention

All public functions (and `OPSreturn`) return a `PSCustomObject` with exactly three fields:

| Field | Type | Description |
|---|---|---|
| `.code` | `int` | `0` = success, `-1` = failure |
| `.msg` | `string` | Human-readable result or error description |
| `.data` | `any` | Return payload (path, index, hashtable, list, …) — `$null` on failure |

```powershell
$r = SomeFunction -Param 'value'
if ($r.code -eq 0) {
    Write-Host "Success: $($r.msg)"
    # use $r.data ...
} else {
    Write-Error "Error: $($r.msg)"
}
```

---

## Official Download Sources

| Component | Source | URL |
|---|---|---|
| **PowerShell 7.x** | GitHub Releases | [https://github.com/PowerShell/PowerShell/releases](https://github.com/PowerShell/PowerShell/releases) |
| **.NET Framework 4.8** | Microsoft | [https://dotnet.microsoft.com/en-us/download/dotnet-framework](https://dotnet.microsoft.com/en-us/download/dotnet-framework) |
| **Windows ADK** (includes oscdimg) | Microsoft | [https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) |
| **UUP Dump** | Web | [https://uupdump.net](https://uupdump.net) |
| **WinISO.ScriptFXLib** (this module) | GitHub | [https://github.com/praetoriani/PowerShell.Mods/tree/main/WinISO.ScriptFXLib](https://github.com/praetoriani/PowerShell.Mods/tree/main/WinISO.ScriptFXLib) |
| **PSAppCoreLib** (companion module) | GitHub | [https://github.com/praetoriani/PowerShell.Mods/tree/main/PSAppCoreLib](https://github.com/praetoriani/PowerShell.Mods/tree/main/PSAppCoreLib) |

---

*Module by [Praetoriani](https://github.com/praetoriani) — Licensed for personal and corporate use.*
