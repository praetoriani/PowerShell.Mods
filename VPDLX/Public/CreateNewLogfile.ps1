function CreateNewLogfile {
    <#
    .SYNOPSIS
    Creates a new named virtual log file instance.

    .DESCRIPTION
    CreateNewLogfile initializes a new virtual log file instance inside the VPDLX
    module's in-memory storage. The provided filename is validated against the
    following rules before the instance is created:

      - Only alphanumeric characters and the special characters  _  -  .  are allowed.
      - The name must be between 3 and 64 characters in length (after trimming).
      - A virtual log file with that name must not already exist.

    On success, the new filename is automatically registered in $script:filestorage
    so that the caller can always retrieve a current list of active log files via
    VPDLXcore -KeyID 'filestorage'.

    .PARAMETER filename
    The name of the virtual log file to create (without file extension).
    Must be 3-64 characters, alphanumeric plus _ - . only.

    .OUTPUTS
    PSCustomObject with the following properties:
      code  [int]    :  0 on success, -1 on failure
      msg   [string] :  human-readable status or error message
      data  [object] :  $null on failure; on success the newly created logfile
                        instance (hashtable with keys: name, data, info)

    .EXAMPLE
    $result = CreateNewLogfile -filename 'ApplicationLog'
    if ($result.code -eq 0) { Write-Host "Created: $($result.data.name)" }

    .EXAMPLE
    $result = CreateNewLogfile -filename 'Setup_Log-2026.04.05'
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

        $filename = $filename.Trim()

        if ($filename.Length -lt 3 -or $filename.Length -gt 64) {
            return VPDLXreturn -Code -1 -Message "Parameter 'filename' must be between 3 and 64 characters in length. Provided length: $($filename.Length)."
        }

        if ($filename -notmatch '^[a-zA-Z0-9_\-\.]+$') {
            return VPDLXreturn -Code -1 -Message "Parameter 'filename' contains invalid characters. Only alphanumeric characters and the special characters _ - . are allowed."
        }

        # --- Duplicate check --------------------------------------------------------
        $normalizedKey = $filename.ToLower()

        if ($script:loginstances.ContainsKey($normalizedKey)) {
            return VPDLXreturn -Code -1 -Message "A virtual log file with the name '$filename' already exists. Use a different name or delete the existing instance first."
        }

        # --- Create instance --------------------------------------------------------
        $timestamp = Get-Date -Format '[dd.MM.yyyy | HH:mm:ss]'

        $newInstance = @{
            name = $filename
            data = @()
            info = @{
                created = $timestamp
                updated = $timestamp
                entries = 0
            }
        }

        $script:loginstances[$normalizedKey] = $newInstance

        # --- Register in filestorage ------------------------------------------------
        $script:filestorage += $filename

        return VPDLXreturn -Code 0 -Message "Virtual log file '$filename' created successfully." -Data $newInstance
    }
    catch {
        return VPDLXreturn -Code -1 -Message "Unexpected error in CreateNewLogfile: $($_.Exception.Message)"
    }
}
