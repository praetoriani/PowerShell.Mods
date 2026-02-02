function CopyFiles {
    <#
    .SYNOPSIS
    Copies multiple files from various locations to a single destination directory.
    
    .DESCRIPTION
    The CopyFiles function copies multiple files (which can be located in different
    directories) to a single destination directory. It validates all source files,
    checks the destination, handles name conflicts, and reports detailed results
    through a standardized return object. All files are copied to the same destination
    directory with their original filenames.
    
    .PARAMETER SourcePaths
    Array of full paths to the source files to copy. Each path must be an existing file.
    Files can be located in different directories. Supports both local and UNC paths.
    
    .PARAMETER DestinationDirectory
    The destination directory where all files will be copied to. If the directory
    doesn't exist, it will be created automatically. All source files will be copied
    to this single directory with their original filenames.
    
    .PARAMETER Force
    Optional switch parameter. When specified, overwrites existing files at the
    destination without prompting. Default is $false.
    
    .PARAMETER PreserveTimestamps
    Optional switch parameter. When specified, preserves the original files'
    creation time, last write time, and last access time. Default is $true.
    
    .PARAMETER StopOnError
    Optional switch parameter. When specified, stops the entire operation if any
    single file copy fails. When not specified, continues copying remaining files
    and reports errors in the results. Default is $false.
    
    .EXAMPLE
    $files = @("C:\Data\file1.txt", "C:\Reports\file2.pdf", "D:\Images\photo.jpg")
    CopyFiles -SourcePaths $files -DestinationDirectory "E:\Backup"
    Copies all three files to E:\Backup directory.
    
    .EXAMPLE
    $files = Get-ChildItem "C:\Source\*.log" | Select-Object -ExpandProperty FullName
    CopyFiles -SourcePaths $files -DestinationDirectory "D:\Logs\Archive" -Force
    Copies all log files to the archive directory, overwriting existing files.
    
    .EXAMPLE
    $result = CopyFiles -SourcePaths @("C:\file1.txt", "C:\file2.txt") -DestinationDirectory "D:\Backup"
    Write-Host "Successfully copied: $($result.successCount) files"
    Write-Host "Failed: $($result.failureCount) files"
    Write-Host "Total size: $($result.totalSizeBytes) bytes"
    
    .EXAMPLE
    # Stop on first error
    CopyFiles -SourcePaths $fileList -DestinationDirectory "D:\Backup" -StopOnError
    
    .NOTES
    - Requires read permissions on all source files and write permissions on destination
    - If a filename conflict occurs (two source files with same name), later files
      will overwrite earlier ones unless -Force is not specified
    - Creates destination directory automatically if it doesn't exist
    - Returns detailed results including success/failure counts and error messages
    - With -StopOnError, no files are copied if any error occurs
    - File attributes and timestamps are preserved by default
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$SourcePaths,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationDirectory,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [bool]$PreserveTimestamps = $true,
        
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
        destinationDirectory = $null
        copiedFiles = @()
        failedFiles = @()
    }
    
    # Validate mandatory parameters
    if ($null -eq $SourcePaths -or $SourcePaths.Count -eq 0) {
        $status.msg = "Parameter 'SourcePaths' is required but was not provided or is empty"
        return $status
    }
    
    if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
        $status.msg = "Parameter 'DestinationDirectory' is required but was not provided or is empty"
        return $status
    }
    
    try {
        # Normalize destination directory path
        $NormalizedDestination = $DestinationDirectory.Replace('/', '\').TrimEnd('\')
        
        # Check if destination exists as a file
        if (Test-Path -Path $NormalizedDestination -PathType Leaf) {
            $status.msg = "Destination path '$NormalizedDestination' exists as a file, not a directory"
            return $status
        }
        
        # Create destination directory if it doesn't exist
        if (-not (Test-Path -Path $NormalizedDestination -PathType Container)) {
            try {
                Write-Verbose "Creating destination directory: $NormalizedDestination"
                New-Item -Path $NormalizedDestination -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            catch {
                $status.msg = "Failed to create destination directory '$NormalizedDestination': $($_.Exception.Message)"
                return $status
            }
        }
        
        $status.destinationDirectory = (Get-Item -Path $NormalizedDestination).FullName
        
        # Validate all source files first (if StopOnError is specified)
        if ($StopOnError) {
            Write-Verbose "Validating all source files before copying..."
            foreach ($sourcePath in $SourcePaths) {
                if ([string]::IsNullOrWhiteSpace($sourcePath)) {
                    $status.msg = "One of the source paths is null or empty"
                    return $status
                }
                
                $NormalizedSource = $sourcePath.Replace('/', '\').TrimEnd('\')
                
                if (-not (Test-Path -Path $NormalizedSource -PathType Leaf)) {
                    $status.msg = "Source file '$NormalizedSource' does not exist or is not a file"
                    return $status
                }
            }
        }
        
        # Prepare confirmation message
        $ConfirmMessage = "Copy $($SourcePaths.Count) file(s) to '$NormalizedDestination'"
        
        # Attempt to copy all files
        if ($Force -or $PSCmdlet.ShouldProcess($NormalizedDestination, $ConfirmMessage)) {
            
            Write-Verbose "Starting copy operation for $($SourcePaths.Count) file(s)"
            
            $CopiedCount = 0
            $FailedCount = 0
            $TotalSize = 0
            
            foreach ($sourcePath in $SourcePaths) {
                try {
                    # Skip empty paths
                    if ([string]::IsNullOrWhiteSpace($sourcePath)) {
                        Write-Verbose "Skipping empty source path"
                        continue
                    }
                    
                    $NormalizedSource = $sourcePath.Replace('/', '\').TrimEnd('\')
                    
                    # Check if source file exists
                    if (-not (Test-Path -Path $NormalizedSource -PathType Leaf)) {
                        $errorMsg = "Source file '$NormalizedSource' does not exist or is not a file"
                        $status.failedFiles += [PSCustomObject]@{
                            SourcePath = $NormalizedSource
                            Error = $errorMsg
                        }
                        $FailedCount++
                        
                        if ($StopOnError) {
                            $status.msg = $errorMsg
                            $status.successCount = $CopiedCount
                            $status.failureCount = $FailedCount
                            return $status
                        }
                        
                        Write-Verbose "Skipping: $errorMsg"
                        continue
                    }
                    
                    # Get source file info
                    $SourceFile = Get-Item -Path $NormalizedSource -ErrorAction Stop
                    $DestinationPath = Join-Path -Path $NormalizedDestination -ChildPath $SourceFile.Name
                    
                    # Check if destination file exists
                    if ((Test-Path -Path $DestinationPath) -and -not $Force) {
                        $errorMsg = "Destination file '$DestinationPath' already exists. Use -Force to overwrite."
                        $status.failedFiles += [PSCustomObject]@{
                            SourcePath = $NormalizedSource
                            Error = $errorMsg
                        }
                        $FailedCount++
                        
                        if ($StopOnError) {
                            $status.msg = $errorMsg
                            $status.successCount = $CopiedCount
                            $status.failureCount = $FailedCount
                            return $status
                        }
                        
                        Write-Verbose "Skipping: $errorMsg"
                        continue
                    }
                    
                    # Perform the copy
                    Write-Verbose "Copying: $NormalizedSource -> $DestinationPath"
                    Copy-Item -Path $NormalizedSource -Destination $DestinationPath -Force:$Force -ErrorAction Stop
                    
                    # Verify copy
                    if (-not (Test-Path -Path $DestinationPath -PathType Leaf)) {
                        $errorMsg = "Copy operation reported success, but destination file was not created"
                        $status.failedFiles += [PSCustomObject]@{
                            SourcePath = $NormalizedSource
                            Error = $errorMsg
                        }
                        $FailedCount++
                        
                        if ($StopOnError) {
                            $status.msg = $errorMsg
                            $status.successCount = $CopiedCount
                            $status.failureCount = $FailedCount
                            return $status
                        }
                        
                        continue
                    }
                    
                    $DestinationFile = Get-Item -Path $DestinationPath -ErrorAction Stop
                    
                    # Preserve timestamps if requested
                    if ($PreserveTimestamps) {
                        try {
                            $DestinationFile.CreationTime = $SourceFile.CreationTime
                            $DestinationFile.LastWriteTime = $SourceFile.LastWriteTime
                            $DestinationFile.LastAccessTime = $SourceFile.LastAccessTime
                        }
                        catch {
                            Write-Verbose "Warning: Could not preserve timestamps for '$($DestinationFile.Name)'"
                        }
                    }
                    
                    # Record success
                    $status.copiedFiles += [PSCustomObject]@{
                        SourcePath = $SourceFile.FullName
                        DestinationPath = $DestinationFile.FullName
                        SizeBytes = $SourceFile.Length
                    }
                    
                    $CopiedCount++
                    $TotalSize += $SourceFile.Length
                    
                    Write-Verbose "Successfully copied: $($SourceFile.Name) ($($SourceFile.Length) bytes)"
                }
                catch {
                    $errorMsg = "Failed to copy '$sourcePath': $($_.Exception.Message)"
                    $status.failedFiles += [PSCustomObject]@{
                        SourcePath = $sourcePath
                        Error = $errorMsg
                    }
                    $FailedCount++
                    
                    if ($StopOnError) {
                        $status.msg = $errorMsg
                        $status.successCount = $CopiedCount
                        $status.failureCount = $FailedCount
                        return $status
                    }
                    
                    Write-Verbose "Error: $errorMsg"
                }
            }
            
            # Set final statistics
            $status.successCount = $CopiedCount
            $status.failureCount = $FailedCount
            $status.totalSizeBytes = $TotalSize
            
            Write-Verbose "Copy operation completed: $CopiedCount succeeded, $FailedCount failed, Total size: $TotalSize bytes"
            
            # Determine overall success
            if ($FailedCount -eq 0) {
                $status.code = 0
                $status.msg = ""
            }
            elseif ($CopiedCount -gt 0) {
                $status.code = 0
                $status.msg = "Partial success: $CopiedCount file(s) copied, $FailedCount file(s) failed"
            }
            else {
                $status.msg = "All copy operations failed"
            }
        }
        else {
            $status.msg = "Operation cancelled by user"
        }
        
        return $status
    }
    catch {
        $status.msg = "Unexpected error in CopyFiles function: $($_.Exception.Message)"
        return $status
    }
}
