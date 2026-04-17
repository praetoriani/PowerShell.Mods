<#
.SYNOPSIS
    VPDLXwritelogfile - Public wrapper: writes a new entry to a virtual log file.

.DESCRIPTION
    VPDLXwritelogfile is the public-facing wrapper for appending a single
    formatted log entry to a named virtual log file. It wraps the
    [Logfile].Write() method call in a safe, standardised function that:

      1. Validates the supplied log file name and confirms the file exists.
      2. Retrieves the [Logfile] instance from $script:storage via VPDLXcore.
      3. Validates the Level and Message parameters at the PowerShell binding
         layer ([ValidateSet] for Level) before passing them to .Write().
      4. Calls .Write($Level, $Message) on the instance, which:
             a. Validates the level against [Logfile]::LogLevels.
             b. Validates the message (min 3 non-whitespace chars, no newlines).
             c. Builds a formatted log line:
                    [dd.MM.yyyy | HH:mm:ss]  [LEVEL]  ->  MESSAGE
             d. Appends the line to the internal List<string>.
             e. Calls _details.RecordWrite() - updates metadata (last updated,
                access type, access count, entry count).
      5. Returns a standardised [PSCustomObject] via VPDLXreturn:

             code  0   - success; .data holds the new total entry count [int]
             code -1   - failure; .msg describes the reason; .data is $null

    LOG LINE FORMAT:
        Every written entry follows this fixed format (defined in [Logfile]):

            [06.04.2026 | 19:58:00]  [INFO]      ->  Application started.
            [06.04.2026 | 19:58:01]  [WARNING]   ->  Disk space low.
            [06.04.2026 | 19:58:02]  [CRITICAL]  ->  Service unreachable.

        The timestamp is captured at the moment of the Write() call inside
        [Logfile].BuildEntry(), so each entry reflects its exact creation time.

    SUPPORTED LOG LEVELS:
        info, debug, verbose, trace, warning, error, critical, fatal
        The Level parameter is validated by [ValidateSet] at the PowerShell
        binding layer (fast, early rejection) AND again inside [Logfile].Write()
        via ValidateLevel(). Both checks are case-insensitive.

    MESSAGE CONSTRAINTS (enforced by [Logfile].ValidateMessage()):
        - Must not be null, empty, or whitespace-only.
        - Must contain at least 3 non-whitespace characters.
        - Must not contain newline characters (CR or LF) - prevents log
          injection attacks in exported files.

    INTERNAL DEPENDENCIES:
        - VPDLXcore    (root module accessor - exposes $script:storage)
        - VPDLXreturn  (return object factory - Private/)
        - [FileStorage].Get()   (retrieves the [Logfile] instance by name)
        - [Logfile].Write()     (performs the actual entry append)
        - [Logfile].EntryCount() (used to report the new total in .data)
        The VPDLX.psm1 load order guarantees all are available when this
        file is dot-sourced.

.PARAMETER Logfile
    The name of the virtual log file to write to.
    Leading and trailing whitespace is trimmed. The lookup is case-insensitive.

.PARAMETER Level
    The log level for the new entry. Must be one of:
        info | debug | verbose | trace | warning | error | critical | fatal
    Case-insensitive. Validated by [ValidateSet] at the PowerShell binding layer
    so invalid values are rejected with a clear error before any module logic runs.

.PARAMETER Message
    The human-readable log message to record.
    Constraints (enforced by [Logfile].ValidateMessage()):
      - Must not be null, empty, or whitespace-only.
      - Must contain at least 3 non-whitespace characters.
      - Must not contain newline characters (CR or LF).

.OUTPUTS
    [PSCustomObject] with three properties:
        code  [int]    -  0 on success, -1 on failure
        msg   [string] -  human-readable status or error description
        data  [object] -  the new total entry count [int] on success,
                           $null on failure

.EXAMPLE
    # Basic usage - write an info entry and check the result
    $result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Application started.'
    if ($result.code -eq 0) {
        Write-Host "Entry written. Total entries: $($result.data)"
    } else {
        Write-Warning "Write failed: $($result.msg)"
    }

.EXAMPLE
    # Write a warning entry using a different log level
    $result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'warning' -Message 'Disk space below 10%.'

.EXAMPLE
    # Write a critical error with full error pipeline
    $result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'critical' -Message 'Database connection lost.'
    if ($result.code -ne 0) { Write-Error $result.msg }

.EXAMPLE
    # Invalid level - rejected at the [ValidateSet] binding layer
    $result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'notice' -Message 'Test.'
    # PowerShell emits: "Cannot validate argument on parameter 'Level'..."

.EXAMPLE
    # Message with newline - rejected by [Logfile].ValidateMessage()
    $result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message "Line1`nLine2"
    # $result.code -> -1
    # $result.msg  -> "... must not contain newline characters ..."

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.02
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Website : https://github.com/praetoriani/PowerShell.Mods
    Created : 06.04.2026
    Updated : 17.04.2026
    Scope   : Public - exported via Export-ModuleMember in VPDLX.psm1
