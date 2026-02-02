function OPSreturn {
    <#
    .SYNOPSIS
    Creates a standardized return object for operation status reporting.
    
    .DESCRIPTION
    The OPSreturn function creates a consistent PSCustomObject for returning operation
    status information across all module functions. It provides a uniform interface for
    success/failure reporting with optional data payload.
    
    .PARAMETER Code
    Status code indicating success (0) or failure (-1).
    Default is -1 (failure).
    
    .PARAMETER Message
    Detailed message describing the operation result or error.
    Default is empty string.
    
    .PARAMETER Data
    Optional data payload to return with the status object.
    Can contain any type of data (strings, arrays, objects, binary data, etc.).
    Default is $null.
    
    .EXAMPLE
    OPSreturn -Code 0 -Message "Operation completed successfully"
    Returns a success status object without data payload.
    
    .EXAMPLE
    OPSreturn -Code -1 -Message "File not found: C:\test.txt"
    Returns a failure status object with error message.
    
    .EXAMPLE
    $fileContent = Get-Content -Path "C:\data.bin" -Raw -Encoding Byte
    OPSreturn -Code 0 -Message "File loaded successfully" -Data $fileContent
    Returns a success status object with binary file data.
    
    .NOTES
    This is an internal helper function used by all public module functions to ensure
    consistent return value structure throughout the PSAppCoreLib module.
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, -1)]
        [int]$Code = -1,
        
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",
        
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Data = $null
    )
    
    # Create and return standardized status object
    return [PSCustomObject]@{
        code = $Code
        msg  = $Message
        data = $Data
    }
}
