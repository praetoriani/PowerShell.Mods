function OPSsuccess {
    <#
    .SYNOPSIS
        Shorthand for OPSreturn -Code success.
    .EXAMPLE
        return OPSsuccess "Config loaded" -Data $config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Data = $null
    )
    return OPSreturn -Code ([OPScode]::success) -Message $Message -Data $Data
}
