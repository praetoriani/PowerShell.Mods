# VPDLX - Changelog

All notable changes to the **VPDLX** module are documented here.
This file follows a *reverse-chronological* order - the newest version is always at the top.

---

## [1.02.06] - 17.04.2026

### Overview
Advanced Features and Bugfix release. Implements the remaining two tasks from **Priorität 10** of the Developer ToDo-Liste: two new export formats (HTML and NDJSON) for `VPDLXexportlogfile`, and a configurable minimum log level for the `[Logfile]` class. These additions bring the total number of supported export formats to six and allow callers to control log verbosity at construction time.

Resolves two critical defects that were identified during `Demo.ps1` testing after the v1.02.06 release: a wrong return-object evaluation in all nine Public Wrapper functions, and a missing `GetAllEntries()` method on the `[Logfile]` class.

### Fixed - Public Wrapper Functions: Incorrect `VPDLXcore` Return Evaluation

- **Root cause:** All nine Public Wrapper functions in `Public/` called `VPDLXcore -KeyID 'storage'` and then tested whether the result `-is [PSCustomObject]`. Because `VPDLXcore` **always** returns a `[PSCustomObject]` (the standardised `VPDLXreturn` envelope with `.code`, `.msg`, and `.data` fields), this condition was unconditionally `$true` — even on a healthy, fully initialised module. Every wrapper therefore immediately returned a `[FAILED]` error without ever reaching its actual logic.
- **Fix applied to all nine wrappers:**
  - `VPDLXnewlogfile.ps1`
  - `VPDLXislogfile.ps1`
  - `VPDLXdroplogfile.ps1`
  - `VPDLXreadlogfile.ps1`
  - `VPDLXwritelogfile.ps1`
  - `VPDLXexportlogfile.ps1`
  - `VPDLXgetalllogfiles.ps1`
  - `VPDLXresetlogfile.ps1`
  - `VPDLXfilterlogfile.ps1`
- **Corrected pattern:** The wrappers now inspect the `.code` field of the returned envelope. A non-zero `.code` indicates a genuine internal error; only then is the failure path taken. The actual `[FileStorage]` instance is extracted from `.data`:

```powershell
$coreResult = VPDLXcore -KeyID 'storage'
if ($coreResult.code -ne 0) {
    return VPDLXreturn -Code -1 -Message $coreResult.msg
}
$storage = $coreResult.data
```

- **`VPDLXislogfile.ps1` (special case):** This function returns `[bool]` instead of a `VPDLXreturn` object. On error it now returns `$false` and emits a `Write-Warning` diagnostic instead of calling `VPDLXreturn`.
- **`VPDLXexportlogfile.ps1` (special case):** This wrapper calls `VPDLXcore` twice — once for `'storage'` and once for `'export'`. Both call sites have been corrected with the new pattern.

### Fixed - `[Logfile]` Class: `GetAllEntries()` Method Missing

- **Root cause:** `Demo.ps1` STEP 07 called `$logInstance.GetAllEntries()` and `VPDLXexportlogfile` internally called `$logInstance.GetAllEntries()` as well. The method did not exist on the `[Logfile]` class — the implementation was present under the legacy name `SoakUp()`, which was never documented in the public API and was never referenced in the changelog.
- **Symptoms:**
  - STEP 07 threw `MethodNotFound: [Logfile] does not contain a method named 'GetAllEntries'`.
  - STEP 13 (all four export formats: txt, log, csv, json) failed silently because `VPDLXexportlogfile` called the same missing method internally.
- **Fix:** `SoakUp()` is retained as the primary implementation (containing `GuardDestroyed()`, `RecordSoakUp()`, and the data copy). A new thin public wrapper `GetAllEntries()` is added that delegates to `SoakUp()`:

```powershell
[string[]] SoakUp() {
    $this.GuardDestroyed()
    $this._details.RecordSoakUp()
    if ($this._data.Count -eq 0) { return @() }
    return $this._data.ToArray()
}

# Forward-compatible alias — delegates to SoakUp()
[string[]] GetAllEntries() {
    return $this.SoakUp()
}
```

  This approach preserves full backwards compatibility (any code calling `SoakUp()` continues to work) while providing the clean, self-documenting name that the changelog has documented since v1.01.00.

### Changed - No Version Bump

- `VPDLXClasses.ps1`: `GetAllEntries()` method added to `[Logfile]`.
- All nine `Public/*.ps1` files: `VPDLXcore` result evaluation corrected.

### Impact

- `Demo.ps1` now runs to completion without errors across all 16 steps.
- STEP 07 (`GetAllEntries()` class API) returns all log entries correctly.
- STEP 13 (export to disk) succeeds for all four formats (txt, log, csv, json) as well as the two formats added in v1.02.06 (html, ndjson).
- STEP 16 (error handling examples) was not affected by these bugs — all seven sub-scenarios produce the expected controlled error outputs.

### Added - HTML Export Format (`VPDLXexportlogfile -ExportAs 'html'`)

- **New export format key: `html`** - generates a self-contained HTML document with
  embedded CSS styling. No external dependencies - the entire document can be opened
  in any browser directly from disk.

- **Document structure:**
  - **Header section:** Log file name, export timestamp (`dd.MM.yyyy | HH:mm:ss`),
    and total entry count.
  - **Data table:** Three columns - `Timestamp`, `Level`, and `Message`. Each row
    represents one log entry.
  - **Footer:** VPDLX module version stamp.

