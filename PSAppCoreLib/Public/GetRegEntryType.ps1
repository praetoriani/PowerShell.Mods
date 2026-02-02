function GetRegEntryType {
    <#
    .SYNOPSIS
    Determines the type of a registry entry.
    
    .DESCRIPTION
    The GetRegEntryType function retrieves the registry value type (REG_SZ, REG_DWORD, etc.)
    of a specific registry entry. It validates the path format, checks if the value exists,
    and returns the type information through a standardized return object.
    
    .PARAMETER Path
    The registry path containing the value to inspect. Must be in PowerShell
    drive format (e.g., "HKLM:\SOFTWARE\MyCompany\MyApp" or "HKCU:\Software\MyApp").
    
    .PARAMETER Name
    The name of the registry value to inspect. Use "(Default)" or empty string to
    check the default value of a registry key.
    
    .EXAMPLE
    GetRegEntryType -Path "HKCU:\Software\MyApp" -Name "Version"
    Returns the type of the "Version" registry entry (e.g., "String").
    
    .EXAMPLE
    GetRegEntryType -Path "HKLM:\SOFTWARE\MyApp" -Name "Timeout"
    Returns the type of the "Timeout" registry entry (e.g., "DWord").
    
    .EXAMPLE
    $result = GetRegEntryType -Path "HKCU:\Software\TestApp" -Name "Settings"
    if ($result.code -eq 0) {
        Write-Host "Value Type: $($result.valueType)"
        Write-Host "Type Name: $($result.typeName)"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires read permissions for the specified registry path
    - Returns both the .NET RegistryValueKind enum and a friendly type name
    - Possible type values: String, ExpandString, Binary, DWord, QWord, MultiString, Unknown
    - The valueType property contains the numeric enum value
    - The typeName property contains the friendly string name
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        valueType = $null
        typeName = $null
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $status.msg = "Parameter 'Path' is required but was not provided or is empty"
        return $status
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
            $status.msg = "Parameter 'Path' must start with a valid registry hive (HKLM:, HKCU:, HKCR:, HKU:, or HKCC:)"
            return $status
        }
        
        # Normalize path - ensure it uses PowerShell drive format
        $NormalizedPath = $Path.Replace('HKEY_LOCAL_MACHINE:', 'HKLM:')
        $NormalizedPath = $NormalizedPath.Replace('HKEY_CURRENT_USER:', 'HKCU:')
        $NormalizedPath = $NormalizedPath.Replace('HKEY_CLASSES_ROOT:', 'HKCR:')
        $NormalizedPath = $NormalizedPath.Replace('HKEY_USERS:', 'HKU:')
        $NormalizedPath = $NormalizedPath.Replace('HKEY_CURRENT_CONFIG:', 'HKCC:')
        
        # Remove trailing backslash if present
        $NormalizedPath = $NormalizedPath.TrimEnd('\')
        
        # Check if the registry key exists
        if (-not (Test-Path -Path $NormalizedPath)) {
            $status.msg = "Registry key '$NormalizedPath' does not exist"
            return $status
        }
        
        # Handle default value case
        $ValueName = if ([string]::IsNullOrEmpty($Name) -or $Name -eq "(Default)") { 
            "" 
        } else { 
            $Name 
        }
        
        # Get the registry key object for direct access
        try {
            # Convert PowerShell path to .NET registry path
            $HiveName = $NormalizedPath.Split(':')[0]
            $SubKeyPath = $NormalizedPath.Substring($NormalizedPath.IndexOf(':') + 2)
            
            # Map PowerShell hive names to .NET RegistryHive enum
            $RegistryHive = switch ($HiveName.ToUpper()) {
                'HKLM' { [Microsoft.Win32.RegistryHive]::LocalMachine }
                'HKCU' { [Microsoft.Win32.RegistryHive]::CurrentUser }
                'HKCR' { [Microsoft.Win32.RegistryHive]::ClassesRoot }
                'HKU'  { [Microsoft.Win32.RegistryHive]::Users }
                'HKCC' { [Microsoft.Win32.RegistryHive]::CurrentConfig }
                default { 
                    $status.msg = "Unsupported registry hive: $HiveName"
                    return $status
                }
            }
            
            # Open the registry key
            $RegistryKey = [Microsoft.Win32.Registry]::$($HiveName.ToUpper()).OpenSubKey($SubKeyPath, $false)
            
            if ($null -eq $RegistryKey) {
                $status.msg = "Failed to open registry key '$NormalizedPath'"
                return $status
            }
            
            # Check if the value exists
            $ValueNames = $RegistryKey.GetValueNames()
            $ValueExists = $ValueName -in $ValueNames -or ($ValueName -eq "" -and "" -in $ValueNames)
            
            if (-not $ValueExists) {
                $DisplayName = if ($ValueName -eq "") { "(Default)" } else { $ValueName }
                $status.msg = "Registry value '$DisplayName' does not exist at path '$NormalizedPath'"
                $RegistryKey.Close()
                return $status
            }
            
            # Get the value type
            $ValueKind = $RegistryKey.GetValueKind($ValueName)
            
            # Set return values
            $status.valueType = [int]$ValueKind
            $status.typeName = $ValueKind.ToString()
            
            # Close the registry key
            $RegistryKey.Close()
            
            Write-Verbose "Successfully determined type of registry value '$ValueName' at: $NormalizedPath (Type: $($status.typeName))"
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied when reading registry value '$ValueName' at path '$NormalizedPath'"
            if ($RegistryKey) { $RegistryKey.Close() }
            return $status
        }
        catch [System.Security.SecurityException] {
            $status.msg = "Security exception when reading registry value '$ValueName' at path '$NormalizedPath': $($_.Exception.Message)"
            if ($RegistryKey) { $RegistryKey.Close() }
            return $status
        }
        catch {
            $status.msg = "Failed to determine type of registry value '$ValueName' at path '$NormalizedPath': $($_.Exception.Message)"
            if ($RegistryKey) { $RegistryKey.Close() }
            return $status
        }
        
        # Success - reset status object
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in GetRegEntryType function: $($_.Exception.Message)"
        return $status
    }
}
