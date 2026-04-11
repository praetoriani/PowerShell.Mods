# VPDLX — Changelog

All notable changes to the **VPDLX** module are documented here.
This file follows a *reverse-chronological* order — the newest version is always at the top.

---

## [1.02.03] — 11.04.2026

### Overview
Critical bugfix release targeting the `Destroy()` and `ToString()` methods in
`[Logfile]`. Three issues are resolved in this version, all affecting
`Classes/Logfile.ps1`. Together, they bring `Destroy()` and `ToString()` in line
with the defensive `GuardDestroyed()` contract that every other public method
already follows.

### Fixed — `Destroy()` Hardening (Issue #1 + Issue #6)

- **`Destroy()` now calls `GuardDestroyed()` at the very beginning** (Issue #1).
  Previously, calling `Destroy()` a second time on an already-destroyed instance
  silently succeeded instead of throwing `ObjectDisposedException`. This was
  inconsistent with every other public method in the class. The redundant
  `if ($null -ne $this._data)` conditional has been removed — `GuardDestroyed()`
  makes it unnecessary.

- **`Destroy()` now wraps `storage.Remove()` in `try/catch/finally`** (Issue #6).
  `FileStorage.Remove()` throws `InvalidOperationException` by design when the
  name is not found (e.g. after direct manipulation via `VPDLXcore`). Without
  exception handling, this interrupted cleanup and left the instance in a
  half-destroyed state: removed from storage but still holding live `_data` and
  `_details` references. The `finally` block now unconditionally clears `_data`
  and sets both `_data` and `_details` to `$null`, guaranteeing full cleanup
  regardless of whether `Remove()` succeeds or throws. The `catch` block emits
  a `Write-Verbose` diagnostic instead of re-throwing.

### Fixed — `ToString()` Post-Destroy Safety (Issue #3)

- **`ToString()` now calls `GuardDestroyed()` at the top** (Issue #3).
  Previously, `ToString()` contained a partial null-check for `_data` but
  unconditionally accessed `_details.GetCreated()`. After `Destroy()`, this
  caused an unhelpful `NullReferenceException` instead of the expected
  `ObjectDisposedException`. The partial `if/else` construct has been removed
  — with `GuardDestroyed()` in place, both `_data` and `_details` are guaranteed
  non-null when the return statement executes.

### Fixed — `FilterByLevel()` Call-Order + Label (Issue #2 + Issue #4)

- **`RecordFilter()` call moved from before to after the `foreach` loop** (Issue #2).
  In `Logfile.FilterByLevel()`, the metadata-recording call
  `$this._details.RecordFilter()` was placed *before* the `foreach` loop that
  collects matching entries. This meant `_lastAccessed` and `_axcount` were updated
  even if the method returned early or encountered an error during iteration.
  The call has been moved to immediately *after* the loop, just before `return`,
  so metadata is recorded only when filtering actually completes successfully.

- **`RecordFilter()` renamed to `RecordFilterByLevel()`** (Issue #4).
  The hidden method `RecordFilter()` in `[FileDetails]` set
  `_lastAccessType = 'Filter'` — a generic label that did not clearly identify
  which operation was performed. The method has been renamed to
  `RecordFilterByLevel()` and the label updated to `'FilterByLevel'`, matching
  the public method name. The single call-site in `Logfile.ps1` has been updated
  accordingly.

### Fixed — `FunctionsToExport` Single Source of Truth (Issue #5)

- **`Export-ModuleMember` call removed from `VPDLX.psm1` Section 7** (Issue #5).
  When a `.psd1` manifest is present, PowerShell ignores any `Export-ModuleMember`
  calls in the `.psm1` file — the manifest's `FunctionsToExport` array takes
  precedence. The `Export-ModuleMember -Function $PublicFunctions` call was
  therefore misleading and has been replaced with an explanatory comment.

- **`VPDLX.psd1` `FunctionsToExport` annotated as SINGLE SOURCE OF TRUTH.**
  A comment block has been added above the `FunctionsToExport` array in the
  manifest, clearly marking it as the authoritative list and instructing future
  developers to add new public functions there.

### Fixed — `VPDLXreturn` Status Code Extensibility (Issue #8)

- **`[ValidateSet(0, -1)]` replaced with `[ValidateRange(-99, 99)]`** (Issue #8).
  The `$Code` parameter in `VPDLXreturn.ps1` was hard-coded to accept only `0`
  (success) and `-1` (failure). This prevented future wrapper functions from
  returning granular status codes. The constraint has been widened to
  `[ValidateRange(-99, 99)]` and a documentation block added above the parameter
  defining the status code conventions:
  - `0` = success
  - `-1` = general failure
  - `1..99` = partial success / warning codes
  - `-2..-99` = typed / categorised error codes

### Improved — `Print()` Batch Validation Diagnostics (Issue #7)

- **Pre-validation loop now tracks the 0-based element index** (Issue #7).
  When `ValidateMessage()` throws `ArgumentException` inside `Print()`, the
  exception is caught, enriched with the element index and a safe preview of
  the offending value, and re-thrown as a new `ArgumentException` with the
  parameter name `'messages'`. The preview is truncated to 40 characters,
  and control characters (`\r`, `\n`) are escaped to their literal
  backslash representations so they are visible in the error output.
  `ValidateMessage()` itself remains unchanged — the improvement is fully
  isolated to `Print()`.

### Fixed — FileStorage Type Safety via Class Consolidation (Issue #9)

- **Three separate class files merged into `Classes/VPDLXClasses.ps1`** (Issue #9).
  `FileDetails.ps1`, `FileStorage.ps1`, and `Logfile.ps1` have been consolidated
  into a single file. This eliminates the PowerShell 5.1 forward-reference
  limitation that forced `FileStorage` to use `[object]` instead of `[Logfile]`
  in its dictionary, `Get()` return type, and `Add()` parameter type.

- **`FileStorage._registry` is now `Dictionary[string, Logfile]`.**
  Inserting a non-`Logfile` object is now a type error at the insertion point
  instead of silently succeeding.

- **`FileStorage.Get()` returns `[Logfile]` instead of `[object]`.**
  Callers no longer need to cast the result — IntelliSense and static type
  checking work correctly on the returned reference.

- **`FileStorage.Add()` accepts `[Logfile]` instead of `[object]`.**
  Combined with the typed dictionary, this provides full compile-time type
  safety for the registry.

- **`VPDLX.psm1` Section 2** updated to load the single `VPDLXClasses.ps1`
  instead of three separate files.

- **`VPDLX.psd1` `FileList`** updated to reference the new consolidated file.

### Added — `FileStorage.DestroyAll()` + `OnRemove` Integration (Issue #10)

- **`FileStorage.DestroyAll()` method added** (Issue #10).
  Iterates over all registered `[Logfile]` instances, calls `Destroy()` on
  each one (with per-instance `try/catch` to prevent one failure from
  blocking cleanup of remaining instances), and performs a final `Clear()`
  on both `_registry` and `_names` as a safety measure.

- **`OnRemove` handler in `VPDLX.psm1` now calls `DestroyAll()`** before
  removing TypeAccelerators. Previously, `Remove-Module VPDLX` cleaned up
  TypeAccelerators but left all `[Logfile]` instances orphaned in memory.
  Now all instances are properly destroyed, their `_data` and `_details`
  fields are cleared, and the `FileStorage` registry is empty when the
  module finishes unloading.

- **`VPDLXcore -KeyID 'destroyall'`** exposes batch cleanup to callers.
  Returns a `VPDLXreturn` object with `code 0` and a message indicating
  how many instances were destroyed.

### Changed
- Version stays at `1.02.03` — all fixes are bundled into the same release.
- Developer ToDo-Liste updated: all Prioritäten (1–8) marked as completed.
- Old class files (`FileDetails.ps1`, `FileStorage.ps1`, `Logfile.ps1`)
  replaced by consolidated `Classes/VPDLXClasses.ps1`.

---

## [1.01.02] — 06.04.2026

### Overview
Introduces the complete **Public Wrapper Layer** — a set of standalone `.ps1` files
in `Public/` that expose safe, standardised PowerShell functions on top of the
class-based internals from v1.01.00. Each wrapper follows an identical defensive
pipeline pattern and returns a consistent `{ code, msg, data }` object via
`VPDLXreturn`. This release also adds the first physical export capability:
`VPDLXexportlogfile` writes a virtual log file to disk in one of four formats.

### Added — Public Wrapper Functions

| Function | Replaces (v1.00.00) | Description |
|---|---|---|
| `VPDLXnewlogfile` | `CreateNewLogfile` | Creates a new named virtual log file via `[Logfile]::new()`. Returns `code 0` + the new instance name in `.data` on success. |
| `VPDLXislogfile` | — *(new)* | Checks whether a named log file exists in `$script:storage` via `.Contains()`. Returns `$true` / `$false` directly (not a return object). |
| `VPDLXdroplogfile` | `DeleteLogfile` | Calls `.Destroy()` on the named instance and removes it from storage. Five-stage defensive pipeline including double-verification of removal. |
| `VPDLXreadlogfile` | `ReadLogfileEntry` | Reads a specific line (1-based index) via `.Read()`. Index is automatically clamped; effective line number is reported in `.msg`. Returns the log line as `string` in `.data`. |
| `VPDLXwritelogfile` | `WriteLogfileEntry` | Appends a formatted entry via `.Write(level, message)`. Level validated by `[ValidateSet]` at binding layer AND by `[Logfile].ValidateLevel()` internally. Returns new `EntryCount()` in `.data`. |
| `VPDLXexportlogfile` | — *(new)* | Exports a virtual log file to a physical file on disk. See *Export Function* section below. |

### Added — Export Function (`VPDLXexportlogfile`)

`VPDLXexportlogfile` is the centrepiece of v1.01.02. It executes an 8-stage pipeline:

1. **Pre-flight** — retrieves `$script:storage` and `$script:export` via `VPDLXcore`
2. **Format validation** — `ExportAs` is validated at runtime against `$script:export` keys (dynamic, not a static `[ValidateSet]`)
3. **Existence check** — confirms the named log file is registered in storage
4. **Instance retrieval** — `Get()` with null-guard
5. **Empty-log guard** — rejects export of logs with zero entries
6. **Directory creation** — creates the full `LogPath` tree automatically (`New-Item -Force`) if it does not yet exist
7. **Override logic** — without `-Override`: blocks overwrite; with `-Override`: removes existing file before writing
8. **Serialisation + write** — format-specific serialisation, then `Set-Content -Encoding UTF8`

**Parameters:**

| Parameter | Type | Mandatory | Description |
|---|---|---|---|
| `Logfile` | `[string]` | yes | Name of the virtual log file to export |
| `LogPath` | `[string]` | yes | Full path to the target directory (auto-created if missing) |
| `ExportAs` | `[string]` | yes | Target format: `txt` \| `csv` \| `json` \| `log` |
| `Override` | `[switch]` | no | When set, overwrites an existing file at the target path |

**Supported export formats:**

| Key | Extension | Description |
|---|---|---|
| `txt` | `.txt` | Plain text. Each log line written as-is. |
| `log` | `.log` | Identical to `txt` but with `.log` extension. |
| `csv` | `.csv` | RFC 4180-compliant. Header: `"Timestamp","Level","Message"`. Each entry is parsed from the log line format. |
| `json` | `.json` | JSON array wrapped in a root object: `{ LogFile, ExportedAt, EntryCount, Entries[] }`. Each entry: `{ Timestamp, Level, Message }`. |

**Output naming convention:** `<LogPath>\<Logfile><extension>` (e.g. `C:\Logs\AppLog.csv`)

### Added — Wrapper Design Conventions
All six Public Wrapper functions share the following design conventions:
- **Defensive pipeline:** every stage runs in order; any failure returns immediately with `code -1` and a descriptive `.msg`
- **Scope bridge:** all wrappers access module internals via `VPDLXcore` (dot-sourced functions cannot read `$script:*` variables directly)
- **`[ObjectDisposedException]` handling:** all wrappers that touch a `[Logfile]` instance catch this exception separately to report destroyed-instance scenarios clearly
- **Name trimming:** all `Logfile` parameters are trimmed of leading/trailing whitespace before use, consistent with the `[Logfile]` constructor
- **Return objects:** all wrappers (except `VPDLXislogfile`) return `[PSCustomObject] { code, msg, data }` via `VPDLXreturn`

---

## [1.01.01] — 06.04.2026

### Overview
Bugfix release. Corrects a critical TypeAccelerator registration error introduced
in v1.01.00 that prevented the documented `[Logfile]::new()` syntax from working
after a standard `Import-Module VPDLX` call.

### Fixed
- **TypeAccelerator registration used `FullName` instead of `Name`.**
  Classes were registered as `VPDLX.Logfile`, `VPDLX.FileStorage`, and
  `VPDLX.FileDetails` instead of the short names `Logfile`, `FileStorage`,
  and `FileDetails`. This forced callers to write `[VPDLX.Logfile]::new()`
  instead of the documented `[Logfile]::new()`, causing `TypeNotFound`
  errors in all demo scripts and any real caller code.
  **Fix:** changed `$Type.FullName` to `$Type.Name` in the TypeAccelerator
  registration loop in `VPDLX.psm1`.

---

## [1.01.00] — 06.04.2026

### Overview
Complete architectural rewrite. The previous function-based API (v1.00.00) has
been replaced by a fully class-based OOP architecture. **This is a breaking change**
— all v1.00.00 public functions have been removed and replaced by class methods.

### Breaking Changes
- All public functions from v1.00.00 have been removed:
  `CreateNewLogfile`, `WriteLogfileEntry`, `ReadLogfileEntry`,
  `ResetLogfile`, `DeleteLogfile` and related helpers no longer exist.
- Log levels changed from uppercase identifiers (`DEBUG`, `INFO`, …) to
  **lowercase** identifiers (`debug`, `info`, …). The output prefix in log
  lines remains uppercase (e.g. `[INFO]`).
- In-memory storage moved from a `$script:LogfileRegistry` hashtable to a
  dedicated `[FileStorage]` class instance (`$script:storage`).

### Added — Architecture
- Class `[Logfile]` — central user-facing class; replaces all v1.00 functions.
- Class `[FileStorage]` — module-level singleton registry for all active `[Logfile]` instances.
- Class `[FileDetails]` — metadata companion for each `[Logfile]` instance.
- Private function `VPDLXreturn` — standardised return-object factory `{ code, msg, data }`.
- Public function `VPDLXcore` — controlled read-only accessor for module-scope variables
  (`appinfo`, `storage`, `export`).
- Module-scope variable `$script:export` — hashtable of supported export formats
  (`txt`, `csv`, `json`, `log`) for use by future export functions.
- TypeAccelerator registration on module load — all three classes available as
  `[Logfile]`, `[FileDetails]`, `[FileStorage]` after `Import-Module` (no `using module` required).
- TypeAccelerator cleanup in `OnRemove` handler — no type conflicts on module re-import.

### Added — Log Levels
| Identifier | Shortcut method | Output prefix |
|---|---|---|
| `info`     | `.Info()`       | `[INFO]`     |
| `debug`    | `.Debug()`      | `[DEBUG]`    |
| `verbose`  | `.Verbose()`    | `[VERBOSE]`  |
| `trace`    | `.Trace()`      | `[TRACE]`    |
| `warning`  | `.Warning()`    | `[WARNING]`  |
| `error`    | `.Error()`      | `[ERROR]`    |
| `critical` | `.Critical()`   | `[CRITICAL]` |
| `fatal`    | `.Fatal()`      | `[FATAL]`    |

### Added — `[Logfile]` Methods
| Method | Description |
|---|---|
| `Write(level, message)` | Appends a single formatted entry |
| `Print(level, messages[])` | Batch write with transactional pre-validation (all-or-nothing) |
| `Read(line)` | Returns the entry at the given 1-based index; auto-clamps out-of-range values |
| `GetAllEntries()` | Returns all entries as `string[]` |
| `FilterByLevel(level)` | Returns all entries matching the given level as `string[]` |
| `IsEmpty()` | Returns `$true` if the log has no entries |
| `HasEntries()` | Returns `$true` if the log has at least one entry |
| `EntryCount()` | Returns the current entry count as `int` |
| `Reset()` | Clears all data entries; preserves creation timestamp and interaction count |
| `Destroy()` | Removes the instance from `$script:storage` and nulls all data; any subsequent call throws `ObjectDisposedException` |
| `GetDetails()` | Returns the `[FileDetails]` companion object |
| `ToString()` | Returns a one-line summary string |
| `GuardDestroyed()` | Internal safety guard called at the start of every method |
| Shortcut methods | `.Info()`, `.Debug()`, `.Verbose()`, `.Trace()`, `.Warning()`, `.Error()`, `.Critical()`, `.Fatal()` — thin wrappers around `Write()` |

### Added — `[FileDetails]` Fields
| Field key | Getter method | Description |
|---|---|---|
| `created` | `GetCreated()` | Timestamp of instance creation |
| `updated` | `GetUpdated()` | Timestamp of last `Write` / `Print` / `Reset` call |
| `lastacc` | `GetLastAccessed()` | Timestamp of last `Read` / `GetAllEntries()` / `FilterByLevel()` call |
| `acctype` | `GetLastAccessType()` | Type of most recent interaction (`write`, `print`, `read`, `reset`, …) |
| `entries` | `GetEntries()` | Current number of log entries |
| `axcount` | `GetAxcount()` | Total number of interactions since creation (never reset unless `Destroy()` is called) |

### Added — Log Entry Format
```
[dd.MM.yyyy | HH:mm:ss]  [LEVEL]     ->  MESSAGE
```
Example:
```
[06.04.2026 | 19:58:00]  [INFO]      ->  Application started.
[06.04.2026 | 19:58:01]  [WARNING]   ->  Disk space below 10%.
[06.04.2026 | 19:58:02]  [CRITICAL]  ->  Database connection lost.
```

### Changed
- `FileDetails.RecordWrite()` now only records `write`-type interactions.
  A new `RecordPrint()` method records `print`-type interactions separately,
  so `acctype` accurately reflects whether the last write was a single `Write()`
  or a batch `Print()` call.
- `FilterByLevel()` rewritten: replaced `Where-Object` pipeline with a
  `foreach` loop and `String.Contains()` — no regex overhead, lower pipeline cost.
- Newline characters (`\r`, `\n`) are explicitly rejected in message validation
  to prevent log injection into exported files.

### Known Limitations
- **Not designed for parallel execution.** Multiple threads writing to the same
  `[Logfile]` instance simultaneously can cause data corruption. Use one instance
  per thread, or implement external locking.
- `hidden` class members are not truly private in PowerShell 5.1/7.x —
  disciplined callers should use the public getter methods only.
- Timestamps are stored as formatted strings; direct time arithmetic requires
  parsing with `[datetime]::ParseExact()`.

---

## [1.00.00] — 05.04.2026

### Overview
Initial release of the VPDLX module. Function-based architecture.

### Added
- Public function `CreateNewLogfile([string] $Name)` — creates a new in-memory log file.
- Public function `WriteLogfileEntry([string] $Name, [string] $Level, [string] $Message)` — writes a single log entry.
- Public function `ReadLogfileEntry([string] $Name, [int] $Line)` — reads a specific line.
- Public function `ResetLogfile([string] $Name)` — clears all entries.
- Public function `DeleteLogfile([string] $Name)` — removes the log file from memory.
- 8 log levels: `DEBUG`, `INFO`, `VERBOSE`, `TRACE`, `WARNING`, `ERROR`, `CRITICAL`, `FATAL`
  (uppercase identifiers, case-sensitive).
- In-memory storage via `$script:LogfileRegistry` hashtable.
- Standardised return objects `{ code, msg, data }` for all public functions.
