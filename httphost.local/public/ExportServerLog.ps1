function ExportServerLog {
    [CmdletBinding()]
    param(
        # This is the path, where the logfile will be exported to.
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ExportPath,
        # This is the path, where the logfile will be exported to.
        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateSet('txt','log')]
        [string]$FileFormat
    )
    
}