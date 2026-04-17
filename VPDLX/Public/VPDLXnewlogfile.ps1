<#
.SYNOPSIS
    VPDLXnewlogfile - Public wrapper: creates a new virtual log file.

.DESCRIPTION
    VPDLXnewlogfile is the public-facing wrapper for creating a new named
    virtual log file within the VPDLX module. It wraps the [Logfile]::new()
    constructor call in a safe, standardised function that:

      1. Validates the supplied name before attempting object creation.
      2. Calls [Logfile]::new() to create the in-memory log file and register
         it with the module-level [FileStorage] singleton ($script:storage).
      3. Returns a standardised [PSCustomObject] via VPDLXreturn so callers
         can branch on .code without catching exceptions:

             code  0   - success; .data holds the new [Logfile] instance
             code -1   - failure; .msg describes the reason; .data is $null

    This design separates error handling from business logic: callers do not
    need try/catch blocks and can rely on a predictable return contract.

    NAMING CONVENTION:
        The function follows the VPDLX flat-name convention (no verb-noun
        hyphen). All public wrapper functions are prefixed with 'VPDLX'
        followed by a lowercase verb-descriptor compound:
            VPDLXnewlogfile    (this function)
            VPDLXislogfile     (existence check - future)
            VPDLXdroplogfile   (removal - future)
            VPDLXreadlogfile   (read a line - future)
            VPDLXwritelogfile  (write a line - future)
            VPDLXexportlogfile (export to disk - future)

    INTERNAL DEPENDENCIES:
        - VPDLXcore    (root module accessor - exposes $script:storage)
        - VPDLXreturn  (return object factory - Private/)
        - [Logfile]    (core class - Classes/Logfile.ps1)
        The VPDLX.psm1 load order guarantees all three are available when
        this file is dot-sourced.

.PARAMETER Logfile
    The name for the new virtual log file.

    Constraints (enforced by the [Logfile] constructor):
      - Must not be null, empty, or whitespace-only.
      - Must be between 3 and 64 characters long.
      - May only contain alphanumeric characters plus underscore (_),
        hyphen (-), and dot (.).
      - Must be unique (case-insensitive) within the current session;
        a log file with the same name must not already be registered.

.OUTPUTS
    [PSCustomObject] with three properties:
        code  [int]    - 0 on success, -1 on failure
        msg   [string] - human-readable status or error description
        data  [object] - the new [Logfile] instance on success, $null on failure

.EXAMPLE
    # Basic usage - create a new log file and check the result
    $result = VPDLXnewlogfile -Logfile 'AppLog'
    if ($result.code -eq 0) {
        Write-Host "Log file created: $($result.data.Name)"
        $log = $result.data
        $log.Info('Application started.')
    } else {
        Write-Warning "Failed to create log file: $($result.msg)"
    }

.EXAMPLE
    # Duplicate-name attempt - returns code -1 with a descriptive message
    $r1 = VPDLXnewlogfile -Logfile 'MyLog'   # code 0
    $r2 = VPDLXnewlogfile -Logfile 'MyLog'   # code -1, already exists

.EXAMPLE
    # Invalid name - too short
    $result = VPDLXnewlogfile -Logfile 'AB'
    # $result.code  -> -1
    # $result.msg   -> "... must be between 3 and 64 characters ..."

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.02
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Website : https://github.com/praetoriani/PowerShell.Mods
    Created : 06.04.2026
    Updated : 06.04.2026
    Scope   : Public - exported via Export-ModuleMember in VPDLX.psm1
#>

function VPDLXnewlogfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # The name for the new virtual log file.
        # The [Logfile] constructor enforces all naming constraints.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Logfile
    )

    # ── Step 1: Pre-flight - verify the VPDLX core is accessible ─────────────
    # VPDLXcore bridges the scope gap between dot-sourced Public/ functions and
    # the $script:* variables that live in VPDLX.psm1's root module scope.
    # If VPDLXcore itself returns an error object (code -1), the module is in
    # an inconsistent state and we must abort early rather than risk a confusing
    # runtime error further down.
    try {
        $coreResult_storage = VPDLXcore -KeyID 'storage'
        if ($coreResult_storage.code -ne 0) {
            return VPDLXreturn -Code -1 -Message $coreResult_storage.msg
        }
        $storage = $coreResult_storage.data
    }
    catch {
        # VPDLXcore threw - very unlikely but guard defensively.
        return VPDLXreturn -Code -1 -Message (
            "VPDLXnewlogfile: Unable to access module storage via VPDLXcore. " +
            "Ensure the VPDLX module is loaded correctly. " +
            "Internal error: $($_.Exception.Message)"
        )
    }

    # VPDLXcore returns a PSCustomObject with code -1 on key-not-found errors.
    # A healthy storage object is a [FileStorage] instance, not a PSCustomObject.
    if ($storage -is [PSCustomObject]) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXnewlogfile: VPDLXcore did not return a valid storage object. " +
            "Module may not be initialised correctly."
        )
    }

    # ── Step 2: Duplicate check ───────────────────────────────────────────────
    # Perform an explicit Contains() check here before calling [Logfile]::new().
    # This allows us to return a clean, user-friendly message rather than
    # surfacing the raw [InvalidOperationException] thrown by the constructor.
    # The trimmed name is used to match the normalisation inside the constructor.
    [string] $trimmedName = $Logfile.Trim()

    if ($storage.Contains($trimmedName)) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXnewlogfile: A log file named '$trimmedName' already exists in " +
            "the current session. Use VPDLXdroplogfile to remove it first, or " +
            "choose a different name."
        )
    }

    # ── Step 3: Create the [Logfile] instance ─────────────────────────────────
    # [Logfile]::new() performs full validation of the name (length, character
    # set) and registers the new instance in $script:storage automatically.
    # We wrap this in try/catch to convert constructor exceptions into the
    # standardised return object rather than letting them propagate as
    # terminating errors to the caller.
    try {
        $newLogfile = [Logfile]::new($trimmedName)
    }
    catch [System.ArgumentException] {
        # Thrown by the constructor for invalid name format (too short/long,
        # disallowed characters, null/empty input).
        return VPDLXreturn -Code -1 -Message (
            "VPDLXnewlogfile: Invalid log file name '$trimmedName'. " +
            $_.Exception.Message
        )
    }
    catch [System.InvalidOperationException] {
        # Thrown by the constructor if the duplicate check inside [Logfile]
        # fires (race condition between our pre-check and the constructor;
        # extremely unlikely but handled for correctness).
        return VPDLXreturn -Code -1 -Message (
            "VPDLXnewlogfile: Log file '$trimmedName' could not be created " +
            "because a duplicate was detected. " +
            $_.Exception.Message
        )
    }
    catch {
        # Catch-all for any unexpected error from the constructor or from
        # [FileStorage].Add() that was not covered above.
        return VPDLXreturn -Code -1 -Message (
            "VPDLXnewlogfile: An unexpected error occurred while creating " +
            "log file '$trimmedName'. Error: $($_.Exception.Message)"
        )
    }

    # ── Step 4: Return success ────────────────────────────────────────────────
    # The new [Logfile] instance is returned in the .data property so the
    # caller can capture and use it immediately without a separate lookup.
    return VPDLXreturn -Code 0 `
        -Message "VPDLXnewlogfile: Log file '$trimmedName' created successfully." `
        -Data $newLogfile
}
