# VPDLX — Changelog

All notable changes to the **VPDLX** module are documented here.

---

## [1.01.00] — 06.04.2026

### Overview
Complete architectural rewrite. The previous function-based API (v1.00.00) has been replaced by a class-based OOP architecture. **This is a breaking change** — all v1.00.00 functions have been removed.

### Breaking Changes
- All public functions from v1.00.00 have been removed:
  `CreateNewLogfile`, `WriteLogfileEntry`, `ReadLogfileEntry`,
  `ResetLogfile`, `DeleteLogfile` and related helpers no longer exist.
- Log levels changed from 8 levels (DEBUG, INFO, VERBOSE, TRACE, WARNING, ERROR, CRITICAL, FATAL) with uppercase identifiers to 8 levels with **lowercase** identifiers. See *Added* below.

### Added — Architecture
- Class `[Logfile]` — central user-facing class; replaces all v1.00 functions.
- Class `[FileStorage]` — module-level singleton registry for all active `[Logfile]` instances.
- Class `[FileDetails]` — metadata companion for each `[Logfile]` instance.
- Private function `VPDLXreturn` — standardised return-object factory `{ code, msg, data }`.
- Public function `VPDLXcore` — controlled read-only accessor for module-scope variables (`appinfo`, `storage`, `export`).
- TypeAccelerator registration on module load — all three classes are available as `[Logfile]`, `[FileDetails]`, `[FileStorage]` after `Import-Module` (no `using module` required).
- TypeAccelerator cleanup in `OnRemove` handler.

### Added — Log Levels (v1.01.00)
| Identifier | Shortcut method | Output prefix          |
|------------|-----------------|------------------------|
| `info`     | `.Info()`       | `[INFO]`               |
| `debug`    | `.Debug()`      | `[DEBUG]`              |
| `verbose`  | `.Verbose()`    | `[VERBOSE]`            |
| `trace`    | `.Trace()`      | `[TRACE]`              |
| `warning`  | `.Warning()`    | `[WARNING]`            |
| `error`    | `.Error()`      | `[ERROR]`              |
| `critical` | `.Critical()`   | `[CRITICAL]`           |
| `fatal`    | `.Fatal()`      | `[FATAL]`              |

### Added — Logfile Methods
- `Write(level, message)` — single entry
- `Print(level, messages[])` — batch write with transactional pre-validation
- `Read(line)` — 1-based, auto-clamped
- `SoakUp()` — returns all entries as `string[]`
- `Filter(level)` — returns matching lines (optimised `foreach` + `.Contains()`, no `Where-Object` pipeline)
- `IsEmpty()` / `HasEntries()` — guard helpers
- `EntryCount()` — direct entry count without accessor chain
- `Reset()` — clears data, preserves creation timestamp and axcount
- `Destroy()` — removes from storage, nulls data; subsequent calls throw `ObjectDisposedException`
- Shortcut methods: `Info`, `Debug`, `Verbose`, `Trace`, `Warning`, `Error`, `Critical`, `Fatal`
- `GetDetails()` — returns the `[FileDetails]` companion
- `ToString()` — one-line summary
- `GuardDestroyed()` — internal safety guard on all methods

### Added — FileDetails Fields
| Field key  | Getter method         | Description                                   |
|------------|-----------------------|-----------------------------------------------|
| `created`  | `GetCreated()`        | Timestamp of instance creation                |
| `updated`  | `GetUpdated()`        | Timestamp of last Write / Print / Reset call  |
| `lastacc`  | `GetLastAccessed()`   | Timestamp of last Read / SoakUp / Filter call |
| `acctype`  | `GetLastAccessType()` | Type of most recent interaction               |
| `entries`  | `GetEntries()`        | Current number of log entries                 |
| `axcount`  | `GetAxcount()`        | Total interactions since creation (never reset unless Destroy is called) |

### Added — Logfile Entry Format
```
[dd.MM.yyyy | HH:mm:ss]  [LEVEL]     ->  MESSAGE
```

### Changed
- `FileDetails.RecordWrite()` now only records Write-type interactions.
  A new `RecordPrint()` method records Print-type interactions separately,
  so `acctype` accurately reflects whether the last write was a single Write or a batch Print.
- `Filter()` rewritten: replaced `Where-Object` pipeline with a
  `foreach` loop using `String.Contains()` — no regex overhead, lower pipeline cost.
- Newline characters (`\r`, `\n`) are now explicitly rejected in message validation
  to prevent log-injection into exported files.

### Known Limitations
- **Not designed for parallel execution.** See README.md for details.
- `hidden` members are not truly private in PowerShell — disciplined callers should use public getters only.
- Timestamps are stored as formatted strings; direct time arithmetic requires parsing.

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
- 8 log levels: `DEBUG`, `INFO`, `VERBOSE`, `TRACE`, `WARNING`, `ERROR`, `CRITICAL`, `FATAL` (uppercase identifiers, case-sensitive).
- In-memory storage via `$script:LogfileRegistry` hashtable.
- Standardised return objects `{ code, msg, data }` for all public functions.
