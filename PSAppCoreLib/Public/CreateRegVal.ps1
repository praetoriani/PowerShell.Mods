function CreateRegVal {
    <#
    .SYNOPSIS
    Creates a new registry value at the specified path.
    
    .DESCRIPTION
    The CreateRegVal function creates a new registry value (entry) at the specified
    registry key location. It validates the path format, value type, checks if the
    value already exists, and handles proper error reporting through a standardized
    return object. The function supports all standard registry value types.
    
    .PARAMETER Path
    The registry path where the new value should be created. Must be in PowerShell
    drive format (e.g., "HKLM:\SOFTWARE\MyCompany\MyApp" or "HKCU:\Software\MyApp").
    The registry key must already exist.
    
    .PARAMETER Name
    The name of the registry value to create. Use "(Default)" or empty string to
    set the default value of a registry key.
    
    .PARAMETER Type
    The type of the registry value. Valid types are:
    - String: REG_SZ - A string value
    - ExpandString: REG_EXPAND_SZ - An expandable string value (can contain environment variables)
    - Binary: REG_BINARY - Binary data
    - DWord: REG_DWORD - A 32-bit number
    - QWord: REG_QWORD - A 64-bit number
    - MultiString: REG_MULTI_SZ - A multi-string value (array of strings)
    
    .PARAMETER Value
    The value to set for the registry entry. The type of data should match the
    specified Type parameter:
    - For String/ExpandString: Use string values
    - For Binary: Use byte array (e.g., [byte[]](0x01, 0x02, 0x03))
    - For DWord/QWord: Use integer values
    - For MultiString: Use string array (e.g., @("Line1", "Line2"))
    
    .EXAMPLE
    CreateRegVal -Path "HKLM:\SOFTWARE\MyCompany\MyApp" -Name "Version" -Type "String" -Value "1.0.0"
    Creates a new string registry value "Version" with the value "1.0.0".
    
    .EXAMPLE
    CreateRegVal -Path "HKCU:\Software\MyApp\Settings" -Name "Timeout" -Type "DWord" -Value 30
    Creates a new DWORD registry value "Timeout" with the value 30.
    
    .EXAMPLE
    CreateRegVal -Path "HKLM:\SOFTWARE\MyApp" -Name "InstallPath" -Type "ExpandString" -Value "%ProgramFiles%\MyApp"
    Creates a new expandable string value that will expand environment variables.
    
    .EXAMPLE
    CreateRegVal -Path "HKCU:\Software\MyApp" -Name "Servers" -Type "MultiString" -Value @("Server1", "Server2", "Server3")
    Creates a new multi-string value with multiple server names.
    
    .EXAMPLE
    $binaryData = [byte[]](0x48, 0x65, 0x6C, 0x6C, 0x6F)
    CreateRegVal -Path "HKLM:\SOFTWARE\MyApp" -Name "BinaryData" -Type "Binary" -Value $binaryData
    Creates a new binary registry value with byte array data.
    
    .EXAMPLE
    $result = CreateRegVal -Path "HKCU:\Software\Test" -Name "TestValue" -Type "String" -Value "Test"
    if ($result.code -eq 0) {
        Write-Host "Registry value created: $($result.data.Name) = $($result.data.Value)"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to create registry values in the specified hive
    - For HKLM operations, administrator privileges are typically required
    - The registry key (path) must exist before creating a value
    - If the value already exists, the function will return an error
    - For MultiString type, pass an array of strings as the Value parameter
    - For Binary type, pass a byte array as the Value parameter
    - Returns value name and actual stored value in the data field on success
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("String", "ExpandString", "Binary", "DWord", "QWord", "MultiString", IgnoreCase = $true)]
        [string]$Type,
        
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty"
    }
    
    # Note: Name can be empty (for default value), so we don't validate it
    # Type is validated by ValidateSet attribute
    
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
            return OPSreturn -Code -1 -Message "Registry key '$NormalizedPath' does not exist. Please create the key first using CreateRegKey."
        }
        
        # Handle default value case
        $ValueName = if ([string]::IsNullOrEmpty($Name)) { "(Default)" } else { $Name }
        
        # Check if the value already exists
        try {
            $ExistingValue = Get-ItemProperty -Path $NormalizedPath -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $ExistingValue) {
                return OPSreturn -Code -1 -Message "Registry value '$ValueName' already exists at path '$NormalizedPath'"
            }
        }
        catch {
            # Value doesn't exist, which is what we want - continue
            Write-Verbose "Registry value '$ValueName' does not exist (as expected)"
        }
        
        # Validate and convert value based on type
        $ValidatedValue = $null
        $RegistryValueKind = $null
        
        switch ($Type.ToLower()) {
            "string" {
                $RegistryValueKind = [Microsoft.Win32.RegistryValueKind]::String
                if ($null -eq $Value) {
                    $ValidatedValue = ""
                }
                else {
                    $ValidatedValue = [string]$Value
                }
            }
            "expandstring" {
                $RegistryValueKind = [Microsoft.Win32.RegistryValueKind]::ExpandString
                if ($null -eq $Value) {
                    $ValidatedValue = ""
                }
                else {
                    $ValidatedValue = [string]$Value
                }
            }
            "binary" {
                $RegistryValueKind = [Microsoft.Win32.RegistryValueKind]::Binary
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
                        return OPSreturn -Code -1 -Message "Parameter 'Value' for type 'Binary' must be a byte array. Conversion failed: $($_.Exception.Message)"
                    }
                }
            }
            "dword" {
                $RegistryValueKind = [Microsoft.Win32.RegistryValueKind]::DWord
                if ($null -eq $Value) {
                    $ValidatedValue = 0
                }
                else {
                    try {
                        $ValidatedValue = [int]$Value
                        if ($ValidatedValue -lt 0 -or $ValidatedValue -gt [UInt32]::MaxValue) {
                            return OPSreturn -Code -1 -Message "Parameter 'Value' for type 'DWord' must be between 0 and $([UInt32]::MaxValue)"
                        }
                    }
                    catch {
                        return OPSreturn -Code -1 -Message "Parameter 'Value' for type 'DWord' must be a valid 32-bit integer: $($_.Exception.Message)"
                    }
                }
            }
            "qword" {
                $RegistryValueKind = [Microsoft.Win32.RegistryValueKind]::QWord
                if ($null -eq $Value) {
                    $ValidatedValue = 0
                }
                else {
                    try {
                        $ValidatedValue = [long]$Value
                        if ($ValidatedValue -lt 0 -or $ValidatedValue -gt [UInt64]::MaxValue) {
                            return OPSreturn -Code -1 -Message "Parameter 'Value' for type 'QWord' must be between 0 and $([UInt64]::MaxValue)"
                        }
                    }
                    catch {
                        return OPSreturn -Code -1 -Message "Parameter 'Value' for type 'QWord' must be a valid 64-bit integer: $($_.Exception.Message)"
                    }
                }
            }
            "multistring" {
                $RegistryValueKind = [Microsoft.Win32.RegistryValueKind]::MultiString
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
                        return OPSreturn -Code -1 -Message "Parameter 'Value' for type 'MultiString' must be a string array: $($_.Exception.Message)"
                    }
                }
            }
            default {
                return OPSreturn -Code -1 -Message "Invalid registry value type '$Type'. Valid types are: String, ExpandString, Binary, DWord, QWord, MultiString"
            }
        }
        
        # Attempt to create the registry value
        try {
            Write-Verbose "Creating registry value '$ValueName' of type '$Type' at path '$NormalizedPath'"
            
            # Use New-ItemProperty to create the value
            if ([string]::IsNullOrEmpty($Name)) {
                # Setting the default value requires special handling
                $NewValue = Set-ItemProperty -Path $NormalizedPath -Name "(Default)" -Value $ValidatedValue -ErrorAction Stop
            }
            else {
                $NewValue = New-ItemProperty -Path $NormalizedPath -Name $Name -PropertyType $RegistryValueKind -Value $ValidatedValue -Force -ErrorAction Stop
            }
            
            if ($null -eq $NewValue) {
                return OPSreturn -Code -1 -Message "Failed to create registry value '$ValueName' at path '$NormalizedPath'. New-ItemProperty returned null."
            }
            
            # Verify the value was created
            try {
                $VerifyValue = Get-ItemProperty -Path $NormalizedPath -Name $Name -ErrorAction Stop
                if ($null -eq $VerifyValue) {
                    return OPSreturn -Code -1 -Message "Registry value creation reported success, but verification failed for '$ValueName' at path '$NormalizedPath'"
                }
            }
            catch {
                return OPSreturn -Code -1 -Message "Registry value creation reported success, but verification failed for '$ValueName' at path '$NormalizedPath': $($_.Exception.Message)"
            }
            
            Write-Verbose "Successfully created registry value '$ValueName' at path '$NormalizedPath'"
            
            # Prepare return data object with created value information
            $ReturnData = [PSCustomObject]@{
                Path  = $NormalizedPath
                Name  = $ValueName
                Type  = $Type
                Value = $ValidatedValue
            }
        }
        catch [System.UnauthorizedAccessException] {
            return OPSreturn -Code -1 -Message "Access denied when creating registry value '$ValueName' at path '$NormalizedPath'. Administrator privileges may be required for this operation."
        }
        catch [System.Security.SecurityException] {
            return OPSreturn -Code -1 -Message "Security exception when creating registry value '$ValueName' at path '$NormalizedPath': $($_.Exception.Message)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to create registry value '$ValueName' at path '$NormalizedPath': $($_.Exception.Message)"
        }
        
        # Success - return with value information in data field
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in CreateRegVal function: $($_.Exception.Message)"
    }
}
