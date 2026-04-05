function WriteLogfileEntry {
    <#
    .SYNOPSIS
    Writes a new formatted entry into an existing virtual log file.

    .DESCRIPTION
    WriteLogfileEntry appends a new log entry to the specified virtual log file.
    Before writing, the function performs the following checks:

      - The virtual log file identified by 'filename' must exist in $script:filestorage.
      - The 'loglevel' parameter must match one of the keys defined in $script:loglevel.
      - The 'message' parameter must contain at least 3 non-whitespace characters.

    Each entry is formatted as a single line:
      [dd.MM.yyyy | HH:mm:ss]<loglevel prefix>MESSAGE

    After a successful write, $script:loginstances[key]['info']['updated'] is set to
    the current timestamp and $script:loginstances[key]['info']['entries'] is incremented.

    .PARAMETER filename
    The name of the existing virtual log file to write to (without file extension).

    .PARAMETER loglevel
    The severity level of the entry. Must be one of:
    info | debug | warning | error | critical
    Comparison is case-insensitive.

    .PARAMETER message
    The content of the log entry. Must be at least 3 non-whitespace characters.

    .OUTPUTS
    PSCustomObject with the following properties:
      code  [int]    :  0 on success, -1 on failure
      msg   [string] :  human-readable status or error message
      data  [object] :  $null on failure; on success the formatted log line that was written

    .EXAMPLE
    $result = WriteLogfileEntry -filename 'AppLog' -loglevel 'info' -message 'Application started.'
    if ($result.code -eq 0) { Write-Host "Written: $($result.data)" }

    .EXAMPLE
    $result = WriteLogfileEntry -filename 'AppLog' -loglevel 'ERROR' -message 'Connection refused by remote host.'
    if ($result.code -ne 0) { Write-Warning $result.msg }
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$filename,

        [Parameter(Mandatory = $true)]
        [string]$loglevel,

        [Parameter(Mandatory = $true)]
        [string]$message
    )

    try {
        # --- Parameter validation ---------------------------------------------------
        if ([string]::IsNullOrWhiteSpace($filename)) {
            return VPDLXreturn -Code -1 -Message "Parameter 'filename' is required and must not be null, empty, or whitespace-only."
        }

        if ([string]::IsNullOrWhiteSpace($loglevel)) {
            return VPDLXreturn -Code -1 -Message "Parameter 'loglevel' is required and must not be null, empty, or whitespace-only."
        }

        if ([string]::IsNullOrWhiteSpace($message)) {
            return VPDLXreturn -Code -1 -Message "Parameter 'message' is required and must not be null, empty, or whitespace-only."
        }

        # Message must contain at least 3 non-whitespace characters
        $strippedMessage = $message -replace '\s', ''
        if ($strippedMessage.Length -lt 3) {
            return VPDLXreturn -Code -1 -Message "Parameter 'message' must contain at least 3 non-whitespace characters."
        }

        # --- Logfile existence check ------------------------------------------------
        $normalizedKey = $filename.Trim().ToLower()

        if (-not $script:loginstances.ContainsKey($normalizedKey)) {
            return VPDLXreturn -Code -1 -Message "Virtual log file '$filename' does not exist. Use CreateNewLogfile to create it first."
        }

        # --- Log level validation ---------------------------------------------------
        $normalizedLevel = $loglevel.Trim().ToLower()

        if (-not $script:loglevel.ContainsKey($normalizedLevel)) {
            $validLevels = ($script:loglevel.Keys | Where-Object { $_ -ne 'default' }) -join ', '
            return VPDLXreturn -Code -1 -Message "Unknown log level '$loglevel'. Valid levels are: $validLevels."
        }

        # --- Build log entry -------------------------------------------------------
        $timestamp  = Get-Date -Format '[dd.MM.yyyy | HH:mm:ss]'
        $prefix     = $script:loglevel[$normalizedLevel]
        $logEntry   = "$timestamp$prefix$message"

        # --- Append to instance ----------------------------------------------------
        $script:loginstances[$normalizedKey]['data'] += $logEntry
        $script:loginstances[$normalizedKey]['info']['updated'] = $timestamp
        $script:loginstances[$normalizedKey]['info']['entries']  = $script:loginstances[$normalizedKey]['data'].Count

        return VPDLXreturn -Code 0 -Message "Entry written to '$filename' successfully." -Data $logEntry
    }
    catch {
        return VPDLXreturn -Code -1 -Message "Unexpected error in WriteLogfileEntry: $($_.Exception.Message)"
    }
}
