function GetInstallDir {
    <#
    .SYNOPSIS
    Retrieves the PSx Composer installation directory from Windows Registry.
    
    .DESCRIPTION
    The GetInstallDir function queries the Windows Registry to locate the PSx Composer
    installation directory. It checks the standard uninstall registry path and returns
    the installation location if found. This function is used by other module functions
    that need to access PSx Composer installation files.
    
    .EXAMPLE
    $result = GetInstallDir
    if ($result.code -eq 0) {
        Write-Host "PSx Composer is installed at: $($result.data)"
    }
    Retrieves the installation directory and displays it if found.
    
    .EXAMPLE
    $installPath = (GetInstallDir).data
    Uses the installation path directly from the returned data property.
    
    .NOTES
    This function is both a public function (exported) and used internally by other
    module functions. It requires read access to HKEY_LOCAL_MACHINE registry hive.
    
    Registry Path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PSx Composer
    Registry Value: InstallLocation
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        # Define registry path for PSx Composer installation
        $RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PSx Composer"
        $ValueName = "InstallLocation"
        
        # Check if registry path exists
        if (-not (Test-Path -Path $RegistryPath)) {
            return (OPSreturn -Code -1 -Message "PSx Composer installation not found in registry. Registry path does not exist: $RegistryPath")
        }
        
        # Try to read the InstallLocation value
        try {
            $InstallLocation = Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction Stop
            
            # Validate that the value is not null or empty
            if ([string]::IsNullOrWhiteSpace($InstallLocation.$ValueName)) {
                return (OPSreturn -Code -1 -Message "PSx Composer installation path is empty or invalid in registry")
            }
            
            # Get the actual path value
            $InstallPath = $InstallLocation.$ValueName
            
            # Verify that the installation directory actually exists on disk
            if (-not (Test-Path -Path $InstallPath -PathType Container)) {
                return (OPSreturn -Code -1 -Message "PSx Composer installation directory does not exist on disk: $InstallPath")
            }
            
            # Success - return installation path in data property
            return (OPSreturn -Code 0 -Message "PSx Composer installation found" -Data $InstallPath)
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to read InstallLocation value from registry: $($_.Exception.Message)")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in GetInstallDir function: $($_.Exception.Message)")
    }
}
