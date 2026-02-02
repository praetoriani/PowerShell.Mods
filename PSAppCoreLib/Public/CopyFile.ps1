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
    CopyFile -SourcePath "C:\Data\report.xlsx" -DestinationPath "D:\Archive\\" -Force
    Copies the file to the Archive directory and overwrites if it exists.
    
    .EXAMPLE
    CopyFile -SourcePath "\\Server\Share\file.txt" -DestinationPath "C:\Local\file.txt"
    Copies a file from a network share to local disk.
    
    .EXAMPLE
    $result = CopyFile -SourcePath "C:\Source\data.db" -DestinationPath "D:\Backup\\"
    if ($result.code -eq 0) {
        Write-Host "File copied successfully"
        Write-Host "Source: $($result.data.SourcePath)"
        Write-Host "Destination: $($result.data.DestinationPath)"
        Write-Host "Size: $($result.data.SizeBytes) bytes"
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
    - Returns file paths and size in the data field on success
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
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return OPSreturn -Code -1 -Message "Parameter 'SourcePath' is required but was not provided or is empty"
    }
    
    if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        return OPSreturn -Code -1 -Message "Parameter 'DestinationPath' is required but was not provided or is empty"
    }
    
    try {
        # Normalize paths
        $NormalizedSource = $SourcePath.Replace('/', '\\').TrimEnd('\\')
        $NormalizedDestination = $DestinationPath.Replace('/', '\\').TrimEnd('\\')
        
        # Check if source file exists
        if (-not (Test-Path -Path $NormalizedSource -PathType Leaf)) {
            return OPSreturn -Code -1 -Message "Source file '$NormalizedSource' does not exist or is not a file"
        }
        
        # Check if source is a directory instead of file
        if (Test-Path -Path $NormalizedSource -PathType Container) {
            return OPSreturn -Code -1 -Message "Source path '$NormalizedSource' is a directory, not a file. Use CopyDir for directories."
        }
        
        # Get source file information
        try {
            $SourceFile = Get-Item -Path $NormalizedSource -ErrorAction Stop
            $SourceFullPath = $SourceFile.FullName
            $FileSizeBytes = $SourceFile.Length
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to access source file '$NormalizedSource': $($_.Exception.Message)"
        }
        
        # Determine if destination is a directory or file path
        $DestinationIsDirectory = $false
        $FinalDestination = $NormalizedDestination
        
        if (Test-Path -Path $NormalizedDestination -PathType Container) {
            # Destination exists and is a directory - append source filename
            $DestinationIsDirectory = $true
            $FinalDestination = Join-Path -Path $NormalizedDestination -ChildPath $SourceFile.Name
        }
        elseif ($NormalizedDestination.EndsWith('\\')) {
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
            return OPSreturn -Code -1 -Message "Cannot copy file '$($SourceFile.FullName)' to itself"
        }
        
        # Check if destination file already exists
        $DestinationExists = Test-Path -Path $FinalDestination -PathType Leaf
        if ($DestinationExists -and -not $Force) {
            return OPSreturn -Code -1 -Message "Destination file '$FinalDestination' already exists. Use -Force to overwrite."
        }
        
        # Ensure destination parent directory exists
        $DestinationParent = Split-Path -Path $FinalDestination -Parent
        if ($DestinationParent -and -not (Test-Path -Path $DestinationParent -PathType Container)) {
            try {
                Write-Verbose "Creating destination directory: $DestinationParent"
                New-Item -Path $DestinationParent -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            catch {
                return OPSreturn -Code -1 -Message "Failed to create destination directory '$DestinationParent': $($_.Exception.Message)"
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
                    return OPSreturn -Code -1 -Message "Copy operation reported success, but destination file '$FinalDestination' was not created"
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
                    return OPSreturn -Code -1 -Message "File copied but size mismatch detected. Source: $($SourceFile.Length) bytes, Destination: $($DestinationFile.Length) bytes"
                }
                
                Write-Verbose "Successfully copied file: $SourceFullPath -> $($DestinationFile.FullName) ($FileSizeBytes bytes)"
                
                # Prepare return data object with file information
                $ReturnData = [PSCustomObject]@{
                    SourcePath      = $SourceFullPath
                    DestinationPath = $DestinationFile.FullName
                    SizeBytes       = $FileSizeBytes
                }
            }
            else {
                return OPSreturn -Code -1 -Message "Operation cancelled by user"
            }
        }
        catch [System.UnauthorizedAccessException] {
            return OPSreturn -Code -1 -Message "Access denied during copy operation. Check permissions on source '$NormalizedSource' and destination '$FinalDestination'."
        }
        catch [System.IO.IOException] {
            return OPSreturn -Code -1 -Message "I/O error during copy operation: $($_.Exception.Message)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to copy file from '$NormalizedSource' to '$FinalDestination': $($_.Exception.Message)"
        }
        
        # Success - return with file information in data field
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in CopyFile function: $($_.Exception.Message)"
    }
}
