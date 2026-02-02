function RemoveAllOnReboot {
    <#
    .SYNOPSIS
    Schedules complete removal of a directory and all its contents on next system reboot.
    
    .DESCRIPTION
    The RemoveAllOnReboot function recursively traverses the specified directory,
    creates separate lists of all files and subdirectories, and registers each item
    in the PendingFileRenameOperations registry key for deletion on next reboot.
    Files are registered first, then directories (in reverse order to delete from
    deepest to shallowest). This ensures complete directory removal even if files
    are locked during normal operation.
    
    This function requires administrative privileges to modify the registry.
    
    .PARAMETER Path
    The full path of the directory to schedule for removal on reboot.
    Must be an existing directory. The directory and all its contents will be
    marked for deletion during the next system startup.
    
    .PARAMETER IncludeRootDirectory
    Optional switch parameter. When specified, the root directory itself is also
    scheduled for deletion. When not specified (default), only the contents of
    the directory are deleted, leaving the empty root directory. Default is $true.
    
    .EXAMPLE
    RemoveAllOnReboot -Path "C:\TempData"
    Schedules the complete TempData directory and all contents for removal on reboot.
    
    .EXAMPLE
    RemoveAllOnReboot -Path "C:\ProgramData\OldApp" -IncludeRootDirectory:$false
    Schedules all contents of OldApp directory for removal, but keeps the empty directory.
    
    .EXAMPLE
    $result = RemoveAllOnReboot -Path "D:\LockedFiles"
    if ($result.code -eq 0) {
        Write-Host "Successfully scheduled for deletion:"
        Write-Host "Files: $($result.fileCount)"
        Write-Host "Directories: $($result.directoryCount)"
        Write-Host "Total size: $($result.totalSizeBytes) bytes"
        Write-Host "Reboot required to complete deletion"
    }
    
    .NOTES
    - Requires administrative privileges (runs with elevated rights)
    - Modifies HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations
    - Changes take effect only after system reboot
    - Files and directories are deleted by Windows during boot process
    - Use with caution - deletion is irreversible after reboot
    - Items are registered in specific order: all files first, then directories (deepest first)
    - If registry modification fails for any item, the operation continues but reports errors
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeRootDirectory = $true
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        path = $null
        fileCount = 0
        directoryCount = 0
        totalSizeBytes = 0
        registeredItems = @()
        failedItems = @()
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $status.msg = "Parameter 'Path' is required but was not provided or is empty"
        return $status
    }
    
    # Check for administrative privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        $status.msg = "This function requires administrative privileges. Please run PowerShell as Administrator."
        return $status
    }
    
    try {
        # Normalize path
        $NormalizedPath = $Path.Replace('/', '\').TrimEnd('\')
        
        # Check if directory exists
        if (-not (Test-Path -Path $NormalizedPath -PathType Container)) {
            $status.msg = "Directory '$NormalizedPath' does not exist or is not a directory"
            return $status
        }
        
        # Check if path is a file instead of directory
        if (Test-Path -Path $NormalizedPath -PathType Leaf) {
            $status.msg = "Path '$NormalizedPath' is a file, not a directory. Use RemoveOnReboot for single files."
            return $status
        }
        
        # Get directory item
        try {
            $RootDirectory = Get-Item -Path $NormalizedPath -ErrorAction Stop
            $status.path = $RootDirectory.FullName
        }
        catch {
            $status.msg = "Failed to access directory '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Confirmation for high-impact operation
        $ItemCount = (Get-ChildItem -Path $NormalizedPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
        $ConfirmMessage = "Schedule deletion of directory '$NormalizedPath' and all $ItemCount items on next reboot"
        
        if (-not $PSCmdlet.ShouldProcess($NormalizedPath, $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        Write-Verbose "Starting recursive directory traversal: $NormalizedPath"
        
        # Lists to store files and directories
        $AllFiles = New-Object System.Collections.ArrayList
        $AllDirectories = New-Object System.Collections.ArrayList
        
        # Recursively collect all files and directories
        try {
            Write-Verbose "Collecting all files and directories..."
            
            # Get all items recursively
            $AllItems = Get-ChildItem -Path $NormalizedPath -Recurse -Force -ErrorAction Stop
            
            foreach ($item in $AllItems) {
                if ($item.PSIsContainer) {
                    # It's a directory
                    [void]$AllDirectories.Add($item)
                }
                else {
                    # It's a file
                    [void]$AllFiles.Add($item)
                    $status.totalSizeBytes += $item.Length
                }
            }
            
            # Sort directories by depth (deepest first) to ensure proper deletion order
            $AllDirectories = $AllDirectories | Sort-Object { $_.FullName.Split('\').Count } -Descending
            
            Write-Verbose "Found $($AllFiles.Count) files and $($AllDirectories.Count) directories"
        }
        catch {
            $status.msg = "Failed to enumerate directory contents: $($_.Exception.Message)"
            return $status
        }
        
        # Registry path for pending operations
        $RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $RegistryValueName = "PendingFileRenameOperations"
        
        # Get current pending operations
        try {
            $CurrentValue = Get-ItemProperty -Path $RegistryPath -Name $RegistryValueName -ErrorAction SilentlyContinue
            if ($null -eq $CurrentValue) {
                $PendingOperations = @()
            }
            else {
                $PendingOperations = [System.Collections.ArrayList]@($CurrentValue.$RegistryValueName)
            }
        }
        catch {
            $PendingOperations = New-Object System.Collections.ArrayList
        }
        
        Write-Verbose "Current pending operations: $($PendingOperations.Count)"
        
        # Counter for successfully registered items
        $RegisteredCount = 0
        
        # Register all FILES first
        Write-Verbose "Registering $($AllFiles.Count) files for deletion..."
        foreach ($file in $AllFiles) {
            try {
                # Convert to native path format (e.g., \??\C:\path\to\file)
                $NativePath = "\??\" + $file.FullName
                
                # Add file path and empty string (for deletion)
                [void]$PendingOperations.Add($NativePath)
                [void]$PendingOperations.Add("")
                
                $status.registeredItems += $file.FullName
                $status.fileCount++
                $RegisteredCount++
                
                Write-Verbose "Registered file: $($file.FullName)"
            }
            catch {
                $ErrorInfo = [PSCustomObject]@{
                    path = $file.FullName
                    error = $_.Exception.Message
                }
                $status.failedItems += $ErrorInfo
                Write-Verbose "Failed to register file: $($file.FullName) - $($_.Exception.Message)"
            }
        }
        
        # Register all DIRECTORIES (deepest first)
        Write-Verbose "Registering $($AllDirectories.Count) directories for deletion..."
        foreach ($directory in $AllDirectories) {
            try {
                # Convert to native path format
                $NativePath = "\??\" + $directory.FullName
                
                # Add directory path and empty string (for deletion)
                [void]$PendingOperations.Add($NativePath)
                [void]$PendingOperations.Add("")
                
                $status.registeredItems += $directory.FullName
                $status.directoryCount++
                $RegisteredCount++
                
                Write-Verbose "Registered directory: $($directory.FullName)"
            }
            catch {
                $ErrorInfo = [PSCustomObject]@{
                    path = $directory.FullName
                    error = $_.Exception.Message
                }
                $status.failedItems += $ErrorInfo
                Write-Verbose "Failed to register directory: $($directory.FullName) - $($_.Exception.Message)"
            }
        }
        
        # Register root directory if requested
        if ($IncludeRootDirectory) {
            try {
                $NativePath = "\??\" + $RootDirectory.FullName
                [void]$PendingOperations.Add($NativePath)
                [void]$PendingOperations.Add("")
                
                $status.registeredItems += $RootDirectory.FullName
                $status.directoryCount++
                $RegisteredCount++
                
                Write-Verbose "Registered root directory: $($RootDirectory.FullName)"
            }
            catch {
                $ErrorInfo = [PSCustomObject]@{
                    path = $RootDirectory.FullName
                    error = $_.Exception.Message
                }
                $status.failedItems += $ErrorInfo
                Write-Verbose "Failed to register root directory: $($RootDirectory.FullName) - $($_.Exception.Message)"
            }
        }
        
        # Write updated pending operations to registry
        try {
            Write-Verbose "Writing $($PendingOperations.Count) operations to registry..."
            
            Set-ItemProperty -Path $RegistryPath -Name $RegistryValueName -Value $PendingOperations.ToArray() -Type MultiString -ErrorAction Stop
            
            Write-Verbose "Successfully updated registry with $RegisteredCount new deletion operations"
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied writing to registry. Ensure you have administrative privileges."
            return $status
        }
        catch {
            $status.msg = "Failed to write pending operations to registry: $($_.Exception.Message)"
            return $status
        }
        
        # Check if any items failed to register
        if ($status.failedItems.Count -gt 0) {
            $status.msg = "Successfully registered $RegisteredCount items, but $($status.failedItems.Count) items failed. Check failedItems property for details."
            $status.code = 1  # Partial success
            return $status
        }
        
        # Complete success
        $status.code = 0
        $status.msg = ""
        
        Write-Verbose "Successfully scheduled complete directory deletion on reboot: $($status.path)"
        Write-Verbose "Files: $($status.fileCount), Directories: $($status.directoryCount), Total size: $($status.totalSizeBytes) bytes"
        
        return $status
    }
    catch {
        $status.msg = "Unexpected error in RemoveAllOnReboot function: $($_.Exception.Message)"
        return $status
    }
}