- **Level-specific row styling:** Each table row receives a CSS class based on the
  log level of the entry. The visual treatment is:

  | Level         | CSS Class       | Visual Treatment                        |
  |---------------|-----------------|------------------------------------------|
  | `INFO`        | `lvl-info`      | Green text colour                        |
  | `DEBUG`       | `lvl-debug`     | Blue text colour                         |
  | `VERBOSE`     | `lvl-verbose`   | Default (dark text)                      |
  | `TRACE`       | `lvl-trace`     | Default (dark text)                      |
  | `WARNING`     | `lvl-warning`   | Orange background + dark text            |
  | `ERROR`       | `lvl-error`     | Red background + white text              |
  | `CRITICAL`    | `lvl-critical`  | Red background + white text              |
  | `FATAL`       | `lvl-fatal`     | Red background + white text              |

- **XSS safety:** All message content is HTML-encoded via
  `[System.Net.WebUtility]::HtmlEncode()` before being inserted into the HTML table.
  This prevents any HTML or JavaScript in log messages from being interpreted by the
  browser.

- **Performance:** Table row assembly uses `[System.Text.StringBuilder]` to avoid
  repeated string concatenation overhead when exporting large log files.

- **Print-friendly:** The CSS includes a print media query that preserves the table
  layout and level colours when the document is printed or saved as PDF from a browser.

- **Respects `-NoBOM` and `-Override` switches** - same behaviour as all other export
  formats.

**Usage example:**

```powershell
# Export as HTML
$r = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'html'
if ($r.code -eq 0) { Start-Process $r.data }   # opens in default browser

# Export as HTML with BOM-free UTF-8
$r = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'html' -NoBOM
```

### Added - NDJSON Export Format (`VPDLXexportlogfile -ExportAs 'ndjson'`)

- **New export format key: `ndjson`** - Newline-Delimited JSON. Each log entry is
  serialised as a single compact JSON object on its own line. There is no root
  wrapper, no opening `[`, and no trailing `]` - just one JSON object per line.

- **Output format:**
  ```
  {"Timestamp":"11.04.2026 | 14:30:01","Level":"INFO","Message":"Application started."}
  {"Timestamp":"11.04.2026 | 14:30:02","Level":"WARNING","Message":"Disk space low."}
  {"Timestamp":"11.04.2026 | 14:30:03","Level":"ERROR","Message":"Connection failed."}
  ```

- **Why NDJSON:**
  NDJSON (also known as JSON Lines / `.jsonl`) is the standard format for streaming
  log data into modern observability pipelines. Each line is a valid, independent
  JSON document that can be parsed without reading the entire file. This makes it
  ideal for:
  - **Elasticsearch / Logstash** - `json` codec reads NDJSON natively
  - **AWS Kinesis / CloudWatch** - one record per line
  - **Grafana Loki** - direct NDJSON ingestion
  - **Kafka** - one message per line
  - **`jq` command-line processing** - `cat log.ndjson | jq .Level`
  - **Streaming uploads** - send lines as they arrive, no buffering needed

- **Entry parsing:** Uses the same parsing logic as the existing CSV and JSON export
  blocks - each log line is split into Timestamp, Level, and Message components.
  Each parsed entry is converted via `ConvertTo-Json -Compress` to produce a single
  compact line.

- **Respects `-NoBOM` and `-Override` switches.**

**Usage example:**

```powershell
# Export as NDJSON
$r = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'ndjson'

# Export as NDJSON for Unix pipeline consumption
$r = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM
```

### Added - Configurable Minimum Log Level (`[Logfile]` Constructor Overload)

- **New constructor overload: `[Logfile]::new([string] $name, [string] $minLevel)`**
  Creates a new virtual log file with a minimum severity threshold. Any `Write()` or
  `Print()` call with a level below the threshold is silently discarded - no exception
  is thrown, no side effects occur (no metadata update, no entry count change).

- **Severity ranking** (low → high):

  | Level      | Severity Index |
  |------------|---------------|
  | `trace`    | 0             |
  | `debug`    | 1             |
  | `verbose`  | 2             |
  | `info`     | 3             |
  | `warning`  | 4             |
  | `error`    | 5             |
  | `critical` | 6             |
  | `fatal`    | 7             |

  This ranking is exposed as a static hashtable: `[Logfile]::LevelSeverity`.

- **New hidden instance fields:**
  - `$_minLevelIndex` (`[int]`) - the numeric severity threshold. `-1` means no
    filter is active (all entries accepted). Set to the severity index of the
    configured minimum level (e.g. `4` for `warning`).
  - `$_minLevelName` (`[string]`) - the human-readable name of the configured
    minimum level (e.g. `'warning'`). Empty string when no filter is active.

- **New hidden method: `_InitLogfile()`** - shared initialisation logic used by both
  constructors. Contains all the code that was previously in the single-argument
  constructor (name validation, storage registration, FileDetails creation, data
  list initialisation). This follows the DRY principle and ensures both constructors
  behave identically for the common initialisation path.

- **New public method: `GetMinLogLevel()`** - returns the configured minimum level
  name as a `[string]`, or `'none'` if no filter is active.

