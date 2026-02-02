function DeleteRegVal {
    <#
    .SYNOPSIS
    Deletes a single registry value from a registry key.
    
    .DESCRIPTION
    The DeleteRegVal function removes a specific registry value (entry) from a
    registry key. It validates the path format, checks if the value exists, and
    handles proper error reporting through a standardized return object. The registry
    key itself remains intact, only the specified value is removed.
    
    .PARAMETER Path
    The registry path containing the value to delete. Must be in PowerShell
    drive format (e.g., "HKLM:\SOFTWARE\MyCompany\MyApp" or "HKCU:\Software\MyApp").
    The registry key must exist.
    
    .PARAMETER Name
    The name of the registry value to delete. Use "(Default)" or empty string to
    delete the default value of a registry key.
    
    .PARAMETER Force
    Optional switch parameter. When specified, suppresses confirmation prompts.
    Default is $false.
    
    .EXAMPLE
    DeleteRegVal -Path "HKCU:\Software\MyApp\Settings" -Name "ObsoleteOption"
    Deletes the registry value "ObsoleteOption" from the specified key.
    
    .EXAMPLE
    DeleteRegVal -Path "HKLM:\SOFTWARE\MyCompany\MyApp" -Name "TempValue" -Force
    Deletes the registry value without confirmation prompt.
    
    .EXAMPLE
    DeleteRegVal -Path "HKCU:\Software\MyApp" -Name "(Default)"
    Deletes the default value of the registry key.
    
    .EXAMPLE
    $result = DeleteRegVal -Path "HKCU:\Software\TestApp" -Name "TestValue"
    if ($result.code -eq 0) {
        Write-Host "Registry value deleted successfully"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to delete registry values in the specified hive
    - For HKLM operations, administrator privileges are typically required
    - This operation is irreversible - deleted values cannot be recovered
    - The registry key itself is not deleted, only the specified value
    - Consider creating a registry backup before deleting important values
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $status.msg = "Parameter 'Path' is required but was not provided or is empty"
        return $status
    }
    
    # Note: Name can be empty (for default value), so we don't validate it as null/empty
    
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
            "(Default)" 
        } else { 
            $Name 
        }
        
        # Check if the value exists
        $ValueExists = $false
        try {
            if ($ValueName -eq "(Default)") {
                # Check default value
                $KeyItem = Get-Item -Path $NormalizedPath -ErrorAction Stop
                $DefaultValue = $KeyItem.GetValue("")
                # Default value exists if it's not null (even if empty string)
                $ValueExists = $null -ne $DefaultValue -or $DefaultValue -eq ""
            }
            else {
                # Check named value
                $Property = Get-ItemProperty -Path $NormalizedPath -Name $Name -ErrorAction Stop
                $ValueExists = $null -ne $Property
            }
        }
        catch {
            # Value doesn't exist
            $ValueExists = $false
        }
        
        if (-not $ValueExists) {
            $status.msg = "Registry value '$ValueName' does not exist at path '$NormalizedPath'"
            return $status
        }
        
        # Prepare confirmation message
        $ConfirmMessage = "Delete registry value '$ValueName' from key '$NormalizedPath'"
        
        # Attempt to delete the registry value
        try {
            Write-Verbose "Deleting registry value '$ValueName' from: $NormalizedPath"
            
            if ($Force) {
                # Force deletion without confirmation
                if ($ValueName -eq "(Default)") {
                    # Remove default value by setting it to empty
                    Set-ItemProperty -Path $NormalizedPath -Name "(Default)" -Value "" -Force -ErrorAction Stop
                }
                else {
                    Remove-ItemProperty -Path $NormalizedPath -Name $Name -Force -ErrorAction Stop
                }
            }
            else {
                # With confirmation (ShouldProcess)
                if ($PSCmdlet.ShouldProcess("$NormalizedPath\$ValueName", $ConfirmMessage)) {
                    if ($ValueName -eq "(Default)") {
                        # Remove default value by setting it to empty
                        Set-ItemProperty -Path $NormalizedPath -Name "(Default)" -Value "" -ErrorAction Stop
                    }
                    else {
                        Remove-ItemProperty -Path $NormalizedPath -Name $Name -ErrorAction Stop
                    }
                }
                else {
                    $status.msg = "Operation cancelled by user"
                    return $status
                }
            }
            
            # Verify the value was deleted
            $StillExists = $false
            try {
                if ($ValueName -eq "(Default)") {
                    # For default value, we can't really verify deletion as it always "exists"
                    # We just check if it's empty
                    $KeyItem = Get-Item -Path $NormalizedPath -ErrorAction Stop
                    $CheckValue = $KeyItem.GetValue("")
                    $StillExists = ![string]::IsNullOrEmpty($CheckValue)
                }
                else {
                    $CheckProperty = Get-ItemProperty -Path $NormalizedPath -Name $Name -ErrorAction Stop
                    $StillExists = $null -ne $CheckProperty
                }
            }
            catch {
                # If we get an error, the value doesn't exist (which is what we want)
                $StillExists = $false
            }
            
            if ($StillExists) {
                $status.msg = "Registry value deletion reported success, but verification failed. Value '$ValueName' still exists at '$NormalizedPath'."
                return $status
            }
            
            Write-Verbose "Successfully deleted registry value '$ValueName' from: $NormalizedPath"
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied when deleting registry value '$ValueName' at path '$NormalizedPath'. Administrator privileges may be required for this operation."
            return $status
        }
        catch [System.Security.SecurityException] {
            $status.msg = "Security exception when deleting registry value '$ValueName' at path '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        catch {
            $status.msg = "Failed to delete registry value '$ValueName' at path '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Success - reset status object
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in DeleteRegVal function: $($_.Exception.Message)"
        return $status
    }
}
