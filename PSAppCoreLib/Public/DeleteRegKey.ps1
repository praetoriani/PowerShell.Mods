function DeleteRegKey {
    <#
    .SYNOPSIS
    Deletes a registry key including all its values and subkeys.
    
    .DESCRIPTION
    The DeleteRegKey function removes a registry key and all its contents recursively.
    It validates the path format, checks if the key exists, optionally verifies the
    key is empty before deletion, and handles proper error reporting through a
    standardized return object. Use with caution as this operation is irreversible.
    
    .PARAMETER Path
    The full registry path including the key to delete. Must be in PowerShell
    drive format (e.g., "HKLM:\SOFTWARE\MyCompany\MyApp" or "HKCU:\Software\MyApp").
    
    .PARAMETER Recurse
    Optional switch parameter. When specified, deletes the key and all subkeys and values.
    When not specified, the key must be empty (no subkeys or values) to be deleted.
    Default is $false (key must be empty).
    
    .PARAMETER Force
    Optional switch parameter. When specified, suppresses confirmation prompts.
    Use with extreme caution, especially with the Recurse parameter.
    Default is $false.
    
    .EXAMPLE
    DeleteRegKey -Path "HKCU:\Software\MyApp\TempSettings"
    Deletes the registry key "TempSettings" only if it's empty (no subkeys or values).
    
    .EXAMPLE
    DeleteRegKey -Path "HKCU:\Software\MyApp\OldVersion" -Recurse
    Deletes the registry key "OldVersion" and all its subkeys and values.
    
    .EXAMPLE
    DeleteRegKey -Path "HKLM:\SOFTWARE\MyCompany\ObsoleteApp" -Recurse -Force
    Deletes the registry key and all contents without confirmation (use with caution).
    
    .EXAMPLE
    $result = DeleteRegKey -Path "HKCU:\Software\TestApp"
    if ($result.code -eq 0) {
        Write-Host "Registry key deleted successfully"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to delete registry keys in the specified hive
    - For HKLM operations, administrator privileges are typically required
    - This operation is IRREVERSIBLE - deleted keys cannot be recovered
    - Use the Recurse parameter with caution as it deletes all subkeys
    - Protected system keys cannot be deleted even with Force parameter
    - Consider creating a registry backup before deleting important keys
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$Recurse,
        
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
        
        # Prevent deletion of root hive keys (safety check)
        $RootHivePattern = '^(HKLM:|HKCU:|HKCR:|HKU:|HKCC:)$'
        if ($NormalizedPath -match $RootHivePattern) {
            $status.msg = "Cannot delete root registry hive '$NormalizedPath'. This operation is not allowed for safety reasons."
            return $status
        }
        
        # Additional safety check for critical system paths
        $CriticalPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows',
            'HKLM:\SYSTEM',
            'HKLM:\SOFTWARE\Classes',
            'HKCU:\SOFTWARE\Microsoft\Windows'
        )
        
        foreach ($criticalPath in $CriticalPaths) {
            if ($NormalizedPath -eq $criticalPath -or $NormalizedPath.StartsWith("$criticalPath\", [System.StringComparison]::OrdinalIgnoreCase)) {
                $status.msg = "Cannot delete critical system registry path '$NormalizedPath'. This operation is blocked for system protection."
                return $status
            }
        }
        
        # Check if the registry key exists
        if (-not (Test-Path -Path $NormalizedPath)) {
            $status.msg = "Registry key '$NormalizedPath' does not exist"
            return $status
        }
        
        # If Recurse is not specified, check if the key has subkeys or values
        if (-not $Recurse) {
            try {
                # Check for subkeys
                $SubKeys = Get-ChildItem -Path $NormalizedPath -ErrorAction SilentlyContinue
                if ($SubKeys -and $SubKeys.Count -gt 0) {
                    $status.msg = "Registry key '$NormalizedPath' contains $($SubKeys.Count) subkey(s). Use -Recurse parameter to delete the key and all its subkeys."
                    return $status
                }
                
                # Check for values (excluding the default value)
                $Values = Get-ItemProperty -Path $NormalizedPath -ErrorAction SilentlyContinue
                if ($Values) {
                    # Get all property names except PSPath, PSParentPath, PSChildName, PSDrive, PSProvider
                    $ValueNames = $Values.PSObject.Properties.Name | Where-Object { 
                        $_ -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider') 
                    }
                    
                    if ($ValueNames -and $ValueNames.Count -gt 0) {
                        $status.msg = "Registry key '$NormalizedPath' contains $($ValueNames.Count) value(s): $($ValueNames -join ', '). The key must be empty or use -Recurse parameter."
                        return $status
                    }
                }
            }
            catch {
                Write-Verbose "Error checking key contents: $($_.Exception.Message)"
            }
        }
        
        # Prepare confirmation message
        $ConfirmMessage = if ($Recurse) {
            "Delete registry key '$NormalizedPath' and ALL subkeys and values recursively"
        } else {
            "Delete registry key '$NormalizedPath'"
        }
        
        # Attempt to delete the registry key
        try {
            Write-Verbose "Deleting registry key: $NormalizedPath (Recurse: $Recurse)"
            
            if ($Force) {
                # Force deletion without confirmation
                if ($Recurse) {
                    Remove-Item -Path $NormalizedPath -Recurse -Force -ErrorAction Stop
                } else {
                    Remove-Item -Path $NormalizedPath -Force -ErrorAction Stop
                }
            }
            else {
                # With confirmation (ShouldProcess)
                if ($PSCmdlet.ShouldProcess($NormalizedPath, $ConfirmMessage)) {
                    if ($Recurse) {
                        Remove-Item -Path $NormalizedPath -Recurse -ErrorAction Stop
                    } else {
                        Remove-Item -Path $NormalizedPath -ErrorAction Stop
                    }
                }
                else {
                    $status.msg = "Operation cancelled by user"
                    return $status
                }
            }
            
            # Verify the key was deleted
            if (Test-Path -Path $NormalizedPath) {
                $status.msg = "Registry key deletion reported success, but verification failed. Key '$NormalizedPath' still exists."
                return $status
            }
            
            Write-Verbose "Successfully deleted registry key: $NormalizedPath"
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied when deleting registry key '$NormalizedPath'. Administrator privileges may be required for this operation."
            return $status
        }
        catch [System.Security.SecurityException] {
            $status.msg = "Security exception when deleting registry key '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        catch [System.ArgumentException] {
            $status.msg = "Invalid registry key path '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        catch {
            $status.msg = "Failed to delete registry key '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Success - reset status object
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in DeleteRegKey function: $($_.Exception.Message)"
        return $status
    }
}
