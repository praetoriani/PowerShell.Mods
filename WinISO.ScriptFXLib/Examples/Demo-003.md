<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

***

## `Demo-003.ps1`

This file is available at: [WinISO.ScriptFXLib/Examples/Demo-003.ps1](https://github.com/praetoriani/PowerShell.Mods/blob/main/WinISO.ScriptFXLib/Examples/Demo-003.ps1)

***

## What Was Analyzed and Implemented

### Repository Analysis (v1.00.05)

The following files were evaluated before creating the demo:

| File | Relevance for the Demo |
| :-- | :-- |
| `CHANGELOG.md` | All new features since v1.00.01 — complete version history |
| `Examples/Demo-002.ps1` | Reference for coding style, helper functions, color scheme |
| `Public/InitializeEnvironment.ps1` | Step 03 — Step-by-step result collector pattern |
| `Public/WriteLogMessage.ps1` | Step 04 — All parameters including override logic |
| `Public/GetUUPDumpPackage.ps1` | Step 08 — Complete multi-edition parameters |
| `Public/LoadRegistryHive.ps1` | Step 11 — HiveMap, WinISO_ prefix, tracking mechanism |
| `Public/GetAppxPackages.ps1` | Step 12 — appx['listed'], ExportFile/Format parameters |
| `Public/VerifyEnvironment.ps1` | Step 03 — Return value semantics (code 1 = exists) |

### New / Improved Helper Functions

Compared to `Demo-002.ps1`, the helper functions have been extended and two new ones added:

- **`WaitForEnter`** — complete `.SYNOPSIS` + `.PARAMETER` documentation added
- **`ThrowInternalError`** — identically refined
- **`PrintSectionHeader`** *(NEW)* — Unicode box-drawing border (`┌─┘`) as a visual section separator
- **`PrintResult`** *(NEW)* — colored `[PASS]`/`[FAIL]` output with green/red console color

### 13 Demo Steps

| Step | Content | Live / DEMO |
| :-- | :-- | :-- |
| 01 | WinISOcore accessor — Read/Write/Unwrap including live round-trip | ✅ Live |
| 02 | `CheckModuleRequirements` — 4-state schema, export report | ✅ Live |
| 03 | `InitializeEnvironment` + `VerifyEnvironment` spot checks | ✅ Live |
| 04 | `WriteLogMessage` — all 4 flags + override, content preview | ✅ Live |
| 05 | `GetLatestPowerShellSetup` — win-x64, download only | ✅ Live |
| 06 | `GitHubDownload` — re-download oscdimg.exe as example | ✅ Live |
| 07 | `DownloadUUPDump` — single-edition Pro/Home, state display before/after | ✅ Live |
| 08 | `GetUUPDumpPackage` — multi-edition, all 3 example calls | 💬 DEMO (can be activated by uncommenting) |
| 09 | `ExtractUUPDump` / `CreateUUPDiso` / `RenameUUPDiso` / `ExtractUUPDiso` | 💬 DEMO |
| 10 | `MountWIMimage` / `ImageIndexLookup` / `UnMountWIMimage` | 💬 DEMO |
| 11 | `LoadRegistryHive` + all `RegistryHive*` functions | 💬 DEMO (+ live display LoadedHives.Count) |
| 12 | `GetAppxPackages` / `AppxPackageLookUp` / `RemAppxPackages` / `AddAppxPackages` | ✅ Live WinISOcore write demo |
| 13 | Advanced WinISOcore usage, type safety, OPSreturn pattern | ✅ Live Round-Trip |

