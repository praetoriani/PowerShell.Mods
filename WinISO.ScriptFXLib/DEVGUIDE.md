# DEVGUIDE — WinISO.ScriptFXLib

> **Developer Reference** — complete function documentation, parameter tables, usage examples,
> module-scope internals, and architectural notes.
> Module version: **1.00.05**

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Module Scope Variables](#module-scope-variables)
3. [Return Value Convention](#return-value-convention)
4. [Core & Infrastructure](#core--infrastructure)
   - [AppScope](#appscope)
   - [InitializeEnvironment](#initializeenvironment)
   - [VerifyEnvironment](#verifyenvironment)
   - [CheckModuleRequirements](#checkmodulerequirements)
   - [WinISOcore](#winisocore)
   - [WriteLogMessage](#writelogmessage)
5. [Download Helpers](#download-helpers)
   - [GitHubDownload](#githubdownload)
   - [GetLatestPowerShellSetup](#getlatestpowershellsetup)
6. [UUP Dump Workflow](#uup-dump-workflow)
   - [DownloadUUPDump](#downloaduupdump)
   - [GetUUPDumpPackage](#getuupdumppackage)
   - [ExtractUUPDump](#extractuupdump)
   - [CreateUUPDiso](#createuupdiso)
   - [CleanupUUPDump](#cleanupuupdump)
   - [RenameUUPDiso](#renameuupdiso)
   - [ExtractUUPDiso](#extractuupdiso)
7. [WIM Image Operations](#wim-image-operations)
   - [ImageIndexLookup](#imageindexlookup)
   - [MountWIMimage](#mountwimimage)
   - [UnMountWIMimage](#unmountwimimage)
8. [Registry Hive Operations](#registry-hive-operations)
   - [LoadRegistryHive](#loadregistryhive)
   - [UnloadRegistryHive](#unloadregistryhive)
   - [RegistryHiveAdd](#registryhiveadd)
   - [RegistryHiveRem](#registryhivarem)
   - [RegistryHiveImport](#registryhiveimport)
   - [RegistryHiveExport](#registryhiveexport)
   - [RegistryHiveQuery](#registryhivequery)
9. [Appx / MSIX Package Operations](#appx--msix-package-operations)
   - [GetAppxPackages](#getappxpackages)
   - [RemAppxPackages](#remappxpackages)
   - [AddAppxPackages](#addappxpackages)
   - [AppxPackageLookUp](#appxpackagelookup)
10. [Private Helpers](#private-helpers)

---

## Architecture Overview

```
WinISO.ScriptFXLib\
├── WinISO.ScriptFXLib.psm1    ← Module root: scope init + auto dot-source loader
├── WinISO.ScriptFXLib.psd1    ← Manifest: version, exports, file list, release notes
├── README.md                  ← Quick start and function overview
├── DEVGUIDE.md                ← This file
├── CHANGELOG.md               ← Full version history
├── Public\                    ← Exported functions (one file per function)
└── Private\                   ← Internal helpers (not exported)
```

The `.psm1` dot-sources every `Public\*.ps1` and `Private\*.ps1` file automatically on
import. To add a new function, drop a `.ps1` in the correct folder and add its name to
`FunctionsToExport` in the `.psd1`. No changes to `.psm1` are required.

---

## Module Scope Variables

All variables live in `$script:` (module scope). They are read via `AppScope` and written
via `WinISOcore`.

### `$script:appinfo`

Module metadata. Read-only in normal usage.

```powershell
$info = AppScope -KeyID 'appinfo'
# Keys: AppName | AppVers | AppDevName | AppWebsite | DateCreate | LastUpdate
Write-Host $info['AppVers']   # e.g. 1.00.05
```

### `$script:appenv`

Working directory paths populated by `InitializeEnvironment`.

| Key | Default Value |
|---|---|
| `ISOroot` | `C:\WinISO` |
| `ISOdata` | `C:\WinISO\DATA` |
| `MountPoint` | `C:\WinISO\MountPoint` |
| `installwim` | `C:\WinISO\DATA\sources\install.wim` |
| `LogfileDir` | `C:\WinISO\Logfiles` |
| `AppxBundle` | `C:\WinISO\Appx` |
| `OEMDrivers` | `C:\WinISO\Drivers` |
| `OEMfolder` | `C:\WinISO\OEM` |
| `ScratchDir` | `C:\WinISO\ScratchDir` |
| `TempFolder` | `C:\WinISO\temp` |
| `Downloads` | `C:\WinISO\Downloads` |
| `UUPDumpDir` | `C:\WinISO\uupdump` |
| `OscdimgDir` | `C:\WinISO\Oscdimg` |
| `OscdimgExe` | `C:\WinISO\Oscdimg\oscdimg.exe` |

```powershell
# Read-only
$env = AppScope -KeyID 'appenv'
Write-Host $env['MountPoint']

# Type-safe write
WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' `
           -VarKeyID 'MountPoint' -SetNewVal 'D:\WIM\MountPoint'
```

### `$script:uupdump`

UUP Dump download metadata populated by `DownloadUUPDump` / `GetUUPDumpPackage`.

| Key | Description |
|---|---|
| `ostype` | `'Windows11'` |
| `osvers` | `'24H2'` / `'25H2'` |
| `osarch` | `'amd64'` / `'arm64'` |
| `edition` | `'Pro'` / `'Home'` (single-edition only; empty for multi-edition) |
| `multiedition` | Semicolon-joined edition names (multi-edition only; empty for single) |
| `buildno` | Actual build number, e.g. `'26100.3476'` |
| `kbsize` | Estimated download size in KB |
| `zipname` | ZIP file name as returned by uupdump.net |

### `$script:appverify`

`CheckModuleRequirements` result store. One key per check name + a `result` sub-hashtable.

```powershell
$av = AppScope -KeyID 'appverify'
$av['DISM']        # 'PASS' | 'FAIL' | 'INFO' | 'WARN'
$av['result']      # @{ pass=N; fail=N; info=N; warn=N }
```

Status meanings:

| Status | Meaning |
|---|---|
| `PASS` | Check succeeded |
| `INFO` | Issue present but automatically resolvable (e.g. run `InitializeEnvironment`) |
| `WARN` | Issue requires manual user action (e.g. re-run elevated, upgrade PS) |
| `FAIL` | Hard failure — no automated fix available |

### `$script:appx`

Appx package working lists. Used by all four Appx functions.

| Key | Type | Purpose |
|---|---|---|
| `listed` | `PSCustomObject[]` | Output of `GetAppxPackages` — all provisioned packages in the image |
| `remove` | `PSCustomObject[]` | Packages to remove via `RemAppxPackages` |
| `inject` | `PSCustomObject[]` | Packages to inject via `AddAppxPackages` |

Each entry in `listed` / `remove`:

```powershell
[PSCustomObject]@{
    DisplayName  = 'Microsoft.BingWeather'
    PackageName  = 'Microsoft.BingWeather_4.53.51241.0_neutral~...'
    Version      = '4.53.51241.0'
    Architecture = 'neutral'
    PublisherId  = '8wekyb3d8bbwe'
}
```

Each entry in `inject`:

```powershell
[PSCustomObject]@{
    PackageFile  = 'MyApp.msixbundle'      # filename only — resolved from AppxBundle dir
    LicenseFile  = 'MyApp_License.xml'     # optional; /SkipLicense used if absent
}
```

---

## Return Value Convention

Every public function returns:

```powershell
[PSCustomObject]@{
    code = 0       # int:    0 = success | -1 = failure
    msg  = '...'   # string: human-readable result or error message
    data = ...     # any:    return payload | $null on failure
}
```

Standard error check pattern:

```powershell
$r = SomeFunction -Param 'value'
if ($r.code -ne 0) {
    Write-Error "FAIL: $($r.msg)"
    return
}
# Use $r.data ...
```

---

## Core & Infrastructure

---

### `AppScope`

Read-only accessor that returns a live reference to a module-scope hashtable.
Because it returns a reference (not a copy), mutations to the returned hashtable are
immediately visible module-wide. Use `WinISOcore` for validated write access.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `KeyID` | `string` | **Yes** | `'appinfo'` \| `'appenv'` \| `'uupdump'` \| `'appverify'` \| `'appx'` \| `'appexit'` |

**Returns**: live `[hashtable]` reference on success, `PSCustomObject { code=-1 }` on unknown key.

```powershell
$env  = AppScope -KeyID 'appenv'
$appx = AppScope -KeyID 'appx'
Write-Host $env['ISOroot']                    # C:\WinISO
Write-Host ($appx['listed'].Count)            # number of listed packages
```

---

### `InitializeEnvironment`

Creates the complete WinISO working directory structure under `C:\WinISO` and downloads
`oscdimg.exe` via `GitHubDownload`. Must be run once before using any other functions.

**Parameters**: none.

**Returns**: `.data = $null`.

```powershell
$r = InitializeEnvironment
if ($r.code -eq 0) {
    Write-Host "All directories created. oscdimg.exe downloaded."
}
```

---

### `VerifyEnvironment`

Checks that all WinISO directories (from `$script:appenv`) exist on disk.

**Parameters**: none.

**Returns**: `.data = [array] of missing directory paths` (empty array = all present).

```powershell
$r = VerifyEnvironment
if ($r.code -ne 0) {
    Write-Warning "Missing: $($r.data -join ', ')"
    InitializeEnvironment
}
```

---

### `CheckModuleRequirements`

Full system dependency audit. Checks OS, PowerShell version, .NET Framework, DISM
availability, robocopy, oscdimg, all WinISO directories, and internet connectivity.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `Export` | `int` | No | `0` | `1` = write results to `<LogfileDir>\WinISO.ScriptFXLib.Requirements.Result.txt` |

**Returns**: `.data = [List[PSCustomObject]]` — each entry has `CheckName`, `Status` (`PASS`/`FAIL`/`INFO`/`WARN`), `Detail`.

```powershell
$r = CheckModuleRequirements -Export 1
if ($r.code -eq 0) {
    $r.data | Format-Table CheckName, Status, Detail -AutoSize
    $summary = (AppScope -KeyID 'appverify')['result']
    Write-Host "PASS:$($summary['pass'])  INFO:$($summary['info'])  WARN:$($summary['warn'])  FAIL:$($summary['fail'])"
}
```

> `code = 0` means no `FAIL` was found. `INFO` and `WARN` statuses do not prevent success.

---

### `WinISOcore`

Type-safe read/write accessor for all module-scope variables. Enforces type matching on
write operations — the new value type must match the existing key type exactly.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `Scope` | `string` | **Yes** | — | `'env'` (only supported scope) |
| `GlobalVar` | `string` | No | `''` | `'appinfo'` \| `'appenv'` \| `'uupdump'` \| `'appverify'` \| `'appx'` \| `'appexit'` |
| `Permission` | `string` | **Yes** | `'read'` | `'read'` \| `'write'` |
| `VarKeyID` | `string` | No | `''` | Key to update (write mode only; key must already exist) |
| `SetNewVal` | any | No | `$null` | New value (write mode only; type must match existing) |

**Returns**: on read — `.data = [hashtable]`. On write — `.data = $null`, `.code = 0` on success.

```powershell
# Read
$r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'read'
Write-Host $r.data['ISOroot']

# Write (type-safe string update)
$r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' `
                -VarKeyID 'MountPoint' -SetNewVal 'D:\WIM\MountPoint'

# Write appx 'remove' list
$r = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
                -VarKeyID 'remove' -SetNewVal @(
                    [PSCustomObject]@{ PackageName = 'Microsoft.BingWeather_...' }
                )

# Type mismatch → fails gracefully
$r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' `
                -VarKeyID 'MountPoint' -SetNewVal 42   # $r.code -eq -1
```

---

### `WriteLogMessage`

Structured log writer. Appends a formatted entry to the WinISO log file.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Level` | `string` | **Yes** | `'INFO'` \| `'WARN'` \| `'ERROR'` \| `'DEBUG'` |
| `Message` | `string` | **Yes** | Log message text |

```powershell
WriteLogMessage -Level 'INFO'  -Message 'ISO creation started.'
WriteLogMessage -Level 'WARN'  -Message 'Soft-idle detected — process still running.'
WriteLogMessage -Level 'ERROR' -Message "DISM failed with exit code $($r.code)"
```

---

## Download Helpers

---

### `GitHubDownload`

Downloads a single file from a public GitHub repository.
Converts `github.com/blob/...` URLs to `raw.githubusercontent.com` download URLs automatically.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `URL` | `string` | **Yes** | GitHub file URL (blob or raw) |
| `SaveTo` | `string` | **Yes** | Full target path including filename |

```powershell
$r = GitHubDownload `
    -URL    'https://github.com/praetoriani/PowerShell.Mods/blob/main/Tools/oscdimg.exe' `
    -SaveTo 'C:\WinISO\Oscdimg\oscdimg.exe'
```

---

### `GetLatestPowerShellSetup`

Resolves the latest stable PowerShell release from the GitHub Releases API and downloads
the `.msi` installer. Optionally installs silently.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `Architecture` | `string` | No | `'x64'` | `'x64'` \| `'x86'` \| `'arm64'` |
| `SaveTo` | `string` | No | `$script:appenv['Downloads']` | Full path for the downloaded `.msi` |
| `Install` | `switch` | No | — | Silent install after download |

**Returns**: `.data = [string] path to downloaded .msi`.

```powershell
# Download only
$r = GetLatestPowerShellSetup -Architecture 'x64'
Write-Host "Downloaded: $($r.data)"

# Download and install silently
$r = GetLatestPowerShellSetup -Architecture 'x64' -Install
```

---

## UUP Dump Workflow

---

### `DownloadUUPDump`

Downloads a UUP Dump package ZIP from `uupdump.net` for a single Windows edition.
Stores metadata in `$script:uupdump` on success.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `OStype` | `string` | **Yes** | — | `'Windows11'` |
| `OSvers` | `string` | **Yes** | — | `'24H2'` \| `'25H2'` |
| `OSarch` | `string` | **Yes** | — | `'amd64'` \| `'arm64'` |
| `Edition` | `string` | No | `'Pro'` | `'Pro'` \| `'Home'` |
| `BuildNo` | `string` | No | `''` | Specific build in `'NNNNN.NNNN'` format |
| `Target` | `string` | **Yes** | — | Full path to the destination ZIP file |
| `IncludeNetFX` | `switch` | No | *(default on)* | Include .NET Framework |
| `ExcludeNetFX` | `switch` | No | — | Exclude .NET Framework (mutually exclusive) |
| `UseESD` | `switch` | No | — | Request `install.esd` instead of `install.wim` |

**Returns**: `.data = [string] path to downloaded ZIP`.

```powershell
# Latest 24H2 Pro build
$r = DownloadUUPDump -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' `
                     -Target 'C:\WinISO\uupdump\Win11_24H2.zip'

# Specific build, Home edition, no NetFX
$r = DownloadUUPDump -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' `
                     -Edition 'Home' -BuildNo '26100.3476' -ExcludeNetFX `
                     -Target 'C:\WinISO\uupdump\Win11_24H2_Home.zip'
```

---

### `GetUUPDumpPackage`

Downloads a UUP Dump package ZIP for **multiple / virtual editions** in one package.
Uses `autodl=3` mode from uupdump.net.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `OSvers` | `string` | **Yes** | — | `'24H2'` \| `'25H2'` |
| `OSarch` | `string` | **Yes** | — | `'amd64'` \| `'arm64'` |
| `Editions` | `string[]` | **Yes** | — | One or more of: `ProWorkstations`, `ProEducation`, `Education`, `Enterprise`, `IoTEnterprise` |
| `BuildNo` | `string` | No | `''` | Specific build in `'NNNNN.NNNN'` format |
| `Target` | `string` | **Yes** | — | Full path to the destination ZIP file |
| `IncludeNetFX` | `switch` | No | *(default on)* | Include .NET Framework |
| `ExcludeNetFX` | `switch` | No | — | Exclude .NET Framework |
| `UseESD` | `switch` | No | — | Request ESD instead of WIM |

```powershell
$r = GetUUPDumpPackage -OSvers '24H2' -OSarch 'amd64' `
                       -Editions @('Enterprise', 'Education', 'ProWorkstations') `
                       -Target 'C:\WinISO\uupdump\Win11_24H2_Multi.zip'
```

---

### `ExtractUUPDump`

Extracts a UUP Dump ZIP archive to a target directory.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `ZIPfile` | `string` | **Yes** | — | Full path to the ZIP (must exist) |
| `Target` | `string` | **Yes** | — | Destination directory (created if absent) |
| `Verify` | `int` | **Yes** | `1` | `1` = verify entry count post-extraction |
| `Cleanup` | `int` | **Yes** | `0` | `1` = delete ZIP after successful extraction |

```powershell
$r = ExtractUUPDump -ZIPfile 'C:\WinISO\uupdump\Win11_24H2.zip' `
                    -Target 'C:\WinISO\uupdump' -Verify 1 -Cleanup 1
```

---

### `CreateUUPDiso`

**The central ISO creation function.** Runs `uup_download_windows.cmd` and monitors the
full process with seven independent monitoring layers until the ISO file appears on disk.

> **Important**: `UUPDdir` must **not contain spaces**. The UUP batch script cannot
> handle paths with spaces. Any pre-existing `.iso` files in `UUPDdir` will cause the
> function to abort immediately (required for clean ISO-presence monitoring).

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `UUPDdir` | `string` | **Yes** | — | UUPDump working directory |
| `CleanUp` | `int` | No | `1` | `1` = delete all except ISO after creation |
| `ISOname` | `string` | No | `''` | New base name for the ISO (`.iso` extension handled automatically) |
| `SoftIdleMinutes` | `int` | No | `3` | Minutes before soft-idle warning |
| `HardIdleMinutes` | `int` | No | `30` | Minutes before hard-idle event |
| `GlobalTimeoutMinutes` | `int` | No | `360` | Absolute process timeout |
| `PollSeconds` | `int` | No | `2` | Monitoring poll interval in seconds |
| `KillOnHardIdle` | `switch` | No | — | Kill process tree on hard-idle detection |

**Returns**: `.data = [string] full path to the generated ISO`.

```powershell
$r = CreateUUPDiso -UUPDdir 'C:\WinISO\uupdump' `
                   -CleanUp 1 `
                   -ISOname 'Win11_24H2_Pro_Custom' `
                   -KillOnHardIdle
if ($r.code -eq 0) {
    Write-Host "ISO ready: $($r.data)"
}
```

---

### `CleanupUUPDump`

Removes all files and subdirectories from the UUPDump directory, retaining only `.iso` files.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `UUPDdir` | `string` | **Yes** | UUPDump working directory |

```powershell
$r = CleanupUUPDump -UUPDdir 'C:\WinISO\uupdump'
```

---

### `RenameUUPDiso`

Renames the single `.iso` file found in `UUPDdir`. Fails if 0 or >1 ISO files exist.
`.iso` extension in `ISOname` is handled automatically.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `UUPDdir` | `string` | **Yes** | UUPDump working directory |
| `ISOname` | `string` | **Yes** | New base name (`.iso` extension auto-handled) |

```powershell
$r = RenameUUPDiso -UUPDdir 'C:\WinISO\uupdump' -ISOname 'Win11_24H2_Pro_Custom'
```

---

### `ExtractUUPDiso`

Mounts a UUPDump ISO using `Mount-DiskImage` and copies all contents to a target directory
via `robocopy /E /COPYALL /R:3 /W:5`. The ISO is always dismounted in a `finally` block.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `UUPDiso` | `string` | **Yes** | Full path to the `.iso` file (must exist) |
| `Target` | `string` | **Yes** | Destination directory (created if absent) |

```powershell
$r = ExtractUUPDiso -UUPDiso 'C:\WinISO\uupdump\Win11_24H2_Pro_Custom.iso' `
                    -Target 'C:\WinISO\DATA'
```

---

## WIM Image Operations

---

### `ImageIndexLookup`

Searches a WIM file for a Windows edition by name (case-insensitive substring match) and
returns its unique `ImageIndex`. Fails with a descriptive listing of all available editions
if the result is ambiguous (multiple matches).

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `WIMimage` | `string` | **Yes** | Full path to the `.wim` file (must exist) |
| `ImageLookup` | `string` | **Yes** | Edition name or fragment, e.g. `'Pro'`, `'Home'`, `'Windows 11 Pro'` |

**Returns**: `.data = [int] ImageIndex`.

```powershell
$r = ImageIndexLookup -WIMimage 'C:\WinISO\DATA\sources\install.wim' -ImageLookup 'Pro'
if ($r.code -eq 0) {
    Write-Host "Windows 11 Pro is at index $($r.data)"
}

# If 'Pro' matches multiple editions, narrow it down:
$r = ImageIndexLookup -WIMimage '...\install.wim' -ImageLookup 'Windows 11 Pro'
```

---

### `MountWIMimage`

Mounts a specific image index from a WIM file to a mount-point directory using
`Mount-WindowsImage`. Performs post-mount verification via `Get-WindowsImage -Mounted`.
On any failure, automatically attempts a defensive `Dismount-WindowsImage -Discard`.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `WIMimage` | `string` | **Yes** | Full path to the `.wim` file |
| `IndexNo` | `int` | **Yes** | ImageIndex to mount (must exist in WIM) |
| `MountPoint` | `string` | **Yes** | Mount-point directory (must exist and be **empty**) |

```powershell
$r = MountWIMimage -WIMimage 'C:\WinISO\DATA\sources\install.wim' `
                   -IndexNo 6 `
                   -MountPoint 'C:\WinISO\MountPoint'
if ($r.code -eq 0) {
    Write-Host "WIM mounted at C:\WinISO\MountPoint"
}
```

---

### `UnMountWIMimage`

Dismounts an active WIM mount point. Verifies the mount is active before dismounting,
then verifies full release after dismounting.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `MountPoint` | `string` | **Yes** | Full path to the active mount-point directory |
| `Action` | `string` | **Yes** | `'commit'` (save changes) \| `'discard'` (revert changes) |

```powershell
# Save all customisations
$r = UnMountWIMimage -MountPoint 'C:\WinISO\MountPoint' -Action 'commit'

# Discard all changes
$r = UnMountWIMimage -MountPoint 'C:\WinISO\MountPoint' -Action 'discard'
```

> If a dismount leaves the system in an inconsistent state, run `dism /Cleanup-Wim`
> from an elevated prompt.

---

## Registry Hive Operations

---

### `LoadRegistryHive`

Mounts one or all offline registry hives from the mounted WIM image into the live registry
using `reg.exe load`. Mount points follow the `HKLM\WinISO_<HiveName>` convention.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `MountPoint` | `string` | No | `$script:appenv['MountPoint']` | WIM mount-point directory |
| `HiveName` | `string` | **Yes** | — | `'SYSTEM'` \| `'SOFTWARE'` \| `'DEFAULT'` \| `'SAM'` \| `'SECURITY'` \| `'ALL'` |

```powershell
# Load only SOFTWARE hive
$r = LoadRegistryHive -HiveName 'SOFTWARE'

# Load all hives at once
$r = LoadRegistryHive -HiveName 'ALL'
```

---

### `UnloadRegistryHive`

Unloads one or all previously loaded offline registry hives from the live registry.
Flushes the live registry before unloading to prevent data loss.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `HiveName` | `string` | **Yes** | `'SYSTEM'` \| `'SOFTWARE'` \| `'DEFAULT'` \| `'SAM'` \| `'SECURITY'` \| `'ALL'` |

```powershell
$r = UnloadRegistryHive -HiveName 'SOFTWARE'
$r = UnloadRegistryHive -HiveName 'ALL'
```

---

### `RegistryHiveAdd`

Adds a registry key and/or value to a loaded offline registry hive.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `HiveName` | `string` | **Yes** | Target hive (`SYSTEM`, `SOFTWARE`, …) |
| `KeyPath` | `string` | **Yes** | Sub-path within the hive |
| `ValueName` | `string` | No | Registry value name (omit to create key only) |
| `ValueType` | `string` | No | `REG_SZ` \| `REG_EXPAND_SZ` \| `REG_DWORD` \| `REG_QWORD` \| `REG_BINARY` \| `REG_MULTI_SZ` |
| `ValueData` | `string` | No | Value data as string |

```powershell
# Create a key only
$r = RegistryHiveAdd -HiveName 'SOFTWARE' `
                     -KeyPath 'SOFTWARE\MyCompany\Settings'

# Add a DWORD value
$r = RegistryHiveAdd -HiveName 'SOFTWARE' `
                     -KeyPath 'SOFTWARE\MyCompany\Settings' `
                     -ValueName 'EnableFeature' `
                     -ValueType 'REG_DWORD' `
                     -ValueData '1'
```

---

### `RegistryHiveRem`

Removes a registry key or value from a loaded offline registry hive.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `HiveName` | `string` | **Yes** | Target hive |
| `KeyPath` | `string` | **Yes** | Sub-path within the hive |
| `ValueName` | `string` | No | Value name to remove (omit with `-RemoveKey` to delete entire key) |
| `RemoveKey` | `switch` | No | Delete the entire key tree instead of a single value |

```powershell
# Remove a single value
$r = RegistryHiveRem -HiveName 'SOFTWARE' `
                     -KeyPath 'SOFTWARE\MyCompany\Settings' `
                     -ValueName 'EnableFeature'

# Delete entire key tree
$r = RegistryHiveRem -HiveName 'SOFTWARE' `
                     -KeyPath 'SOFTWARE\MyCompany\Settings' `
                     -RemoveKey
```

---

### `RegistryHiveImport`

Imports a `.reg` file into a loaded offline registry hive via `reg.exe import`.
Calls `ValidateRegFile` before import.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `HiveName` | `string` | **Yes** | Target hive |
| `RegFile` | `string` | **Yes** | Full path to the `.reg` file (must exist and pass validation) |

```powershell
$r = RegistryHiveImport -HiveName 'SOFTWARE' `
                        -RegFile 'C:\WinISO\OEM\MySettings.reg'
```

---

### `RegistryHiveExport`

Exports a registry key branch from a loaded offline hive to a `.reg` file.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `HiveName` | `string` | **Yes** | Source hive |
| `KeyPath` | `string` | **Yes** | Sub-path within the hive |
| `ExportFile` | `string` | **Yes** | Full path for the output `.reg` file |

```powershell
$r = RegistryHiveExport -HiveName 'SOFTWARE' `
                        -KeyPath 'SOFTWARE\MyCompany' `
                        -ExportFile 'C:\WinISO\Logfiles\MyCompany_backup.reg'
```

---

### `RegistryHiveQuery`

Queries registry keys and/or values from a loaded offline hive.

**Parameters**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `HiveName` | `string` | **Yes** | Source hive |
| `KeyPath` | `string` | **Yes** | Sub-path within the hive |
| `ValueName` | `string` | No | Specific value name to query (omit to query all values under key) |

**Returns**: `.data = [array of PSCustomObject]` — each entry: `ValueName`, `ValueType`, `ValueData`.

```powershell
$r = RegistryHiveQuery -HiveName 'SOFTWARE' `
                       -KeyPath 'SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$r.data | Format-Table ValueName, ValueType, ValueData -AutoSize
```

---

## Appx / MSIX Package Operations

The four Appx functions form an integrated sub-system. The recommended workflow is:

1. **`GetAppxPackages`** — populate `$script:appx['listed']` with all current packages.
2. **`AppxPackageLookUp`** — verify that a package is present / a file is ready.
3. **`RemAppxPackages`** — remove packages from `$script:appx['remove']`.
4. **`AddAppxPackages`** — inject packages from `$script:appx['inject']`.

---

### `GetAppxPackages`

Lists all provisioned Appx packages from a mounted WIM image using `Get-AppxProvisionedPackage`.
Always stores results in `$script:appx['listed']`. Optionally exports to TXT / CSV / JSON.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `MountPoint` | `string` | No | `$script:appenv['MountPoint']` | WIM mount-point directory |
| `ExportFile` | `string` | No | `''` | Full path (incl. filename) for the export file |
| `Format` | `string` | No | `'TXT'` | `'TXT'` \| `'CSV'` \| `'JSON'` — only used when `-ExportFile` is provided |

**Returns**: `.data = [PSCustomObject[]]` — each entry: `DisplayName`, `PackageName`, `Version`, `Architecture`, `PublisherId`.

```powershell
# Virtual only — store in $script:appx['listed']
$r = GetAppxPackages
$r.data | Select-Object DisplayName, PackageName | Format-Table -AutoSize

# Virtual + export as CSV
$r = GetAppxPackages -ExportFile 'C:\WinISO\Logfiles\appx-packages.csv' -Format CSV

# Custom mount point, export as JSON
$r = GetAppxPackages -MountPoint 'D:\WIM\MountPoint' `
                     -ExportFile 'C:\WinISO\Logfiles\appx-packages.json' `
                     -Format JSON
```

---

### `RemAppxPackages`

Removes all packages listed in `$script:appx['remove']` from a mounted WIM image.
Each entry must have a `PackageName` property (full provisioned package name string).

**Monitoring behaviour**: after each successful DISM call, the entry is removed from
`$script:appx['remove']`. At completion, only failed entries remain in scope —
an empty `remove` array means a fully clean run.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `MountPoint` | `string` | No | `$script:appenv['MountPoint']` | WIM mount-point directory |
| `ContinueOnError` | `switch` | No | — | Continue processing despite individual DISM failures |

**Returns**: `.data = @{ Succeeded=[array]; Failed=[array] }`.

```powershell
# Step 1: populate the remove list
WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
           -VarKeyID 'remove' -SetNewVal @(
               [PSCustomObject]@{ PackageName = 'Microsoft.BingWeather_4.53.51241.0_neutral~...' }
               [PSCustomObject]@{ PackageName = 'Microsoft.BingNews_4.2.27001.0_neutral~...'    }
           )

# Step 2: remove (abort on first failure)
$r = RemAppxPackages

# Step 2 alternative: continue even if individual packages fail
$r = RemAppxPackages -ContinueOnError

# Step 3: check results
if ($r.code -eq 0) {
    Write-Host "All removed. $($r.data.Succeeded.Count) packages."
} else {
    Write-Warning "Some failed: $($r.data.Failed.Count) remaining in scope."
    $r.data.Failed | ForEach-Object { Write-Host $_.PackageName }
}
```

**Tip — find package names from the listed cache:**

```powershell
GetAppxPackages | Out-Null
$pkgToRemove = (AppScope -KeyID 'appx')['listed'] |
               Where-Object { $_.DisplayName -like '*Bing*' }
WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
           -VarKeyID 'remove' -SetNewVal $pkgToRemove
RemAppxPackages -ContinueOnError
```

---

### `AddAppxPackages`

Injects all packages listed in `$script:appx['inject']` into a mounted WIM image.
Each entry must have a `PackageFile` property (filename only; resolved against `-AppxSourceDir`).
An optional `LicenseFile` property is used per entry; `/SkipLicense` is applied if absent.

**Monitoring behaviour**: after each successful DISM call, the entry is removed from
`$script:appx['inject']`. At completion, only failed entries remain in scope.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `MountPoint` | `string` | No | `$script:appenv['MountPoint']` | WIM mount-point directory |
| `AppxSourceDir` | `string` | No | `$script:appenv['AppxBundle']` | Directory containing the Appx / MSIX files |
| `ContinueOnError` | `switch` | No | — | Continue processing despite individual DISM failures |

**Supported extensions**: `.appx` \| `.appxbundle` \| `.msix` \| `.msixbundle`

**Returns**: `.data = @{ Succeeded=[array]; Failed=[array] }`.

```powershell
# Prepare the inject list (files must exist in C:\WinISO\Appx\)
WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
           -VarKeyID 'inject' -SetNewVal @(
               [PSCustomObject]@{
                   PackageFile = 'Microsoft.WindowsStore.msixbundle'
                   LicenseFile = 'Microsoft.WindowsStore_License.xml'
               }
               [PSCustomObject]@{
                   PackageFile = 'MyCustomApp.appx'
                   # No LicenseFile → /SkipLicense is used automatically
               }
           )

# Inject all packages
$r = AddAppxPackages
if ($r.code -eq 0) {
    Write-Host "All injected. $($r.data.Succeeded.Count) packages."
}

# Custom source directory
$r = AddAppxPackages -AppxSourceDir 'D:\MyAppxPackages' -ContinueOnError
```

---

### `AppxPackageLookUp`

Dual-mode verification helper for Appx / MSIX packages.

- **Mode 1 – IMAGE**: case-insensitive substring search against `DisplayName` and `PackageName`
  of all provisioned packages in the mounted WIM.
  Uses `$script:appx['listed']` as cache; `-ForceRefresh` bypasses the cache.
- **Mode 2 – FILE**: physical file existence check for a given filename in the Appx source directory.

Both modes are combinable in a single call.

**Parameters**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `SearchTerm` | `string` | *Cond.* | `''` | Substring to search in `DisplayName`/`PackageName` (Mode 1) |
| `PackageFile` | `string` | *Cond.* | `''` | File name with extension to check in `AppxSourceDir` (Mode 2) |
| `MountPoint` | `string` | No | `$script:appenv['MountPoint']` | WIM mount-point directory |
| `AppxSourceDir` | `string` | No | `$script:appenv['AppxBundle']` | Appx / MSIX source directory |
| `ForceRefresh` | `switch` | No | — | Bypass cache and re-query DISM directly |

> At least one of `-SearchTerm` or `-PackageFile` must be provided.

**Returns**: `.data = @{ ImageMatches=[array]; FileExists=[bool|null]; SearchTerm; PackageFile }`.
`.code = 0` with an empty `ImageMatches` means not found — this is not an error condition.

```powershell
# Check if 'Calculator' is in the image
$r = AppxPackageLookUp -SearchTerm 'Calculator'
if ($r.code -eq 0) {
    if ($r.data.ImageMatches.Count -gt 0) {
        Write-Host "Found: $($r.data.ImageMatches[0].PackageName)"
    } else {
        Write-Host "Calculator not found in the image."
    }
}

# Check if a specific package file is ready to inject
$r = AppxPackageLookUp -PackageFile 'MyApp.msixbundle'
Write-Host "File ready: $($r.data.FileExists)"

# Combined check with forced DISM refresh
$r = AppxPackageLookUp -SearchTerm 'MyApp' `
                       -PackageFile 'MyApp.msixbundle' `
                       -ForceRefresh
Write-Host "Image matches: $($r.data.ImageMatches.Count) | File ready: $($r.data.FileExists)"

# Pre-inject safety check pattern
$lookup = AppxPackageLookUp -SearchTerm 'WindowsStore' `
                            -PackageFile 'Microsoft.WindowsStore.msixbundle'
if ($lookup.data.ImageMatches.Count -gt 0) {
    Write-Warning "WindowsStore already in image — skipping inject."
} elseif (-not $lookup.data.FileExists) {
    Write-Error "Package file not found — cannot inject."
} else {
    # Safe to proceed with AddAppxPackages
}
```

---

## Private Helpers

These functions are dot-sourced from `Private\` and are accessible only within the module.
They are not exported and must not be called from external scripts.

| Function | File | Description |
|---|---|---|
| `OPSreturn` | `OPSreturn.ps1` | Creates standardised `{ .code, .msg, .data }` return objects. `code=0` = success, `code=-1` = failure. |
| `Invoke-UUPRuntimeLog` | `Invoke-UUPRuntimeLog.ps1` | Creates / rotates the runtime log file used by `uup_download_windows.cmd`. |
| `Get-UUPLogTail` | `Get-UUPLogTail.ps1` | Reads the last N lines of a large text file efficiently via `StreamReader` — avoids `Get-Content` overhead for large log files. |
| `Test-UUPConversionPhase` | `Test-UUPConversionPhase.ps1` | Detects the download → conversion phase transition by checking for WIM/ESD file creation and oscdimg-specific log keywords. |
| `Invoke-UUPProcessKill` | `Invoke-UUPProcessKill.ps1` | Terminates a process and all its child processes via `Win32_Process` WMI query. |
| `Get-UUPNewestISO` | `Get-UUPNewestISO.ps1` | Returns the newest `.iso` file in a directory by `LastWriteTime` — used for ISO-presence monitoring in `CreateUUPDiso`. |
| `ValidateRegFile` | `ValidateRegFile.ps1` | Validates `.reg` file syntax: valid header (`Windows Registry Editor`), non-empty content, and correct key/value format. Called by `RegistryHiveImport` before any import. |

---

*Module by [Praetoriani](https://github.com/praetoriani)*
*Developer Guide for WinISO.ScriptFXLib v1.00.05*
