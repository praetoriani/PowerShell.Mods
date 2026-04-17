<#
.SYNOPSIS
    VPDLXdroplogfile - Public wrapper: permanently destroys a virtual log file.

.DESCRIPTION
    VPDLXdroplogfile is the public-facing wrapper for completely and
    irreversibly removing a named virtual log file from the VPDLX module’s
    in-memory storage. It wraps the [Logfile].Destroy() method call in a safe,
    standardised function that:

      1. Validates the supplied name and confirms the log file exists.
      2. Retrieves the [Logfile] instance from $script:storage via VPDLXcore.
      3. Calls .Destroy() on the instance, which:
             a. Removes the entry from the [FileStorage] registry.
             b. Clears the internal data list (List<string>) and sets it to $null.
             c. Sets the internal [FileDetails] companion object to $null.
         After .Destroy() returns, the instance is no longer usable. Any
         external variable still holding a reference to the old instance will
         receive [System.ObjectDisposedException] if a method is called on it.
      4. Returns a standardised [PSCustomObject] via VPDLXreturn:

             code  0   - success; log file was found and destroyed; .data is $null
             code -1   - failure; .msg describes the reason (not found, storage
                          unavailable, unexpected error); .data is $null

    WARNING:
        This operation is destructive and CANNOT be undone. All log data held
        in the virtual log file is permanently lost. There is no recycle bin,
        no recovery path, and no confirmation prompt. Callers should verify
        they have exported or processed the data (via VPDLXexportlogfile) before
        calling this function if the data must be preserved.

    RELATIONSHIP TO [Logfile].Destroy():
        Callers who hold a direct [Logfile] reference can call .Destroy()
        themselves on the class instance. VPDLXdroplogfile exists as the
        public-wrapper alternative for callers who:
          - only know the log file’s name (not the object reference), or
          - prefer the consistent VPDLXreturn contract over direct OOP calls, or
          - want a single ‘drop by name’ operation with built-in error handling.

    INTERNAL DEPENDENCIES:
        - VPDLXcore    (root module accessor - exposes $script:storage)
        - VPDLXreturn  (return object factory - Private/)
        - [FileStorage].Get()     (retrieves the [Logfile] instance by name)
        - [Logfile].Destroy()     (performs the actual removal and cleanup)
        The VPDLX.psm1 load order guarantees all are available when this
        file is dot-sourced.

.PARAMETER Logfile
    The name of the virtual log file to destroy.

    The lookup is case-insensitive, matching the OrdinalIgnoreCase comparer
    used internally by [FileStorage]. Leading and trailing whitespace is
    trimmed before the lookup.

.OUTPUTS
    [PSCustomObject] with three properties:
        code  [int]    -  0 on success, -1 on failure
        msg   [string] -  human-readable status or error description
        data  [object] -  always $null (destroyed instances carry no payload)

.EXAMPLE
    # Basic usage - drop a log file by name
    $result = VPDLXdroplogfile -Logfile 'AppLog'
    if ($result.code -eq 0) {
        Write-Host 'Log file dropped successfully.'
    } else {
        Write-Warning "Failed: $($result.msg)"
    }

.EXAMPLE
    # Safe pattern: check existence before dropping
    if (VPDLXislogfile -Logfile 'TempLog') {
        $result = VPDLXdroplogfile -Logfile 'TempLog'
    }

.EXAMPLE
    # Attempt to drop a non-existent log file - returns code -1
    $result = VPDLXdroplogfile -Logfile 'Ghost'
    # $result.code  -> -1
    # $result.msg   -> "... 'Ghost' does not exist ..."

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.02
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Website : https://github.com/praetoriani/PowerShell.Mods
    Created : 06.04.2026
    Updated : 06.04.2026
    Scope   : Public - exported via Export-ModuleMember in VPDLX.psm1
#>

function VPDLXdroplogfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # The name of the virtual log file to permanently destroy.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Logfile
    )

    # ── Step 1: Pre-flight - verify module storage is accessible ────────────
    # VPDLXcore bridges the scope gap between dot-sourced Public/ functions
    # and $script:* variables in VPDLX.psm1. A PSCustomObject return from
    # VPDLXcore (code -1) signals that the module is in a broken state.
    try {
        $storage = VPDLXcore -KeyID 'storage'
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXdroplogfile: Unable to access module storage via VPDLXcore. ' +
            'Ensure the VPDLX module is loaded correctly. ' +
            "Internal error: $($_.Exception.Message)"
        )
    }

    if ($storage -is [PSCustomObject]) {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXdroplogfile: VPDLXcore did not return a valid FileStorage object. ' +
            'Module may not be initialised correctly.'
        )
    }

    # ── Step 2: Trim name and verify the log file exists ───────────────────
    # Trim to match the normalisation applied in [Logfile]::new() and the
    # other public wrappers. Then guard early with a clear, user-friendly
    # message if the log file is not registered - avoids a raw exception
    # from FileStorage.Get() or Logfile.Destroy().
    [string] $trimmedName = $Logfile.Trim()

    if (-not $storage.Contains($trimmedName)) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXdroplogfile: Log file '$trimmedName' does not exist in the " +
            'current session. Nothing was removed. ' +
            'Use VPDLXislogfile to check existence before calling this function.'
        )
    }

    # ── Step 3: Retrieve the [Logfile] instance from storage ──────────────
    # FileStorage.Get() returns $null if the name is not found. We already
    # confirmed existence above, so a $null result here would be an internal
    # consistency error (extremely unlikely race condition).
    [object] $logInstance = $storage.Get($trimmedName)

    if ($null -eq $logInstance) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXdroplogfile: Log file '$trimmedName' was found by Contains() " +
            'but Get() returned $null. This indicates an internal storage ' +
            'inconsistency. Please report this as a bug.'
        )
    }

    # ── Step 4: Destroy the [Logfile] instance ─────────────────────────────
    # [Logfile].Destroy() performs three actions atomically:
    #   1. Calls $script:storage.Remove(this.Name)  - deregisters from FileStorage
    #   2. Calls _data.Clear() and sets _data = $null  - releases log content
    #   3. Sets _details = $null  - releases companion metadata object
    # After this call the instance is a "zombie" object: it still exists as a
    # .NET reference if the caller holds one, but every method call on it will
    # throw [System.ObjectDisposedException] via the GuardDestroyed() check.
    #
    # We wrap in try/catch to convert any unexpected runtime error into the
    # standardised return object rather than letting it propagate.
    try {
        $logInstance.Destroy()
    }
    catch [System.ObjectDisposedException] {
        # The instance was already destroyed before this call - for example
        # if the caller previously called .Destroy() directly on their reference.
        # The log file is gone either way; treat as success with a note.
        return VPDLXreturn -Code 0 -Message (
            "VPDLXdroplogfile: Log file '$trimmedName' was already destroyed " +
            '(ObjectDisposedException). It has been removed from storage.'
        )
    }
    catch {
        # Any other unexpected error from Destroy() or the underlying Remove().
        return VPDLXreturn -Code -1 -Message (
            "VPDLXdroplogfile: An unexpected error occurred while destroying " +
            "log file '$trimmedName'. Error: $($_.Exception.Message)"
        )
    }

    # ── Step 5: Return success ────────────────────────────────────────────────
    # .data is $null by design: the log file no longer exists, so there is no
    # object to return. Callers should set any variable that held the old
    # [Logfile] reference to $null to avoid accidentally calling methods on the
    # now-destroyed zombie instance.
    return VPDLXreturn -Code 0 `
        -Message "VPDLXdroplogfile: Log file '$trimmedName' was destroyed successfully. " +
                 'All data has been permanently removed. Set any held references to $null.'
}
