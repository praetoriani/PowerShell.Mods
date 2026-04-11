<#
.SYNOPSIS
    VPDLXexportlogfile — Public wrapper: exports a virtual log file to disk.

.DESCRIPTION
    VPDLXexportlogfile is the primary export function introduced in VPDLX
    v1.01.02. It writes the in-memory contents of a named virtual log file
    to a physical file on the local file system.

    The function executes an 8-stage pipeline:

      Stage 1  — Pre-flight       : verify module storage is accessible
      Stage 2  — Format check     : validate ExportAs against $script:export
      Stage 3  — Existence check  : confirm the named log file exists
      Stage 4  — Instance fetch   : retrieve the [Logfile] instance from storage
      Stage 5  — Content check    : guard against exporting an empty log
      Stage 6  — Path preparation : create the target directory if it does not exist
      Stage 7  — Override logic   : handle the -Override switch
      Stage 8  — Write to disk    : serialise the log entries and flush to file

    SUPPORTED EXPORT FORMATS:
        The ExportAs parameter must match a key defined in $script:export:

            txt   —  Plain text. Each log line is written as-is.
                     File extension: .txt

            log   —  Identical to txt format but with .log extension.
                     Suitable for tools that expect a .log file.
                     File extension: .log

            csv   —  Comma-Separated Values. Each log entry is parsed and
                     written as a structured row:
                     "Timestamp","Level","Message"
                     "06.04.2026 | 19:58:00","INFO","Application started."
                     File extension: .csv

            json  —  JSON array of objects. Each entry becomes:
                     { "Timestamp": "...", "Level": "...", "Message": "..." }
                     The full array is wrapped in a root object:
                     { "LogFile": "<name>", "ExportedAt": "...", "Entries": [...] }
                     File extension: .json

    OUTPUT FILE NAMING CONVENTION:
        The physical file is named after the virtual log file name + extension:

            <Logfile>.<extension>

        Examples:
            VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'txt'
            -> C:\Logs\AppLog.txt

            VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json'
            -> C:\Logs\AppLog.json

    DIRECTORY AUTO-CREATION:
        If the directory specified by -LogPath does not exist, the function
        creates the full directory path automatically (equivalent to
        New-Item -ItemType Directory -Force). No manual mkdir required.

    OVERRIDE BEHAVIOUR:
        Without -Override: if the target file already exists, the function
        returns code -1 and leaves the existing file untouched.

        With -Override: if the target file already exists, it is deleted
        before the new file is written. If deletion fails, the function
        returns code -1 immediately without creating a partial file.

    LOG LINE PARSING (CSV / JSON formats):
        The [Logfile].BuildEntry() format is:

            [06.04.2026 | 19:58:00]  [INFO]      ->  Application started.

        The parser splits on the FIRST occurrence of '  ->  ' (two spaces,
        arrow, two spaces) to extract the message. The left part is then
        split on ']  [' to separate timestamp and level. This approach is
        resilient to messages that contain '->' themselves.

    ENCODING:
        All output files are written with UTF-8 encoding. By default,
        Windows PowerShell 5.1 writes a UTF-8 BOM (Byte Order Mark),
        while PowerShell 7.x writes BOM-free UTF-8.

        The -NoBOM switch forces BOM-free UTF-8 output on ALL PowerShell
        versions, including 5.1. This is important for interoperability
        with external log aggregators, Unix-based tools, and web services
        that do not expect or handle a BOM prefix correctly.

        When -NoBOM is specified, the function uses
        [System.IO.File]::WriteAllText() with an explicit
        [System.Text.UTF8Encoding]::new($false) encoder instead of
        Set-Content -Encoding UTF8. This bypasses the PowerShell 5.1
        BOM behaviour entirely.

    IMPROVEMENT v1.02.04 (Priorität 9):
        Added -NoBOM switch parameter for BOM-free UTF-8 export.

    INTERNAL DEPENDENCIES:
        - VPDLXcore     (root module accessor — exposes $script:storage,
                         $script:export)
        - VPDLXreturn   (return object factory — Private/)
        - [FileStorage].Contains() / .Get()  (log file lookup)
        - [Logfile].IsEmpty() / .EntryCount() / .GetAllEntries()
                              (content access)
        The VPDLX.psm1 load order guarantees all are available.

