function VPDLXreturn {
    <#
    .SYNOPSIS
    Creates a standardized return object for VPDLX operation status reporting.

    .DESCRIPTION
    VPDLXreturn creates a consistent PSCustomObject that is returned by every
    public VPDLX function. It provides a uniform interface for success/failure
    reporting with an optional data payload, following the same schema used by
    OPSreturn in WinISO.ScriptFXLib.

    .PARAMETER Code
    Status code indicating success (0) or failure (-1).
    Default is -1 (failure).

    .PARAMETER Message
    Detailed message describing the operation result or the error that occurred.
    Default is an empty string.

    .PARAMETER Data
    Optional data payload returned with the status object.
    Can contain any type: strings, arrays, hashtables, PSCustomObjects, etc.
    Default is $null.

    .EXAMPLE
    return VPDLXreturn -Code 0 -Message "Logfile created successfully."
    Returns a success object with no data payload.

    .EXAMPLE
    return VPDLXreturn -Code -1 -Message "Logfile 'MyLog' does not exist."
    Returns a failure object with an error message.

    .EXAMPLE
    $entry = $script:loginstances[$key]['data'][$index]
    return VPDLXreturn -Code 0 -Message "Entry read successfully." -Data $entry
    Returns a success object carrying the requested log entry.

    .NOTES
    This is an internal (Private) helper function used exclusively by all public
    VPDLX functions to ensure a consistent return value structure.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, -1)]
        [int]$Code = -1,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = '',

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Data = $null
    )

    return [PSCustomObject]@{
        code = $Code
        msg  = $Message
        data = $Data
    }
}