- **`Write()` filtering behaviour:** At the top of `Write()`, before any validation
  or entry formatting, the method checks whether the entry's level meets the minimum
  severity threshold:
  ```
  if $_minLevelIndex is not -1
    and the entry's severity < $_minLevelIndex
  then
    return silently (no exception, no metadata update)
  ```

- **`Print()` filtering behaviour:** At the top of `Print()`, the same severity
  check is performed. If the batch level is below the minimum, the entire batch is
  silently discarded - after parameter validation (null/empty checks) but before
  message validation and entry formatting.

- **`ToString()` updated:** When a minimum level filter is active, `ToString()`
  appends `| MinLevel: <name>` to the output string (e.g.
  `Logfile: ProdLog | Entries: 42 | Created: 11.04.2026 | 14:30:00 | MinLevel: warning`).

- **Original constructor unchanged:** `[Logfile]::new([string] $name)` continues to
  create log files with no minimum level filter (`$_minLevelIndex = -1`). All
  existing code remains fully compatible.

**Usage examples:**

```powershell
# Create a production log that only records warnings and above
$prodLog = [Logfile]::new('ProdLog', 'warning')

$prodLog.Info('This will be silently discarded.')       # below 'warning'
$prodLog.Debug('This too.')                              # below 'warning'
$prodLog.Warning('This will be recorded.')               # >= 'warning'
$prodLog.Error('This will be recorded.')                 # >= 'warning'
$prodLog.Fatal('This will be recorded.')                 # >= 'warning'

$prodLog.EntryCount()   # → 3 (only warning, error, fatal)

# Check the configured minimum level
$prodLog.GetMinLogLevel()   # → 'warning'

# Create a log with no filter (default behaviour)
$devLog = [Logfile]::new('DevLog')
$devLog.GetMinLogLevel()    # → 'none'

# Severity ranking is available as a static property
[Logfile]::LevelSeverity
# → @{ trace = 0; debug = 1; verbose = 2; info = 3; warning = 4; error = 5; critical = 6; fatal = 7 }
```

### Changed - Export Format Table (Updated)

The complete list of supported export formats as of v1.02.06:

| Key      | Extension  | Description                                                         |
|----------|------------|---------------------------------------------------------------------|
| `txt`    | `.txt`     | Plain text - each log line written as-is                            |
| `log`    | `.log`     | Same as `txt` with `.log` extension                                 |
| `csv`    | `.csv`     | RFC 4180-compliant: `"Timestamp","Level","Message"`                 |
| `json`   | `.json`    | JSON object: `{ LogFile, ExportedAt, EntryCount, Entries[] }`       |
| `html`   | `.html`    | Self-contained HTML document with embedded CSS **(new)**             |
| `ndjson` | `.ndjson`  | Newline-Delimited JSON - one object per line **(new)**               |

### Changed - Manifest & Module Updates

- **`VPDLX.psd1`:**
  - `ModuleVersion` updated from `1.02.05` to `1.02.06`.
  - `Description` updated to reflect new export formats and min-level constructor.
  - `ReleaseNotes` updated with the full v1.02.06 entry.
- **`VPDLX.psm1`:**
  - `$script:appinfo.appvers` updated to `'1.02.06'`.
  - `$script:export` extended with `html` (`.html`) and `ndjson` (`.ndjson`) keys.
  - Architecture overview in `.DESCRIPTION` updated for new formats.
  - Changelog section extended with v1.02.06 entry.
  - `VPDLXcore` `.DESCRIPTION` updated to mention html/ndjson in the export key.
- **`VPDLXClasses.ps1`:**
  - Version updated to `1.02.06`.
  - Static `LevelSeverity` hashtable added to `[Logfile]`.
  - Hidden fields `$_minLevelIndex` and `$_minLevelName` added.
  - Hidden method `_InitLogfile()` extracted from original constructor.
  - New constructor overload `Logfile([string] $name, [string] $minLevel)` added.
  - `Write()` and `Print()` updated with severity filtering.
  - `GetMinLogLevel()` public method added.
  - `ToString()` updated to include minimum level.
  - `.NOTES` header updated with feature description.
- **`VPDLXexportlogfile.ps1`:**
  - HTML export block added with full CSS styling and StringBuilder assembly.
  - NDJSON export block added with per-line ConvertTo-Json -Compress.
  - Comment-based help updated with new format descriptions.
- **No changes to `VPDLXreturn.ps1`, or any other existing public wrapper files.**

### Summary of New Features

| Feature                     | Access                                              | Description                                           |
|-----------------------------|------------------------------------------------------|-------------------------------------------------------|
| HTML export                 | `VPDLXexportlogfile -ExportAs 'html'`                | Styled HTML document with level-coloured rows          |
| NDJSON export               | `VPDLXexportlogfile -ExportAs 'ndjson'`              | One JSON object per line for streaming pipelines       |
| Minimum log level           | `[Logfile]::new('Name', 'warning')`                  | Silently discards entries below the threshold           |
| `GetMinLogLevel()`          | `$log.GetMinLogLevel()`                              | Returns configured minimum level or `'none'`           |
| `[Logfile]::LevelSeverity`  | Static property                                      | Hashtable mapping level names to severity indices      |

---

## [1.02.05] - 11.04.2026

