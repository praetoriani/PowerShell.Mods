# WinISO.ScriptFXLib

> **PowerShell module for fully automated Windows 11 ISO creation, customisation, and rebuilding**
> Using [UUP Dump](https://uupdump.net), DISM, and oscdimg.

[![Module Version](https://img.shields.io/badge/version-1.00.05-blue)](CHANGELOG.md)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-lightgrey)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/license-Personal%20%26%20Corporate%20Use-green)](LICENSE)

---

## Table of Contents

1. [Overview](#overview)
2. [Requirements & Dependencies](#requirements--dependencies)
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

**WinISO.ScriptFXLib** is a PowerShell module that provides a complete, fully automatable
pipeline for:

- Downloading the latest Windows 11 build package from **UUP Dump**
- Extracting and converting the package into a bootable ISO via `uup_download_windows.cmd`
- Mounting and customising the `install.wim` image (Appx packages, registry hives, drivers, …)
- **Adding and removing provisioned Appx / MSIX packages** from the offline image
- **Manipulating offline registry hives** without booting the target OS
- Rebuilding a final, bootable Windows 11 Setup ISO using `oscdimg.exe`

All public functions return a uniform `PSCustomObject { .code, .msg, .data }` result so they
integrate cleanly into larger automation pipelines.

> For a full function reference with parameters, examples, and module-scope internals,
> see **[DEVGUIDE.md](DEVGUIDE.md)**.
> For a full version history, see **[CHANGELOG.md](CHANGELOG.md)**.

---

## Requirements & Dependencies

### Software

| Dependency | Min. Version | Notes |
|---|---|---|
| **Windows OS** | Windows 10 / Windows 11 | — |
| **PowerShell** | 5.1 or 7.x+ | [PowerShell GitHub](https://github.com/PowerShell/PowerShell/releases) |
| **.NET Framework** | 4.7.2 (PS 5.x Desktop) | [Microsoft .NET](https://dotnet.microsoft.com/en-us/download/dotnet-framework/net472) |
| **DISM** | Windows 10 1809+ built-in | `%SystemRoot%\System32\dism.exe` |
| **DISM PowerShell module** | built-in | Ships with Windows |
| **robocopy.exe** | built-in | Ships with Windows |
| **oscdimg.exe** | ADK component | See [Further Reading](#further-reading) |

### Privileges

All DISM, ISO-mount, and UUP build operations **require administrator privileges**.
Add `#requires -RunAsAdministrator` to any calling script.

---

## Installation

```powershell
# 1. Clone the repository
git clone https://github.com/praetoriani/PowerShell.Mods.git

# 2. Copy the module to a module path
Copy-Item -Path '.\PowerShell.Mods\WinISO.ScriptFXLib' `
          -Destination "$env:ProgramFiles\WindowsPowerShell\Modules\WinISO.ScriptFXLib" `
          -Recurse -Force

# 3. Import
Import-Module WinISO.ScriptFXLib -Verbose

# 4. Run first-time environment setup
$r = InitializeEnvironment
if ($r.code -eq 0) { Write-Host "Environment ready." }
```

---

## Module Architecture

```
WinISO.ScriptFXLib\
├── WinISO.ScriptFXLib.psm1        ← Module root: scope initialisation + dot-source loader
├── WinISO.ScriptFXLib.psd1        ← Module manifest (version, exports, file list)
├── CHANGELOG.md                   ← Full version history
├── DEVGUIDE.md                    ← Developer reference (parameters, examples, internals)
├── README.md                      ← This file
│
├── Public\                        ← All exported functions (one file per function)
│   │
│   │   # Core / Infrastructure
│   ├── AppScope.ps1
│   ├── InitializeEnvironment.ps1
│   ├── VerifyEnvironment.ps1
│   ├── CheckModuleRequirements.ps1
│   ├── WinISOcore.ps1
│   ├── WriteLogMessage.ps1
│   │
│   │   # Download Helpers
│   ├── GitHubDownload.ps1
│   ├── GetLatestPowerShellSetup.ps1
│   │
│   │   # UUP Dump Workflow
│   ├── DownloadUUPDump.ps1
│   ├── GetUUPDumpPackage.ps1
│   ├── ExtractUUPDump.ps1
│   ├── CreateUUPDiso.ps1
│   ├── CleanupUUPDump.ps1
│   ├── RenameUUPDiso.ps1
│   ├── ExtractUUPDiso.ps1
│   │
│   │   # WIM Image Operations
│   ├── ImageIndexLookup.ps1
│   ├── MountWIMimage.ps1
│   ├── UnMountWIMimage.ps1
│   │
│   │   # Registry Hive Operations
│   ├── LoadRegistryHive.ps1
│   ├── UnloadRegistryHive.ps1
│   ├── RegistryHiveAdd.ps1
│   ├── RegistryHiveRem.ps1
│   ├── RegistryHiveImport.ps1
│   ├── RegistryHiveExport.ps1
│   ├── RegistryHiveQuery.ps1
│   │
│   │   # Appx / MSIX Package Operations
│   ├── GetAppxPackages.ps1
│   ├── RemAppxPackages.ps1
│   ├── AddAppxPackages.ps1
│   └── AppxPackageLookUp.ps1
│
└── Private\                       ← Internal helpers (not exported)
    ├── OPSreturn.ps1
    ├── Invoke-UUPRuntimeLog.ps1
    ├── Get-UUPLogTail.ps1
    ├── Test-UUPConversionPhase.ps1
    ├── Invoke-UUPProcessKill.ps1
    ├── Get-UUPNewestISO.ps1
    └── ValidateRegFile.ps1
```

The `.psm1` dot-sources **all** `Public\*.ps1` and `Private\*.ps1` files automatically.
No edits to `.psm1` are needed when adding new functions — place the `.ps1` in the correct
subfolder and add the name to `FunctionsToExport` in `.psd1`.

---

## Public Functions

### Core & Infrastructure

| Function | Description |
|---|---|
| `AppScope` | Read-only accessor for module-scope hashtables (`appinfo`, `appenv`, `appx`, …) |
| `InitializeEnvironment` | Creates the WinISO directory structure and downloads `oscdimg.exe` |
| `VerifyEnvironment` | Verifies all WinISO directories and required files are present |
| `CheckModuleRequirements` | Full system dependency audit (OS, PS, .NET, DISM, oscdimg, connectivity) |
| `WinISOcore` | Type-safe read/write accessor for all module-scope variables |
| `WriteLogMessage` | Structured log writer with timestamp and severity level |

### Download Helpers

| Function | Description |
|---|---|
| `GitHubDownload` | Downloads a single asset from a public GitHub repository |
| `GetLatestPowerShellSetup` | Fetches the latest PowerShell release from GitHub and installs it silently |

### UUP Dump Workflow

| Function | Description |
|---|---|
| `DownloadUUPDump` | Downloads a UUP Dump ZIP for a single edition (Pro / Home) |
| `GetUUPDumpPackage` | Downloads a UUP Dump ZIP for multiple / virtual editions (Pro, Enterprise, Education, …) |
| `ExtractUUPDump` | Extracts the UUP Dump ZIP to a target directory |
| `CreateUUPDiso` | Runs `uup_download_windows.cmd` with full multi-layer process monitoring |
| `CleanupUUPDump` | Removes all files from the UUPDump directory except the generated ISO |
| `RenameUUPDiso` | Renames the ISO file found in the UUPDump directory |
| `ExtractUUPDiso` | Mounts the ISO and copies all contents to a target directory via robocopy |

### WIM Image Operations

| Function | Description |
|---|---|
| `ImageIndexLookup` | Searches a WIM file for an edition by name and returns its `ImageIndex` |
| `MountWIMimage` | Mounts a WIM image index to a directory using DISM |
| `UnMountWIMimage` | Dismounts an active WIM mount with `commit` or `discard` |

### Registry Hive Operations

| Function | Description |
|---|---|
| `LoadRegistryHive` | Mounts one or all offline registry hives from the mounted WIM into the live registry |
| `UnloadRegistryHive` | Unloads previously loaded offline registry hives |
| `RegistryHiveAdd` | Adds a registry key and/or value to a loaded offline hive |
| `RegistryHiveRem` | Removes a registry key and/or value from a loaded offline hive |
| `RegistryHiveImport` | Imports a validated `.reg` file into a loaded offline hive |
| `RegistryHiveExport` | Exports a key branch from a loaded offline hive to a `.reg` file |
| `RegistryHiveQuery` | Queries keys and/or values from a loaded offline hive |

### Appx / MSIX Package Operations

| Function | Description |
|---|---|
| `GetAppxPackages` | Lists all provisioned Appx packages from a mounted WIM; stores results in `$script:appx['listed']`; optional TXT/CSV/JSON export |
| `RemAppxPackages` | Removes packages listed in `$script:appx['remove']` via DISM; self-cleaning monitoring (failed entries remain in scope) |
| `AddAppxPackages` | Injects packages listed in `$script:appx['inject']` via DISM; supports `.appx`, `.appxbundle`, `.msix`, `.msixbundle`; auto license / `/SkipLicense` |
| `AppxPackageLookUp` | Dual-mode verification: IMAGE mode (substring search in mounted WIM) + FILE mode (physical file check in Appx source directory) |

---

## Private Helpers

| Function | Description |
|---|---|
| `OPSreturn` | Creates standardised `{ .code, .msg, .data }` return objects |
| `Invoke-UUPRuntimeLog` | Creates/rotates the UUP Dump runtime log |
| `Get-UUPLogTail` | Reads the last N lines of a large log file efficiently |
| `Test-UUPConversionPhase` | Detects download → conversion phase transition |
| `Invoke-UUPProcessKill` | Kills a process and its entire child tree via WMI |
| `Get-UUPNewestISO` | Finds the newest `.iso` file in a UUPDump directory |
| `ValidateRegFile` | Validates `.reg` file syntax before import |

---

## Module Scope Variables

All module-scope variables are accessible read-only via `AppScope` and with type-safe write
access via `WinISOcore`. Key scopes:

| Variable | Key(s) | Purpose |
|---|---|---|
| `$script:appinfo` | `AppName`, `AppVers`, `AppDevName`, `AppWebsite`, `DateCreate`, `LastUpdate` | Module metadata |
| `$script:appenv` | `ISOroot`, `ISOdata`, `MountPoint`, `installwim`, `LogfileDir`, `AppxBundle`, `OEMDrivers`, `OEMfolder`, `ScratchDir`, `TempFolder`, `Downloads`, `UUPDumpDir`, `OscdimgDir`, `OscdimgExe` | Working directory paths |
| `$script:uupdump` | `ostype`, `osvers`, `osarch`, `edition`, `multiedition`, `buildno`, `kbsize`, `zipname` | UUP Dump download metadata |
| `$script:appverify` | `<CheckName>` → `PASS/FAIL/INFO/WARN`, `result` sub-hashtable | `CheckModuleRequirements` results |
| `$script:appx` | `listed` (array), `remove` (array), `inject` (array) | Appx package working lists |

For full schema details and usage examples, see **[DEVGUIDE.md](DEVGUIDE.md)**.

---

## Return Value Convention

Every public function returns a `PSCustomObject` with three fields:

| Field | Type | Meaning |
|---|---|---|
| `.code` | `int` | `0` = success, `-1` = failure |
| `.msg` | `string` | Human-readable result or error description |
| `.data` | any | Return payload — `$null` on failure |

```powershell
$r = SomeFunction -Param 'value'
if ($r.code -eq 0) {
    Write-Host "OK: $($r.msg)"
    # use $r.data ...
} else {
    Write-Error "FAIL: $($r.msg)"
}
```

---

## Typical Workflow

```powershell
#requires -RunAsAdministrator
Import-Module WinISO.ScriptFXLib

# 1. First-time setup
InitializeEnvironment

# 2. Check requirements
$req = CheckModuleRequirements -Export 1
if ($req.code -ne 0) { throw $req.msg }

# 3. Download Win11 24H2 Pro ISO package
$dl = DownloadUUPDump -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' `
                      -Target 'C:\WinISO\uupdump\Win11_24H2.zip'

# 4. Extract + build ISO
ExtractUUPDump -ZIPfile $dl.data -Target 'C:\WinISO\uupdump' -Verify 1 -Cleanup 1
$iso = CreateUUPDiso -UUPDdir 'C:\WinISO\uupdump' -CleanUp 1 -ISOname 'Win11_24H2_Pro'

# 5. Extract ISO → DATA directory, mount WIM
ExtractUUPDiso -UUPDiso $iso.data -Target 'C:\WinISO\DATA'
$idx = ImageIndexLookup -WIMimage 'C:\WinISO\DATA\sources\install.wim' -ImageLookup 'Pro'
MountWIMimage -WIMimage 'C:\WinISO\DATA\sources\install.wim' `
              -IndexNo $idx.data -MountPoint 'C:\WinISO\MountPoint'

# 6. List provisioned Appx packages
$pkgs = GetAppxPackages -ExportFile 'C:\WinISO\Logfiles\appx-packages.csv' -Format CSV

# 7. Remove unwanted packages (populate $script:appx['remove'] first)
WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' -VarKeyID 'remove' `
           -SetNewVal @( [PSCustomObject]@{ PackageName = 'Microsoft.BingWeather_...' } )
RemAppxPackages -ContinueOnError

# 8. Commit and unmount
UnMountWIMimage -MountPoint 'C:\WinISO\MountPoint' -Action 'commit'
```

> For the complete Registry Hive workflow, Appx injection examples, and `AppxPackageLookUp`
> usage, refer to **[DEVGUIDE.md](DEVGUIDE.md)**.

---

## Further Reading

| Resource | Link |
|---|---|
| **Developer Guide** (full function reference) | [DEVGUIDE.md](DEVGUIDE.md) |
| **Changelog** (version history) | [CHANGELOG.md](CHANGELOG.md) |
| **PowerShell Releases** | [github.com/PowerShell/PowerShell/releases](https://github.com/PowerShell/PowerShell/releases) |
| **.NET Framework 4.8** | [dotnet.microsoft.com](https://dotnet.microsoft.com/en-us/download/dotnet-framework) |
| **Windows ADK** (includes oscdimg) | [learn.microsoft.com/windows-hardware/get-started/adk-install](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) |
| **UUP Dump** | [uupdump.net](https://uupdump.net) |
| **WinISO.ScriptFXLib on GitHub** | [github.com/praetoriani/PowerShell.Mods/tree/main/WinISO.ScriptFXLib](https://github.com/praetoriani/PowerShell.Mods/tree/main/WinISO.ScriptFXLib) |

---

*Module by [Praetoriani](https://github.com/praetoriani) — Licensed for personal and corporate use.*
