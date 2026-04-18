# OPSreturn

> **Standardized operation status return objects for PowerShell modules**

OPSreturn is a lightweight PowerShell module that provides a consistent, structured `PSCustomObject` for returning operation status information from functions and scripts. Instead of returning raw booleans, magic numbers, or unstructured strings, OPSreturn gives you a unified return contract — with a numeric status code, a human-readable state name, an optional message, optional data payload, optional exception details, the calling function's name, and an optional timestamp.

---

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Module Configuration](#module-configuration)
- [Return Object Structure](#return-object-structure)
- [Status Codes & Functions](#status-codes--functions)
- [Public Functions Reference](#public-functions-reference)
- [Usage Examples](#usage-examples)
- [Architecture](#architecture)
- [Code Review Notes](#code-review-notes)
- [Changelog](#changelog)
- [Author](#author)

---

## Overview

When building larger PowerShell modules or automation scripts, inconsistent return values become a maintenance nightmare. One function returns `$true`/`$false`, another throws exceptions, another returns a string — and the caller always has to know exactly what to expect.

OPSreturn solves this with a single, predictable pattern:

```
Every function returns the same PSCustomObject shape — always.
```

The object carries a numeric code, a named state, a message, optional data, optional exception info, the source function name, and a timestamp. This makes error handling, logging, and branching logic uniform across your entire codebase.

---

## Requirements

| Requirement | Details |
|---|---|
| PowerShell Version | 5.1 or higher |
| PS Editions | Desktop & Core |
| External Dependencies | None |
| Operating System | Windows, Linux, macOS (PS Core) |

---

## Installation

### Manual Installation

1. Clone or download the repository
2. Copy the `OPSreturn` folder into one of your `$PSModulePath` directories, e.g.:
   ```
   C:\Users\<YourUser>\Documents\PowerShell\Modules\OPSreturn\
   ```
3. Import the module in your script:
   ```powershell
   Import-Module OPSreturn
   ```

### Direct Import (without installing)

```powershell
Import-Module "C:\Path\To\OPSreturn\OPSreturn.psd1"
```

---

## Quick Start

```powershell
# Step 1: Import the module
Import-Module OPSreturn

# Step 2: (Optional) Configure the module
SetCoreConfig -timestamp $true -verbosed $false

# Step 3: Use in your functions
function Get-Config {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return OPSfail "Config file not found: $Path"
    }

    try {
        $config = Get-Content $Path | ConvertFrom-Json
        return OPSsuccess "Config loaded successfully" -Data $config
    }
    catch {
        return OPSerror "Failed to parse config file" -Exception $_.Exception
    }
}

# Step 4: Evaluate the result
$result = Get-Config -Path "C:\config.json"

if ($result.code -eq 0) {
    Write-Host "Success: $($result.msg)"
    # Access payload via $result.data
} else {
    Write-Warning "[$($result.state)] $($result.msg)"
}
```

---

## Module Configuration

Use `SetCoreConfig` to adjust module behaviour at runtime. All parameters are optional — only the parameters you explicitly pass will be updated; everything else keeps its current value.

```powershell
SetCoreConfig [-timestamp <bool>] [-verbosed <bool>]
```

### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `timestamp` | `bool` | `$true` | When `$true`, each return object includes a formatted timestamp (`dd.MM.yyyy ; HH:mm:ss.fff`) in the `timecode` field. Set to `$false` to suppress timestamps (the field will contain `<notused>`). |
| `verbosed` | `bool` | `$false` | When `$true`, enables verbose output during module operations (module load messages etc.). |

### Example

```powershell
# Disable timestamps, enable verbose output
SetCoreConfig -timestamp $false -verbosed $true

# Only change timestamp, leave verbosed as-is
SetCoreConfig -timestamp $true
```

---

## Return Object Structure

Every public function in OPSreturn returns a `PSCustomObject` with the following properties:

```powershell
[PSCustomObject]@{
    code      = [int]         # Numeric status code (see table below)
    state     = [string]      # Human-readable name of the status code
    msg       = [string]      # Optional short message from the caller
    data      = [object]      # Optional payload (any type, $null if unused)
    exception = [object]      # Optional exception object ($null if unused)
    source    = [string]      # Name of the calling function (auto-resolved)
    timecode  = [string]      # Timestamp or '<notused>' depending on config
}
```

### Field Details

| Field | Type | Description |
|---|---|---|
| `code` | `int` | Numeric code. Positive/zero = non-critical states. Negative = error/failure states. |
| `state` | `string` | String representation of the `OPScode` enum value (e.g. `"success"`, `"error"`). |
| `msg` | `string` | A short human-readable message. Can be empty. |
| `data` | `any` | Arbitrary data payload — pass back objects, arrays, hashtables, strings, etc. |
| `exception` | `any` | Pass `$_.Exception` from a `catch` block here for structured error details. |
| `source` | `string` | Auto-resolved via `Get-PSCallStack`. Shows which function triggered the return. |
| `timecode` | `string` | Local timestamp formatted as `dd.MM.yyyy ; HH:mm:ss.fff`, or `<notused>` if disabled. |

---

## Status Codes & Functions

OPSreturn defines a typed `enum` called `OPScode` with 9 named status levels, split into informational (≥ 0) and failure (< 0) categories.

| Function | Enum Name | Code | Meaning |
|---|---|---|---|
| `OPSsuccess` | `success` | `0` | Operation completed successfully |
| `OPSinfo` | `info` | `1` | Informational return, no action required |
| `OPSdebug` | `debug` | `2` | Debug-level return for diagnostic output |
| `OPStimeout` | `timeout` | `3` | Operation timed out |
| `OPSwarn` | `warn` | `4` | Warning — operation completed but with caveats |
| `OPSfail` | `fail` | `-1` | Operation failed (expected/recoverable) |
| `OPSerror` | `error` | `-2` | Error occurred during operation |
| `OPScritical` | `critical` | `-3` | Critical error, requires immediate attention |
| `OPSfatal` | `fatal` | `-4` | Fatal error, unrecoverable — terminate |

> **Convention:** A `code` of `0` means success. Any negative `code` represents a failure state. Positive codes (`1`–`4`) represent informational or non-fatal states that do not indicate failure.

You can branch on the numeric `code` directly:

```powershell
$result = Do-Something

switch ($result.code) {
    0  { Write-Host "OK" }
    { $_ -lt 0 } { Write-Error "Failed: $($result.state) — $($result.msg)" }
    default { Write-Verbose "Info: $($result.msg)" }
}
```

---

## Public Functions Reference

All public functions are thin, named wrappers around the private `OPSreturn` function. They exist for readability and convenience.

---

### `SetCoreConfig`

Configures the module's runtime settings. See [Module Configuration](#module-configuration).

---

### `OPSsuccess`

Returns a success object (`code = 0`). Use when an operation completed without issues.

```powershell
OPSsuccess [[-Message] <string>] [[-Data] <object>]
```

**Parameters:** `Message`, `Data`
**Does not accept:** `Exception` (success states do not carry exception info)

```powershell
return OPSsuccess "User account created" -Data $newUser
```

---

### `OPSinfo`

Returns an informational object (`code = 1`). Use to signal a neutral status with context data.

```powershell
OPSinfo [[-Message] <string>] [[-Data] <object>]
```

```powershell
return OPSinfo "No changes detected — skipping update" -Data $currentState
```

---

### `OPSdebug`

Returns a debug-level object (`code = 2`). Use during development to return diagnostic information.

```powershell
OPSdebug [[-Message] <string>] [[-Data] <object>] [[-Exception] <object>]
```

```powershell
return OPSdebug "Variable state at checkpoint" -Data $debugPayload
```

---

### `OPStimeout`

Returns a timeout object (`code = 3`). Use when an operation exceeded its time limit.

```powershell
OPStimeout [[-Message] <string>] [[-Data] <object>] [[-Exception] <object>]
```

```powershell
return OPStimeout "Connection attempt timed out after 30s" -Data $connectionInfo
```

---

### `OPSwarn`

Returns a warning object (`code = 4`). Use when the operation completed but something noteworthy occurred.

```powershell
OPSwarn [[-Message] <string>] [[-Data] <object>] [[-Exception] <object>]
```

```powershell
return OPSwarn "Config loaded with deprecated keys" -Data $config
```

---

### `OPSfail`

Returns a failure object (`code = -1`). Use for expected, recoverable failures (e.g., file not found, validation error).

```powershell
OPSfail [[-Message] <string>] [[-Data] <object>] [[-Exception] <object>]
```

```powershell
return OPSfail "Input validation failed: Path is empty"
```

---

### `OPSerror`

Returns an error object (`code = -2`). Use when an unexpected error occurred during execution.

```powershell
OPSerror [[-Message] <string>] [[-Data] <object>] [[-Exception] <object>]
```

```powershell
return OPSerror "Failed to write to registry" -Exception $_.Exception
```

---

### `OPScritical`

Returns a critical error object (`code = -3`). Use for severe errors that likely require intervention.

```powershell
OPScritical [[-Message] <string>] [[-Data] <object>] [[-Exception] <object>]
```

```powershell
return OPScritical "Cannot access Windows object" -Exception $_.Exception
```

---

### `OPSfatal`

Returns a fatal error object (`code = -4`). Use when the operation has failed in an unrecoverable way.

```powershell
OPSfatal [[-Message] <string>] [[-Data] <object>] [[-Exception] <object>]
```

```powershell
return OPSfatal "Fatal error during startup — module cannot continue" -Exception $_.Exception
```

---

## Usage Examples

### Pattern 1 — Simple Success/Failure Check

```powershell
function Remove-TempFiles {
    param([string]$Directory)

    if (-not (Test-Path $Directory)) {
        return OPSfail "Directory does not exist: $Directory"
    }

    try {
        Remove-Item -Path "$Directory\*" -Recurse -Force
        return OPSsuccess "Temp files removed from $Directory"
    }
    catch {
        return OPSerror "Unexpected error while cleaning temp directory" -Exception $_.Exception
    }
}

$result = Remove-TempFiles -Directory "C:\Temp"

if ($result.code -lt 0) {
    Write-Error "[$($result.state)] $($result.msg)"
    if ($result.exception) { Write-Error $result.exception.Message }
}
```

---

### Pattern 2 — Passing Data Payloads

```powershell
function Get-SystemInfo {
    $info = [PSCustomObject]@{
        OS       = (Get-CimInstance Win32_OperatingSystem).Caption
        CPU      = (Get-CimInstance Win32_Processor).Name
        RAM_GB   = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
    }
    return OPSsuccess "System info collected" -Data $info
}

$result = Get-SystemInfo
if ($result.code -eq 0) {
    $result.data | Format-List
}
```

---

### Pattern 3 — Using `source` and `timecode` for Logging

```powershell
function Write-OPSLog {
    param([PSCustomObject]$Result)
    Write-Host "[$($Result.timecode)] [$($Result.source)] [$($Result.state.ToUpper())] $($Result.msg)"
}

$result = OPSwarn "Disk usage above 85%"
Write-OPSLog -Result $result
# Output: [18.04.2026 ; 00:36:12.847] [<unknown>] [WARN] Disk usage above 85%
```

---

### Pattern 4 — Chaining Calls

```powershell
function Deploy-Application {
    $step1 = Validate-Config
    if ($step1.code -lt 0) { return OPSfail "Config validation failed" -Data $step1 }

    $step2 = Copy-Files
    if ($step2.code -lt 0) { return OPSerror "File copy failed" -Exception $step2.exception }

    return OPSsuccess "Deployment completed"
}
```

---

## Architecture

```
OPSreturn/
├── OPSreturn.psd1          ← Module manifest (metadata, exports, GUID, version)
├── OPSreturn.psm1          ← Root module (config, bootstrapping, dot-sourcing)
├── private/
│   └── OPSreturn.ps1       ← Private core: OPScode enum + OPSreturn function
└── public/
    ├── OPSsuccess.ps1      ← Public wrapper: code  0
    ├── OPSinfo.ps1         ← Public wrapper: code  1
    ├── OPSdebug.ps1        ← Public wrapper: code  2
    ├── OPStimeout.ps1      ← Public wrapper: code  3
    ├── OPSwarn.ps1         ← Public wrapper: code  4
    ├── OPSfail.ps1         ← Public wrapper: code -1
    ├── OPSerror.ps1        ← Public wrapper: code -2
    ├── OPScritical.ps1     ← Public wrapper: code -3
    └── OPSfatal.ps1        ← Public wrapper: code -4
```

### Design Decisions

- **Export via PSD1 only** — `Export-ModuleMember` is intentionally not used in the `.psm1`. All exports are controlled exclusively through `FunctionsToExport` in `OPSreturn.psd1`. This is the recommended modern approach and avoids accidental leakage of private functions.
- **Dot-sourcing at bootstrap** — All `*.ps1` files in `public\` and `private\` are dot-sourced into the module scope at load time via `Get-ChildItem` loops in `OPSreturn.psm1`. This keeps the root module file clean and makes adding new functions as simple as dropping a new `.ps1` file into the correct folder.
- **Typed enum** — The `OPScode` enum in `private\OPSreturn.ps1` ensures that only valid, named status codes can be passed to the core function. Invalid values are rejected with a descriptive error.
- **Auto-resolved source** — The `source` field is populated automatically via `Get-PSCallStack`, removing the need for callers to pass their own function name. Index `[2]` is used to skip over both `OPSreturn` itself and the wrapper function (e.g., `OPSfail`), surfacing the actual calling function's name.
- **Script-scope config** — The `$script:conf` hashtable holds module configuration and is only accessible within the module scope. `SetCoreConfig` only updates keys that were explicitly passed, leaving all other settings unchanged.

---

## Code Review Notes

The following observations were made during the code review of `v1.00.00`:

**Strengths:**
- Clean separation of public and private functions
- Consistent use of `[CmdletBinding()]` and `[OutputType()]` throughout
- Type-safe status codes via the `OPScode` enum
- No external dependencies — entirely self-contained
- Well-structured PSD1 manifest with correct GUID, version, and exports
- `SetCoreConfig` gracefully handles partial updates via `$PSBoundParameters`

**Minor observations:**
- In `private\OPSreturn.ps1`, there is a duplicate `$callerSrc` block at the bottom of the file (outside the function body) that appears to be a leftover snippet and can be safely removed.
- The commented-out alternate `timecode` format (`UTC`) in the private function suggests a future configuration option — this could be added to `SetCoreConfig` as a `utctime` parameter in a future version.
- `OPSsuccess` and `OPSinfo` do not expose an `Exception` parameter, which is intentional for semantic clarity but worth documenting explicitly for consumers.

---

## Changelog

### v1.00.00 — 17.04.2026

- Initial release
- `OPScode` enum with 9 named status levels
- Private `OPSreturn` core function with auto-resolved caller source
- 9 public wrapper functions: `OPSsuccess`, `OPSinfo`, `OPSdebug`, `OPStimeout`, `OPSwarn`, `OPSfail`, `OPSerror`, `OPScritical`, `OPSfatal`
- `SetCoreConfig` for runtime configuration of `timestamp` and `verbosed` settings
- Compatible with PowerShell 5.1 (Desktop) and PowerShell 7+ (Core)

---

## Author

**Praetoriani** <br>
GitHub: [https://github.com/praetoriani](https://github.com/praetoriani) <br>
Project: [https://github.com/praetoriani/PowerShell.Mods](https://github.com/praetoriani/PowerShell.Mods)

---

*© 2026 Praetoriani. All rights reserved.*