### Overview
New Wrapper Functions & Module Statistics release. Implements four features from
**Priorität 10** of the Developer ToDo-Liste: three new public wrapper functions
(`VPDLXgetalllogfiles`, `VPDLXresetlogfile`, `VPDLXfilterlogfile`) and a new
`VPDLXcore -KeyID 'stats'` accessor for module-wide statistics. These additions
complete the public wrapper API, giving callers standardised, safe access to
every major log file operation without needing to interact with the class API
directly.

### Added - `VPDLXgetalllogfiles` (List All Active Log Files)

- **New file: `Public\VPDLXgetalllogfiles.ps1`** - a parameterless public wrapper
  that returns a summary of every virtual log file currently registered in the
  module’s in-memory storage.
- Iterates all registered names via `FileStorage.GetNames()`, retrieves each
  `[Logfile]` instance, and collects the following properties into a
  `[PSCustomObject]` per log file:

  | Property       | Type       | Description                                 |
  |----------------|------------|---------------------------------------------|
  | `Name`         | `string`   | Log file name (case-preserved)              |
  | `EntryCount`   | `int`      | Current number of log entries                |
  | `Created`      | `string`   | Creation timestamp (`dd.MM.yyyy \| HH:mm:ss`) |
  | `Updated`      | `string`   | Last write/reset timestamp                  |
  | `LastAccessed` | `string`   | Last read/filter/export timestamp           |
  | `AccessCount`  | `int`      | Total interaction count since creation      |

- **Return contract (via `VPDLXreturn`):**
  - `code  0` - success; `.data` holds `[PSCustomObject[]]` (empty array `@()` if
    no log files are registered).
  - `code -1` - failure; `.msg` describes the reason.
- **Read-only operation:** Calls only public getter methods on `[FileDetails]`
  and `[Logfile]`. Does **not** increment `axcount` or update `lastacc` on any
  log file. Safe for monitoring and dashboard use.
- Skips destroyed instances gracefully (catches `ObjectDisposedException`,
  continues enumeration) and logs skipped names via `Write-Verbose`.

**Usage example:**

```powershell
$result = VPDLXgetalllogfiles
if ($result.code -eq 0) {
    $result.data | Format-Table -AutoSize
}
```

### Added - `VPDLXresetlogfile` (Clear Log File Entries)

- **New file: `Public\VPDLXresetlogfile.ps1`** - a public wrapper that clears all
  entries from a named virtual log file while preserving the log file itself
  (its registration, name, and metadata skeleton).
- Wraps the `[Logfile].Reset()` method in the standardised error-handling and
  return-object pattern established by all other VPDLX public wrappers.
- **Parameter:**
  - `-Logfile` (mandatory, position 0) - the name of the log file to reset.
    Case-insensitive lookup, leading/trailing whitespace trimmed.
- **Return contract (via `VPDLXreturn`):**
  - `code  0` - success; `.data` holds the entry count **before** the reset
    (so the caller knows how many entries were cleared).
  - `code -1` - failure; `.msg` describes the reason.
- **Key behaviour:**
  - The log file remains registered in `FileStorage` and can immediately accept
    new entries after reset.
  - `_details.ApplyReset()` updates: `updated`, `lastacc`, `acctype` (→ `'Reset'`),
    `axcount` (+1), `entries` (→ 0). The `created` timestamp is preserved.
- **Difference from `VPDLXdroplogfile`:**
  - `VPDLXresetlogfile` - clears DATA, keeps the log file alive.
  - `VPDLXdroplogfile` - destroys EVERYTHING (data + metadata + registration).

**Usage example:**

```powershell
# Log rotation: export, then clear
$export = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json'
if ($export.code -eq 0) {
    $reset = VPDLXresetlogfile -Logfile 'AppLog'
    Write-Host "Exported and cleared $($reset.data) entries."
}
```

### Added - `VPDLXfilterlogfile` (Filter Entries by Level)

- **New file: `Public\VPDLXfilterlogfile.ps1`** - a public wrapper that retrieves
  all log entries matching a specific log level from a named virtual log file.
- Wraps the `[Logfile].FilterByLevel()` method in the standardised error-handling
  and return-object pattern.
- **Parameters:**
  - `-Logfile` (mandatory, position 0) - the name of the log file to filter.
  - `-Level` (mandatory, position 1) - the log level to filter for. Validated by
    `[ValidateSet]` at the binding layer (provides tab-completion in interactive
    sessions and editors).
    Accepted values: `info`, `debug`, `verbose`, `trace`, `warning`, `error`,
    `critical`, `fatal` (case-insensitive).
- **Return contract (via `VPDLXreturn`):**
  - `code  0` - success; `.data` holds a `[PSCustomObject]` with:

    | Property  | Type        | Description                        |
    |-----------|-------------|------------------------------------|
    | `Entries` | `string[]`  | Matching log lines (or empty `@()`)|
    | `Count`   | `int`       | Number of matches                  |
    | `Level`   | `string`    | The level that was filtered        |

  - `code -1` - failure; `.msg` describes the reason.
- **Matching strategy (from `[Logfile].FilterByLevel()`):** Each log line is
  checked with `String.Contains()` against the uppercase bracket notation
  (e.g. `[WARNING]`). This is a fixed-string comparison - faster than regex.
- Updates `_details.RecordFilterByLevel()` on the log file - modifies `lastacc`,
  `acctype` (→ `'FilterByLevel'`), and `axcount`.

**Usage example:**

