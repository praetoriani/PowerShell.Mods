function ResetLogfile {
    <#
    .SYNOPSIS
    Resets the content of an existing virtual log file to its initial empty state.

    .DESCRIPTION
    ResetLogfile clears all log entries from the specified virtual log file and
    resets all info metadata (entries count, updated timestamp) as if the file had
    just been freshly created. The original creation timestamp and the filename
    are preserved. The file registration in $script:filestorage is not affected.

    After a successful reset, the log file is ready to receive new entries via
    WriteLogfileEntry without having to call CreateNewLogfile again.

    .PARAMETER filename
    The name of the existing virtual log file to reset (without file extension).

    .OUTPUTS
    PSCustomObject with the following properties:
      code  [int]    :  0 on success, -1 on failure
      msg   [string] :  human-readable status or error message
      data  [object] :  $null

    .EXAMPLE
    $result = ResetLogfile -filename 'AppLog'
    if ($result.code -eq 0) { Write-Host "Log file reset successfully." }

    .EXAMPLE
    $result = ResetLogfile -filename 'NonExistingLog'
    if ($result.code -ne 0) { Write-Warning $result.msg }
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$filename
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

        # --- Reset instance content -------------------------------------------------
        $resetTimestamp = Get-Date -Format '[dd.MM.yyyy | HH:mm:ss]'

        # Clear the data array
        $script:loginstances[$normalizedKey]['data']            = @()
        # Reset entry count
        $script:loginstances[$normalizedKey]['info']['entries'] = 0
        # Update 'updated' timestamp to reflect the reset event
        $script:loginstances[$normalizedKey]['info']['updated'] = $resetTimestamp

        return VPDLXreturn -Code 0 -Message "Virtual log file '$filename' has been reset successfully."
    }
    catch {
        return VPDLXreturn -Code -1 -Message "Unexpected error in ResetLogfile: $($_.Exception.Message)"
    }
}
