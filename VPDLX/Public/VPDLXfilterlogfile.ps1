<#
.SYNOPSIS
    VPDLXfilterlogfile - Public wrapper: retrieves log entries matching a specific level.

.DESCRIPTION
    VPDLXfilterlogfile is the public-facing wrapper for filtering the entries of
    a named virtual log file by log level. It wraps the [Logfile].FilterByLevel()
    method call in a safe, standardised function that:

      1. Validates the supplied log file name and confirms the file exists.
      2. Retrieves the [Logfile] instance from $script:storage via VPDLXcore.
      3. Validates the Level parameter at the PowerShell binding layer
         ([ValidateSet] for Level) before passing it to .FilterByLevel().
      4. Calls .FilterByLevel($Level) on the instance, which:
             a. Validates the level against [Logfile]::LogLevels.
             b. Constructs the bracket marker (e.g. 'warning' -> '[WARNING]').
             c. Iterates all log entries and collects those containing the marker.
             d. Calls _details.RecordFilterByLevel() - updates metadata
                (last accessed, access type = 'FilterByLevel', access count).
             e. Returns the matching entries as [string[]] (never $null).
      5. Returns a standardised [PSCustomObject] via VPDLXreturn:

             code  0   - success; .data holds a [PSCustomObject] with:
                           Entries  [string[]]  - matching log lines
                           Count    [int]        - number of matches
                           Level    [string]     - the level that was filtered
             code -1   - failure; .msg describes the reason; .data is $null

    SUPPORTED LOG LEVELS:
        info, debug, verbose, trace, warning, error, critical, fatal
        The Level parameter is validated by [ValidateSet] at the PowerShell
        binding layer AND again inside [Logfile].FilterByLevel() via
        ValidateLevel(). Both checks are case-insensitive.

    MATCHING STRATEGY (implemented in [Logfile].FilterByLevel()):
        Each log line is checked with String.Contains() against the uppercase
        bracket notation of the level (e.g. '[WARNING]'). This is a fixed-string
        comparison - faster than regex and avoids PowerShell pipeline overhead.

    INTERNAL DEPENDENCIES:
        - VPDLXcore    (root module accessor - exposes $script:storage)
        - VPDLXreturn  (return object factory - Private/)
        - [FileStorage].Get()            (retrieves the [Logfile] instance by name)
        - [Logfile].FilterByLevel()      (performs the actual filter operation)
        - [Logfile].EntryCount()         (used to report total count for context)
        The VPDLX.psm1 load order guarantees all are available when this
        file is dot-sourced.

.PARAMETER Logfile
    The name of the virtual log file to filter.
    Leading and trailing whitespace is trimmed. The lookup is case-insensitive.

.PARAMETER Level
    The log level to filter for. Must be one of:
        info | debug | verbose | trace | warning | error | critical | fatal
    Case-insensitive. Validated by [ValidateSet] at the PowerShell binding layer
    so invalid values are rejected with a clear error before any module logic runs.

.OUTPUTS
    [PSCustomObject] with three properties:
        code  [int]    -  0 on success, -1 on failure
        msg   [string] -  human-readable status or error description
        data  [object] -  [PSCustomObject] with Entries, Count, Level on success;
                           $null on failure

.EXAMPLE
    # Filter for all error entries
    $result = VPDLXfilterlogfile -Logfile 'AppLog' -Level 'error'
    if ($result.code -eq 0) {
        Write-Host "Found $($result.data.Count) error(s):"
        $result.data.Entries | ForEach-Object { Write-Host "  $_" }
    }

.EXAMPLE
    # Filter for warnings and process them
    $result = VPDLXfilterlogfile -Logfile 'AppLog' -Level 'warning'
    if ($result.code -eq 0 -and $result.data.Count -gt 0) {
        Write-Host "$($result.data.Count) warning(s) found in AppLog."
    } else {
        Write-Host 'No warnings found.'
    }

.EXAMPLE
    # Combine with export - filter critical entries then export full log
    $criticals = VPDLXfilterlogfile -Logfile 'ProdLog' -Level 'critical'
    if ($criticals.data.Count -gt 0) {
        Write-Warning "CRITICAL entries detected - exporting log."
        VPDLXexportlogfile -Logfile 'ProdLog' -LogPath 'C:\Logs' -ExportAs 'json'
    }

.EXAMPLE
    # No matches - returns code 0 with Count = 0 and empty Entries array
    $result = VPDLXfilterlogfile -Logfile 'CleanLog' -Level 'fatal'
    # $result.code       -> 0
    # $result.data.Count -> 0
    # $result.data.Entries -> @()

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.05
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Website : https://github.com/praetoriani/PowerShell.Mods
    Created : 11.04.2026
    Updated : 11.04.2026
    Scope   : Public - exported via FunctionsToExport in VPDLX.psd1
