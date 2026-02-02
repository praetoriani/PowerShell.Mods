function RemoveFiles {
    <#
    .SYNOPSIS
    Deletes multiple files permanently from various locations.
    
    .DESCRIPTION
    The RemoveFiles function permanently deletes multiple files (which can be located
    in different directories) from the filesystem. It validates all file paths,
    implements safety checks, handles special file attributes, and reports detailed
    results through a standardized return object. This operation is IRREVERSIBLE -
    deleted files cannot be recovered from the Recycle Bin.
    
    .PARAMETER Paths
    Array of full paths to the files to delete. Each path must be an existing file.
    Files can be located in different directories. Supports both local and UNC paths.
    
    .PARAMETER Force
    Optional switch parameter. When specified, removes read-only, hidden, and system
    files without prompting and suppresses confirmation. Use with extreme caution.
    Default is $false.
    
    .PARAMETER StopOnError
    Optional switch parameter. When specified, stops the entire operation if any
    single file deletion fails. When not specified, continues deleting remaining
    files and reports errors in the results. Default is $false.
    
    .EXAMPLE
    $files = @("C:\Temp\file1.txt", "C:\Logs\old.log", "D:\Cache\temp.dat")
    RemoveFiles -Paths $files -Force
    Deletes all three files without confirmation.
    
    .EXAMPLE
    $oldLogs = Get-ChildItem "C:\Logs\*.log" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Select-Object -ExpandProperty FullName
    RemoveFiles -Paths $oldLogs -Force
    Deletes all log files older than 30 days.
    
    .EXAMPLE
    $result = RemoveFiles -Paths @("C:\file1.txt", "C:\file2.txt") -Force
    Write-Host "Successfully deleted: $($result.successCount) files"
    Write-Host "Failed: $($result.failureCount) files"
    Write-Host "Total size freed: $($result.totalSizeBytes) bytes"
    
    .EXAMPLE
    # Stop on first error
    RemoveFiles -Paths $fileList -Force -StopOnError
    
    .NOTES
    - Requires appropriate permissions to delete all specified files
    - This operation is IRREVERSIBLE - files are deleted permanently, not moved to Recycle Bin
    - Protected system files in critical directories are blocked from deletion
    - Returns detailed results including success/failure counts and error messages
    - With -StopOnError, no files are deleted if any error occurs in validation
    - Read-only attributes are automatically removed with -Force parameter
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
        deletedFiles = @()
        failedFiles = @()
    }
    
    # Validate mandatory parameters
    if ($null -eq $Paths -or $Paths.Count -eq 0) {
        $status.msg = "Parameter 'Paths' is required but was not provided or is empty"
        return $status
    }
    
    try {
        # Validate all files first (if StopOnError is specified)
        if ($StopOnError) {
            Write-Verbose "Validating all files before deletion..."
            foreach ($path in $Paths) {
                if ([string]::IsNullOrWhiteSpace($path)) {
                    $status.msg = "One of the file paths is null or empty"
                    return $status
                }
                
                $NormalizedPath = $path.Replace('/', '\').TrimEnd('\')
                
                if (-not (Test-Path -Path $NormalizedPath -PathType Leaf)) {
                    $status.msg = "File '$NormalizedPath' does not exist or is not a file"
                    return $status
                }
            }
        }
        
        # Prepare confirmation message
        $ConfirmMessage = "Permanently delete $($Paths.Count) file(s) - THIS CANNOT BE UNDONE"
        
        # Attempt to delete all files
        if ($Force -or $PSCmdlet.ShouldProcess("$($Paths.Count) file(s)", $ConfirmMessage)) {
            
            Write-Verbose "Starting deletion operation for $($Paths.Count) file(s)"
            
            $DeletedCount = 0
            $FailedCount = 0
            $TotalSize = 0
            
            foreach ($path in $Paths) {
                try {
                    # Skip empty paths
                    if ([string]::IsNullOrWhiteSpace($path)) {
                        Write-Verbose "Skipping empty path"
                        continue
                    }
                    
                    $NormalizedPath = $path.Replace('/', '\').TrimEnd('\')
                    
                    # Check if file exists
                    if (-not (Test-Path -Path $NormalizedPath -PathType Leaf)) {
                        $errorMsg = "File '$NormalizedPath' does not exist or is not a file"
                        $status.failedFiles += [PSCustomObject]@{
                            Path = $NormalizedPath
                            Error = $errorMsg
                        }
                        $FailedCount++
                        
                        if ($StopOnError) {
                            $status.msg = $errorMsg
                            $status.successCount = $DeletedCount
                            $status.failureCount = $FailedCount
                            return $status
                        }
                        
                        Write-Verbose "Skipping: $errorMsg"
                        continue
                    }
                    
                    # Get file info
                    $FileInfo = Get-Item -Path $NormalizedPath -Force -ErrorAction Stop
                    $FileSize = $FileInfo.Length
                    $FullPath = $FileInfo.FullName
                    
                    # Safety check for system files in critical directories
                    $CriticalDirs = @(
                        "$env:SystemRoot\System32",
                        "$env:SystemRoot\SysWOW64",
                        "$env:SystemRoot"
                    )
                    
                    $FileDirectory = $FileInfo.DirectoryName.ToLower()
                    $IsInCriticalDir = $false
                    
                    foreach ($criticalDir in $CriticalDirs) {
                        if ($criticalDir -and $FileDirectory.StartsWith($criticalDir.ToLower())) {
                            if ($FileInfo.Attributes -band [System.IO.FileAttributes]::System) {
                                $errorMsg = "Cannot delete system file in critical directory: '$FullPath'"
                                $status.failedFiles += [PSCustomObject]@{
                                    Path = $FullPath
                                    Error = $errorMsg
                                }
                                $FailedCount++
                                
                                if ($StopOnError) {
                                    $status.msg = $errorMsg
                                    $status.successCount = $DeletedCount
                                    $status.failureCount = $FailedCount
                                    return $status
                                }
                                
                                Write-Verbose "Skipping: $errorMsg"
                                $IsInCriticalDir = $true
                                break
                            }
                        }
                    }
                    
                    if ($IsInCriticalDir) {
                        continue
                    }
                    
                    # Remove read-only attribute if present and Force is specified
                    if ($Force) {
                        $IsReadOnly = $FileInfo.Attributes -band [System.IO.FileAttributes]::ReadOnly
                        if ($IsReadOnly) {
                            try {
                                $FileInfo.Attributes = $FileInfo.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                                Write-Verbose "Removed ReadOnly attribute from '$($FileInfo.Name)'"
                            }
                            catch {
                                Write-Verbose "Warning: Could not remove ReadOnly attribute: $($_.Exception.Message)"
                            }
                        }
                    }
                    
                    # Perform the deletion
                    Write-Verbose "Deleting: $FullPath"
                    Remove-Item -Path $NormalizedPath -Force:$Force -ErrorAction Stop
                    
                    # Verify deletion
                    if (Test-Path -Path $NormalizedPath) {
                        $errorMsg = "Deletion reported success, but file still exists: '$FullPath'"
                        $status.failedFiles += [PSCustomObject]@{
                            Path = $FullPath
                            Error = $errorMsg
                        }
                        $FailedCount++
                        
                        if ($StopOnError) {
                            $status.msg = $errorMsg
                            $status.successCount = $DeletedCount
                            $status.failureCount = $FailedCount
                            return $status
                        }
                        
                        continue
                    }
                    
                    # Record success
                    $status.deletedFiles += [PSCustomObject]@{
                        Path = $FullPath
                        SizeBytes = $FileSize
                    }
                    
                    $DeletedCount++
                    $TotalSize += $FileSize
                    
                    Write-Verbose "Successfully deleted: $($FileInfo.Name) ($FileSize bytes)"
                }
                catch {
                    $errorMsg = "Failed to delete '$path': $($_.Exception.Message)"
                    $status.failedFiles += [PSCustomObject]@{
                        Path = $path
                        Error = $errorMsg
                    }
                    $FailedCount++
                    
                    if ($StopOnError) {
                        $status.msg = $errorMsg
                        $status.successCount = $DeletedCount
                        $status.failureCount = $FailedCount
                        return $status
                    }
                    
                    Write-Verbose "Error: $errorMsg"
                }
            }
            
            # Set final statistics
            $status.successCount = $DeletedCount
            $status.failureCount = $FailedCount
            $status.totalSizeBytes = $TotalSize
            
            Write-Verbose "Deletion operation completed: $DeletedCount succeeded, $FailedCount failed, Total size: $TotalSize bytes"
            
            # Determine overall success
            if ($FailedCount -eq 0) {
                $status.code = 0
                $status.msg = ""
            }
            elseif ($DeletedCount -gt 0) {
                $status.code = 0
                $status.msg = "Partial success: $DeletedCount file(s) deleted, $FailedCount file(s) failed"
            }
            else {
                $status.msg = "All deletion operations failed"
            }
        }
        else {
            $status.msg = "Operation cancelled by user"
        }
        
        return $status
    }
    catch {
        $status.msg = "Unexpected error in RemoveFiles function: $($_.Exception.Message)"
        return $status
    }
}
