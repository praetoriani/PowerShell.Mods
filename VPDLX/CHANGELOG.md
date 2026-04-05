# CHANGELOG — VPDLX

All notable changes to this module are documented in this file.
Versions follow the `Major.Minor.Patch` scheme used in the module manifest.

---

## [1.00.00] — 2026-04-05

### Project Bootstrap

- Repository structure created: `VPDLX/`, `Public/`, `Private/`.
- Module skeleton (`VPDLX.psm1`, `VPDLX.psd1`) committed.
- Module-scope variables initialised:
  `$script:loginstances`, `$script:filestorage`, `$script:loglevel`, `$script:exit`.

### New Functions

#### `VPDLXreturn` *(Private)*
- Creates standardised `PSCustomObject { .code, .msg, .data }` return objects.
- Used internally by all public functions to guarantee a uniform return schema.
- `.code = 0` signals success; `.code = -1` signals failure.
- `.data` carries the return payload or `$null` on failure.

#### `VPDLXcore` *(Public)*
- Type-safe read/write accessor for all `$script:` module-scope variables.
- Exposes four scopes via `-Scope`: `'instances'`, `'storage'`, `'loglevel'`, `'exit'`.
- Read access (`-Permission 'read'`) returns the current value via `.data`.
- Write access (`-Permission 'write'`) validates the type before assignment;
  type mismatches are rejected and the original value is left unchanged.
- Returns a standardised `VPDLXreturn` object.

#### `CreateNewLogfile` *(Public)*
- Creates a new named virtual log file instance in `$script:loginstances`.
- **Filename validation**: only alphanumeric characters plus `_`, `-`, `.` are permitted;
  minimum 3 characters, maximum 64 characters.
- Duplicate detection: returns `.code = -1` if a log file with the same name already exists.
- On success, the normalised (lowercase) key is stored in `$script:filestorage` and a
  fully initialised instance hashtable is written to `$script:loginstances`.
- Instance schema on creation:
  ```
  name    = <original filename string>
  data    = [System.Collections.Generic.List[string]] (empty)
  info    = @{ created = <timestamp>; updated = <timestamp>; entries = 0 }
  ```
- Returns the new instance name as `.data` on success.

#### `WriteLogfileEntry` *(Public)*
- Appends a formatted, timestamped log entry to the specified virtual log file.
- **Existence check**: validates `$script:filestorage` before writing.
- **Log level check**: validates that `-LogLevel` exists in `$script:loglevel`.
- **Message check**: `-Message` must contain at least 3 non-whitespace characters.
- Entry format: `[yyyy-MM-dd HH:mm:ss] [LOGLEVEL] Message`
- Increments `$script:loginstances[key]['info']['entries']` after every successful write.
- Updates `$script:loginstances[key]['info']['updated']` timestamp.
- Returns the formatted entry string as `.data` on success.

#### `ReadLogfileEntry` *(Public)*
- Returns a single entry string from the specified virtual log file by 1-based line number.
- **Existence check**: validates `$script:filestorage` before reading.
- **Empty log guard**: returns `.code = -1` if the log file has zero entries.
- **Auto-clamp**: if `-Line` exceeds the total entry count, the last entry is returned
  automatically (no error is raised).
- Returns the entry string as `.data` on success.

#### `ResetLogfile` *(Public)*
- Clears all log entries from the specified virtual log file.
- **Existence check**: validates `$script:filestorage` before resetting.
- Replaces `data` with a new empty `List[string]`; sets `entries` to `0`.
- Preserves the original `created` timestamp.
- Updates the `updated` timestamp to the moment of the reset.
- Returns the log file name as `.data` on success.

#### `DeleteLogfile` *(Public)*
- Removes a virtual log file instance entirely from module scope.
- **Existence check**: validates `$script:filestorage` before deleting.
- Removes the instance from `$script:loginstances` via `Remove()`.
- Rebuilds `$script:filestorage` via `Where-Object` to exclude the deleted entry.
- Returns the deleted log file name as `.data` on success.

### Module Manifest (`VPDLX.psd1`)
- `ModuleVersion` set to `'1.00.00'`.
- `FunctionsToExport`: `VPDLXcore`, `CreateNewLogfile`, `WriteLogfileEntry`,
  `ReadLogfileEntry`, `ResetLogfile`, `DeleteLogfile`.
- `FileList` fully populated with all module files.
- `Tags`: `Logging`, `VirtualLog`, `DataLogger`, `PowerShell`, `Automation`.

### Documentation
- `README.md`: created — full module reference.
- `QUICKSTART.md`: created — hands-on quick-start guide.
- `CHANGELOG.md`: created — this file.
- `demo-001.ps1`: created — working demonstration script.

---

*Maintained by [Praetoriani](https://github.com/praetoriani)*
