function RemoveDirs {
    <#
    .SYNOPSIS
    Removes multiple directories recursively and permanently.
    
    .DESCRIPTION
    The RemoveDirs function receives an array of directory paths and deletes each
    directory recursively (including all files and subdirectories) just like RemoveDir.
    The deletion is permanent and cannot be undone. It validates each directory path,
    checks permissions, removes all contents recursively, and reports detailed results
    through a standardized return object including success/failure counts.
    
    .PARAMETER Paths
    Array of full paths to the directories to remove. Each directory and all its
    contents will be deleted recursively and permanently. Supports both local and UNC paths.
    
    .PARAMETER Force
    Optional switch parameter. When specified, removes readonly, hidden, and system
    files without prompting. Also bypasses confirmation prompts. Default is $false.
    
    .PARAMETER StopOnError
    Optional switch parameter. When specified, stops the entire operation if any
    single directory removal fails. When not specified, continues removing remaining
    directories and reports errors in the results. Default is $false.
    
    .EXAMPLE
    RemoveDirs -Paths @("C:\Temp\Dir1", "C:\Temp\Dir2", "D:\OldData")
    Removes three directories and all their contents permanently.
    
    .EXAMPLE
    $dirsToRemove = @("C:\Logs\Old", "D:\Cache")
    RemoveDirs -Paths $dirsToRemove -Force
    Removes directories including readonly files without prompting.
    
    .EXAMPLE
    $result = RemoveDirs -Paths @("C:\Dir1", "C:\Dir2") -StopOnError
    if ($result.code -eq 0) {
        Write-Host "Successfully removed $($result.successCount) directories"
    } else {
        Write-Host "Failed to remove directories: $($result.msg)"
    }
    
    .EXAMPLE
    $result = RemoveDirs -Paths $directoryList
    Write-Host "Success: $($result.successCount), Failed: $($result.failureCount)"
    foreach ($success in $result.removedDirs) {
        Write-Host "Removed: $success"
    }
    foreach ($failure in $result.failedDirs) {
        Write-Host "Failed: $($failure.path) - $($failure.error)"
    }
    
    .NOTES
    - Requires write/delete permissions on all directories and their contents
    - Deletion is permanent and cannot be undone - files do NOT go to Recycle Bin
    - With -StopOnError, operation halts immediately on first failure
    - Without -StopOnError, continues with remaining directories and reports all errors
    - Handles readonly, hidden, and system files when -Force is specified
    - Each directory is deleted recursively (all files and subdirectories)
    - Use with extreme caution - this operation is irreversible
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Paths,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [switch]$StopOnError
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        successCount = 0
        failureCount = 0
        totalSizeBytes = 0
        totalFileCount = 0
        totalDirCount = 0
        removedDirs = @()
        failedDirs = @()
    }
    
    # Validate mandatory parameters
    if ($null -eq $Paths -or $Paths.Count -eq 0) {
        $status.msg = "Parameter 'Paths' is required but was not provided or is empty"
        return $status
    }
    
    try {
        # Validate all paths first if StopOnError is specified
        if ($StopOnError) {
            Write-Verbose "Validating all directory paths before deletion..."
            foreach ($path in $Paths) {
                if ([string]::IsNullOrWhiteSpace($path)) {
                    $status.msg = "One of the directory paths is null or empty"
                    return $status
                }
                
                $NormalizedPath = $path.Replace('/', '\').TrimEnd('\')
                
                if (-not (Test-Path -Path $NormalizedPath -PathType Container)) {
                    $status.msg = "Directory '$NormalizedPath' does not exist or is not a directory"
                    return $status
                }
            }
        }
        
        # Prepare confirmation message
        $TotalDirs = $Paths.Count
        $ConfirmMessage = "Permanently remove $TotalDirs directories and all their contents"
        
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("$TotalDirs directories", $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        # Process each directory
        Write-Verbose "Starting removal of $TotalDirs directories..."
        
        foreach ($path in $Paths) {
            # Skip null or empty paths
            if ([string]::IsNullOrWhiteSpace($path)) {
                $ErrorInfo = [PSCustomObject]@{
                    path = $path
                    error = "Path is null or empty"
                }
                $status.failedDirs += $ErrorInfo
                $status.failureCount++
                Write-Verbose "Skipped null or empty path"
                
                if ($StopOnError) {
                    $status.msg = "Operation stopped due to error: Path is null or empty"
                    return $status
                }
                continue
            }
            
            try {
                # Normalize path
                $NormalizedPath = $path.Replace('/', '\').TrimEnd('\')
                
                Write-Verbose "Processing directory: $NormalizedPath"
                
                # Check if directory exists
                if (-not (Test-Path -Path $NormalizedPath -PathType Container)) {
                    $ErrorInfo = [PSCustomObject]@{
                        path = $NormalizedPath
                        error = "Directory does not exist or is not a directory"
                    }
                    $status.failedDirs += $ErrorInfo
                    $status.failureCount++
                    Write-Verbose "Directory not found: $NormalizedPath"
                    
                    if ($StopOnError) {
                        $status.msg = "Operation stopped due to error: Directory '$NormalizedPath' does not exist"
                        return $status
                    }
                    continue
                }
                
                # Check if path is a file instead of directory
                if (Test-Path -Path $NormalizedPath -PathType Leaf) {
                    $ErrorInfo = [PSCustomObject]@{
                        path = $NormalizedPath
                        error = "Path is a file, not a directory"
                    }
                    $status.failedDirs += $ErrorInfo
                    $status.failureCount++
                    Write-Verbose "Path is a file, not a directory: $NormalizedPath"
                    
                    if ($StopOnError) {
                        $status.msg = "Operation stopped due to error: Path '$NormalizedPath' is a file, not a directory"
                        return $status
                    }
                    continue
                }
                
                # Get directory information and calculate size before deletion
                try {
                    $DirItem = Get-Item -Path $NormalizedPath -ErrorAction Stop
                    $DirFullPath = $DirItem.FullName
                    
                    # Calculate directory size and item counts
                    $AllItems = Get-ChildItem -Path $DirFullPath -Recurse -Force -ErrorAction SilentlyContinue
                    $Files = $AllItems | Where-Object { -not $_.PSIsContainer }
                    $Dirs = $AllItems | Where-Object { $_.PSIsContainer }
                    
                    $DirSize = ($Files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($null -eq $DirSize) { $DirSize = 0 }
                    
                    $FileCount = ($Files | Measure-Object).Count
                    $SubDirCount = ($Dirs | Measure-Object).Count
                    
                    Write-Verbose "Directory contains $FileCount files and $SubDirCount subdirectories ($DirSize bytes)"
                }
                catch {
                    $ErrorInfo = [PSCustomObject]@{
                        path = $NormalizedPath
                        error = "Failed to access directory: $($_.Exception.Message)"
                    }
                    $status.failedDirs += $ErrorInfo
                    $status.failureCount++
                    Write-Verbose "Failed to access directory: $NormalizedPath - $($_.Exception.Message)"
                    
                    if ($StopOnError) {
                        $status.msg = "Operation stopped due to error accessing directory '$NormalizedPath': $($_.Exception.Message)"
                        return $status
                    }
                    continue
                }
                
                # Attempt to remove the directory recursively
                try {
                    Write-Verbose "Removing directory recursively: $DirFullPath"
                    
                    if ($Force) {
                        # Remove readonly, hidden, and system attributes from all items
                        try {
                            Get-ChildItem -Path $DirFullPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                                if ($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                                    $_.Attributes = $_.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly
                                }
                            }
                        }
                        catch {
                            Write-Verbose "Warning: Could not remove attributes from some items: $($_.Exception.Message)"
                        }
                        
                        Remove-Item -Path $DirFullPath -Recurse -Force -ErrorAction Stop
                    }
                    else {
                        Remove-Item -Path $DirFullPath -Recurse -ErrorAction Stop
                    }
                    
                    # Verify directory was removed
                    if (Test-Path -Path $DirFullPath) {
                        $ErrorInfo = [PSCustomObject]@{
                            path = $DirFullPath
                            error = "Remove operation reported success, but directory still exists"
                        }
                        $status.failedDirs += $ErrorInfo
                        $status.failureCount++
                        
                        if ($StopOnError) {
                            $status.msg = "Operation stopped: Directory '$DirFullPath' was not removed"
                            return $status
                        }
                        continue
                    }
                    
                    # Successfully removed
                    $status.removedDirs += $DirFullPath
                    $status.successCount++
                    $status.totalSizeBytes += $DirSize
                    $status.totalFileCount += $FileCount
                    $status.totalDirCount += ($SubDirCount + 1)  # +1 for the root directory itself
                    
                    Write-Verbose "Successfully removed directory: $DirFullPath ($FileCount files, $SubDirCount subdirs, $DirSize bytes)"
                }
                catch [System.UnauthorizedAccessException] {
                    $ErrorInfo = [PSCustomObject]@{
                        path = $NormalizedPath
                        error = "Access denied. Check permissions or use -Force for readonly files."
                    }
                    $status.failedDirs += $ErrorInfo
                    $status.failureCount++
                    Write-Verbose "Access denied removing directory: $NormalizedPath"
                    
                    if ($StopOnError) {
                        $status.msg = "Operation stopped due to access denied on directory '$NormalizedPath'"
                        return $status
                    }
                }
                catch [System.IO.IOException] {
                    $ErrorInfo = [PSCustomObject]@{
                        path = $NormalizedPath
                        error = "I/O error: $($_.Exception.Message)"
                    }
                    $status.failedDirs += $ErrorInfo
                    $status.failureCount++
                    Write-Verbose "I/O error removing directory: $NormalizedPath - $($_.Exception.Message)"
                    
                    if ($StopOnError) {
                        $status.msg = "Operation stopped due to I/O error on directory '$NormalizedPath': $($_.Exception.Message)"
                        return $status
                    }
                }
                catch {
                    $ErrorInfo = [PSCustomObject]@{
                        path = $NormalizedPath
                        error = $_.Exception.Message
                    }
                    $status.failedDirs += $ErrorInfo
                    $status.failureCount++
                    Write-Verbose "Failed to remove directory: $NormalizedPath - $($_.Exception.Message)"
                    
                    if ($StopOnError) {
                        $status.msg = "Operation stopped due to error on directory '$NormalizedPath': $($_.Exception.Message)"
                        return $status
                    }
                }
            }
            catch {
                $ErrorInfo = [PSCustomObject]@{
                    path = $path
                    error = $_.Exception.Message
                }
                $status.failedDirs += $ErrorInfo
                $status.failureCount++
                Write-Verbose "Unexpected error processing path: $path - $($_.Exception.Message)"
                
                if ($StopOnError) {
                    $status.msg = "Operation stopped due to unexpected error on path '$path': $($_.Exception.Message)"
                    return $status
                }
            }
        }
        
        # Determine final status
        if ($status.failureCount -eq 0) {
            # Complete success
            $status.code = 0
            $status.msg = ""
            Write-Verbose "Successfully removed all $($status.successCount) directories"
        }
        elseif ($status.successCount -eq 0) {
            # Complete failure
            $status.msg = "Failed to remove all $($status.failureCount) directories. Check failedDirs property for details."
            Write-Verbose "Failed to remove all directories"
        }
        else {
            # Partial success
            $status.code = 1
            $status.msg = "Partially successful: Removed $($status.successCount) directories, but $($status.failureCount) failed. Check failedDirs property for details."
            Write-Verbose "Partial success: $($status.successCount) removed, $($status.failureCount) failed"
        }
        
        Write-Verbose "Total removed: $($status.totalFileCount) files, $($status.totalDirCount) directories, $($status.totalSizeBytes) bytes"
        
        return $status
    }
    catch {
        $status.msg = "Unexpected error in RemoveDirs function: $($_.Exception.Message)"
        return $status
    }
}
