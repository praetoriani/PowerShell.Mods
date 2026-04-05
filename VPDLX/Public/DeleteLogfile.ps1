function DeleteLogfile {
    <#
    .SYNOPSIS
    Permanently removes a virtual log file instance and all its data.

    .DESCRIPTION
    DeleteLogfile removes the entire virtual log file instance identified by
    'filename' from $script:loginstances, including all stored log entries and
    metadata. The filename is also removed from $script:filestorage.

    After a successful deletion, the filename can be reused in a subsequent call
    to CreateNewLogfile.

    .PARAMETER filename
    The name of the existing virtual log file to delete (without file extension).

    .OUTPUTS
    PSCustomObject with the following properties:
      code  [int]    :  0 on success, -1 on failure
      msg   [string] :  human-readable status or error message
      data  [object] :  $null

    .EXAMPLE
    $result = DeleteLogfile -filename 'AppLog'
    if ($result.code -eq 0) { Write-Host "Log file deleted successfully." }

    .EXAMPLE
    $result = DeleteLogfile -filename 'NonExistingLog'
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
            return VPDLXreturn -Code -1 -Message "Virtual log file '$filename' does not exist. Nothing to delete."
        }

        # --- Remove from loginstances -----------------------------------------------
        $script:loginstances.Remove($normalizedKey)

        # --- Remove from filestorage ------------------------------------------------
        # Rebuild the filestorage array excluding the deleted filename (case-insensitive)
        $script:filestorage = @(
            $script:filestorage | Where-Object { $_.ToLower() -ne $normalizedKey }
        )

        return VPDLXreturn -Code 0 -Message "Virtual log file '$filename' has been deleted successfully."
    }
    catch {
        return VPDLXreturn -Code -1 -Message "Unexpected error in DeleteLogfile: $($_.Exception.Message)"
    }
}
