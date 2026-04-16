function ReadJSON {
    <#
    .SYNOPSIS
    Reads a JSON file from the specified location and returns a standardized status object with the deserialized content.
    
    .DESCRIPTION
    This function attempts to read a JSON file from the given location, deserializes its content,
    and returns a consistent status object indicating success or failure. The return object includes
    a code (0 for success, -1 for failure), a message describing the result, and the data if successful.
    
    .PARAMETER Location
    The file path to the JSON file that should be read and deserialized.
    This parameter is mandatory and must not be null or empty.
    
    .EXAMPLE
    ReadJSON -Location "C:\config\settings.json"
    
    .NOTES
    This is an internal helper function used by all public module functions to ensure
    consistent return value structure throughout the module.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Location
    )

    if (Test-Path $Location) {
        try {
            $JSONdata = Get-Content $Location -Raw | ConvertFrom-Json -ErrorAction Stop
            return(OPSreturn -Code 0 -Message "File '$Location' successfully loaded" -Data $JSONdata)
        }
        catch {
            return(OPSreturn -Code -1 -Message "Failed to load JSON: $($_.Exception.Message)")
        }
    }
    else {
        return(OPSreturn -Code -1 -Message "Configuration file not found: $Location")
        exit 1
    }
}