.PARAMETER Logfile
    The name of the virtual log file to export.
    Leading and trailing whitespace is trimmed.

.PARAMETER LogPath
    The full path to the directory where the exported file will be saved.
    If the directory does not exist it will be created automatically.
    Leading and trailing whitespace is trimmed.

.PARAMETER ExportAs
    The target file format. Must be one of: txt | csv | json | log
    The value is validated against $script:export at runtime so it
    automatically reflects any future changes to the supported format list.
    Case-insensitive.

.PARAMETER Override
    Optional switch. When set, an existing file at the target path will be
    deleted before the new file is written. Without this switch, an existing
    file causes the function to return code -1 without overwriting anything.

.PARAMETER NoBOM
    Optional switch. When set, forces BOM-free UTF-8 encoding on ALL
    PowerShell versions, including Windows PowerShell 5.1.

    By default, Windows PowerShell 5.1 writes a UTF-8 BOM (EF BB BF)
    at the beginning of the file when using Set-Content -Encoding UTF8.
    This 3-byte prefix can cause issues with:
      - Unix/Linux log aggregators (e.g. Filebeat, Fluentd)
      - JSON parsers that do not expect a BOM before the opening bracket
      - CSV readers in non-Microsoft tools
      - Web APIs that interpret the BOM as content

    When -NoBOM is specified, the function writes the file using
    [System.IO.File]::WriteAllText() with an explicit BOM-free encoder
    ([System.Text.UTF8Encoding]::new($false)), bypassing the PS 5.1
    default behaviour entirely.

    On PowerShell 7.x, -NoBOM is effectively a no-op because PS 7.x
    already writes BOM-free UTF-8 by default. However, using -NoBOM
    explicitly is still recommended for scripts that must work across
    both PS editions, as it makes the encoding intent clear.

.OUTPUTS
    [PSCustomObject] with three properties:
        code  [int]    —  0 on success, -1 on failure
        msg   [string] —  human-readable status or error description
        data  [object] —  the full path to the created file [string] on success,
                           $null on failure

.EXAMPLE
    # Export as plain text
    $result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'txt'
    if ($result.code -eq 0) { Write-Host "Exported to: $($result.data)" }

.EXAMPLE
    # Export as CSV to a directory that does not yet exist (auto-created)
    $result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\NewDir\SubDir' -ExportAs 'csv'

.EXAMPLE
    # Export as JSON and overwrite if the file already exists
    $result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json' -Override

.EXAMPLE
    # Export as .log file
    $result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'log'
    # -> C:\Logs\AppLog.log

.EXAMPLE
    # Without -Override: existing file is NOT overwritten
    $result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'txt'
    # If C:\Logs\AppLog.txt already exists:
    # $result.code -> -1
    # $result.msg  -> "... already exists. Use -Override to overwrite ..."

.EXAMPLE
    # Export as JSON with BOM-free UTF-8 (important for Unix tools / log aggregators)
    $result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json' -NoBOM
    # On Windows PowerShell 5.1, the file will NOT have the 3-byte BOM prefix (EF BB BF).
    # On PowerShell 7.x, -NoBOM is a no-op (PS 7 is BOM-free by default).

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.04
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Website : https://github.com/praetoriani/PowerShell.Mods
    Created : 06.04.2026
    Updated : 11.04.2026
    Scope   : Public — exported via FunctionsToExport in VPDLX.psd1

    CHANGES (11.04.2026, v1.02.04):
      - Added -NoBOM switch parameter for BOM-free UTF-8 export.
        Uses [System.Text.UTF8Encoding]::new($false) + [System.IO.File]::WriteAllText()
        to bypass the Windows PowerShell 5.1 BOM default.
#>

function VPDLXexportlogfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # Name of the virtual log file to export.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Logfile,

        # Full path to the target directory.
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $LogPath,

        # Target format. Runtime-validated against $script:export keys.
        # [ValidateSet] is intentionally NOT used here because the valid set
        # lives in $script:export and we want validation to reflect that
        # single source of truth dynamically — not a static list duplicated
        # in the parameter declaration.
        [Parameter(Mandatory = $true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string] $ExportAs,

        # When set, an existing file at the target path is deleted first.
        [Parameter(Mandatory = $false)]
        [switch] $Override,

        # When set, forces BOM-free UTF-8 output on all PowerShell versions.
        # Without this switch, Windows PowerShell 5.1 writes a UTF-8 BOM (EF BB BF).
        # On PowerShell 7.x this is effectively a no-op (PS 7 is BOM-free by default).
        # NEW v1.02.04 (Priorität 9).
        [Parameter(Mandatory = $false)]
        [switch] $NoBOM
    )

    # ── Stage 1: Pre-flight — verify module storage and export map ───────────
    # Both $script:storage and $script:export are required. Fetch them in a
    # single try/catch. If either VPDLXcore call fails the module is broken.
    try {
        $storage   = VPDLXcore -KeyID 'storage'
        $exportMap = VPDLXcore -KeyID 'export'
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXexportlogfile: Unable to access module internals via VPDLXcore. ' +
            'Ensure the VPDLX module is loaded correctly. ' +
            "Internal error: $($_.Exception.Message)"
        )
    }

    # Guard: VPDLXcore returns a [PSCustomObject] error carrier on failure.
    if ($storage -is [PSCustomObject]) {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXexportlogfile: VPDLXcore did not return a valid FileStorage object. ' +
            'Module may not be initialised correctly.'
        )
    }
    if ($exportMap -isnot [hashtable]) {
        return VPDLXreturn -Code -1 -Message (
            'VPDLXexportlogfile: VPDLXcore did not return a valid export map (hashtable). ' +
            'Module may not be initialised correctly.'
        )
    }

    # ── Stage 2: Validate ExportAs against $script:export ───────────────────
    # Runtime validation against the live hashtable ensures this check always
    # mirrors the supported format list — no static [ValidateSet] duplication.
    [string] $formatKey = $ExportAs.Trim().ToLower()

    if (-not $exportMap.ContainsKey($formatKey)) {
        [string] $validFormats = ($exportMap.Keys | Sort-Object) -join ', '
        return VPDLXreturn -Code -1 -Message (
            "VPDLXexportlogfile: '$ExportAs' is not a supported export format. " +
            "Valid values: $validFormats. " +
            'The ExportAs value must match a key defined in $script:export.'
        )
    }

    # Resolve the file extension from the map (e.g. 'txt' -> '.txt').
    [string] $fileExtension = $exportMap[$formatKey]

    # ── Stage 3: Trim parameters and verify log file existence ─────────────
    [string] $trimmedName = $Logfile.Trim()
    [string] $trimmedPath = $LogPath.Trim()

    if (-not $storage.Contains($trimmedName)) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXexportlogfile: Log file '$trimmedName' does not exist in the " +
            'current session. Use VPDLXnewlogfile to create it first, or ' +
            'VPDLXislogfile to check existence before exporting.'
        )
    }

    # ── Stage 4: Retrieve the [Logfile] instance ───────────────────────────
    [object] $logInstance = $storage.Get($trimmedName)

    if ($null -eq $logInstance) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXexportlogfile: Log file '$trimmedName' was found by Contains() " +
            'but Get() returned $null. Internal storage inconsistency — please report.'
        )
    }

    # ── Stage 5: Guard against exporting an empty log ─────────────────────
    # Exporting an empty file is technically possible but almost certainly
    # a caller mistake. We fail fast with a helpful message rather than
    # producing a 0-byte or header-only file.
    try {
        [bool] $isEmpty = $logInstance.IsEmpty()
    }
    catch [System.ObjectDisposedException] {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXexportlogfile: Log file '$trimmedName' has been destroyed and " +
            'is no longer accessible. Set any held references to $null.'
        )
    }

    if ($isEmpty) {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXexportlogfile: Log file '$trimmedName' contains no entries. " +
            'Write at least one entry via VPDLXwritelogfile before exporting.'
        )
    }

    # ── Stage 6: Ensure the target directory exists ────────────────────────
    # Create the full directory path if it does not already exist.
    # New-Item -Force creates all missing intermediate directories in one call,
    # analogous to 'mkdir -p' on Unix systems.
    if (-not (Test-Path -LiteralPath $trimmedPath -PathType Container)) {
        try {
            New-Item -Path $trimmedPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            return VPDLXreturn -Code -1 -Message (
                "VPDLXexportlogfile: Failed to create target directory '$trimmedPath'. " +
                "Error: $($_.Exception.Message)"
            )
        }
    }

    # Build the full target file path: <LogPath>\<Logfile><.ext>
    [string] $targetFile = Join-Path -Path $trimmedPath -ChildPath ($trimmedName + $fileExtension)

    # ── Stage 7: Override logic ────────────────────────────────────────────────
    # Without -Override: block export if a file already exists at the target path.
    # With -Override:    delete the existing file before writing the new one.
    #                    If deletion fails, abort — never write a partial file.
    if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
        if (-not $Override) {
            return VPDLXreturn -Code -1 -Message (
                "VPDLXexportlogfile: Target file '$targetFile' already exists. " +
                'Use -Override to overwrite the existing file.'
            )
        }

        # -Override was specified — remove the existing file first.
        try {
            Remove-Item -LiteralPath $targetFile -Force -ErrorAction Stop
        }
        catch {
            return VPDLXreturn -Code -1 -Message (
                "VPDLXexportlogfile: -Override was specified but the existing file " +
                "'$targetFile' could not be deleted. " +
                "Error: $($_.Exception.Message)"
            )
        }
    }

    # ── Stage 8: Serialise and write to disk ───────────────────────────────
    # Retrieve all entries from the log instance as a string array.
    # [Logfile].GetAllEntries() returns a copy of the internal List<string>
    # as [string[]] so iteration is safe even if the log is written to
    # concurrently (unlikely in PS but good practice).
    try {
        [string[]] $entries = $logInstance.GetAllEntries()
    }
    catch [System.ObjectDisposedException] {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXexportlogfile: Log file '$trimmedName' was destroyed during " +
            'content retrieval. Set any held references to $null.'
        )
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXexportlogfile: Failed to retrieve entries from log file '$trimmedName'. " +
            "Error: $($_.Exception.Message)"
        )
    }

    # ── Helper: Write content to file with correct encoding ──────────────────
    # Encapsulates the BOM/NoBOM decision in a single helper so the format-
    # specific blocks below do not need to repeat the encoding logic.
    #
    # When -NoBOM is specified (or the caller wants BOM-free UTF-8 on PS 5.1),
    # this helper joins the lines into a single string and writes via
    # [System.IO.File]::WriteAllText() with an explicit BOM-free encoder.
    # Otherwise, it falls back to Set-Content -Encoding UTF8 (standard PS).
    #
    # NEW v1.02.04 (Priorität 9).
    $writeLinesToFile = {
        param(
            [string]   $FilePath,
            [string[]] $Lines,
            [bool]     $UseBomFreeUtf8
        )
        if ($UseBomFreeUtf8) {
            # BOM-free UTF-8 encoder: the $false argument to UTF8Encoding
            # suppresses the 3-byte BOM prefix (EF BB BF).
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [string] $content = $Lines -join [System.Environment]::NewLine
            [System.IO.File]::WriteAllText($FilePath, $content, $utf8NoBom)
        }
        else {
            $Lines | Set-Content -LiteralPath $FilePath -Encoding UTF8 -ErrorAction Stop
        }
    }

    # Format the content according to ExportAs.
    # Each format has its own serialisation block; all are wrapped in a
    # single try/catch that reports the format name in the error message.
    try {
        switch ($formatKey) {

            # ── txt / log: write each entry as a plain line ─────────────────
            { $_ -in 'txt','log' } {
                & $writeLinesToFile -FilePath $targetFile -Lines $entries -UseBomFreeUtf8 $NoBOM.IsPresent
            }

            # ── csv: parse each entry into Timestamp/Level/Message columns ──
            'csv' {
                # Build CSV rows. The header is always the first line.
                [System.Collections.Generic.List[string]] $csvLines =
                    [System.Collections.Generic.List[string]]::new()
                $csvLines.Add('"Timestamp","Level","Message"')

                foreach ($entry in $entries) {
                    # Log line format:
                    #   [06.04.2026 | 19:58:00]  [INFO]      ->  Message text
                    #
                    # Split strategy:
                    #   1. Split on '  ->  ' (double-space arrow double-space) to isolate
                    #      the message. Use -Count 2 so arrows inside the message are kept.
                    #   2. Strip the outer [ ] brackets from the left part.
                    #   3. Split on ']  [' to separate timestamp and level.
                    #
                    # Fallback: if parsing fails, write the raw line in the Message column.
                    [string] $ts      = ''
                    [string] $lvl     = ''
                    [string] $msg     = ''

                    $arrowParts = $entry -split '  ->  ', 2
                    if ($arrowParts.Count -eq 2) {
                        $msg = $arrowParts[1].Trim()

                        # Left part: "[06.04.2026 | 19:58:00]  [INFO]"
                        # Strip leading '[' and trailing ']', then split on ']  ['
                        [string] $leftPart = $arrowParts[0].Trim()
                        $leftPart = $leftPart.TrimStart('[')    # remove opening [
                        $bracketParts = $leftPart -split '\]\s+\[', 2
                        if ($bracketParts.Count -eq 2) {
                            $ts  = $bracketParts[0].Trim()
                            $lvl = $bracketParts[1].TrimEnd(']').Trim()
                        } else {
                            $ts  = $leftPart.Trim()
                            $lvl = 'UNKNOWN'
                        }
                    } else {
                        # Unparseable line — preserve as raw message
                        $msg = $entry
                        $ts  = ''
                        $lvl = 'RAW'
                    }

                    # Escape double-quotes in all fields (CSV RFC 4180).
                    $ts  = $ts  -replace '"', '""'
                    $lvl = $lvl -replace '"', '""'
                    $msg = $msg -replace '"', '""'

                    $csvLines.Add("`"$ts`",`"$lvl`",`"$msg`"")
                }

                & $writeLinesToFile -FilePath $targetFile -Lines $csvLines.ToArray() -UseBomFreeUtf8 $NoBOM.IsPresent
            }

            # ── json: structured array wrapped in a root object ─────────────
            'json' {
                [System.Collections.Generic.List[object]] $jsonEntries =
                    [System.Collections.Generic.List[object]]::new()

                foreach ($entry in $entries) {
                    # Same parsing approach as CSV above.
                    [string] $ts  = ''
                    [string] $lvl = ''
                    [string] $msg = ''

                    $arrowParts = $entry -split '  ->  ', 2
                    if ($arrowParts.Count -eq 2) {
                        $msg = $arrowParts[1].Trim()
                        [string] $leftPart = $arrowParts[0].Trim().TrimStart('[')
                        $bracketParts = $leftPart -split '\]\s+\[', 2
                        if ($bracketParts.Count -eq 2) {
                            $ts  = $bracketParts[0].Trim()
                            $lvl = $bracketParts[1].TrimEnd(']').Trim()
                        } else {
                            $ts  = $leftPart.Trim()
                            $lvl = 'UNKNOWN'
                        }
                    } else {
                        $msg = $entry
                        $ts  = ''
                        $lvl = 'RAW'
                    }

                    $jsonEntries.Add([ordered]@{
                        Timestamp = $ts
                        Level     = $lvl
                        Message   = $msg
                    })
                }

                # Build the root wrapper object.
                $jsonRoot = [ordered]@{
                    LogFile    = $trimmedName
                    ExportedAt = (Get-Date -Format 'dd.MM.yyyy | HH:mm:ss')
                    EntryCount = $jsonEntries.Count
                    Entries    = $jsonEntries
                }

                # ConvertTo-Json -Depth must be >= 3 to serialise the nested
                # Entries array fully (root -> Entries -> each entry object).
                [string] $jsonString = $jsonRoot | ConvertTo-Json -Depth 5
                & $writeLinesToFile -FilePath $targetFile -Lines @($jsonString) -UseBomFreeUtf8 $NoBOM.IsPresent
            }
        }
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXexportlogfile: Failed to write '$formatKey' output to '$targetFile'. " +
            "Error: $($_.Exception.Message)"
        )
    }

    # ── Success ───────────────────────────────────────────────────────────────
    # .data holds the full path to the created file so callers can immediately
    # open, attach, or forward the file without reconstructing the path.
    [int] $totalWritten = $entries.Count

    return VPDLXreturn -Code 0 `
        -Message ("VPDLXexportlogfile: Successfully exported log file '$trimmedName' " +
                  "as '$formatKey' to '$targetFile'. " +
                  "$totalWritten $( if ($totalWritten -eq 1) { 'entry' } else { 'entries' } ) written.") `
        -Data $targetFile
}