```powershell
$result = VPDLXfilterlogfile -Logfile 'AppLog' -Level 'error'
if ($result.code -eq 0 -and $result.data.Count -gt 0) {
    Write-Host "Found $($result.data.Count) error(s):"
    $result.data.Entries | ForEach-Object { Write-Host "  $_" }
}
```

### Added - `VPDLXcore -KeyID 'stats'` (Module-Wide Statistics)

- **New `switch` case in `VPDLXcore`** (defined in `VPDLX.psm1`, Section 5) —
  returns a `[PSCustomObject]` containing aggregated module-wide statistics.
- Iterates all registered log files and collects:

  | Property          | Type     | Description                                   |
  |-------------------|----------|-----------------------------------------------|
  | `ActiveLogfiles`  | `int`    | Number of currently registered log files       |
  | `TotalEntries`    | `int`    | Sum of all entries across all log files         |
  | `MaxEntries`      | `int`    | Highest entry count among all log files         |
  | `MaxEntriesLog`   | `string` | Name of the log file with the most entries      |
  | `MinEntries`      | `int`    | Lowest entry count among all log files          |
  | `MinEntriesLog`   | `string` | Name of the log file with the fewest entries    |
  | `ModuleVersion`   | `string` | Current VPDLX module version                    |

- **Read-only operation:** Uses `EntryCount()` which is a simple `_data.Count`
  call. Does **not** modify any log file state.

**Usage example:**

```powershell
$stats = (VPDLXcore -KeyID 'stats').data
Write-Host "Active logs: $($stats.ActiveLogfiles), Total entries: $($stats.TotalEntries)"
Write-Host "Largest: $($stats.MaxEntriesLog) ($($stats.MaxEntries) entries)"
```

### Changed - Manifest & Module Updates

- **`VPDLX.psd1`:**
  - `ModuleVersion` updated from `1.02.04` to `1.02.05`.
  - `FunctionsToExport` extended with `VPDLXgetalllogfiles`, `VPDLXresetlogfile`,
    and `VPDLXfilterlogfile`.
  - `FileList` extended with the three new function files.
  - `ReleaseNotes` updated with the full v1.02.05 entry.
- **`VPDLX.psm1`:**
  - `$script:appinfo.appvers` updated to `'1.02.05'`.
  - Architecture overview in `.DESCRIPTION` extended with the three new files.
  - Changelog section extended with v1.02.05 entry.
  - `VPDLXcore` function:
    - New `'stats'` case added (see above).
    - `.DESCRIPTION` and `.PARAMETER` documentation updated to include `'stats'`.
    - Default/error message updated to list `'stats'` as a valid key.
- **No changes to `VPDLXClasses.ps1`, `VPDLXreturn.ps1`, or any existing public
  wrapper files.** The three new wrappers build on existing class methods
  (`Reset()`, `FilterByLevel()`, `GetNames()`, `Get()`, `EntryCount()`,
  `GetDetails()`) without modification.

### Summary of New Public API Surface

| Function              | Parameters                  | `.data` on Success                                |
|-----------------------|-----------------------------|---------------------------------------------------|
| `VPDLXgetalllogfiles` | *(none)*                    | `PSCustomObject[]` - one per log file              |
| `VPDLXresetlogfile`   | `-Logfile <name>`           | `int` - entries cleared                            |
| `VPDLXfilterlogfile`  | `-Logfile <name> -Level <l>`| `PSCustomObject { Entries, Count, Level }`         |
| `VPDLXcore -KeyID 'stats'` | *(via KeyID)*          | `PSCustomObject { ActiveLogfiles, TotalEntries, … }`|

---

## [1.02.04] - 11.04.2026

### Overview
Performance & Quality improvement release. Implements all three tasks from
**Priorität 9** of the Developer ToDo-Liste: a pre-import environment check,
a configurable maximum message length, and a BOM-free UTF-8 export option.
These changes harden the module against edge-case failures and improve
interoperability with external log-processing tools.

### Added - Pre-Import Environment Validation (`VPDLX.Precheck.ps1`)

- **New file: `VPDLX.Precheck.ps1`** - a lightweight pre-import script that
  validates the PowerShell environment before the root module (`VPDLX.psm1`)
  is loaded.

- **Registered via `ScriptsToProcess` in `VPDLX.psd1`** - PowerShell executes
  this script automatically when `Import-Module VPDLX` is called, before any
  class definitions or function files are processed.

- **Check performed: PowerShell version >= 5.1.**
  VPDLX uses PowerShell 5 class syntax, generic collections, and
  TypeAccelerator registration - all of which require at least PS 5.1.
  Running on PS 4.0 or earlier would produce cryptic parse errors that do not
  clearly indicate the root cause. The precheck script catches this early and
  emits a clear, actionable error message:
  ```
  VPDLX requires PowerShell 5.1 or higher.
  Your current PowerShell version is 4.0.
  ...
  ```

- **Design decision:** The script uses `Write-Error -ErrorAction Stop` to
  prevent module loading entirely. A `Write-Warning` would allow the module
  to continue loading and fail later with confusing errors. Stopping here
  gives the user a single, clear diagnostic message.

- **Silent on success** - when the check passes, the precheck produces no
  output (only a `Write-Verbose` message for diagnostic tracing).

### Added - Configurable Maximum Message Length

