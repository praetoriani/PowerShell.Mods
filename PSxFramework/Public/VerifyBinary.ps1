function VerifyBinary {
    <#
    .SYNOPSIS
    Verifies the existence of an executable file at a specified path.
    
    .DESCRIPTION
    The VerifyBinary function checks whether a specified executable (*.exe) file exists
    at the given path. This is commonly used to verify that required tools like 7-Zip,
    Resource Hacker, or other dependencies are present before attempting to use them.
    
    .PARAMETER ExePath
    Full path to the executable file (*.exe) to verify.
    This parameter is mandatory.
    
    .EXAMPLE
    $result = VerifyBinary -ExePath "C:\Program Files\7-Zip\7z.exe"
    if ($result.code -eq 0) {
        Write-Host "7-Zip executable found and verified"
    }
    Verifies that 7-Zip executable exists at the specified location.
    
    .EXAMPLE
    $installDir = (GetInstallDir).data
    $rhPath = Join-Path -Path $installDir -ChildPath "include\ResourceHacker\ResourceHacker.exe"
    $result = VerifyBinary -ExePath $rhPath
    Combines GetInstallDir with VerifyBinary to check for Resource Hacker in the PSx installation.
    
    .NOTES
    This function is both a public function (exported) and used internally by other
    module functions to validate the presence of required binaries before operations.
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExePath
    )
    
    try {
        # Validate parameter
        if ([string]::IsNullOrWhiteSpace($ExePath)) {
            return (OPSreturn -Code -1 -Message "Parameter 'ExePath' is required but was not provided or is empty")
        }
        
        # Normalize path (resolve any relative paths or environment variables)
        try {
            $ResolvedPath = [System.IO.Path]::GetFullPath($ExePath)
        }
        catch {
            return (OPSreturn -Code -1 -Message "Invalid path format: $ExePath - $($_.Exception.Message)")
        }
        
        # Verify that the path has .exe extension
        $Extension = [System.IO.Path]::GetExtension($ResolvedPath)
        if ($Extension -ne ".exe") {
            return (OPSreturn -Code -1 -Message "Specified path does not point to an executable file (.exe): $ResolvedPath")
        }
        
        # Check if the file exists
        if (-not (Test-Path -Path $ResolvedPath -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Executable file not found at specified path: $ResolvedPath")
        }
        
        # Additional verification: Check if it's actually a file (not a directory)
        $Item = Get-Item -Path $ResolvedPath -ErrorAction Stop
        if ($Item.PSIsContainer) {
            return (OPSreturn -Code -1 -Message "Specified path points to a directory, not a file: $ResolvedPath")
        }
        
        # Success - executable exists and is valid
        return (OPSreturn -Code 0 -Message "Executable verified successfully" -Data $ResolvedPath)
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in VerifyBinary function: $($_.Exception.Message)")
    }
}
