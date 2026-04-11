<#
.SYNOPSIS
    VPDLX.Precheck — Pre-import environment validation for the VPDLX module.

.DESCRIPTION
    This script is executed automatically by PowerShell before the root module
    (VPDLX.psm1) is loaded, because it is listed in the ScriptsToProcess key
    of the module manifest (VPDLX.psd1).

    Purpose:
      Validate that the current PowerShell host meets the minimum requirements
      for VPDLX. If the requirements are not met, the script emits a clear,
      actionable error message and returns early — preventing the module from
      loading in an environment where it would fail with cryptic errors later.

    Checks performed:
      1. PowerShell version >= 5.1
         VPDLX uses PowerShell 5 class syntax, generic collections, and
         TypeAccelerator registration — all of which require at least PS 5.1.
         Running on PS 4.0 or earlier produces parse errors that do not
         clearly indicate the root cause.

    This script intentionally does NOT use any VPDLX classes or functions —
    it runs before any of them are loaded. It uses only built-in PowerShell
    cmdlets and language features that are available on all PS versions >= 2.0
    so the error messages are always reachable.

    DESIGN DECISION:
      The script uses Write-Error with -ErrorAction Stop to prevent module
      loading. A simple Write-Warning would allow the module to continue
      loading and fail later with confusing parse errors. Stopping here
      gives the user a single, clear diagnostic message.

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.04
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 11.04.2026
    Updated : 11.04.2026

    NEW v1.02.04:
      This file was introduced as part of the Performance & Quality
      improvements. It is referenced by VPDLX.psd1 → ScriptsToProcess.
#>

# ── Check 1: PowerShell version ────────────────────────────────────────────────
# Minimum required: PowerShell 5.1 (Desktop) or PowerShell 7.x (Core).
# $PSVersionTable is available in all PowerShell versions >= 2.0.

[int] $psMajor = $PSVersionTable.PSVersion.Major
[int] $psMinor = $PSVersionTable.PSVersion.Minor

if ($psMajor -lt 5 -or ($psMajor -eq 5 -and $psMinor -lt 1)) {

    # Build a clear, multi-line error message that tells the user exactly
    # what version they are running, what version is required, and how to
    # check their version.
    [string] $currentVersion = "$psMajor.$psMinor"
    [string] $errorMessage   = @(
        "VPDLX requires PowerShell 5.1 or higher."
        "Your current PowerShell version is $currentVersion."
        ""
        "VPDLX uses class syntax, generic collections, and TypeAccelerator"
        "registration that are not available in PowerShell $currentVersion."
        ""
        "To resolve this issue:"
        "  - Windows PowerShell: Update to at least version 5.1"
        "    (included in Windows 10 / Server 2016 and later)."
        "  - PowerShell Core: Install PowerShell 7.x from"
        "    https://github.com/PowerShell/PowerShell/releases"
        ""
        "To check your version, run:  `$PSVersionTable.PSVersion"
    ) -join "`n"

    Write-Error -Message $errorMessage -ErrorAction Stop
    return
}

# ── All checks passed ──────────────────────────────────────────────────────────
# The module loader (VPDLX.psm1) will continue with class and function loading.
# No output is produced on success — the precheck is silent when everything is OK.
Write-Verbose "VPDLX Precheck: PowerShell $psMajor.$psMinor detected — requirements met."
