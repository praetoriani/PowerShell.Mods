function CreateNewDir {
    <#
    .SYNOPSIS
    Creates a new directory at the specified path.
    
    .DESCRIPTION
    The CreateNewDir function creates a new directory (folder) at the specified location.
    It validates the path format, checks if the directory already exists, creates parent
    directories if needed, and handles proper error reporting through a standardized
    return object. Supports both local and UNC paths.
    
    .PARAMETER Path
    The full path where the new directory should be created. Can be a local path
    (e.g., "C:\MyFolder\NewFolder") or UNC path (e.g., "\\Server\Share\NewFolder").
    Parent directories will be created automatically if they don't exist.
    
    .PARAMETER Force
    Optional switch parameter. When specified, suppresses confirmation prompts and
    creates all necessary parent directories without asking. Default is $false.
    
    .EXAMPLE
    CreateNewDir -Path "C:\MyApplication\Data"
    Creates the "Data" directory and any necessary parent directories.
    
    .EXAMPLE
    CreateNewDir -Path "C:\Temp\TestFolder" -Force
    Creates the directory without confirmation prompts.
    
    .EXAMPLE
    CreateNewDir -Path "\\Server\Share\NewFolder"
    Creates a directory on a network share (requires appropriate permissions).
    
    .EXAMPLE
    $result = CreateNewDir -Path "C:\Projects\NewProject"
    if ($result.code -eq 0) {
        Write-Host "Directory created: $($result.fullPath)"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to create directories at the specified location
    - Parent directories are created automatically if they don't exist
    - If the directory already exists, the function returns an error
    - Supports both local paths (C:\...) and UNC paths (\\Server\Share\...)
    - Path length must not exceed Windows maximum path length (260 characters by default)
    - Reserved names (CON, PRN, AUX, NUL, COM1-9, LPT1-9) are not allowed
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        fullPath = $null
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $status.msg = "Parameter 'Path' is required but was not provided or is empty"
        return $status
    }
    
    try {
        # Normalize path separators and remove trailing slashes
        $NormalizedPath = $Path.TrimEnd('\', '/')
        
        # Validate path format and check for invalid characters
        $InvalidPathChars = [System.IO.Path]::GetInvalidPathChars()
        foreach ($char in $InvalidPathChars) {
            if ($NormalizedPath.Contains($char)) {
                $status.msg = "Path contains invalid character: '$char'"
                return $status
            }
        }
        
        # Check for reserved Windows names (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
        $DirectoryName = Split-Path -Path $NormalizedPath -Leaf
        $ReservedNames = @('CON', 'PRN', 'AUX', 'NUL', 
                           'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
                           'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
        
        if ($DirectoryName -in $ReservedNames) {
            $status.msg = "Directory name '$DirectoryName' is a reserved Windows name and cannot be used"
            return $status
        }
        
        # Check path length (Windows default max path is 260 characters)
        if ($NormalizedPath.Length -gt 260) {
            $status.msg = "Path length ($($NormalizedPath.Length) characters) exceeds Windows maximum path length (260 characters)"
            return $status
        }
        
        # Validate that path is not just a drive letter
        if ($NormalizedPath -match '^[A-Za-z]:$') {
            $status.msg = "Cannot create a directory with only a drive letter. Please specify a directory name."
            return $status
        }
        
        # Check if directory already exists
        if (Test-Path -Path $NormalizedPath -PathType Container) {
            $status.msg = "Directory '$NormalizedPath' already exists"
            return $status
        }
        
        # Check if path exists as a file (not a directory)
        if (Test-Path -Path $NormalizedPath -PathType Leaf) {
            $status.msg = "A file with the name '$NormalizedPath' already exists. Cannot create directory."
            return $status
        }
        
        # Get parent directory
        $ParentPath = Split-Path -Path $NormalizedPath -Parent
        
        # Check if we need to create parent directories
        $ParentMessage = ""
        if ($ParentPath -and -not (Test-Path -Path $ParentPath)) {
            $ParentMessage = " (including parent directories)"
        }
        
        # Prepare confirmation message
        $ConfirmMessage = "Create directory '$NormalizedPath'$ParentMessage"
        
        # Attempt to create the directory
        try {
            Write-Verbose "Creating directory: $NormalizedPath"
            
            if ($Force) {
                # Force creation without confirmation
                $CreatedDir = New-Item -Path $NormalizedPath -ItemType Directory -Force -ErrorAction Stop
            }
            else {
                # With confirmation (ShouldProcess)
                if ($PSCmdlet.ShouldProcess($NormalizedPath, $ConfirmMessage)) {
                    $CreatedDir = New-Item -Path $NormalizedPath -ItemType Directory -ErrorAction Stop
                }
                else {
                    $status.msg = "Operation cancelled by user"
                    return $status
                }
            }
            
            if ($null -eq $CreatedDir) {
                $status.msg = "Failed to create directory '$NormalizedPath'. New-Item returned null."
                return $status
            }
            
            # Verify the directory was created
            if (-not (Test-Path -Path $NormalizedPath -PathType Container)) {
                $status.msg = "Directory creation reported success, but verification failed for '$NormalizedPath'"
                return $status
            }
            
            # Get the full path of the created directory
            $status.fullPath = $CreatedDir.FullName
            
            Write-Verbose "Successfully created directory: $($status.fullPath)"
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied when creating directory '$NormalizedPath'. Check your permissions."
            return $status
        }
        catch [System.IO.IOException] {
            $status.msg = "I/O error when creating directory '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        catch [System.IO.DirectoryNotFoundException] {
            $status.msg = "Parent directory not found for '$NormalizedPath'. Use -Force to create parent directories automatically."
            return $status
        }
        catch {
            $status.msg = "Failed to create directory '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Success - reset status object
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in CreateNewDir function: $($_.Exception.Message)"
        return $status
    }
}
