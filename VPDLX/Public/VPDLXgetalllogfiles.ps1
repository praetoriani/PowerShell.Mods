<#
.SYNOPSIS
    VPDLXgetalllogfiles - Public wrapper: retrieves a summary of all active virtual log files.

.DESCRIPTION
    VPDLXgetalllogfiles is the public-facing wrapper that returns an overview of
    every virtual log file currently registered in the VPDLX module's in-memory
    storage. It iterates the [FileStorage] singleton and collects key metadata
    for each [Logfile] instance into an array of [PSCustomObject] entries.

    The function performs the following steps:

      1. Accesses the [FileStorage] singleton via VPDLXcore -KeyID 'storage'.
      2. Checks whether any log files are registered. If storage is empty, a
         success result is returned with an empty array in .data and a note
         that no log files exist.
      3. Iterates all registered names (via FileStorage.GetNames()), retrieves
         each [Logfile] instance, and collects the following properties per
         log file into a [PSCustomObject]:

             Name         [string]  - the log file name (case-preserved)
             EntryCount   [int]     - current number of log entries
             Created      [string]  - creation timestamp (dd.MM.yyyy | HH:mm:ss)
             Updated      [string]  - last write/reset timestamp
             LastAccessed [string]  - last read/filter/export timestamp
             AccessCount  [int]     - total interaction count since creation

      4. Returns a standardised [PSCustomObject] via VPDLXreturn:

             code  0   - success; .data holds [PSCustomObject[]] with one entry
                          per registered log file (or an empty array if none exist)
             code -1   - failure; .msg describes the reason; .data is $null

    NOTE ON METADATA INTERACTION:
        This function reads metadata via the public getters on [FileDetails]
        (GetCreated, GetUpdated, GetLastAccessed, GetAxcount) and [Logfile]
        (EntryCount). These are read-only operations and do NOT increment the
        interaction counter (axcount) or update the last-accessed timestamp of
        any log file. The function is therefore safe to call repeatedly for
        monitoring or dashboard purposes without affecting log file state.

    INTERNAL DEPENDENCIES:
        - VPDLXcore    (root module accessor - exposes $script:storage)
        - VPDLXreturn  (return object factory - Private/)
        - [FileStorage].GetNames()   (retrieves all registered log file names)
        - [FileStorage].Get()        (retrieves a [Logfile] instance by name)
        - [Logfile].EntryCount()     (current entry count)
        - [Logfile].GetDetails()     (access to [FileDetails] companion)
        - [FileDetails] getters      (metadata access)
        The VPDLX.psm1 load order guarantees all are available when this
        file is dot-sourced.

.OUTPUTS
    [PSCustomObject] with three properties:
        code  [int]    -  0 on success, -1 on failure
        msg   [string] -  human-readable status or error description
        data  [object] -  [PSCustomObject[]] array on success (one object per
                           log file, or empty array if none exist); $null on failure

    Each element of .data has the following properties:
        Name         [string]  - log file name
        EntryCount   [int]     - number of stored entries
        Created      [string]  - creation timestamp
        Updated      [string]  - last modification timestamp
        LastAccessed [string]  - last read/filter timestamp
        AccessCount  [int]     - total interaction count

.EXAMPLE
    # List all active log files
    $result = VPDLXgetalllogfiles
    if ($result.code -eq 0) {
        $result.data | Format-Table -AutoSize
    }

.EXAMPLE
    # Check whether any log files exist
    $result = VPDLXgetalllogfiles
    if ($result.data.Count -eq 0) {
        Write-Host 'No log files in the current session.'
    } else {
        Write-Host "$($result.data.Count) log file(s) active."
    }

.EXAMPLE
    # Find the log file with the most entries
    $result = VPDLXgetalllogfiles
    $largest = $result.data | Sort-Object -Property EntryCount -Descending | Select-Object -First 1
    Write-Host "Largest log: $($largest.Name) with $($largest.EntryCount) entries."

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.05
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Website : https://github.com/praetoriani/PowerShell.Mods
    Created : 11.04.2026
    Updated : 11.04.2026
    Scope   : Public - exported via FunctionsToExport in VPDLX.psd1
#>

function VPDLXgetalllogfiles {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

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
            'VPDLXgetalllogfiles: Unable to access module storage via VPDLXcore. ' +
            'Ensure the VPDLX module is loaded correctly. ' +
            "Internal error: $($_.Exception.Message)"
        )
    }

    if ($storage -is [PSCustomObject]) {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXgetalllogfiles: VPDLXcore did not return a valid FileStorage object. ' +
            'Module may not be initialised correctly.'
        )
    }

    # ── Step 2: Handle empty storage ───────────────────────────────────────
    # Return early with an empty array if no log files are registered.
    # This is still a success case (code 0) - the caller simply has no logs yet.
    if ($storage.Count() -eq 0) {
        return VPDLXreturn -Code 0 `
            -Message 'VPDLXgetalllogfiles: No log files registered in the current session.' `
            -Data @()
    }

    # ── Step 3: Iterate all registered log files and collect metadata ──────
    # GetNames() returns the original case-preserved names. For each name
    # we retrieve the [Logfile] instance via Get() and read its metadata
    # through the public [FileDetails] getters.
    #
    # A typed List<PSCustomObject> is used instead of array += to avoid
    # quadratic copy overhead when many log files are registered.
    $summaries = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($logName in $storage.GetNames()) {
        try {
            [object] $logInstance = $storage.Get($logName)

            if ($null -eq $logInstance) {
                # Internal inconsistency - GetNames() listed a name but Get()
                # returned $null. Skip this entry and continue with others.
                Write-Verbose (
                    "VPDLXgetalllogfiles: Skipping '$logName' - Get() returned `$null " +
                    'despite being listed by GetNames(). Possible storage inconsistency.'
                )
                continue
            }

            # Read metadata via the [FileDetails] companion object.
            # These are pure getter calls - they do NOT modify the log file state.
            $details = $logInstance.GetDetails()

            $summaries.Add([PSCustomObject] [ordered] @{
                Name         = $logInstance.Name
                EntryCount   = $logInstance.EntryCount()
                Created      = $details.GetCreated()
                Updated      = $details.GetUpdated()
                LastAccessed = $details.GetLastAccessed()
                AccessCount  = $details.GetAxcount()
            })
        }
        catch [System.ObjectDisposedException] {
            # The instance was destroyed between GetNames() and our Get()/read.
            # This is a rare race condition - skip and continue.
            Write-Verbose (
                "VPDLXgetalllogfiles: Skipping '$logName' - instance was destroyed " +
                'during enumeration (ObjectDisposedException).'
            )
            continue
        }
        catch {
            # Unexpected error for this particular log file - skip and continue
            # rather than failing the entire enumeration.
            Write-Verbose (
                "VPDLXgetalllogfiles: Skipping '$logName' due to unexpected error: " +
                $_.Exception.Message
            )
            continue
        }
    }

    # ── Step 4: Return success ────────────────────────────────────────────────
    [int] $totalCount = $summaries.Count

    return VPDLXreturn -Code 0 `
        -Message "VPDLXgetalllogfiles: Retrieved $totalCount log file(s)." `
        -Data $summaries.ToArray()
}
