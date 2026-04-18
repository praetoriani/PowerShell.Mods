function OPScritical {
    <#
    .SYNOPSIS
        Shorthand for OPSreturn -Code critical.
    .EXAMPLE
        return OPScritical "Critical Error: Cannot access windo object!" -Exception $_.Exception
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # PARAM: Message → A short Message you want to pass to the caller
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",

        # PARAM: Data → Can be used to pass data to the caller
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Data = $null,

        # PARAM: Exception → Use it to pass a more detailed message to the caller
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Exception = $null
    )
    return OPSreturn -Code ([OPScode]::critical) -Message $Message -Exception $Exception -Data $Data
}
