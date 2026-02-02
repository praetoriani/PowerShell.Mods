function CopyDir {
    <#
    .SYNOPSIS
    Copies a complete directory with all its contents to a new location.
    
    .DESCRIPTION
    The CopyDir function recursively copies a directory and all its contents (files and
    subdirectories) to a new location. It validates both source and destination paths,
    provides progress information, handles file conflicts, and reports results through
    a standardized return object. Supports both local and UNC paths.
    
    .PARAMETER SourcePath
    The full path of the source directory to copy. Must be an existing directory.
    Can be a local path (e.g., "C:\SourceFolder") or UNC path (e.g., "\\Server\Share\Folder").
    
    .PARAMETER DestinationPath
    The full path where the directory should be copied to. If the destination exists,
    the source directory will be copied inside it. Parent directories are created
    automatically if they don't exist.
    
    .PARAMETER Force
    Optional switch parameter. When specified, overwrites existing files at the
    destination and creates parent directories if needed. Default is $false.
    
    .PARAMETER ExcludeFiles
    Optional array of file name patterns to exclude from copying. Supports wildcards.
    Example: @("*.tmp", "*.log", "desktop.ini")
    
    .PARAMETER ExcludeDirs
    Optional array of directory name patterns to exclude from copying. Supports wildcards.
    Example: @(".git", ".svn", "node_modules", "bin", "obj")
    
    .EXAMPLE
    CopyDir -SourcePath "C:\Projects\MyApp" -DestinationPath "D:\Backup\MyApp"
    Copies the entire MyApp directory to the backup location.
    
    .EXAMPLE
    CopyDir -SourcePath "C:\Source" -DestinationPath "C:\Destination" -Force
    Copies the directory and overwrites existing files without prompting.
    
    .EXAMPLE
    CopyDir -SourcePath "C:\Data" -DestinationPath "\\Server\Share\Backup" -ExcludeFiles @("*.tmp", "*.log")
    Copies the directory but excludes temporary and log files.
    
    .EXAMPLE
    CopyDir -SourcePath "C:\Project" -DestinationPath "D:\Backup" -ExcludeDirs @(".git", "node_modules")
    Copies the directory but excludes version control and dependency folders.
    
    .EXAMPLE
    $result = CopyDir -SourcePath "C:\Source" -DestinationPath "D:\Backup"
    if ($result.code -eq 0) {
        Write-Host "Copied $($result.filesCopied) files and $($result.directoriesCopied) directories"
        Write-Host "Total size: $($result.totalSizeBytes) bytes"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires read permissions on source and write permissions on destination
    - Copies all files, subdirectories, and attributes recursively
    - Preserves file timestamps and attributes
    - Large directory operations may take significant time
    - Network copies depend on network speed and reliability
    - Progress information is written to Verbose stream
    - If destination directory doesn't exist, it will be created
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
        [string[]]$ExcludeFiles = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeDirs = @()
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        filesCopied = 0
        directoriesCopied = 0
        totalSizeBytes = 0
        destinationPath = $null
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
        $NormalizedSource = $SourcePath.TrimEnd('\', '/')
        $NormalizedDestination = $DestinationPath.TrimEnd('\', '/')
        
        # Check if source directory exists
        if (-not (Test-Path -Path $NormalizedSource -PathType Container)) {
            $status.msg = "Source directory '$NormalizedSource' does not exist or is not a directory"
            return $status
        }
        
        # Check if source is a file instead of directory
        if (Test-Path -Path $NormalizedSource -PathType Leaf) {
            $status.msg = "Source path '$NormalizedSource' is a file, not a directory. Use Copy-Item for files."
            return $status
        }
        
        # Get source directory info
        try {
            $SourceDir = Get-Item -Path $NormalizedSource -ErrorAction Stop
            $SourceDirName = $SourceDir.Name
        }
        catch {
            $status.msg = "Failed to access source directory '$NormalizedSource': $($_.Exception.Message)"
            return $status
        }
        
        # Prevent copying directory into itself
        if ($NormalizedDestination.StartsWith($NormalizedSource + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $status.msg = "Cannot copy directory '$NormalizedSource' into itself or its subdirectory '$NormalizedDestination'"
            return $status
        }
        
        # Determine final destination path
        # If destination exists as a directory, copy source directory inside it
        if (Test-Path -Path $NormalizedDestination -PathType Container) {
            $FinalDestination = Join-Path -Path $NormalizedDestination -ChildPath $SourceDirName
        }
        else {
            $FinalDestination = $NormalizedDestination
        }
        
        # Check if final destination already exists
        if (Test-Path -Path $FinalDestination -PathType Container) {
            if (-not $Force) {
                $status.msg = "Destination directory '$FinalDestination' already exists. Use -Force to merge/overwrite."
                return $status
            }
            Write-Verbose "Destination exists and will be merged (Force parameter specified)"
        }
        
        # Prepare confirmation message
        $ConfirmMessage = "Copy directory '$NormalizedSource' to '$FinalDestination' (including all subdirectories and files)"
        
        # Attempt to copy the directory
        try {
            if ($Force -or $PSCmdlet.ShouldProcess($FinalDestination, $ConfirmMessage)) {
                
                Write-Verbose "Starting copy operation from '$NormalizedSource' to '$FinalDestination'"
                
                # Create destination directory if it doesn't exist
                if (-not (Test-Path -Path $FinalDestination)) {
                    New-Item -Path $FinalDestination -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    Write-Verbose "Created destination directory: $FinalDestination"
                }
                
                # Initialize counters
                $FileCount = 0
                $DirCount = 0
                $TotalSize = 0
                
                # Build exclude parameters for Copy-Item
                $CopyParams = @{
                    Path = "$NormalizedSource\*"
                    Destination = $FinalDestination
                    Recurse = $true
                    Force = $Force
                    ErrorAction = 'Stop'
                }
                
                # Add exclude parameters if provided
                if ($ExcludeFiles.Count -gt 0 -or $ExcludeDirs.Count -gt 0) {
                    $AllExcludes = $ExcludeFiles + $ExcludeDirs
                    $CopyParams['Exclude'] = $AllExcludes
                }
                
                # Perform the copy operation
                Copy-Item @CopyParams
                
                # Count copied items and calculate total size
                Write-Verbose "Calculating copied items..."
                
                try {
                    # Count directories
                    $AllDirs = Get-ChildItem -Path $FinalDestination -Directory -Recurse -Force -ErrorAction SilentlyContinue
                    $DirCount = if ($AllDirs) { $AllDirs.Count } else { 0 }
                    
                    # Count files and calculate size
                    $AllFiles = Get-ChildItem -Path $FinalDestination -File -Recurse -Force -ErrorAction SilentlyContinue
                    if ($AllFiles) {
                        $FileCount = $AllFiles.Count
                        $TotalSize = ($AllFiles | Measure-Object -Property Length -Sum).Sum
                    }
                }
                catch {
                    Write-Verbose "Warning: Could not calculate complete statistics: $($_.Exception.Message)"
                }
                
                # Verify destination was created
                if (-not (Test-Path -Path $FinalDestination -PathType Container)) {
                    $status.msg = "Copy operation reported success, but destination directory '$FinalDestination' was not created"
                    return $status
                }
                
                # Set return values
                $status.filesCopied = $FileCount
                $status.directoriesCopied = $DirCount
                $status.totalSizeBytes = $TotalSize
                $status.destinationPath = $FinalDestination
                
                Write-Verbose "Successfully copied $FileCount files and $DirCount directories ($TotalSize bytes)"
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
            $status.msg = "Failed to copy directory from '$NormalizedSource' to '$FinalDestination': $($_.Exception.Message)"
            return $status
        }
        
        # Success - reset status object
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in CopyDir function: $($_.Exception.Message)"
        return $status
    }
}