- **New static property: `[Logfile]::MaxMessageLength`** (default: `8192`).
  This property defines the upper bound for the length of a single log
  message. Any message exceeding this limit is rejected by `ValidateMessage()`
  with a descriptive `ArgumentException` that includes:
  - The actual length of the message
  - The configured maximum length
  - Instructions on how to increase the limit

- **Why this matters:**
  Without a length limit, a caller could accidentally pass a multi-megabyte
  string (e.g. the contents of an entire file, a serialised object, or a
  runaway string concatenation) as a single log message. Since VPDLX stores
  all entries in a `List<string>` in RAM, a single oversized message could
  consume significant memory and degrade performance for the entire session.

- **Configurable at runtime** - callers can adjust the limit without
  modifying source code:
  ```powershell
  [Logfile]::MaxMessageLength = 16384   # double the default
  [Logfile]::MaxMessageLength = 1024    # stricter limit for production
  ```
  The minimum sensible value is `10` - setting it lower would conflict with
  the existing "at least 3 non-whitespace characters" rule.

- **Validation order in `ValidateMessage()`** (all four rules):
  1. Must not be null, empty, or whitespace-only
  2. Must contain at least 3 non-whitespace characters
  3. Must not contain newline characters (CR or LF)
  4. Must not exceed `[Logfile]::MaxMessageLength` characters **(new)**

- **Backwards compatible** - the default limit of 8192 characters is generous
  enough that no existing caller should be affected. Messages shorter than
  8192 characters pass without any change in behaviour.

### Added - BOM-Free UTF-8 Export (`-NoBOM` Switch)

- **New switch parameter: `-NoBOM` on `VPDLXexportlogfile`.**
  When specified, forces BOM-free UTF-8 encoding on all PowerShell versions,
  including Windows PowerShell 5.1.

- **The problem this solves:**
  Windows PowerShell 5.1 writes a 3-byte UTF-8 BOM (Byte Order Mark:
  `EF BB BF`) at the beginning of files when using `Set-Content -Encoding UTF8`.
  This invisible prefix causes issues with:
  - **Unix/Linux log aggregators** (Filebeat, Fluentd, Logstash) that do not
    expect a BOM and may treat it as data corruption or display garbled
    characters at the start of the first log entry
  - **JSON parsers** that interpret the BOM as invalid JSON before the
    opening `{` bracket, causing parse failures
  - **CSV readers** in non-Microsoft tools that show the BOM as a visible
    character (`﻿`) in the first header field
  - **Web APIs** that interpret the BOM as part of the request body

- **Implementation:**
  When `-NoBOM` is specified, the export function bypasses `Set-Content`
  entirely and writes the file via `[System.IO.File]::WriteAllText()` with
  an explicit BOM-free encoder:
  ```powershell
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($filePath, $content, $utf8NoBom)
  ```
  The `$false` argument to `UTF8Encoding` suppresses BOM generation.

- **Behaviour on PowerShell 7.x:**
  On PS 7.x, `-NoBOM` is effectively a no-op because PS 7 already writes
  BOM-free UTF-8 by default. However, using `-NoBOM` explicitly is still
  recommended for scripts that must work across both PS editions, as it
  makes the encoding intent clear and self-documenting.

- **Usage example:**
  ```powershell
  VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json' -NoBOM
  ```

- **Applies to all four export formats** - `txt`, `log`, `csv`, and `json`
  all respect the `-NoBOM` switch. The encoding logic is encapsulated in a
  single internal helper scriptblock so all formats share the same
  implementation.

### Changed
- Module version updated to `1.02.04` in all files (psd1, psm1, VPDLXClasses.ps1).
- `$script:appinfo.appvers` updated to `'1.02.04'`.
- `VPDLX.psd1` `ScriptsToProcess` activated (was previously commented out).
- `VPDLX.psd1` `FileList` updated to include `VPDLX.Precheck.ps1`.
- Developer ToDo-Liste: Priorität 9 tasks marked as completed.

---

## [1.02.03] - 11.04.2026

### Overview
Critical bugfix release targeting the `Destroy()` and `ToString()` methods in
`[Logfile]`. Three issues are resolved in this version, all affecting
`Classes/Logfile.ps1`. Together, they bring `Destroy()` and `ToString()` in line
with the defensive `GuardDestroyed()` contract that every other public method
already follows.

### Fixed - `Destroy()` Hardening (Issue #1 + Issue #6)

