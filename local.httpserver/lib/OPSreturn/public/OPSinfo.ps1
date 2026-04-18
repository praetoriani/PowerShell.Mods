function OPSinfo {
    <#
    .SYNOPSIS
        Shorthand for OPSreturn -Code info.
    .EXAMPLE
        return OPSinfo "This is an information message"
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
        $Data = $null
    )
    return OPSreturn -Code ([OPScode]::info) -Message $Message -Data $Data
}
