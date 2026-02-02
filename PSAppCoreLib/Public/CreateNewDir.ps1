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
        Write-Host "Directory created: $($result.data)"
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
    - Returns the full path of the created directory in the data field on success
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty"
    }
    
    try {
        # Normalize path separators and remove trailing slashes
        $NormalizedPath = $Path.TrimEnd('\\', '/')
        
        # Validate path format and check for invalid characters
        $InvalidPathChars = [System.IO.Path]::GetInvalidPathChars()
        foreach ($char in $InvalidPathChars) {
            if ($NormalizedPath.Contains($char)) {
                return OPSreturn -Code -1 -Message "Path contains invalid character: '$char'"
            }
        }
        
        # Check for reserved Windows names (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
        $DirectoryName = Split-Path -Path $NormalizedPath -Leaf
        $ReservedNames = @('CON', 'PRN', 'AUX', 'NUL', 
                           'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
                           'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
        
        if ($DirectoryName -in $ReservedNames) {
            return OPSreturn -Code -1 -Message "Directory name '$DirectoryName' is a reserved Windows name and cannot be used"
        }
        
        # Check path length (Windows default max path is 260 characters)
        if ($NormalizedPath.Length -gt 260) {
            return OPSreturn -Code -1 -Message "Path length ($($NormalizedPath.Length) characters) exceeds Windows maximum path length (260 characters)"
        }
        
        # Validate that path is not just a drive letter
        if ($NormalizedPath -match '^[A-Za-z]:$') {
            return OPSreturn -Code -1 -Message "Cannot create a directory with only a drive letter. Please specify a directory name."
        }
        
        # Check if directory already exists
        if (Test-Path -Path $NormalizedPath -PathType Container) {
            return OPSreturn -Code -1 -Message "Directory '$NormalizedPath' already exists"
        }
        
        # Check if path exists as a file (not a directory)
        if (Test-Path -Path $NormalizedPath -PathType Leaf) {
            return OPSreturn -Code -1 -Message "A file with the name '$NormalizedPath' already exists. Cannot create directory."
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
                    return OPSreturn -Code -1 -Message "Operation cancelled by user"
                }
            }
            
            if ($null -eq $CreatedDir) {
                return OPSreturn -Code -1 -Message "Failed to create directory '$NormalizedPath'. New-Item returned null."
            }
            
            # Verify the directory was created
            if (-not (Test-Path -Path $NormalizedPath -PathType Container)) {
                return OPSreturn -Code -1 -Message "Directory creation reported success, but verification failed for '$NormalizedPath'"
            }
            
            Write-Verbose "Successfully created directory: $($CreatedDir.FullName)"
        }
        catch [System.UnauthorizedAccessException] {
            return OPSreturn -Code -1 -Message "Access denied when creating directory '$NormalizedPath'. Check your permissions."
        }
        catch [System.IO.IOException] {
            return OPSreturn -Code -1 -Message "I/O error when creating directory '$NormalizedPath': $($_.Exception.Message)"
        }
        catch [System.IO.DirectoryNotFoundException] {
            return OPSreturn -Code -1 -Message "Parent directory not found for '$NormalizedPath'. Use -Force to create parent directories automatically."
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to create directory '$NormalizedPath': $($_.Exception.Message)"
        }
        
        # Success - return with full path in data field
        return OPSreturn -Code 0 -Message "" -Data $CreatedDir.FullName
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in CreateNewDir function: $($_.Exception.Message)"
    }
}
