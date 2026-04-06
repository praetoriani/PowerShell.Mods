<#
.SYNOPSIS
    VPDLXreturn — Standardised return object factory for VPDLX.

.DESCRIPTION
    Every operation inside VPDLX that needs to communicate a result to the
    caller uses VPDLXreturn to build a consistent [PSCustomObject] with three
    well-known properties:

        code  [int]     —  0 on success, -1 on failure
        msg   [string]  —  human-readable status or error description
        data  [object]  —  optional payload (any type); $null when not applicable

    This contract is stable across all VPDLX versions so that callers can
    always inspect the 'code' property to branch on success/failure without
    parsing the 'msg' string.

    Although the current v1.01.00 release exposes only the class-based OOP
    surface (no exported public functions), VPDLXreturn is retained so that
    future public wrapper functions can provide a consistent return type
    without changing the caller contract.

    USAGE (internal, inside any VPDLX function or method):
        return VPDLXreturn -Code 0  -Message 'Operation completed.' -Data $result
        return VPDLXreturn -Code -1 -Message 'Something went wrong.'

.PARAMETER Code
    0 for success, -1 for failure. Validated via [ValidateSet].
    Default: -1

.PARAMETER Message
    A human-readable description of the outcome or the error that occurred.
    Default: empty string

.PARAMETER Data
    Optional data payload. Accepts any type: string, array, hashtable,
    PSCustomObject, class instance, etc. Default: $null

.OUTPUTS
    [PSCustomObject] with properties: code [int], msg [string], data [object]

.EXAMPLE
    # Success with payload
    return VPDLXreturn -Code 0 -Message 'Logfile created.' -Data $logInstance

.EXAMPLE
    # Failure with error message only
    return VPDLXreturn -Code -1 -Message "Logfile '$name' does not exist."

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.00
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 05.04.2026
    Updated : 06.04.2026
    Scope   : Private — used exclusively by VPDLX internals
#>

function VPDLXreturn {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Status code: 0 = success, -1 = failure.
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, -1)]
        [int] $Code = -1,

        # Human-readable outcome description.
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Message = '',

        # Optional data payload (any type).
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Data = $null
    )

    # Build and return the standardised result object.
    # [ordered] ensures predictable property order in Format-List / Format-Table.
    return [PSCustomObject] [ordered] @{
        code = $Code
        msg  = $Message
        data = $Data
    }
}