- **`Destroy()` now calls `GuardDestroyed()` at the very beginning** (Issue #1).
  Previously, calling `Destroy()` a second time on an already-destroyed instance
  silently succeeded instead of throwing `ObjectDisposedException`. This was
  inconsistent with every other public method in the class. The redundant
  `if ($null -ne $this._data)` conditional has been removed - `GuardDestroyed()`
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

### Fixed - `ToString()` Post-Destroy Safety (Issue #3)

- **`ToString()` now calls `GuardDestroyed()` at the top** (Issue #3).
  Previously, `ToString()` contained a partial null-check for `_data` but
  unconditionally accessed `_details.GetCreated()`. After `Destroy()`, this
  caused an unhelpful `NullReferenceException` instead of the expected
  `ObjectDisposedException`. The partial `if/else` construct has been removed
  - with `GuardDestroyed()` in place, both `_data` and `_details` are guaranteed
  non-null when the return statement executes.

### Fixed - `FilterByLevel()` Call-Order + Label (Issue #2 + Issue #4)

- **`RecordFilter()` call moved from before to after the `foreach` loop** (Issue #2).
  In `Logfile.FilterByLevel()`, the metadata-recording call
  `$this._details.RecordFilter()` was placed *before* the `foreach` loop that
  collects matching entries. This meant `_lastAccessed` and `_axcount` were updated
  even if the method returned early or encountered an error during iteration.
  The call has been moved to immediately *after* the loop, just before `return`,
  so metadata is recorded only when filtering actually completes successfully.

- **`RecordFilter()` renamed to `RecordFilterByLevel()`** (Issue #4).
  The hidden method `RecordFilter()` in `[FileDetails]` set
  `_lastAccessType = 'Filter'` - a generic label that did not clearly identify
  which operation was performed. The method has been renamed to
  `RecordFilterByLevel()` and the label updated to `'FilterByLevel'`, matching
  the public method name. The single call-site in `Logfile.ps1` has been updated
  accordingly.

### Fixed - `FunctionsToExport` Single Source of Truth (Issue #5)

- **`Export-ModuleMember` call removed from `VPDLX.psm1` Section 7** (Issue #5).
  When a `.psd1` manifest is present, PowerShell ignores any `Export-ModuleMember`
  calls in the `.psm1` file - the manifest's `FunctionsToExport` array takes
  precedence. The `Export-ModuleMember -Function $PublicFunctions` call was
  therefore misleading and has been replaced with an explanatory comment.

- **`VPDLX.psd1` `FunctionsToExport` annotated as SINGLE SOURCE OF TRUTH.**
  A comment block has been added above the `FunctionsToExport` array in the
  manifest, clearly marking it as the authoritative list and instructing future
  developers to add new public functions there.

### Fixed - `VPDLXreturn` Status Code Extensibility (Issue #8)

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

### Improved - `Print()` Batch Validation Diagnostics (Issue #7)

- **Pre-validation loop now tracks the 0-based element index** (Issue #7).
  When `ValidateMessage()` throws `ArgumentException` inside `Print()`, the
  exception is caught, enriched with the element index and a safe preview of
  the offending value, and re-thrown as a new `ArgumentException` with the
  parameter name `'messages'`. The preview is truncated to 40 characters,
  and control characters (`\r`, `\n`) are escaped to their literal
  backslash representations so they are visible in the error output.
  `ValidateMessage()` itself remains unchanged - the improvement is fully
  isolated to `Print()`.

### Fixed - FileStorage Type Safety via Class Consolidation (Issue #9)

- **Three separate class files merged into `Classes/VPDLXClasses.ps1`** (Issue #9).
  `FileDetails.ps1`, `FileStorage.ps1`, and `Logfile.ps1` have been consolidated
  into a single file. This eliminates the PowerShell 5.1 forward-reference
  limitation that forced `FileStorage` to use `[object]` instead of `[Logfile]`
  in its dictionary, `Get()` return type, and `Add()` parameter type.

- **`FileStorage._registry` is now `Dictionary[string, Logfile]`.**
  Inserting a non-`Logfile` object is now a type error at the insertion point
  instead of silently succeeding.

- **`FileStorage.Get()` returns `[Logfile]` instead of `[object]`.**
  Callers no longer need to cast the result - IntelliSense and static type
  checking work correctly on the returned reference.

- **`FileStorage.Add()` accepts `[Logfile]` instead of `[object]`.**
  Combined with the typed dictionary, this provides full compile-time type
  safety for the registry.

- **`VPDLX.psm1` Section 2** updated to load the single `VPDLXClasses.ps1`
  instead of three separate files.

- **`VPDLX.psd1` `FileList`** updated to reference the new consolidated file.

### Added - `FileStorage.DestroyAll()` + `OnRemove` Integration (Issue #10)

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
- Version stays at `1.02.03` - all fixes are bundled into the same release.
- Developer ToDo-Liste updated: all Prioritäten (1–8) marked as completed.
- Old class files (`FileDetails.ps1`, `FileStorage.ps1`, `Logfile.ps1`)
  replaced by consolidated `Classes/VPDLXClasses.ps1`.

---

## [1.01.02] - 06.04.2026

### Overview
Introduces the complete **Public Wrapper Layer** - a set of standalone `.ps1` files
in `Public/` that expose safe, standardised PowerShell functions on top of the
class-based internals from v1.01.00. Each wrapper follows an identical defensive
pipeline pattern and returns a consistent `{ code, msg, data }` object via
`VPDLXreturn`. This release also adds the first physical export capability:
`VPDLXexportlogfile` writes a virtual log file to disk in one of four formats.

### Added - Public Wrapper Functions

| Function | Replaces (v1.00.00) | Description |
|---|---|---|
| `VPDLXnewlogfile` | `CreateNewLogfile` | Creates a new named virtual log file via `[Logfile]::new()`. Returns `code 0` + the new instance name in `.data` on success. |
| `VPDLXislogfile` | - *(new)* | Checks whether a named log file exists in `$script:storage` via `.Contains()`. Returns `$true` / `$false` directly (not a return object). |
| `VPDLXdroplogfile` | `DeleteLogfile` | Calls `.Destroy()` on the named instance and removes it from storage. Five-stage defensive pipeline including double-verification of removal. |
| `VPDLXreadlogfile` | `ReadLogfileEntry` | Reads a specific line (1-based index) via `.Read()`. Index is automatically clamped; effective line number is reported in `.msg`. Returns the log line as `string` in `.data`. |
| `VPDLXwritelogfile` | `WriteLogfileEntry` | Appends a formatted entry via `.Write(level, message)`. Level validated by `[ValidateSet]` at binding layer AND by `[Logfile].ValidateLevel()` internally. Returns new `EntryCount()` in `.data`. |
| `VPDLXexportlogfile` | - *(new)* | Exports a virtual log file to a physical file on disk. See *Export Function* section below. |

### Added - Export Function (`VPDLXexportlogfile`)

`VPDLXexportlogfile` is the centrepiece of v1.01.02. It executes an 8-stage pipeline:

1. **Pre-flight** - retrieves `$script:storage` and `$script:export` via `VPDLXcore`
2. **Format validation** - `ExportAs` is validated at runtime against `$script:export` keys (dynamic, not a static `[ValidateSet]`)
3. **Existence check** - confirms the named log file is registered in storage
4. **Instance retrieval** - `Get()` with null-guard
5. **Empty-log guard** - rejects export of logs with zero entries
6. **Directory creation** - creates the full `LogPath` tree automatically (`New-Item -Force`) if it does not yet exist
7. **Override logic** - without `-Override`: blocks overwrite; with `-Override`: removes existing file before writing
8. **Serialisation + write** - format-specific serialisation, then `Set-Content -Encoding UTF8`

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

### Added - Wrapper Design Conventions
All six Public Wrapper functions share the following design conventions:
- **Defensive pipeline:** every stage runs in order; any failure returns immediately with `code -1` and a descriptive `.msg`
- **Scope bridge:** all wrappers access module internals via `VPDLXcore` (dot-sourced functions cannot read `$script:*` variables directly)
- **`[ObjectDisposedException]` handling:** all wrappers that touch a `[Logfile]` instance catch this exception separately to report destroyed-instance scenarios clearly
- **Name trimming:** all `Logfile` parameters are trimmed of leading/trailing whitespace before use, consistent with the `[Logfile]` constructor
- **Return objects:** all wrappers (except `VPDLXislogfile`) return `[PSCustomObject] { code, msg, data }` via `VPDLXreturn`

---

## [1.01.01] - 06.04.2026

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

## [1.01.00] - 06.04.2026

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

### Added - Architecture
- Class `[Logfile]` - central user-facing class; replaces all v1.00 functions.
- Class `[FileStorage]` - module-level singleton registry for all active `[Logfile]` instances.
- Class `[FileDetails]` - metadata companion for each `[Logfile]` instance.
- Private function `VPDLXreturn` - standardised return-object factory `{ code, msg, data }`.
- Public function `VPDLXcore` - controlled read-only accessor for module-scope variables
  (`appinfo`, `storage`, `export`).
- Module-scope variable `$script:export` - hashtable of supported export formats
  (`txt`, `csv`, `json`, `log`) for use by future export functions.
- TypeAccelerator registration on module load - all three classes available as
  `[Logfile]`, `[FileDetails]`, `[FileStorage]` after `Import-Module` (no `using module` required).
- TypeAccelerator cleanup in `OnRemove` handler - no type conflicts on module re-import.

### Added - Log Levels
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

### Added - `[Logfile]` Methods
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
| Shortcut methods | `.Info()`, `.Debug()`, `.Verbose()`, `.Trace()`, `.Warning()`, `.Error()`, `.Critical()`, `.Fatal()` - thin wrappers around `Write()` |

### Added - `[FileDetails]` Fields
| Field key | Getter method | Description |
|---|---|---|
| `created` | `GetCreated()` | Timestamp of instance creation |
| `updated` | `GetUpdated()` | Timestamp of last `Write` / `Print` / `Reset` call |
| `lastacc` | `GetLastAccessed()` | Timestamp of last `Read` / `GetAllEntries()` / `FilterByLevel()` call |
| `acctype` | `GetLastAccessType()` | Type of most recent interaction (`write`, `print`, `read`, `reset`, …) |
| `entries` | `GetEntries()` | Current number of log entries |
| `axcount` | `GetAxcount()` | Total number of interactions since creation (never reset unless `Destroy()` is called) |

### Added - Log Entry Format
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
  `foreach` loop and `String.Contains()` - no regex overhead, lower pipeline cost.
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

## [1.00.00] - 05.04.2026

### Overview
Initial release of the VPDLX module. Function-based architecture.

### Added
- Public function `CreateNewLogfile([string] $Name)` - creates a new in-memory log file.
- Public function `WriteLogfileEntry([string] $Name, [string] $Level, [string] $Message)` - writes a single log entry.
- Public function `ReadLogfileEntry([string] $Name, [int] $Line)` - reads a specific line.
- Public function `ResetLogfile([string] $Name)` - clears all entries.
- Public function `DeleteLogfile([string] $Name)` - removes the log file from memory.
- 8 log levels: `DEBUG`, `INFO`, `VERBOSE`, `TRACE`, `WARNING`, `ERROR`, `CRITICAL`, `FATAL`
  (uppercase identifiers, case-sensitive).
- In-memory storage via `$script:LogfileRegistry` hashtable.
- Standardised return objects `{ code, msg, data }` for all public functions.
