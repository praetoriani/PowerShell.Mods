<#
.SYNOPSIS
    VPDLXislogfile - Public wrapper: checks whether a named virtual log file exists.

.DESCRIPTION
    VPDLXislogfile is the public-facing wrapper for checking whether a virtual
    log file with a given name is currently registered in the VPDLX module’s
    in-memory storage ($script:storage).

    The function provides a safe, boolean-oriented existence check that is
    analogous to calling $script:storage.Contains() directly - except that
    callers do not need access to the module-internal storage singleton and do
    not need to handle exceptions themselves.

    DESIGN RATIONALE - returning [bool] vs. VPDLXreturn:
        Unlike other VPDLX wrappers that return a standardised [PSCustomObject]
        via VPDLXreturn, VPDLXislogfile returns a plain [bool]. This mirrors
        the contract of .NET’s Contains() / ContainsKey() methods and makes
        the function directly usable in conditional expressions without
        inspecting a .code property:

            # Idiomatic usage:
            if (VPDLXislogfile -Logfile 'AppLog') { ... }

            # vs. the more verbose VPDLXreturn pattern:
            if ((VPDLXislogfile -Logfile 'AppLog').code -eq 0) { ... }

        Returning [bool] is the correct choice here because the question being
        asked is inherently binary: the log file either exists or it does not.
        There is no meaningful ‘failure’ state - a missing storage object (which
        would indicate a broken module load) is surfaced as $false rather than
        an error object, and a Write-Warning is emitted so the caller is not
        silently misled.

    INTERNAL DEPENDENCIES:
        - VPDLXcore    (root module accessor - exposes $script:storage)
        - [FileStorage] .Contains() method (Classes/FileStorage.ps1)
        The VPDLX.psm1 load order guarantees both are available when
        this file is dot-sourced.

.PARAMETER Logfile
    The name of the virtual log file to check for.

    The lookup is case-insensitive, matching the OrdinalIgnoreCase comparer
    used by the [FileStorage] internal dictionary. Leading and trailing
    whitespace is trimmed before the check.

    Passing a null, empty, or whitespace-only string returns $false immediately
    (the [ValidateNotNullOrEmpty()] attribute is intentionally NOT applied here
    so that programmatic callers are never hit with a terminating error —
    instead they receive a safe $false).

.OUTPUTS
    [bool]
        $true   - a log file with the given name exists in the current session
        $false  - no log file with that name is registered, or the name is
                   null/empty/whitespace, or the module storage is unavailable

.EXAMPLE
    # Guard before creating - avoid duplicate creation errors
    if (-not (VPDLXislogfile -Logfile 'AppLog')) {
        $result = VPDLXnewlogfile -Logfile 'AppLog'
    }

.EXAMPLE
    # Guard before writing - verify the target log exists first
    if (VPDLXislogfile -Logfile 'AppLog') {
        $result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Ready.'
    } else {
        Write-Warning "Log file 'AppLog' does not exist."
    }

.EXAMPLE
    # Use in a conditional assignment
    $exists = VPDLXislogfile -Logfile 'DiagLog'
    Write-Host "DiagLog exists: $exists"

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.02
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Website : https://github.com/praetoriani/PowerShell.Mods
    Created : 06.04.2026
    Updated : 06.04.2026
    Scope   : Public - exported via Export-ModuleMember in VPDLX.psm1
#>

function VPDLXislogfile {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # The name of the virtual log file to look up.
        # Null/empty/whitespace input is handled gracefully (returns $false).
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Logfile
    )

    # ── Step 1: Guard - null / empty / whitespace-only name ─────────────────
    # Return $false immediately rather than propagating a parameter-validation
    # error. Programmatic callers should never receive a terminating error from
    # an existence check - $false is the correct, safe answer.
    if ([string]::IsNullOrWhiteSpace($Logfile)) {
        Write-Verbose 'VPDLXislogfile: Received null, empty, or whitespace-only name. Returning $false.'
        return $false
    }

    # Trim leading/trailing whitespace to match the normalisation applied
    # inside [Logfile]::new() and VPDLXnewlogfile.
    [string] $trimmedName = $Logfile.Trim()

    # ── Step 2: Acquire the module storage singleton via VPDLXcore ───────────
    # VPDLXcore is defined in VPDLX.psm1 and is always in scope because Public/
    # functions are dot-sourced into the same module scope. The try/catch here
    # protects against the extreme edge case where the module was loaded in a
    # broken state and VPDLXcore itself throws.
    try {
        $storage = VPDLXcore -KeyID 'storage'
    }
    catch {
        # VPDLXcore threw - module is in an inconsistent state.
        # Emit a warning (so the caller is not silently misled) and return $false.
        Write-Warning (
            "VPDLXislogfile: Unable to access module storage via VPDLXcore. " +
            "Ensure the VPDLX module is loaded correctly. " +
            "Internal error: $($_.Exception.Message)"
        )
        return $false
    }

    # VPDLXcore returns a PSCustomObject with code -1 when an unknown KeyID is
    # given. A healthy storage object is a [FileStorage] instance.
    if ($storage -is [PSCustomObject]) {
        Write-Warning (
            'VPDLXislogfile: VPDLXcore did not return a valid FileStorage object. ' +
            'Module may not be initialised correctly.'
        )
        return $false
    }

    # ── Step 3: Delegate to FileStorage.Contains() ──────────────────────────
    # [FileStorage].Contains() uses an OrdinalIgnoreCase dictionary internally,
    # so the lookup is already case-insensitive. We wrap it in try/catch purely
    # as a defensive measure; Contains() does not throw under normal conditions.
    try {
        [bool] $exists = $storage.Contains($trimmedName)
        Write-Verbose "VPDLXislogfile: Contains('$trimmedName') -> $exists"
        return $exists
    }
    catch {
        # Unexpected error from Contains() - treat as non-existence and warn.
        Write-Warning (
            "VPDLXislogfile: An unexpected error occurred while checking for " +
            "log file '$trimmedName'. Error: $($_.Exception.Message)"
        )
        return $false
    }
}
