function RemoveOnReboot {
    <#
    .SYNOPSIS
    Schedules a file or directory to be deleted on the next system reboot.
    
    .DESCRIPTION
    The RemoveOnReboot function adds entries to the Windows PendingFileRenameOperations
    registry key to schedule files or directories for deletion on the next system reboot.
    This is useful for removing files that are currently in use or locked by processes.
    The function requires administrator privileges as it modifies registry keys in HKEY_LOCAL_MACHINE.
    
    .PARAMETER Path
    The full path of the file or directory to delete on reboot. Can be a local path only
    (e.g., "C:\Temp\locked.dll" or "C:\Program Files\OldApp"). UNC paths are not supported
    for pending file operations.
    
    .PARAMETER IsDirectory
    Optional switch parameter. Specify this when the path points to a directory.
    When not specified, the path is treated as a file. Default is $false.
    
    .PARAMETER Force
    Optional switch parameter. When specified, suppresses confirmation prompts.
    Use with caution as this schedules permanent deletion. Default is $false.
    
    .EXAMPLE
    RemoveOnReboot -Path "C:\Windows\System32\old.dll"
    Schedules the DLL file for deletion on next reboot.
    
    .EXAMPLE
    RemoveOnReboot -Path "C:\Program Files\ObsoleteApp" -IsDirectory -Force
    Schedules an entire directory for deletion on next reboot without confirmation.
    
    .EXAMPLE
    $result = RemoveOnReboot -Path "C:\Temp\locked.log"
    if ($result.code -eq 0) {
        Write-Host "File scheduled for deletion on next reboot"
        Write-Host "Path: $($result.data.Path)"
        Write-Host "Reboot required: $($result.data.RebootRequired)"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires ADMINISTRATOR PRIVILEGES to modify HKLM registry
    - Only works with local paths (C:\, D:\, etc.) - UNC paths are not supported
    - The file/directory will be deleted during the boot process before Windows fully loads
    - This is a Windows built-in mechanism used by Windows Update and installers
    - Multiple files/directories can be scheduled by calling the function multiple times
    - To view pending operations: Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations
    - Deletion occurs automatically on next reboot - cannot be cancelled except by removing registry entry
    - If the file/directory doesn't exist at reboot time, no error occurs
    - Returns reboot scheduling details in the data field
    
    .LINK
    https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$IsDirectory,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty"
    }
    
    try {
        # Check if running as administrator
        $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $IsAdmin) {
            return OPSreturn -Code -1 -Message "Administrator privileges are required to schedule file operations for reboot. Please run PowerShell as Administrator."
        }
        
        # Normalize path
        $NormalizedPath = $Path.Replace('/', '\\').TrimEnd('\\')
        
        # Check if path is a UNC path (not supported for pending operations)
        if ($NormalizedPath.StartsWith('\\\\')) {
            return OPSreturn -Code -1 -Message "UNC paths are not supported for pending file operations. Only local paths (C:\\, D:\\, etc.) can be used."
        }
        
        # Validate that path is a valid Windows path format
        if (-not ($NormalizedPath -match '^[A-Za-z]:\\\\')) {
            return OPSreturn -Code -1 -Message "Path must be a valid Windows local path starting with a drive letter (e.g., C:\\, D:\\)"
        }
        
        # Convert to absolute path if needed
        try {
            $AbsolutePath = [System.IO.Path]::GetFullPath($NormalizedPath)
        }
        catch {
            return OPSreturn -Code -1 -Message "Invalid path format: $($_.Exception.Message)"
        }
        
        # Check if path exists (optional - it may not exist yet or may be locked)
        $PathExists = Test-Path -Path $AbsolutePath
        if ($PathExists) {
            # Verify the path type matches the IsDirectory parameter
            $IsActuallyDirectory = Test-Path -Path $AbsolutePath -PathType Container
            
            if ($IsDirectory -and -not $IsActuallyDirectory) {
                Write-Verbose "Warning: Path exists as a file but -IsDirectory was specified"
            }
            elseif (-not $IsDirectory -and $IsActuallyDirectory) {
                Write-Verbose "Warning: Path exists as a directory but -IsDirectory was not specified. Consider using -IsDirectory parameter."
            }
        }
        else {
            Write-Verbose "Path does not currently exist: $AbsolutePath (it will be deleted if it exists at reboot time)"
        }
        
        # Registry path for pending file operations
        $RegistryPath = "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager"
        $ValueName = "PendingFileRenameOperations"
        
        # Prepare confirmation message
        $TypeString = if ($IsDirectory) { "directory" } else { "file" }
        $ConfirmMessage = "Schedule $TypeString '$AbsolutePath' for PERMANENT deletion on next reboot - THIS CANNOT BE UNDONE"
        
        # Attempt to add pending file operation
        try {
            if ($Force -or $PSCmdlet.ShouldProcess($AbsolutePath, $ConfirmMessage)) {
                
                Write-Verbose "Adding pending file operation for: $AbsolutePath"
                
                # Get existing PendingFileRenameOperations value
                $ExistingValue = $null
                try {
                    $ExistingValue = Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $ValueName
                }
                catch {
                    Write-Verbose "No existing PendingFileRenameOperations found (this is normal)"
                }
                
                # Prepare the new entry
                # Format: Source path, then empty string (which means delete)
                # Paths must be in DOS device format: \??\C:\Path\To\File
                $DosDevicePath = "\\??\\" + $AbsolutePath
                $NewEntry = @($DosDevicePath, "")
                
                # Combine with existing entries
                if ($ExistingValue) {
                    # Existing entries found - append new entry
                    if ($ExistingValue -is [array]) {
                        $CombinedValue = $ExistingValue + $NewEntry
                    }
                    else {
                        # Single existing entry - convert to array
                        $CombinedValue = @($ExistingValue, "") + $NewEntry
                    }
                }
                else {
                    # No existing entries - use only new entry
                    $CombinedValue = $NewEntry
                }
                
                # Write to registry as MultiString (REG_MULTI_SZ)
                try {
                    Set-ItemProperty -Path $RegistryPath -Name $ValueName -Value $CombinedValue -Type MultiString -Force -ErrorAction Stop
                    Write-Verbose "Successfully added pending file operation to registry"
                }
                catch {
                    return OPSreturn -Code -1 -Message "Failed to write to registry: $($_.Exception.Message)"
                }
                
                # Verify the entry was added
                try {
                    $VerifyValue = Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction Stop | Select-Object -ExpandProperty $ValueName
                    
                    if ($VerifyValue -contains $DosDevicePath) {
                        Write-Verbose "Verified: Pending operation was successfully registered"
                    }
                    else {
                        return OPSreturn -Code -1 -Message "Registry write reported success, but verification failed. The pending operation may not have been registered correctly."
                    }
                }
                catch {
                    Write-Verbose "Warning: Could not verify registry entry: $($_.Exception.Message)"
                    # Still consider it successful since the write operation succeeded
                }
                
                Write-Verbose "Successfully scheduled for deletion on reboot: $AbsolutePath"
                Write-Host "`nIMPORTANT: A system reboot is required for the deletion to take effect." -ForegroundColor Yellow
                Write-Host "The $TypeString will be deleted during the boot process.`n" -ForegroundColor Yellow
                
                # Prepare return data object with reboot scheduling details
                $ReturnData = [PSCustomObject]@{
                    Path            = $AbsolutePath
                    IsDirectory     = $IsDirectory.IsPresent
                    PathExists      = $PathExists
                    RebootRequired  = $true
                    DosDevicePath   = $DosDevicePath
                    RegistryPath    = "$RegistryPath\\$ValueName"
                }
                
                return OPSreturn -Code 0 -Message "" -Data $ReturnData
            }
            else {
                return OPSreturn -Code -1 -Message "Operation cancelled by user"
            }
        }
        catch [System.UnauthorizedAccessException] {
            return OPSreturn -Code -1 -Message "Access denied when modifying registry. Ensure you are running as Administrator."
        }
        catch [System.Security.SecurityException] {
            return OPSreturn -Code -1 -Message "Security exception when modifying registry: $($_.Exception.Message)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to schedule deletion for '$AbsolutePath': $($_.Exception.Message)"
        }
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in RemoveOnReboot function: $($_.Exception.Message)"
    }
}
