<#
.SYNOPSIS
    VPDLXattachlogfile - Public wrapper: appends the buffer of a virtual log file to a physical file.

.DESCRIPTION
    Appends the CURRENT in-memory entries of a virtual log file to a physical
    file. Existing file content is never overwritten (in contrast to
    VPDLXexportlogfile, which writes an overwriting snapshot).

    Appendable formats: txt, log, csv, ndjson. For csv the header line is
    written only when the file is new or empty. json and html cannot be
    appended to - use VPDLXexportlogfile for those.

    Target resolution:
      - -LogPath / -AttachAs given  -> used as specified.
      - omitted                     -> the target configured at creation time
                                       (VPDLXnewlogfile -AttachPath/-AttachAs/-DailyFile).
      - nothing configured/given    -> failure (code -1).
    With -Clear the buffer is emptied after a successful append (Reset()).

    The automatic flush of a log file with -MaxEntries / -AttachPath uses the
    same append logic (VPDLXappendcore).

.PARAMETER Logfile   Name of the virtual log file.
.PARAMETER LogPath   Target directory (optional if configured at creation).
.PARAMETER AttachAs  txt | log | csv | ndjson (optional; default: configured format or txt).
.PARAMETER NoBOM     Write a new file as BOM-free UTF-8.
.PARAMETER Clear     Empty the buffer after a successful append.

.OUTPUTS
    [PSCustomObject] code 0 = success (.data = full file path), -1 = failure.

.EXAMPLE
    $r = VPDLXattachlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -AttachAs csv -Clear

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.07
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 30.10.2026
    Scope   : Public - exported via FunctionsToExport in VPDLX.psd1
#>

function VPDLXattachlogfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Logfile,

        [Parameter(Mandatory = $false)]
        [string] $LogPath = '',

        [Parameter(Mandatory = $false)]
        [string] $AttachAs = '',

        [switch] $NoBOM,
        [switch] $Clear
    )

    # -- Step 1: module storage ------------------------------------------------
    try {
        $coreResult_storage = VPDLXcore -KeyID 'storage'
        if ($coreResult_storage.code -ne 0) {
            return VPDLXreturn -Code -1 -Message $coreResult_storage.msg
        }
        $storage = $coreResult_storage.data
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXattachlogfile: Unable to access module storage via VPDLXcore. ' +
            "Internal error: $($_.Exception.Message)"
        )
    }

    if ($storage -is [PSCustomObject]) {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXattachlogfile: VPDLXcore did not return a valid FileStorage object.'
        )
    }

    # -- Step 2: log file lookup -------------------------------------------------
    [string] $trimmedName = $Logfile.Trim()
    if (-not $storage.Contains($trimmedName)) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXattachlogfile: Log file '$trimmedName' does not exist in the current session."
        )
    }
    $logInstance = $storage.Get($trimmedName)
    if ($null -eq $logInstance) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXattachlogfile: Log file '$trimmedName' was found by Contains() but Get() returned `$null."
        )
    }

    try {
        # -- Step 3: resolve target ------------------------------------------------
        [string] $path   = $LogPath.Trim()
        [string] $format = $AttachAs.Trim().ToLower()

        if ([string]::IsNullOrEmpty($path)) {
            $path = $logInstance.GetAttachPath()
            if ([string]::IsNullOrEmpty($path)) {
                return VPDLXreturn -Code -1 -Message (
                    "VPDLXattachlogfile: No target. Specify -LogPath or create '$trimmedName' " +
                    'with -AttachPath.'
                )
            }
            if ([string]::IsNullOrEmpty($format)) { $format = $logInstance.GetAttachAs() }
        }
        if ([string]::IsNullOrEmpty($format)) { $format = 'txt' }

        if (-not [Logfile]::AttachExtensions.ContainsKey($format)) {
            [string] $valid = ([Logfile]::AttachExtensions.Keys | Sort-Object) -join ', '
            return VPDLXreturn -Code -1 -Message (
                "VPDLXattachlogfile: '$AttachAs' is not an appendable format. Valid values: $valid. " +
                'Use VPDLXexportlogfile for json/html.'
            )
        }

        # -- Step 4: nothing to do? ------------------------------------------------
        if ($logInstance.IsEmpty()) {
            return VPDLXreturn -Code -1 -Message (
                "VPDLXattachlogfile: Log file '$trimmedName' contains no entries. Nothing appended."
            )
        }

        # -- Step 5: build file name and append -------------------------------------
        # Same naming as the auto-flush: <Name>[_yyyy-MM-dd]<.ext>. The date
        # variant is used only if the configured target (no explicit -LogPath)
        # was created with -DailyFile.
        [string] $targetFile = [System.IO.Path]::Combine(
            $path, $trimmedName + [Logfile]::AttachExtensions[$format]
        )
        if ([string]::IsNullOrEmpty($LogPath.Trim()) -and
            $format -eq $logInstance.GetAttachAs()) {
            $targetFile = $logInstance.GetAttachFile()
        }

        [string[]] $entries = $logInstance.GetAllEntries()
        $res = VPDLXappendcore -FilePath $targetFile -Lines $entries -Format $format -NoBOM:$NoBOM
        if ($res.code -ne 0) {
            return VPDLXreturn -Code -1 -Message ('VPDLXattachlogfile: ' + $res.msg)
        }

        if ($Clear) { $logInstance.Reset() }

        return VPDLXreturn -Code 0 -Data $targetFile -Message (
            "VPDLXattachlogfile: $($entries.Count) entr$(if ($entries.Count -eq 1) {'y'} else {'ies'}) " +
            "of '$trimmedName' appended to '$targetFile'." +
            $(if ($Clear) { ' Buffer cleared.' } else { '' })
        )
    }
    catch [System.ObjectDisposedException] {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXattachlogfile: Log file '$trimmedName' has been destroyed."
        )
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXattachlogfile: Unexpected error: $($_.Exception.Message)"
        )
    }
}
