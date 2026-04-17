<#
.SYNOPSIS
    VPDLXresetlogfile - Public wrapper: clears all entries from a virtual log file.

.DESCRIPTION
    VPDLXresetlogfile is the public-facing wrapper for clearing the in-memory
    data of a named virtual log file while preserving the log file itself
    (its registration in storage, its name, and its metadata skeleton).
    It wraps the [Logfile].Reset() method call in a safe, standardised
    function that:

      1. Validates the supplied name and confirms the log file exists.
      2. Retrieves the [Logfile] instance from $script:storage via VPDLXcore.
      3. Calls .Reset() on the instance, which:
             a. Calls _data.Clear() - removes all stored log entries.
             b. Calls _details.ApplyReset() - updates metadata:
                  - Sets 'updated' timestamp to now
                  - Sets 'lastacc' (last accessed) timestamp to now
                  - Sets 'acctype' (last access type) to 'Reset'
                  - Increments 'axcount' (total interaction counter)
                  - Zeroes 'entries' counter
             c. Preserves 'created' timestamp and the original filename.
      4. Returns a standardised [PSCustomObject] via VPDLXreturn:

             code  0   - success; .data holds the entry count BEFORE the reset
                          (so the caller knows how many entries were cleared)
             code -1   - failure; .msg describes the reason; .data is $null

    WARNING:
        This operation is destructive and CANNOT be undone. All log entries held
        in the virtual log file are permanently lost. The log file itself
        remains registered and can immediately accept new entries via
        VPDLXwritelogfile or the class shortcut methods.

    DIFFERENCE FROM VPDLXdroplogfile:
        - VPDLXresetlogfile clears the DATA but keeps the log file alive.
          The log file can be reused immediately.
        - VPDLXdroplogfile destroys the ENTIRE log file (data + metadata +
          registration). The log file is gone and must be re-created.

    INTERNAL DEPENDENCIES:
        - VPDLXcore    (root module accessor - exposes $script:storage)
        - VPDLXreturn  (return object factory - Private/)
        - [FileStorage].Get()     (retrieves the [Logfile] instance by name)
        - [Logfile].Reset()       (performs the actual data clear + metadata update)
        - [Logfile].EntryCount()  (used to capture the count before reset)
        The VPDLX.psm1 load order guarantees all are available when this
        file is dot-sourced.

.PARAMETER Logfile
    The name of the virtual log file to reset (clear all entries).

    The lookup is case-insensitive, matching the OrdinalIgnoreCase comparer
    used internally by [FileStorage]. Leading and trailing whitespace is
    trimmed before the lookup.

.OUTPUTS
    [PSCustomObject] with three properties:
        code  [int]    -  0 on success, -1 on failure
        msg   [string] -  human-readable status or error description
        data  [object] -  [int] entry count before the reset on success,
                           $null on failure

.EXAMPLE
    # Basic usage - reset a log file and see how many entries were cleared
    $result = VPDLXresetlogfile -Logfile 'AppLog'
    if ($result.code -eq 0) {
        Write-Host "Cleared $($result.data) entries from AppLog."
    } else {
        Write-Warning "Reset failed: $($result.msg)"
    }

.EXAMPLE
    # Safe pattern: export before resetting (log rotation)
    $export = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json'
    if ($export.code -eq 0) {
        $reset = VPDLXresetlogfile -Logfile 'AppLog'
        Write-Host "Exported and cleared $($reset.data) entries."
    }

.EXAMPLE
    # Reset an empty log file - succeeds with 0 entries cleared
    $result = VPDLXresetlogfile -Logfile 'EmptyLog'
    # $result.code -> 0
    # $result.data -> 0

.EXAMPLE
    # Attempt to reset a non-existent log file - returns code -1
    $result = VPDLXresetlogfile -Logfile 'Ghost'
    # $result.code  -> -1
    # $result.msg   -> "... 'Ghost' does not exist ..."

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.05
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Website : https://github.com/praetoriani/PowerShell.Mods
    Created : 11.04.2026
    Updated : 11.04.2026
    Scope   : Public - exported via FunctionsToExport in VPDLX.psd1
