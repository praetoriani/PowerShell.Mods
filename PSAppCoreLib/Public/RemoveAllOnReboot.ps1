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
        Write-Host "Path: $($result.data.Path)"
        Write-Host "Files: $($result.data.FileCount)"
        Write-Host "Directories: $($result.data.DirectoryCount)"
        Write-Host "Total size: $($result.data.TotalSizeBytes) bytes"
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
    - Returns comprehensive bulk reboot scheduling statistics in the data field
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeRootDirectory = $true
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty"
    }
    
    # Check for administrative privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        return OPSreturn -Code -1 -Message "This function requires administrative privileges. Please run PowerShell as Administrator."
    }
    
    try {
        # Normalize path
        $NormalizedPath = $Path.Replace('/', '\\').TrimEnd('\\')
        
        # Check if directory exists
        if (-not (Test-Path -Path $NormalizedPath -PathType Container)) {
            return OPSreturn -Code -1 -Message "Directory '$NormalizedPath' does not exist or is not a directory"
        }
        
        # Check if path is a file instead of directory
        if (Test-Path -Path $NormalizedPath -PathType Leaf) {
            return OPSreturn -Code -1 -Message "Path '$NormalizedPath' is a file, not a directory. Use RemoveOnReboot for single files."
        }
        
        # Get directory item
        try {
            $RootDirectory = Get-Item -Path $NormalizedPath -ErrorAction Stop
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to access directory '$NormalizedPath': $($_.Exception.Message)"
        }
        
        # Confirmation for high-impact operation
        $ItemCount = (Get-ChildItem -Path $NormalizedPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
        $ConfirmMessage = "Schedule deletion of directory '$NormalizedPath' and all $ItemCount items on next reboot"
        
        if (-not $PSCmdlet.ShouldProcess($NormalizedPath, $ConfirmMessage)) {
            return OPSreturn -Code -1 -Message "Operation cancelled by user"
        }
        
        Write-Verbose "Starting recursive directory traversal: $NormalizedPath"
        
        # Lists to store files and directories
        $AllFiles = New-Object System.Collections.ArrayList
        $AllDirectories = New-Object System.Collections.ArrayList
        $TotalSize = 0
        
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
                    $TotalSize += $item.Length
                }
            }
            
            # Sort directories by depth (deepest first) to ensure proper deletion order
            $AllDirectories = $AllDirectories | Sort-Object { $_.FullName.Split('\\').Count } -Descending
            
            Write-Verbose "Found $($AllFiles.Count) files and $($AllDirectories.Count) directories"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to enumerate directory contents: $($_.Exception.Message)"
        }
        
        # Registry path for pending operations
        $RegistryPath = "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager"
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
        $FileCount = 0
        $DirCount = 0
        $RegisteredItemsList = @()
        $FailedItemsList = @()
        
        # Register all FILES first
        Write-Verbose "Registering $($AllFiles.Count) files for deletion..."
        foreach ($file in $AllFiles) {
            try {
                # Convert to native path format (e.g., \??\C:\path\to\file)
                $NativePath = "\\??\\" + $file.FullName
                
                # Add file path and empty string (for deletion)
                [void]$PendingOperations.Add($NativePath)
                [void]$PendingOperations.Add("")
                
                $RegisteredItemsList += $file.FullName
                $FileCount++
                $RegisteredCount++
                
                Write-Verbose "Registered file: $($file.FullName)"
            }
            catch {
                $ErrorInfo = [PSCustomObject]@{
                    path = $file.FullName
                    error = $_.Exception.Message
                }
                $FailedItemsList += $ErrorInfo
                Write-Verbose "Failed to register file: $($file.FullName) - $($_.Exception.Message)"
            }
        }
        
        # Register all DIRECTORIES (deepest first)
        Write-Verbose "Registering $($AllDirectories.Count) directories for deletion..."
        foreach ($directory in $AllDirectories) {
            try {
                # Convert to native path format
                $NativePath = "\\??\\" + $directory.FullName
                
                # Add directory path and empty string (for deletion)
                [void]$PendingOperations.Add($NativePath)
                [void]$PendingOperations.Add("")
                
                $RegisteredItemsList += $directory.FullName
                $DirCount++
                $RegisteredCount++
                
                Write-Verbose "Registered directory: $($directory.FullName)"
            }
            catch {
                $ErrorInfo = [PSCustomObject]@{
                    path = $directory.FullName
                    error = $_.Exception.Message
                }
                $FailedItemsList += $ErrorInfo
                Write-Verbose "Failed to register directory: $($directory.FullName) - $($_.Exception.Message)"
            }
        }
        
        # Register root directory if requested
        if ($IncludeRootDirectory) {
            try {
                $NativePath = "\\??\\" + $RootDirectory.FullName
                [void]$PendingOperations.Add($NativePath)
                [void]$PendingOperations.Add("")
                
                $RegisteredItemsList += $RootDirectory.FullName
                $DirCount++
                $RegisteredCount++
                
                Write-Verbose "Registered root directory: $($RootDirectory.FullName)"
            }
            catch {
                $ErrorInfo = [PSCustomObject]@{
                    path = $RootDirectory.FullName
                    error = $_.Exception.Message
                }
                $FailedItemsList += $ErrorInfo
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
            return OPSreturn -Code -1 -Message "Access denied writing to registry. Ensure you have administrative privileges."
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to write pending operations to registry: $($_.Exception.Message)"
        }
        
        Write-Verbose "Successfully scheduled complete directory deletion on reboot: $($RootDirectory.FullName)"
        Write-Verbose "Files: $FileCount, Directories: $DirCount, Total size: $TotalSize bytes"
        
        # Prepare return data object with bulk reboot scheduling statistics
        $ReturnData = [PSCustomObject]@{
            Path                   = $RootDirectory.FullName
            FileCount              = $FileCount
            DirectoryCount         = $DirCount
            TotalSizeBytes         = $TotalSize
            IncludeRootDirectory   = $IncludeRootDirectory
            RegisteredItemsCount   = $RegisteredCount
            RegisteredItems        = $RegisteredItemsList
            FailedItemsCount       = $FailedItemsList.Count
            FailedItems            = $FailedItemsList
            RebootRequired         = $true
        }
        
        # Check if any items failed to register
        if ($FailedItemsList.Count -gt 0) {
            return OPSreturn -Code 1 -Message "Successfully registered $RegisteredCount items, but $($FailedItemsList.Count) items failed. Check failedItems property for details." -Data $ReturnData
        }
        
        # Complete success
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in RemoveAllOnReboot function: $($_.Exception.Message)"
    }
}
