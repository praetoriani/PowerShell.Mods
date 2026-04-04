# CHANGELOG — WinISO.ScriptFXLib

All notable changes to this module are documented in this file.
Versions follow the `Major.Minor.Patch` scheme used in the module manifest.

---

## [1.00.05] — 2026-04-04

### New Functions

#### `GetAppxPackages`
- Lists all provisioned Appx packages from a mounted WIM image using `Get-AppxProvisionedPackage`.
- Results are stored as an array of `PSCustomObject` entries in `$script:appx['listed']`.
  Each entry contains: `DisplayName`, `PackageName`, `Version`, `Architecture`, `PublisherId`.
- Defaults `MountPoint` from `$script:appenv['MountPoint']` when not explicitly provided.
- Optional file export via `-ExportFile` and `-Format` (`TXT` | `CSV` | `JSON`).
  Export failure is non-fatal — data is always stored in module scope first.
- On success: `$script:appx['listed']` is replaced with the fresh result array.
- On failure: `$script:appx['listed']` is left unchanged.

#### `RemAppxPackages`
- Removes all provisioned Appx packages listed in `$script:appx['remove']` from a mounted
  WIM image using `DISM.exe /Remove-ProvisionedAppxPackage`.
- Supports `.appx`, `.appxbundle`, `.msix`, `.msixbundle` and bare `PackageName` strings.
- **Monitoring / self-cleaning**: after each successful removal the corresponding entry is
  deleted from `$script:appx['remove']`. At completion, only failed entries remain in scope.
- `-ContinueOnError` switch: process all packages despite individual DISM failures.
  Without this switch the function aborts on the first failure.
- Returns `@{ Succeeded=[array]; Failed=[array] }` as `.data`.

#### `AddAppxPackages`
- Injects provisioned Appx packages listed in `$script:appx['inject']` into a mounted WIM
  image using `DISM.exe /Add-ProvisionedAppxPackage`.
- Supported package file types: `.appx`, `.appxbundle`, `.msix`, `.msixbundle`.
- Resolves package files from `$script:appenv['AppxBundle']` (overridable via `-AppxSourceDir`).
- Per-entry optional `LicenseFile` property; falls back to `/SkipLicense` automatically.
- **Monitoring / self-cleaning**: successfully injected entries are removed from
  `$script:appx['inject']`. At completion, only failed entries remain in scope.
- `-ContinueOnError` switch: process all packages despite individual DISM failures.
- Returns `@{ Succeeded=[array]; Failed=[array] }` as `.data`.

#### `AppxPackageLookUp`
- Dual-mode Appx package verification helper.
- **Mode 1 – IMAGE**: case-insensitive substring search against `DisplayName` and `PackageName`
  of all provisioned packages in a mounted WIM.
  Uses `$script:appx['listed']` as cache; `-ForceRefresh` bypasses the cache and re-queries DISM.
  The refreshed data is written back to `$script:appx['listed']`.
- **Mode 2 – FILE**: physical file existence check in the Appx source directory.
  Validates that the file extension is one of `.appx`, `.appxbundle`, `.msix`, `.msixbundle`.
- Both modes are combinable in a single call via `-SearchTerm` and `-PackageFile`.
- Returns `@{ ImageMatches=[array]; FileExists=[bool|null]; SearchTerm=[string]; PackageFile=[string] }` as `.data`.
- `.code = 0` with an empty `ImageMatches` array means the search ran successfully but the
  package was not found (not an error condition).

### Modified Functions

#### `WinISOcore`
- Extended with full read/write support for `$script:appverify` and `$script:appx`.
  - `appverify` keys: `PASS` / `FAIL` / `INFO` / `WARN` status strings + `result` sub-hashtable.
  - `appx` keys: `listed`, `remove`, `inject` — all accept array replacement.

#### `CheckModuleRequirements`
- Redesigned check status schema with four states: `PASS` / `FAIL` / `INFO` / `WARN`.
  - `INFO` — issue is resolvable automatically (e.g. run `InitializeEnvironment`).
  - `WARN` — requires manual user action (e.g. re-run elevated, upgrade PowerShell).
  - `FAIL` — no known automated fix (hard system component missing).
- All check results are now written into `$script:appverify` via `WinISOcore`.
- Result counters (`pass`, `fail`, `info`, `warn`) are stored in `$script:appverify['result']`.
- Overall function returns `.code = 0` as long as no `FAIL` check exists.
- Export report updated to reflect the new 4-state schema.

#### `DownloadUUPDump`
- New `-Edition` parameter (`'Pro'` / `'Home'`) with UUPDump ID mapping.
- New `-IncludeNetFX` / `-ExcludeNetFX` mutually exclusive switches (default: NetFX included).
- New `-UseESD` switch to request `install.esd` instead of `install.wim` (default: WIM).
- **BUGFIX**: `$script:uupdump['buildno']` now stores the actual build number (e.g. `26100.3476`)
  instead of the internal UUID (incorrect in all prior versions).
- **BUGFIX**: cleanup POST parameter corrected to `'0'` (was incorrectly `'1'`).
- Full `$script:uupdump` write-back on success.
- Returns an error if any `WinISOcore` write operation fails (hard guarantee).

#### `GetUUPDumpPackage`
- New function for multi-edition / Virtual Editions downloads (`autodl=3`).
- `-Editions` array parameter accepts: `ProWorkstations`, `ProEducation`, `Education`,
  `Enterprise`, `IoTEnterprise` (one or more, deduplicated automatically).
- `$script:uupdump['multiedition']` stores the semicolon-joined display names.
- `$script:uupdump['edition']` is cleared (empty) for multi-edition packages.

