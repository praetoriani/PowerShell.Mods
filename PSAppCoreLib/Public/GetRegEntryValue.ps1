function GetRegEntryValue {
    <#
    .SYNOPSIS
    Retrieves the value of a registry entry.
    
    .DESCRIPTION
    The GetRegEntryValue function reads and returns the value of a specific registry
    entry. It validates the path format, checks if the value exists, handles different
    registry value types appropriately, and returns the value through a standardized
    return object. Supports all registry value types including Binary, MultiString, etc.
    
    .PARAMETER Path
    The registry path containing the value to read. Must be in PowerShell
    drive format (e.g., "HKLM:\SOFTWARE\MyCompany\MyApp" or "HKCU:\Software\MyApp").
    
    .PARAMETER Name
    The name of the registry value to read. Use "(Default)" or empty string to
    read the default value of a registry key.
    
    .PARAMETER ExpandEnvironmentVariables
    Optional switch parameter. When specified and the value type is ExpandString (REG_EXPAND_SZ),
    environment variables in the string will be expanded. Default is $false (returns raw string).
    
    .EXAMPLE
    GetRegEntryValue -Path "HKCU:\Software\MyApp" -Name "Version"
    Reads the value of the "Version" registry entry.
    
    .EXAMPLE
    GetRegEntryValue -Path "HKLM:\SOFTWARE\MyApp" -Name "InstallPath" -ExpandEnvironmentVariables
    Reads an ExpandString value and expands environment variables like %ProgramFiles%.
    
    .EXAMPLE
    GetRegEntryValue -Path "HKCU:\Software\MyApp" -Name "(Default)"
    Reads the default value of the registry key.
    
    .EXAMPLE
    $result = GetRegEntryValue -Path "HKCU:\Software\TestApp" -Name "Timeout"
    if ($result.code -eq 0) {
        Write-Host "Value: $($result.data.Value)"
        Write-Host "Type: $($result.data.ValueType)"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires read permissions for the specified registry path
    - Returns the raw value without expansion by default
    - For Binary values, returns a byte array
    - For MultiString values, returns a string array
    - The data.ValueType property contains the registry value type name
    - The data.Value property contains the actual registry value
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [switch]$ExpandEnvironmentVariables
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty"
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
        
        # Check if the registry key exists
        if (-not (Test-Path -Path $NormalizedPath)) {
            return OPSreturn -Code -1 -Message "Registry key '$NormalizedPath' does not exist"
        }
        
        # Handle default value case
        $ValueName = if ([string]::IsNullOrEmpty($Name) -or $Name -eq "(Default)") { 
            "" 
        } else { 
            $Name 
        }
        
        # Get the registry key object for direct access
        $RegistryKey = $null
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
                    return OPSreturn -Code -1 -Message "Unsupported registry hive: $HiveName"
                }
            }
            
            # Open the registry key
            $RegistryKey = [Microsoft.Win32.Registry]::$($HiveName.ToUpper()).OpenSubKey($SubKeyPath, $false)
            
            if ($null -eq $RegistryKey) {
                return OPSreturn -Code -1 -Message "Failed to open registry key '$NormalizedPath'"
            }
            
            # Check if the value exists
            $ValueNames = $RegistryKey.GetValueNames()
            $ValueExists = $ValueName -in $ValueNames -or ($ValueName -eq "" -and "" -in $ValueNames)
            
            if (-not $ValueExists) {
                $DisplayName = if ($ValueName -eq "") { "(Default)" } else { $ValueName }
                $RegistryKey.Close()
                return OPSreturn -Code -1 -Message "Registry value '$DisplayName' does not exist at path '$NormalizedPath'"
            }
            
            # Get the value type
            $ValueKind = $RegistryKey.GetValueKind($ValueName)
            
            # Read the value based on its type
            $ReadValue = $null
            if ($ValueKind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString -and $ExpandEnvironmentVariables) {
                # Get expanded value
                $ReadValue = $RegistryKey.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::None)
            }
            else {
                # Get raw value without expansion
                $ReadValue = $RegistryKey.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            }
            
            # Close the registry key
            $RegistryKey.Close()
            $RegistryKey = $null
            
            Write-Verbose "Successfully read registry value '$ValueName' from: $NormalizedPath (Type: $($ValueKind.ToString()))"
            
            # Prepare return data object with value and type information
            $ReturnData = [PSCustomObject]@{
                Value     = $ReadValue
                ValueType = $ValueKind.ToString()
            }
        }
        catch [System.UnauthorizedAccessException] {
            if ($RegistryKey) { $RegistryKey.Close() }
            return OPSreturn -Code -1 -Message "Access denied when reading registry value '$ValueName' at path '$NormalizedPath'"
        }
        catch [System.Security.SecurityException] {
            if ($RegistryKey) { $RegistryKey.Close() }
            return OPSreturn -Code -1 -Message "Security exception when reading registry value '$ValueName' at path '$NormalizedPath': $($_.Exception.Message)"
        }
        catch {
            if ($RegistryKey) { $RegistryKey.Close() }
            return OPSreturn -Code -1 -Message "Failed to read registry value '$ValueName' at path '$NormalizedPath': $($_.Exception.Message)"
        }
        
        # Success - return with value and type in data field
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in GetRegEntryValue function: $($_.Exception.Message)"
    }
}
