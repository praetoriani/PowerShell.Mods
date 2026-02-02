function CopyFile {
    <#
    .SYNOPSIS
    Copies a single file to a new location.
    
    .DESCRIPTION
    The CopyFile function copies a single file from a source location to a destination.
    It validates both source and destination paths, checks file existence, handles
    overwrite scenarios, preserves file attributes and timestamps, and reports results
    through a standardized return object. Supports both local and UNC paths.
    
    .PARAMETER SourcePath
    The full path of the source file to copy. Must be an existing file.
    Can be a local path (e.g., "C:\Source\file.txt") or UNC path (e.g., "\\Server\Share\file.txt").
    
    .PARAMETER DestinationPath
    The full path where the file should be copied to. Can be either:
    - A full file path (e.g., "C:\Destination\newfile.txt")
    - A directory path (file will be copied with same name)
    Parent directories are created automatically if they don't exist.
    
    .PARAMETER Force
    Optional switch parameter. When specified, overwrites existing files at the
    destination without prompting. Default is $false.
    
    .PARAMETER PreserveTimestamps
    Optional switch parameter. When specified, preserves the original file's
    creation time, last write time, and last access time. Default is $true.
    
    .EXAMPLE
    CopyFile -SourcePath "C:\Source\document.pdf" -DestinationPath "D:\Backup\document.pdf"
    Copies the PDF file to the backup location.
    
    .EXAMPLE
    CopyFile -SourcePath "C:\Data\report.xlsx" -DestinationPath "D:\Archive\" -Force
    Copies the file to the Archive directory and overwrites if it exists.
    
    .EXAMPLE
    CopyFile -SourcePath "\\Server\Share\file.txt" -DestinationPath "C:\Local\file.txt"
    Copies a file from a network share to local disk.
    
    .EXAMPLE
    $result = CopyFile -SourcePath "C:\Source\data.db" -DestinationPath "D:\Backup\"
    if ($result.code -eq 0) {
        Write-Host "File copied successfully"
        Write-Host "Source: $($result.sourcePath)"
        Write-Host "Destination: $($result.destinationPath)"
        Write-Host "Size: $($result.sizeBytes) bytes"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires read permissions on source and write permissions on destination
    - If destination is a directory, the source filename is preserved
    - Parent directories are created automatically if needed
    - File attributes (hidden, readonly, system, archive) are preserved
    - Timestamps are preserved by default
    - If destination file exists, returns error unless -Force is specified
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [bool]$PreserveTimestamps = $true
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        sourcePath = $null
        destinationPath = $null
        sizeBytes = 0
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $status.msg = "Parameter 'SourcePath' is required but was not provided or is empty"
        return $status
    }
    
    if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        $status.msg = "Parameter 'DestinationPath' is required but was not provided or is empty"
        return $status
    }
    
    try {
        # Normalize paths
        $NormalizedSource = $SourcePath.Replace('/', '\').TrimEnd('\')
        $NormalizedDestination = $DestinationPath.Replace('/', '\').TrimEnd('\')
        
        # Check if source file exists
        if (-not (Test-Path -Path $NormalizedSource -PathType Leaf)) {
            $status.msg = "Source file '$NormalizedSource' does not exist or is not a file"
            return $status
        }
        
        # Check if source is a directory instead of file
        if (Test-Path -Path $NormalizedSource -PathType Container) {
            $status.msg = "Source path '$NormalizedSource' is a directory, not a file. Use CopyDir for directories."
            return $status
        }
        
        # Get source file information
        try {
            $SourceFile = Get-Item -Path $NormalizedSource -ErrorAction Stop
            $status.sourcePath = $SourceFile.FullName
            $status.sizeBytes = $SourceFile.Length
        }
        catch {
            $status.msg = "Failed to access source file '$NormalizedSource': $($_.Exception.Message)"
            return $status
        }
        
        # Determine if destination is a directory or file path
        $DestinationIsDirectory = $false
        $FinalDestination = $NormalizedDestination
        
        if (Test-Path -Path $NormalizedDestination -PathType Container) {
            # Destination exists and is a directory - append source filename
            $DestinationIsDirectory = $true
            $FinalDestination = Join-Path -Path $NormalizedDestination -ChildPath $SourceFile.Name
        }
        elseif ($NormalizedDestination.EndsWith('\')) {
            # Destination ends with backslash - treat as directory
            $DestinationIsDirectory = $true
            $FinalDestination = Join-Path -Path $NormalizedDestination -ChildPath $SourceFile.Name
        }
        elseif (-not [System.IO.Path]::HasExtension($NormalizedDestination)) {
            # No extension - could be a directory that doesn't exist yet
            # Check if parent exists as a clue
            $ParentPath = Split-Path -Path $NormalizedDestination -Parent
            if ($ParentPath -and (Test-Path -Path $ParentPath -PathType Container)) {
                # Parent exists - assume destination is a filename without extension
                $FinalDestination = $NormalizedDestination
            }
            else {
                # Ambiguous - treat as directory to be created
                $DestinationIsDirectory = $true
                $FinalDestination = Join-Path -Path $NormalizedDestination -ChildPath $SourceFile.Name
            }
        }
        
        # Prevent copying file to itself
        if ($SourceFile.FullName -eq [System.IO.Path]::GetFullPath($FinalDestination)) {
            $status.msg = "Cannot copy file '$($SourceFile.FullName)' to itself"
            return $status
        }
        
        # Check if destination file already exists
        $DestinationExists = Test-Path -Path $FinalDestination -PathType Leaf
        if ($DestinationExists -and -not $Force) {
            $status.msg = "Destination file '$FinalDestination' already exists. Use -Force to overwrite."
            return $status
        }
        
        # Ensure destination parent directory exists
        $DestinationParent = Split-Path -Path $FinalDestination -Parent
        if ($DestinationParent -and -not (Test-Path -Path $DestinationParent -PathType Container)) {
            try {
                Write-Verbose "Creating destination directory: $DestinationParent"
                New-Item -Path $DestinationParent -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            catch {
                $status.msg = "Failed to create destination directory '$DestinationParent': $($_.Exception.Message)"
                return $status
            }
        }
        
        # Prepare confirmation message
        $ActionMessage = if ($DestinationExists) { "Overwrite" } else { "Copy" }
        $ConfirmMessage = "$ActionMessage file '$NormalizedSource' to '$FinalDestination'"
        
        # Attempt to copy the file
        try {
            Write-Verbose "Copying file: $NormalizedSource -> $FinalDestination"
            
            if ($Force -or $PSCmdlet.ShouldProcess($FinalDestination, $ConfirmMessage)) {
                
                # Perform the copy
                Copy-Item -Path $NormalizedSource -Destination $FinalDestination -Force:$Force -ErrorAction Stop
                
                # Verify the file was copied
                if (-not (Test-Path -Path $FinalDestination -PathType Leaf)) {
                    $status.msg = "Copy operation reported success, but destination file '$FinalDestination' was not created"
                    return $status
                }
                
                # Get destination file info
                $DestinationFile = Get-Item -Path $FinalDestination -ErrorAction Stop
                
                # Preserve timestamps if requested
                if ($PreserveTimestamps) {
                    try {
                        $DestinationFile.CreationTime = $SourceFile.CreationTime
                        $DestinationFile.LastWriteTime = $SourceFile.LastWriteTime
                        $DestinationFile.LastAccessTime = $SourceFile.LastAccessTime
                        Write-Verbose "Preserved file timestamps"
                    }
                    catch {
                        Write-Verbose "Warning: Could not preserve all timestamps: $($_.Exception.Message)"
                    }
                }
                
                # Verify file size matches
                if ($DestinationFile.Length -ne $SourceFile.Length) {
                    $status.msg = "File copied but size mismatch detected. Source: $($SourceFile.Length) bytes, Destination: $($DestinationFile.Length) bytes"
                    return $status
                }
                
                $status.destinationPath = $DestinationFile.FullName
                
                Write-Verbose "Successfully copied file: $($status.sourcePath) -> $($status.destinationPath) ($($status.sizeBytes) bytes)"
            }
            else {
                $status.msg = "Operation cancelled by user"
                return $status
            }
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied during copy operation. Check permissions on source '$NormalizedSource' and destination '$FinalDestination'."
            return $status
        }
        catch [System.IO.IOException] {
            $status.msg = "I/O error during copy operation: $($_.Exception.Message)"
            return $status
        }
        catch {
            $status.msg = "Failed to copy file from '$NormalizedSource' to '$FinalDestination': $($_.Exception.Message)"
            return $status
        }
        
        # Success - reset status object
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in CopyFile function: $($_.Exception.Message)"
        return $status
    }
}