#>

function VPDLXresetlogfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # The name of the virtual log file to reset (clear all entries).
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Logfile
    )

    # ── Step 1: Pre-flight - verify module storage is accessible ────────────
    # VPDLXcore bridges the scope gap between dot-sourced Public/ functions
    # and $script:* variables in VPDLX.psm1. A PSCustomObject return from
    # VPDLXcore (code -1) signals that the module is in a broken state.
    try {
        $coreResult_storage = VPDLXcore -KeyID 'storage'
        if ($coreResult_storage.code -ne 0) {
            return VPDLXreturn -Code -1 -Message $coreResult_storage.msg
        }
        $storage = $coreResult_storage.data
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXresetlogfile: Unable to access module storage via VPDLXcore. ' +
            'Ensure the VPDLX module is loaded correctly. ' +
            "Internal error: $($_.Exception.Message)"
        )
    }

    if ($storage -is [PSCustomObject]) {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXresetlogfile: VPDLXcore did not return a valid FileStorage object. ' +
            'Module may not be initialised correctly.'
        )
    }

    # ── Step 2: Trim name and verify the log file exists ───────────────────
    # Trim to match the normalisation applied in [Logfile]::new() and the
    # other public wrappers. Then guard early with a clear, user-friendly
    # message if the log file is not registered.
    [string] $trimmedName = $Logfile.Trim()

    if (-not $storage.Contains($trimmedName)) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXresetlogfile: Log file '$trimmedName' does not exist in the " +
            'current session. Use VPDLXnewlogfile to create it first, or ' +
            'VPDLXislogfile to check existence before resetting.'
        )
    }

    # ── Step 3: Retrieve the [Logfile] instance from storage ──────────────
    # Contains() confirmed existence above; $null here = internal bug.
    [object] $logInstance = $storage.Get($trimmedName)

    if ($null -eq $logInstance) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXresetlogfile: Log file '$trimmedName' was found by Contains() " +
            'but Get() returned $null. This indicates an internal storage ' +
            'inconsistency. Please report this as a bug.'
        )
    }

    # ── Step 4: Capture entry count before reset ──────────────────────────
    # We capture the count BEFORE calling Reset() so we can report how many
    # entries were cleared. EntryCount() is a simple _data.Count - O(1).
    [int] $entriesBefore = $logInstance.EntryCount()

    # ── Step 5: Reset the [Logfile] instance ──────────────────────────────
    # [Logfile].Reset() performs two actions:
    #   1. _data.Clear() - removes all log entries from the internal List<string>
    #   2. _details.ApplyReset() - updates metadata timestamps and counters
    # After this call the log file is empty but still registered and usable.
    try {
        $logInstance.Reset()
    }
    catch [System.ObjectDisposedException] {
        # The instance was destroyed between our Contains() check and the
        # Reset() call. Race condition - report clearly.
        return VPDLXreturn -Code -1 -Message (
            "VPDLXresetlogfile: Log file '$trimmedName' was destroyed before " +
            'the reset could complete. Set any held references to $null.'
        )
    }
    catch {
        # Catch-all for any unexpected runtime error from Reset().
        return VPDLXreturn -Code -1 -Message (
            "VPDLXresetlogfile: An unexpected error occurred while resetting " +
            "log file '$trimmedName'. Error: $($_.Exception.Message)"
        )
    }

    # ── Step 6: Return success ────────────────────────────────────────────────
    # The number of entries that were cleared is returned in .data so the
    # caller can confirm how much data was removed.
    return VPDLXreturn -Code 0 `
        -Message ("VPDLXresetlogfile: Log file '$trimmedName' has been reset. " +
                  "$entriesBefore entry/entries cleared. " +
                  'The log file is still registered and ready for new entries.') `
        -Data $entriesBefore
}
