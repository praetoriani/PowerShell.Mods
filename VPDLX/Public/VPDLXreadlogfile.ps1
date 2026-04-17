<#
.SYNOPSIS
    VPDLXreadlogfile - Public wrapper: reads a single line from a virtual log file.

.DESCRIPTION
    VPDLXreadlogfile is the public-facing wrapper for reading a specific log
    entry from a named virtual log file. It wraps the [Logfile].Read() method
    call in a safe, standardised function that:

      1. Validates the supplied log file name and confirms the file exists.
      2. Retrieves the [Logfile] instance from $script:storage via VPDLXcore.
      3. Validates the Line parameter (must be a positive integer).
      4. Calls .Read($Line) on the instance, which applies automatic 1-based
         index clamping:
             - Values below 1  → treated as 1 (first entry)
             - Values above the entry count → treated as the last entry
         This means VPDLXreadlogfile never returns an out-of-range error for
         any integer input - only an empty-log error when there are no entries.
      5. Returns a standardised [PSCustomObject] via VPDLXreturn:

             code  0   - success; .data holds the retrieved log line [string]
             code -1   - failure; .msg describes the reason; .data is $null

    LINE CLAMPING BEHAVIOUR:
        The underlying [Logfile].Read() method intentionally clamps the line
        index rather than throwing a range exception. This is a deliberate
        design choice: it makes the method robust for scripted loops that
        iterate over a log whose size is not known in advance. The exact
        clamped index that was actually used is reflected in the .msg of the
        success return so callers can detect when clamping occurred.

        Examples with a log that has 5 entries:
            Line =  0  → clamped to 1  → returns entry #1
            Line =  3  → no clamping   → returns entry #3
            Line = 99  → clamped to 5  → returns entry #5

    INTERNAL DEPENDENCIES:
        - VPDLXcore    (root module accessor - exposes $script:storage)
        - VPDLXreturn  (return object factory - Private/)
        - [FileStorage].Get()     (retrieves the [Logfile] instance by name)
        - [Logfile].Read()        (performs the actual line retrieval)
        - [Logfile].EntryCount()  (used to report total entries in .msg)
        The VPDLX.psm1 load order guarantees all are available when this
        file is dot-sourced.

.PARAMETER Logfile
    The name of the virtual log file to read from.
    Leading and trailing whitespace is trimmed. The lookup is case-insensitive.

.PARAMETER Line
    The 1-based line number to retrieve.
    Values below 1 are automatically clamped to 1 (first entry).
    Values above the total entry count are clamped to the last entry.
    Must be an integer; the parameter type [int] enforces this at the
    PowerShell binding layer.

.OUTPUTS
    [PSCustomObject] with three properties:
        code  [int]    -  0 on success, -1 on failure
        msg   [string] -  human-readable status or error description
        data  [object] -  the retrieved log line [string] on success,
                           $null on failure

.EXAMPLE
    # Read line 3 from an existing log file
    $result = VPDLXreadlogfile -Logfile 'AppLog' -Line 3
    if ($result.code -eq 0) {
        Write-Host "Line 3: $($result.data)"
    } else {
        Write-Warning "Read failed: $($result.msg)"
    }

.EXAMPLE
    # Iterate over all entries using EntryCount - standard read loop pattern
    $check = VPDLXislogfile -Logfile 'AppLog'
    if ($check) {
        $storage = VPDLXcore -KeyID 'storage'
        $log     = $storage.Get('AppLog')
        for ($i = 1; $i -le $log.EntryCount(); $i++) {
            $result = VPDLXreadlogfile -Logfile 'AppLog' -Line $i
            if ($result.code -eq 0) { Write-Host $result.data }
        }
    }

.EXAMPLE
    # Clamping in action - line 999 on a 5-entry log returns the last entry
    $result = VPDLXreadlogfile -Logfile 'AppLog' -Line 999
    # $result.code -> 0
    # $result.data -> content of entry #5 (last)

.EXAMPLE
    # Attempt to read from an empty log - returns code -1
    $result = VPDLXreadlogfile -Logfile 'EmptyLog' -Line 1
    # $result.code -> -1
    # $result.msg  -> "... contains no entries ..."

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.02
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Website : https://github.com/praetoriani/PowerShell.Mods
    Created : 06.04.2026
    Updated : 06.04.2026
    Scope   : Public - exported via Export-ModuleMember in VPDLX.psm1
#>

function VPDLXreadlogfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # The name of the virtual log file to read from.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Logfile,

        # The 1-based line number to retrieve.
        # Values outside the valid range are automatically clamped by .Read().
        [Parameter(Mandatory = $true, Position = 1)]
        [int] $Line
    )

    # ── Step 1: Pre-flight - verify module storage is accessible ────────────
    # VPDLXcore bridges the scope gap between dot-sourced Public/ functions
    # and the $script:* variables that live in VPDLX.psm1's root module scope.
    try {
        $storage = VPDLXcore -KeyID 'storage'
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXreadlogfile: Unable to access module storage via VPDLXcore. ' +
            'Ensure the VPDLX module is loaded correctly. ' +
            "Internal error: $($_.Exception.Message)"
        )
    }

    if ($storage -is [PSCustomObject]) {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXreadlogfile: VPDLXcore did not return a valid FileStorage object. ' +
            'Module may not be initialised correctly.'
        )
    }

    # ── Step 2: Trim name and verify the log file exists ───────────────────
    # Trim to stay consistent with [Logfile]::new() and the other wrappers.
    [string] $trimmedName = $Logfile.Trim()

    if (-not $storage.Contains($trimmedName)) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXreadlogfile: Log file '$trimmedName' does not exist in the " +
            'current session. Use VPDLXnewlogfile to create it first, or ' +
            'VPDLXislogfile to check existence before reading.'
        )
    }

    # ── Step 3: Retrieve the [Logfile] instance ────────────────────────────
    # Contains() confirmed the entry exists, so Get() should never return $null
    # here. We guard anyway for internal consistency - same defensive pattern
    # as VPDLXdroplogfile.
    [object] $logInstance = $storage.Get($trimmedName)

    if ($null -eq $logInstance) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXreadlogfile: Log file '$trimmedName' was found by Contains() " +
            'but Get() returned $null. This indicates an internal storage ' +
            'inconsistency. Please report this as a bug.'
        )
    }

    # ── Step 4: Guard against reading from an empty log file ───────────────
    # [Logfile].Read() throws [InvalidOperationException] when called on an
    # empty log. We check proactively here so we can return a clean, friendly
    # message rather than catching an exception. This also avoids the overhead
    # of throwing and catching when a simple bool check suffices.
    try {
        [bool] $isEmpty = $logInstance.IsEmpty()
    }
    catch [System.ObjectDisposedException] {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXreadlogfile: Log file '$trimmedName' has been destroyed and " +
            'is no longer accessible. Set any held references to $null.'
        )
    }

    if ($isEmpty) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXreadlogfile: Log file '$trimmedName' contains no entries. " +
            'Write at least one entry via VPDLXwritelogfile before reading.'
        )
    }

    # ── Step 5: Read the requested line ───────────────────────────────────────
    # [Logfile].Read() clamps the 1-based $Line index automatically:
    #   - $Line < 1              -> clamped to 1 (first entry)
    #   - $Line > EntryCount()   -> clamped to EntryCount() (last entry)
    # No range exception is ever thrown for integer inputs; only the
    # [InvalidOperationException] for an empty log (already handled above)
    # and [ObjectDisposedException] if .Destroy() raced ahead of us.
    try {
        [string] $entry      = $logInstance.Read($Line)
        [int]    $totalLines = $logInstance.EntryCount()

        # Calculate the effective line number that was actually read after clamping.
        # This mirrors the clamping logic in [Logfile].Read() so the .msg is accurate.
        [int] $effectiveLine = $Line
        if ($effectiveLine -lt 1)            { $effectiveLine = 1 }
        if ($effectiveLine -gt $totalLines)  { $effectiveLine = $totalLines }
    }
    catch [System.ObjectDisposedException] {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXreadlogfile: Log file '$trimmedName' was destroyed during the " +
            'read operation. Set any held references to $null.'
        )
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXreadlogfile: An unexpected error occurred while reading from " +
            "log file '$trimmedName' at line $Line. " +
            "Error: $($_.Exception.Message)"
        )
    }

    # ── Step 6: Return success ────────────────────────────────────────────────
    # The retrieved log line is in .data. The .msg reports both the effective
    # (clamped) line number and the total entry count so callers can detect
    # when clamping occurred without having to inspect the data content itself.
    return VPDLXreturn -Code 0 `
        -Message ("VPDLXreadlogfile: Successfully read line $effectiveLine of $totalLines " +
                  "from log file '$trimmedName'.") `
        -Data $entry
}
