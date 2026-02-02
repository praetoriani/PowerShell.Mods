function CreateRegKey {
    <#
    .SYNOPSIS
    Creates a new registry key at the specified path.
    
    .DESCRIPTION
    The CreateRegKey function creates a new registry key at the specified location.
    It validates the path format, checks if the key already exists, and handles
    proper error reporting through a standardized return object. The function
    supports all standard registry hives (HKLM, HKCU, HKCR, HKU, HKCC).
    
    .PARAMETER Path
    The registry path where the new key should be created. Must be in PowerShell
    drive format (e.g., "HKLM:\SOFTWARE\MyCompany" or "HKCU:\Software\MyApp").
    Supports both short format (HKLM:, HKCU:) and long format (HKEY_LOCAL_MACHINE:).
    
    .PARAMETER Key
    The name of the new registry key to create. Must not contain invalid characters
    for registry keys (\ / : * ? " < > |).
    
    .EXAMPLE
    CreateRegKey -Path "HKLM:\SOFTWARE\MyCompany" -Key "MyApplication"
    Creates a new registry key "MyApplication" under HKLM:\SOFTWARE\MyCompany.
    
    .EXAMPLE
    CreateRegKey -Path "HKCU:\Software\MyApp" -Key "Settings"
    Creates a new registry key "Settings" under HKCU:\Software\MyApp.
    
    .EXAMPLE
    $result = CreateRegKey -Path "HKLM:\SOFTWARE\Test" -Key "NewKey"
    if ($result.code -eq 0) {
        Write-Host "Registry key created successfully at: $($result.data)"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to create registry keys in the specified hive
    - For HKLM operations, administrator privileges are typically required
    - The function will create parent paths if they don't exist
    - If the key already exists, the function will return an error
    - Returns the full registry path in the data field on success
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty"
    }
    
    if ([string]::IsNullOrWhiteSpace($Key)) {
        return OPSreturn -Code -1 -Message "Parameter 'Key' is required but was not provided or is empty"
    }
    
    try {
        # Validate registry path format
        $ValidHives = @('HKLM:', 'HKCU:', 'HKCR:', 'HKU:', 'HKCC:', 
                       'HKEY_LOCAL_MACHINE:', 'HKEY_CURRENT_USER:', 
                       'HKEY_CLASSES_ROOT:', 'HKEY_USERS:', 'HKEY_CURRENT_CONFIG:')
        
        $PathStartsWithValidHive = $false
        foreach ($hive in $ValidHives) {
            if ($Path.StartsWith($hive, [System.StringComparison]::OrdinalIgnoreCase)) {
                $PathStartsWithValidHive = $true
                break
            }
        }
        
        if (-not $PathStartsWithValidHive) {
            return OPSreturn -Code -1 -Message "Parameter 'Path' must start with a valid registry hive (HKLM:, HKCU:, HKCR:, HKU:, or HKCC:)"
        }
        
        # Normalize path - ensure it uses PowerShell drive format
        $NormalizedPath = $Path.Replace('HKEY_LOCAL_MACHINE:', 'HKLM:')
        $NormalizedPath = $NormalizedPath.Replace('HKEY_CURRENT_USER:', 'HKCU:')
        $NormalizedPath = $NormalizedPath.Replace('HKEY_CLASSES_ROOT:', 'HKCR:')
        $NormalizedPath = $NormalizedPath.Replace('HKEY_USERS:', 'HKU:')
        $NormalizedPath = $NormalizedPath.Replace('HKEY_CURRENT_CONFIG:', 'HKCC:')
        
        # Remove trailing backslash if present
        $NormalizedPath = $NormalizedPath.TrimEnd('\\')
        
        # Validate key name - check for invalid characters
        $InvalidChars = @('\\', '/', ':', '*', '?', '"', '<', '>', '|')
        foreach ($char in $InvalidChars) {
            if ($Key.Contains($char)) {
                return OPSreturn -Code -1 -Message "Parameter 'Key' contains invalid character '$char'. Registry key names cannot contain: \\ / : * ? `" < > |"
            }
        }
        
        # Construct full registry key path
        $FullKeyPath = Join-Path -Path $NormalizedPath -ChildPath $Key
        
        # Check if the parent path exists
        if (-not (Test-Path -Path $NormalizedPath)) {
            return OPSreturn -Code -1 -Message "Parent registry path '$NormalizedPath' does not exist. Please create the parent path first."
        }
        
        # Check if the key already exists
        if (Test-Path -Path $FullKeyPath) {
            return OPSreturn -Code -1 -Message "Registry key '$FullKeyPath' already exists"
        }
        
        # Attempt to create the registry key
        try {
            Write-Verbose "Creating registry key: $FullKeyPath"
            $NewKey = New-Item -Path $NormalizedPath -Name $Key -Force -ErrorAction Stop
            
            if ($null -eq $NewKey) {
                return OPSreturn -Code -1 -Message "Failed to create registry key '$FullKeyPath'. New-Item returned null."
            }
            
            # Verify the key was created
            if (-not (Test-Path -Path $FullKeyPath)) {
                return OPSreturn -Code -1 -Message "Registry key creation reported success, but verification failed for '$FullKeyPath'"
            }
            
            Write-Verbose "Successfully created registry key: $FullKeyPath"
        }
        catch [System.UnauthorizedAccessException] {
            return OPSreturn -Code -1 -Message "Access denied when creating registry key '$FullKeyPath'. Administrator privileges may be required for this operation."
        }
        catch [System.Security.SecurityException] {
            return OPSreturn -Code -1 -Message "Security exception when creating registry key '$FullKeyPath': $($_.Exception.Message)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to create registry key '$FullKeyPath': $($_.Exception.Message)"
        }
        
        # Success - return with full key path in data field
        return OPSreturn -Code 0 -Message "" -Data $FullKeyPath
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in CreateRegKey function: $($_.Exception.Message)"
    }
}
