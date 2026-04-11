<#
.SYNOPSIS
    VPDLXreturn — Standardised return object factory for VPDLX.

.DESCRIPTION
    Every operation inside VPDLX that needs to communicate a result to the
    caller uses VPDLXreturn to build a consistent [PSCustomObject] with three
    well-known properties:

        code  [int]     —  status code (see convention below)
        msg   [string]  —  human-readable status or error description
        data  [object]  —  optional payload (any type); $null when not applicable

    Status code convention:
         0       = Success
        -1       = General failure (default)
         1..99   = Reserved for partial-success / warning scenarios
        -2..-99  = Reserved for typed error categories

    This contract is stable across all VPDLX versions so that callers can
    always inspect the 'code' property to branch on success/failure without
    parsing the 'msg' string.

    USAGE (internal, inside any VPDLX function or method):
        return VPDLXreturn -Code 0  -Message 'Operation completed.' -Data $result
        return VPDLXreturn -Code -1 -Message 'Something went wrong.'

.PARAMETER Code
    Integer status code. Validated via [ValidateRange(-99, 99)].
    Convention: 0 = success, -1 = general failure (default).
    See .DESCRIPTION for the full code convention.
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
    Version : 1.02.03
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 05.04.2026
    Updated : 11.04.2026
    Scope   : Private — used exclusively by VPDLX internals

    CHANGES (11.04.2026):
      - Replaced [ValidateSet(0, -1)] with [ValidateRange(-99, 99)] on
        the $Code parameter. The hard-coded ValidateSet blocked any future
        status code beyond 0 and -1, making even minor extensions a
        breaking change. The new range allows typed error categories
        (-2..-99) and partial-success codes (1..99) while preserving
        backward compatibility for all existing callers.
        (Issue #8)
#>

function VPDLXreturn {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Status code.
        # Convention: 0 = success, -1 = general failure.
        # Range -99..99 allows typed error categories and partial-success codes.
        # FIX v1.02.03 (Issue #8): replaced [ValidateSet(0, -1)] with
        # [ValidateRange(-99, 99)] to enable future extensibility.
        [Parameter(Mandatory = $false)]
        [ValidateRange(-99, 99)]
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