### Module Manifest (`WinISO.ScriptFXLib.psd1`)
- `FunctionsToExport`: added `GetAppxPackages`, `RemAppxPackages`, `AddAppxPackages`, `AppxPackageLookUp`.
- `FileList`: added all four new `Public\*.ps1` entries.
- `Tags`: added `AppxPackage`, `MSIX`, `ProvisionedPackage`.
- `ReleaseNotes`: full v1.00.05 changelog block added.

### Documentation
- `README.md`: updated to v1.00.05.
- `DEVGUIDE.md`: created — full developer reference.
- `CHANGELOG.md`: created — full version history from v1.00.00.

---

## [1.00.04] — 2026-03-30

### New Functions

#### `LoadRegistryHive`
- Mounts one or all offline registry hives from a mounted WIM image into the live registry
  using `reg.exe load`.
- Supported hives: `SYSTEM`, `SOFTWARE`, `DEFAULT`, `SAM`, `SECURITY`.
- `-HiveName 'ALL'` loads all supported hives in a single call.
- Hive mount points follow the `HKLM\WinISO_<HiveName>` convention.

#### `UnloadRegistryHive`
- Unloads one or all previously loaded offline registry hives from the live registry.
- Flushes the live registry before unloading to prevent data loss.

#### `RegistryHiveAdd`
- Adds a new registry key and/or value to a loaded offline registry hive.
- Supports: `REG_SZ`, `REG_EXPAND_SZ`, `REG_DWORD`, `REG_QWORD`, `REG_BINARY`, `REG_MULTI_SZ`.

#### `RegistryHiveRem`
- Removes an existing registry key and/or value from a loaded offline registry hive.
- `-RemoveKey` switch deletes the entire key tree.

#### `RegistryHiveImport`
- Imports a validated `.reg` file into a loaded offline registry hive using `reg.exe import`.
- Calls the private `ValidateRegFile` helper before import.

#### `RegistryHiveExport`
- Exports a registry key branch from a loaded offline hive to a `.reg` file via `reg.exe export`.

#### `RegistryHiveQuery`
- Queries registry keys and/or values from a loaded offline hive via `reg.exe query`.
- Returns structured `PSCustomObject` entries per value.

### New Private Helpers

#### `ValidateRegFile`
- Validates `.reg` file syntax: valid header, non-empty content, correct key/value format.

---

## [1.00.03] — 2026-03-29

### New Functions

#### `GetLatestPowerShellSetup`
- Queries the GitHub Releases API for the latest PowerShell stable release.
- Downloads the `.msi` installer for the specified architecture.
- Optional `-Install` switch for silent installation after download.

#### `CreateUUPDiso`
- Central ISO creation orchestration with 7-layer process monitoring.
- Parameters: `-UUPDdir`, `-CleanUp`, `-ISOname`, `-SoftIdleMinutes`, `-HardIdleMinutes`,
  `-GlobalTimeoutMinutes`, `-PollSeconds`, `-KillOnHardIdle`.

#### `WinISOcore`
- Type-safe read/write accessor for all `$script:` module-scope variables.
- Type mismatch on write is rejected; original value unchanged.

#### `ImageIndexLookup`
- Returns a single unambiguous `ImageIndex` for a named edition.

#### `MountWIMimage`
- Mounts with post-mount verification and defensive auto-dismount on failure.

#### `UnMountWIMimage`
- Pre-dismount and post-dismount verification; supports `commit` / `discard`.

#### `CheckModuleRequirements`
- Full system dependency audit; optional `-Export 1` text report.

### New Private Helpers
- `Invoke-UUPRuntimeLog`, `Get-UUPLogTail`, `Test-UUPConversionPhase`,
  `Invoke-UUPProcessKill`, `Get-UUPNewestISO`.

---

## [1.00.02] — 2026-03-28

### New Functions

#### `DownloadUUPDump`
- Downloads a UUP Dump ZIP from uupdump.net.
- Parameters: `-OStype`, `-OSvers`, `-OSarch`, `-BuildNo`, `-Target`.

#### `ExtractUUPDump`
- Extracts UUP Dump ZIP with optional verification and cleanup.

#### `CleanupUUPDump`
- Cleans UUPDump directory, retaining only `.iso` files.

#### `RenameUUPDiso`
- Renames the single ISO in `UUPDdir`; fails gracefully on ambiguous result.

#### `ExtractUUPDiso`
- Mounts ISO via `Mount-DiskImage`; copies contents with robocopy; always dismounts in `finally`.

---

## [1.00.01] — 2026-03-28

### Initial Release

#### `InitializeEnvironment`
- Creates WinISO directory structure; downloads `oscdimg.exe`.

#### `VerifyEnvironment`
- Verifies all required directories exist.

#### `GitHubDownload`
- Generic GitHub file downloader.

#### `WriteLogMessage`
- Structured log writer with severity levels and timestamp.

#### `AppScope`
- Read-only module-scope accessor.

### Module Manifest
- Initial manifest (`ModuleVersion = '1.00.01'`).

### Private Helpers
- `OPSreturn`: standardised `{ code, msg, data }` return object factory.

---

## [1.00.00] — 2026-03-28

### Project Bootstrap
- Repository structure created: `WinISO.ScriptFXLib/`, `Public/`, `Private/`.
- Module skeleton (`WinISO.ScriptFXLib.psm1`, `WinISO.ScriptFXLib.psd1`) committed.
- Module-scope variables initialised:
  `$script:appinfo`, `$script:appenv`, `$script:uupdump`,
  `$script:appverify`, `$script:appx`, `$script:appexit`.
- `README.md` stub created.

---

*Maintained by [Praetoriani](https://github.com/praetoriani)*