#>

function VPDLXwritelogfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # The name of the virtual log file to write to.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Logfile,

        # The log level for the new entry.
        # [ValidateSet] provides early, binding-layer rejection of unknown levels
        # AND tab-completion in interactive sessions and editors - so callers
        # get immediate feedback without reaching the module logic at all.
        # NOTE: [ValidateSet] is case-insensitive by default in PowerShell.
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateSet(
            'info', 'debug', 'verbose', 'trace',
            'warning', 'error', 'critical', 'fatal',
            IgnoreCase = $true
        )]
        [string] $Level,

        # The human-readable log message.
        # Content constraints are enforced by [Logfile].ValidateMessage() —
        # see function description for the full list of rules.
        [Parameter(Mandatory = $true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string] $Message
    )

    # ── Step 1: Pre-flight - verify module storage is accessible ────────────
    # VPDLXcore bridges the scope gap between dot-sourced Public/ functions
    # and the $script:* variables that live in VPDLX.psm1's root module scope.
    try {
        $coreResult_storage = VPDLXcore -KeyID 'storage'
        if ($coreResult_storage.code -ne 0) {
            return VPDLXreturn -Code -1 -Message $coreResult_storage.msg
        }
        $storage = $coreResult_storage.data
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXwritelogfile: Unable to access module storage via VPDLXcore. ' +
            'Ensure the VPDLX module is loaded correctly. ' +
            "Internal error: $($_.Exception.Message)"
        )
    }

    if ($storage -is [PSCustomObject]) {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXwritelogfile: VPDLXcore did not return a valid FileStorage object. ' +
            'Module may not be initialised correctly.'
        )
    }

    # ── Step 2: Trim name and verify the log file exists ───────────────────
    # Trim to stay consistent with [Logfile]::new() and all other public wrappers.
    [string] $trimmedName = $Logfile.Trim()

    if (-not $storage.Contains($trimmedName)) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXwritelogfile: Log file '$trimmedName' does not exist in the " +
            'current session. Use VPDLXnewlogfile to create it first, or ' +
            'VPDLXislogfile to check existence before writing.'
        )
    }

    # ── Step 3: Retrieve the [Logfile] instance ────────────────────────────
    # Contains() confirmed existence above; $null here = internal bug.
    [object] $logInstance = $storage.Get($trimmedName)

    if ($null -eq $logInstance) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXwritelogfile: Log file '$trimmedName' was found by Contains() " +
            'but Get() returned $null. This indicates an internal storage ' +
            'inconsistency. Please report this as a bug.'
        )
    }

    # ── Step 4: Write the entry via [Logfile].Write() ──────────────────────
    # [Logfile].Write() performs two validations internally:
    #   - ValidateLevel()   - rejects unknown level strings (already caught
    #                          by [ValidateSet] above, but defence-in-depth)
    #   - ValidateMessage() - rejects null/empty/whitespace, messages shorter
    #                          than 3 non-whitespace chars, and messages that
    #                          contain CR or LF (log injection prevention)
    # Both throw [System.ArgumentException] on violation.
    # [ObjectDisposedException] is thrown by GuardDestroyed() if the instance
    # was destroyed since our Contains() check.
    #
    # The normalised (lowercase) level is passed to .Write() so the entry's
    # level prefix matches the LogLevels dictionary keys exactly.
    [string] $normalizedLevel = $Level.Trim().ToLower()

    try {
        $logInstance.Write($normalizedLevel, $Message)
    }
    catch [System.ArgumentException] {
        # Validation failure inside [Logfile].Write() - level or message invalid.
        return VPDLXreturn -Code -1 -Message (
            "VPDLXwritelogfile: Write validation failed for log file '$trimmedName'. " +
            $_.Exception.Message
        )
    }
    catch [System.ObjectDisposedException] {
        # The [Logfile] instance was destroyed between our Contains() check and
        # the Write() call. Race condition - report clearly.
        return VPDLXreturn -Code -1 -Message (
            "VPDLXwritelogfile: Log file '$trimmedName' was destroyed before " +
            'the write could complete. Set any held references to $null.'
        )
    }
    catch {
        # Catch-all for any unexpected runtime error from Write() or the
        # underlying List<string>.Add() / _details.RecordWrite().
        return VPDLXreturn -Code -1 -Message (
            "VPDLXwritelogfile: An unexpected error occurred while writing to " +
            "log file '$trimmedName'. Error: $($_.Exception.Message)"
        )
    }

    # ── Step 5: Return success ────────────────────────────────────────────────
    # The new total entry count is returned in .data so callers can track how
    # many entries the log now contains without a separate lookup.
    # EntryCount() is a simple _data.Count call - O(1), no exception risk.
    [int] $newCount = $logInstance.EntryCount()

    return VPDLXreturn -Code 0 `
        -Message ("VPDLXwritelogfile: Entry written successfully to log file " +
                  "'$trimmedName' at level '$normalizedLevel'. " +
                  "Total entries: $newCount.") `
        -Data $newCount
}
