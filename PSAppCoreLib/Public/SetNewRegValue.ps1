function SetNewRegValue {
    <#
    .SYNOPSIS
    Sets a new value for an existing registry entry.
    
    .DESCRIPTION
    The SetNewRegValue function updates the value of an existing registry entry.
    It validates the path format, checks if the value exists, validates the new value
    against the existing type, and handles proper error reporting through a standardized
    return object. The registry value type cannot be changed, only the value itself.
    
    .PARAMETER Path
    The registry path containing the value to update. Must be in PowerShell
    drive format (e.g., "HKLM:\SOFTWARE\MyCompany\MyApp" or "HKCU:\Software\MyApp").
    
    .PARAMETER Name
    The name of the registry value to update. Use "(Default)" or empty string to
    update the default value of a registry key.
    
    .PARAMETER Value
    The new value to set. The type of data should be compatible with the existing
    registry value type:
    - For String/ExpandString: Use string values
    - For Binary: Use byte array (e.g., [byte[]](0x01, 0x02, 0x03))
    - For DWord/QWord: Use integer values
    - For MultiString: Use string array (e.g., @("Line1", "Line2"))
    
    .PARAMETER Force
    Optional switch parameter. When specified, suppresses confirmation prompts for
    system-critical paths. Default is $false.
    
    .EXAMPLE
    SetNewRegValue -Path "HKCU:\Software\MyApp" -Name "Version" -Value "2.0.0"
    Updates the "Version" string value to "2.0.0".
    
    .EXAMPLE
    SetNewRegValue -Path "HKLM:\SOFTWARE\MyApp\Settings" -Name "Timeout" -Value 60
    Updates the "Timeout" DWord value to 60.
    
    .EXAMPLE
    SetNewRegValue -Path "HKCU:\Software\MyApp" -Name "Servers" -Value @("Server1", "Server2", "Server3")
    Updates the MultiString value with a new array of server names.
    
    .EXAMPLE
    $binaryData = [byte[]](0x01, 0x02, 0x03, 0x04)
    SetNewRegValue -Path "HKLM:\SOFTWARE\MyApp" -Name "BinaryData" -Value $binaryData
    Updates the Binary value with new byte array data.
    
    .EXAMPLE
    $result = SetNewRegValue -Path "HKCU:\Software\TestApp" -Name "TestValue" -Value "NewValue"
    if ($result.code -eq 0) {
        Write-Host "Registry value updated successfully"
        Write-Host "Old value: $($result.oldValue)"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to modify registry values in the specified hive
    - For HKLM operations, administrator privileges are typically required
    - The registry value must exist before it can be updated
    - The value type cannot be changed, only the value itself
    - Returns the old value in the return object for reference
    - Consider backing up the old value before making changes to critical settings
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        oldValue = $null
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
        
        $DisplayName = if ($ValueName -eq "") { "(Default)" } else { $ValueName }
        
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
                    $status.msg = "Unsupported registry hive: $HiveName"
                    return $status
                }
            }
            
            # Open the registry key for reading to check existence and get old value
            $RegistryKey = [Microsoft.Win32.Registry]::$($HiveName.ToUpper()).OpenSubKey($SubKeyPath, $false)
            
            if ($null -eq $RegistryKey) {
                $status.msg = "Failed to open registry key '$NormalizedPath'"
                return $status
            }
            
            # Check if the value exists
            $ValueNames = $RegistryKey.GetValueNames()
            $ValueExists = $ValueName -in $ValueNames -or ($ValueName -eq "" -and "" -in $ValueNames)
            
            if (-not $ValueExists) {
                $status.msg = "Registry value '$DisplayName' does not exist at path '$NormalizedPath'. Use CreateRegVal to create new values."
                $RegistryKey.Close()
                return $status
            }
            
            # Get the value type and old value
            $ValueKind = $RegistryKey.GetValueKind($ValueName)
            $status.oldValue = $RegistryKey.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            
            # Close the read-only key
            $RegistryKey.Close()
            $RegistryKey = $null
            
            # Validate and convert new value based on existing type
            $ValidatedValue = $null
            
            switch ($ValueKind) {
                ([Microsoft.Win32.RegistryValueKind]::String) {
                    if ($null -eq $Value) {
                        $ValidatedValue = ""
                    }
                    else {
                        $ValidatedValue = [string]$Value
                    }
                }
                ([Microsoft.Win32.RegistryValueKind]::ExpandString) {
                    if ($null -eq $Value) {
                        $ValidatedValue = ""
                    }
                    else {
                        $ValidatedValue = [string]$Value
                    }
                }
                ([Microsoft.Win32.RegistryValueKind]::Binary) {
                    if ($null -eq $Value) {
                        $ValidatedValue = [byte[]]@()
                    }
                    elseif ($Value -is [byte[]]) {
                        $ValidatedValue = $Value
                    }
                    else {
                        try {
                            $ValidatedValue = [byte[]]$Value
                        }
                        catch {
                            $status.msg = "Parameter 'Value' for type 'Binary' must be a byte array. Conversion failed: $($_.Exception.Message)"
                            return $status
                        }
                    }
                }
                ([Microsoft.Win32.RegistryValueKind]::DWord) {
                    if ($null -eq $Value) {
                        $ValidatedValue = 0
                    }
                    else {
                        try {
                            $ValidatedValue = [int]$Value
                            if ($ValidatedValue -lt 0 -or $ValidatedValue -gt [UInt32]::MaxValue) {
                                $status.msg = "Parameter 'Value' for type 'DWord' must be between 0 and $([UInt32]::MaxValue)"
                                return $status
                            }
                        }
                        catch {
                            $status.msg = "Parameter 'Value' for type 'DWord' must be a valid 32-bit integer: $($_.Exception.Message)"
                            return $status
                        }
                    }
                }
                ([Microsoft.Win32.RegistryValueKind]::QWord) {
                    if ($null -eq $Value) {
                        $ValidatedValue = 0
                    }
                    else {
                        try {
                            $ValidatedValue = [long]$Value
                            if ($ValidatedValue -lt 0 -or $ValidatedValue -gt [UInt64]::MaxValue) {
                                $status.msg = "Parameter 'Value' for type 'QWord' must be between 0 and $([UInt64]::MaxValue)"
                                return $status
                            }
                        }
                        catch {
                            $status.msg = "Parameter 'Value' for type 'QWord' must be a valid 64-bit integer: $($_.Exception.Message)"
                            return $status
                        }
                    }
                }
                ([Microsoft.Win32.RegistryValueKind]::MultiString) {
                    if ($null -eq $Value) {
                        $ValidatedValue = @()
                    }
                    elseif ($Value -is [array]) {
                        $ValidatedValue = $Value | ForEach-Object { [string]$_ }
                    }
                    elseif ($Value -is [string]) {
                        $ValidatedValue = @([string]$Value)
                    }
                    else {
                        try {
                            $ValidatedValue = @([string]$Value)
                        }
                        catch {
                            $status.msg = "Parameter 'Value' for type 'MultiString' must be a string array: $($_.Exception.Message)"
                            return $status
                        }
                    }
                }
                default {
                    $status.msg = "Unsupported registry value type '$ValueKind' for value '$DisplayName'"
                    return $status
                }
            }
            
            # Prepare confirmation message
            $ConfirmMessage = "Update registry value '$DisplayName' at '$NormalizedPath' (Type: $($ValueKind.ToString()))"
            
            # Attempt to update the registry value
            Write-Verbose "Updating registry value '$DisplayName' at path '$NormalizedPath' (Type: $($ValueKind.ToString()))"
            
            if ($Force) {
                # Force update without confirmation
                Set-ItemProperty -Path $NormalizedPath -Name $Name -Value $ValidatedValue -Force -ErrorAction Stop
            }
            else {
                # With confirmation (ShouldProcess)
                if ($PSCmdlet.ShouldProcess("$NormalizedPath\$DisplayName", $ConfirmMessage)) {
                    Set-ItemProperty -Path $NormalizedPath -Name $Name -Value $ValidatedValue -ErrorAction Stop
                }
                else {
                    $status.msg = "Operation cancelled by user"
                    return $status
                }
            }
            
            # Verify the value was updated
            try {
                $RegistryKey = [Microsoft.Win32.Registry]::$($HiveName.ToUpper()).OpenSubKey($SubKeyPath, $false)
                $NewValue = $RegistryKey.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $RegistryKey.Close()
                $RegistryKey = $null
                
                # For complex types like arrays, we need a more sophisticated comparison
                $ValuesMatch = $false
                if ($ValueKind -eq [Microsoft.Win32.RegistryValueKind]::MultiString) {
                    $ValuesMatch = (Compare-Object $ValidatedValue $NewValue) -eq $null
                }
                elseif ($ValueKind -eq [Microsoft.Win32.RegistryValueKind]::Binary) {
                    $ValuesMatch = (Compare-Object $ValidatedValue $NewValue) -eq $null
                }
                else {
                    $ValuesMatch = $ValidatedValue -eq $NewValue
                }
                
                if (-not $ValuesMatch) {
                    $status.msg = "Registry value update reported success, but verification failed for '$DisplayName' at path '$NormalizedPath'"
                    return $status
                }
            }
            catch {
                $status.msg = "Registry value update reported success, but verification failed: $($_.Exception.Message)"
                return $status
            }
            
            Write-Verbose "Successfully updated registry value '$DisplayName' at path '$NormalizedPath'"
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied when updating registry value '$DisplayName' at path '$NormalizedPath'. Administrator privileges may be required for this operation."
            if ($RegistryKey) { $RegistryKey.Close() }
            return $status
        }
        catch [System.Security.SecurityException] {
            $status.msg = "Security exception when updating registry value '$DisplayName' at path '$NormalizedPath': $($_.Exception.Message)"
            if ($RegistryKey) { $RegistryKey.Close() }
            return $status
        }
        catch {
            $status.msg = "Failed to update registry value '$DisplayName' at path '$NormalizedPath': $($_.Exception.Message)"
            if ($RegistryKey) { $RegistryKey.Close() }
            return $status
        }
        
        # Success - reset status object
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in SetNewRegValue function: $($_.Exception.Message)"
        return $status
    }
}