#>

function VPDLXfilterlogfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # The name of the virtual log file to filter.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Logfile,

        # The log level to filter for.
        # [ValidateSet] provides early, binding-layer rejection of unknown levels
        # AND tab-completion in interactive sessions and editors.
        # NOTE: [ValidateSet] is case-insensitive by default in PowerShell.
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateSet(
            'info', 'debug', 'verbose', 'trace',
            'warning', 'error', 'critical', 'fatal',
            IgnoreCase = $true
        )]
        [string] $Level
    )

    # ── Step 1: Pre-flight - verify module storage is accessible ────────────
    # VPDLXcore bridges the scope gap between dot-sourced Public/ functions
    # and the $script:* variables that live in VPDLX.psm1's root module scope.
    try {
        $storage = VPDLXcore -KeyID 'storage'
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXfilterlogfile: Unable to access module storage via VPDLXcore. ' +
            'Ensure the VPDLX module is loaded correctly. ' +
            "Internal error: $($_.Exception.Message)"
        )
    }

    if ($storage -is [PSCustomObject]) {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXfilterlogfile: VPDLXcore did not return a valid FileStorage object. ' +
            'Module may not be initialised correctly.'
        )
    }

    # ── Step 2: Trim name and verify the log file exists ───────────────────
    # Trim to stay consistent with [Logfile]::new() and all other public wrappers.
    [string] $trimmedName = $Logfile.Trim()

    if (-not $storage.Contains($trimmedName)) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXfilterlogfile: Log file '$trimmedName' does not exist in the " +
            'current session. Use VPDLXnewlogfile to create it first, or ' +
            'VPDLXislogfile to check existence before filtering.'
        )
    }

    # ── Step 3: Retrieve the [Logfile] instance ────────────────────────────
    # Contains() confirmed existence above; $null here = internal bug.
    [object] $logInstance = $storage.Get($trimmedName)

    if ($null -eq $logInstance) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXfilterlogfile: Log file '$trimmedName' was found by Contains() " +
            'but Get() returned $null. This indicates an internal storage ' +
            'inconsistency. Please report this as a bug.'
        )
    }

    # ── Step 4: Execute the filter via [Logfile].FilterByLevel() ──────────
    # FilterByLevel() performs its own level validation (defence-in-depth),
    # constructs the bracket marker, iterates all entries, and collects
    # matches. It returns [string[]] - never $null (empty array if no matches).
    # The normalised (lowercase) level is passed for consistent processing.
    [string] $normalizedLevel = $Level.Trim().ToLower()

    try {
        [string[]] $filteredEntries = $logInstance.FilterByLevel($normalizedLevel)
    }
    catch [System.ArgumentException] {
        # Level validation failure inside FilterByLevel() - should not occur
        # because [ValidateSet] already rejects bad levels, but defence-in-depth.
        return VPDLXreturn -Code -1 -Message (
            "VPDLXfilterlogfile: Filter validation failed for log file '$trimmedName'. " +
            $_.Exception.Message
        )
    }
    catch [System.ObjectDisposedException] {
        # The [Logfile] instance was destroyed between our Contains() check and
        # the FilterByLevel() call. Race condition - report clearly.
        return VPDLXreturn -Code -1 -Message (
            "VPDLXfilterlogfile: Log file '$trimmedName' was destroyed before " +
            'the filter could complete. Set any held references to $null.'
        )
    }
    catch {
        # Catch-all for any unexpected runtime error.
        return VPDLXreturn -Code -1 -Message (
            "VPDLXfilterlogfile: An unexpected error occurred while filtering " +
            "log file '$trimmedName'. Error: $($_.Exception.Message)"
        )
    }

    # ── Step 5: Return success ────────────────────────────────────────────────
    # The result payload is a structured object containing the matching entries,
    # the match count, and the level that was filtered. This allows the caller
    # to process results programmatically without parsing the .msg string.
    [int] $matchCount  = $filteredEntries.Count
    [int] $totalCount  = $logInstance.EntryCount()

    $resultPayload = [PSCustomObject] [ordered] @{
        Entries = $filteredEntries
        Count   = $matchCount
        Level   = $normalizedLevel
    }

    return VPDLXreturn -Code 0 `
        -Message ("VPDLXfilterlogfile: Found $matchCount of $totalCount entries " +
                  "at level '$normalizedLevel' in log file '$trimmedName'.") `
        -Data $resultPayload
}
