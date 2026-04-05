function ReadLogfileEntry {
    <#
    .SYNOPSIS
    Reads a specific entry (line) from an existing virtual log file.

    .DESCRIPTION
    ReadLogfileEntry retrieves a single formatted log line from the specified virtual
    log file. Line numbers are 1-based (line 1 = first entry).

    Boundary behavior:
      - If 'line' is less than 1, line 1 is used automatically.
      - If 'line' is greater than the total number of entries, the last available
        entry is returned instead of throwing an error.
      - If the log file exists but contains no entries, an informational failure is
        returned (code -1) with an explanatory message.

    .PARAMETER filename
    The name of the existing virtual log file to read from (without file extension).

    .PARAMETER line
    The 1-based line number to read. If this value exceeds the number of entries,
    the last entry is returned automatically.

    .OUTPUTS
    PSCustomObject with the following properties:
      code  [int]    :  0 on success, -1 on failure
      msg   [string] :  human-readable status or error message
      data  [object] :  $null on failure; on success the requested log entry string

    .EXAMPLE
    $result = ReadLogfileEntry -filename 'AppLog' -line 1
    if ($result.code -eq 0) { Write-Host $result.data }

    .EXAMPLE
    # Always returns the last entry because 9999 exceeds any realistic entry count
    $result = ReadLogfileEntry -filename 'AppLog' -line 9999
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$filename,

        [Parameter(Mandatory = $true)]
        [int]$line
    )

    try {
        # --- Parameter validation ---------------------------------------------------
        if ([string]::IsNullOrWhiteSpace($filename)) {
            return VPDLXreturn -Code -1 -Message "Parameter 'filename' is required and must not be null, empty, or whitespace-only."
        }

        # --- Logfile existence check ------------------------------------------------
        $normalizedKey = $filename.Trim().ToLower()

        if (-not $script:loginstances.ContainsKey($normalizedKey)) {
            return VPDLXreturn -Code -1 -Message "Virtual log file '$filename' does not exist. Use CreateNewLogfile to create it first."
        }

        # --- Entry count check -----------------------------------------------------
        $instance     = $script:loginstances[$normalizedKey]
        $totalEntries = $instance['info']['entries']

        if ($totalEntries -eq 0) {
            return VPDLXreturn -Code -1 -Message "Virtual log file '$filename' contains no entries."
        }

        # --- Clamp line number to valid range (1-based) ----------------------------
        if ($line -lt 1) {
            $line = 1
        }
        elseif ($line -gt $totalEntries) {
            $line = $totalEntries
        }

        # Convert to 0-based index
        $index = $line - 1
        $entry = $instance['data'][$index]

        return VPDLXreturn -Code 0 -Message "Entry at line $line read from '$filename' successfully." -Data $entry
    }
    catch {
        return VPDLXreturn -Code -1 -Message "Unexpected error in ReadLogfileEntry: $($_.Exception.Message)"
    }
}
