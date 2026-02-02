function CreateNewFile {
    <#
    .SYNOPSIS
    Creates a new file at the specified path.
    
    .DESCRIPTION
    The CreateNewFile function creates a new file at the specified location. It validates
    the path format, checks if the file already exists, ensures the parent directory exists,
    optionally writes initial content, and handles proper error reporting through a
    standardized return object. Supports both text and binary content.
    
    .PARAMETER Path
    The full path including filename where the new file should be created.
    Can be a local path (e.g., "C:\MyFolder\file.txt") or UNC path.
    The parent directory must exist or use -Force to create it automatically.
    
    .PARAMETER Content
    Optional initial content to write to the file. Can be a string, string array,
    or byte array. If not specified, an empty file is created. For text content,
    UTF-8 encoding is used by default.
    
    .PARAMETER Encoding
    Optional encoding for text content. Valid values are: UTF8, UTF7, UTF32, Unicode,
    BigEndianUnicode, ASCII, Default. Default is UTF8. Ignored for byte array content.
    
    .PARAMETER Force
    Optional switch parameter. When specified, overwrites existing files and creates
    parent directories if they don't exist. Default is $false.
    
    .EXAMPLE
    CreateNewFile -Path "C:\Logs\application.log"
    Creates an empty log file.
    
    .EXAMPLE
    CreateNewFile -Path "C:\Data\config.txt" -Content "Setting1=Value1"
    Creates a text file with initial content.
    
    .EXAMPLE
    CreateNewFile -Path "C:\Temp\data.txt" -Content @("Line 1", "Line 2", "Line 3")
    Creates a text file with multiple lines.
    
    .EXAMPLE
    $binaryData = [byte[]](0x50, 0x4B, 0x03, 0x04)
    CreateNewFile -Path "C:\Temp\file.bin" -Content $binaryData
    Creates a binary file with byte array content.
    
    .EXAMPLE
    CreateNewFile -Path "C:\Projects\NewFolder\readme.md" -Content "# Project" -Force
    Creates the file and parent directory if it doesn't exist.
    
    .EXAMPLE
    $result = CreateNewFile -Path "C:\Temp\test.txt" -Content "Test" -Encoding "ASCII"
    if ($result.code -eq 0) {
        Write-Host "File created: $($result.fullPath)"
        Write-Host "Size: $($result.sizeBytes) bytes"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to create files at the specified location
    - Parent directory must exist unless -Force is specified
    - If the file already exists, the function returns an error unless -Force is used
    - For text content, UTF-8 encoding without BOM is used by default
    - Binary content (byte arrays) is written directly without encoding
    - Path length must not exceed Windows maximum path length (260 characters by default)
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [object]$Content = $null,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("UTF8", "UTF7", "UTF32", "Unicode", "BigEndianUnicode", "ASCII", "Default")]
        [string]$Encoding = "UTF8",
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        fullPath = $null
        sizeBytes = 0
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $status.msg = "Parameter 'Path' is required but was not provided or is empty"
        return $status
    }
    
    try {
        # Normalize path separators
        $NormalizedPath = $Path.Replace('/', '\')
        
        # Validate path format and check for invalid characters
        $InvalidPathChars = [System.IO.Path]::GetInvalidPathChars()
        foreach ($char in $InvalidPathChars) {
            if ($NormalizedPath.Contains($char)) {
                $status.msg = "Path contains invalid character: '$char'"
                return $status
            }
        }
        
        # Validate filename
        try {
            $FileName = Split-Path -Path $NormalizedPath -Leaf
            $InvalidFileNameChars = [System.IO.Path]::GetInvalidFileNameChars()
            foreach ($char in $InvalidFileNameChars) {
                if ($FileName.Contains($char)) {
                    $status.msg = "Filename contains invalid character: '$char'"
                    return $status
                }
            }
        }
        catch {
            $status.msg = "Invalid path format: $($_.Exception.Message)"
            return $status
        }
        
        # Check for reserved Windows names
        $FileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
        $ReservedNames = @('CON', 'PRN', 'AUX', 'NUL', 
                           'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
                           'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
        
        if ($FileNameWithoutExt.ToUpper() -in $ReservedNames) {
            $status.msg = "Filename '$FileName' uses a reserved Windows name and cannot be used"
            return $status
        }
        
        # Check path length
        if ($NormalizedPath.Length -gt 260) {
            $status.msg = "Path length ($($NormalizedPath.Length) characters) exceeds Windows maximum path length (260 characters)"
            return $status
        }
        
        # Check if file already exists
        if (Test-Path -Path $NormalizedPath -PathType Leaf) {
            if (-not $Force) {
                $status.msg = "File '$NormalizedPath' already exists. Use -Force to overwrite."
                return $status
            }
            Write-Verbose "File exists and will be overwritten (Force parameter specified)"
        }
        
        # Check if path exists as a directory
        if (Test-Path -Path $NormalizedPath -PathType Container) {
            $status.msg = "A directory with the name '$NormalizedPath' already exists. Cannot create file."
            return $status
        }
        
        # Get parent directory
        $ParentPath = Split-Path -Path $NormalizedPath -Parent
        
        # Check if parent directory exists
        if ($ParentPath -and -not (Test-Path -Path $ParentPath -PathType Container)) {
            if ($Force) {
                try {
                    Write-Verbose "Creating parent directory: $ParentPath"
                    New-Item -Path $ParentPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
                catch {
                    $status.msg = "Failed to create parent directory '$ParentPath': $($_.Exception.Message)"
                    return $status
                }
            }
            else {
                $status.msg = "Parent directory '$ParentPath' does not exist. Use -Force to create it automatically."
                return $status
            }
        }
        
        # Prepare confirmation message
        $ActionMessage = if (Test-Path -Path $NormalizedPath) { "Overwrite" } else { "Create" }
        $ContentInfo = if ($null -eq $Content) { " (empty file)" } else { " with content" }
        $ConfirmMessage = "$ActionMessage file '$NormalizedPath'$ContentInfo"
        
        # Attempt to create the file
        try {
            Write-Verbose "Creating file: $NormalizedPath"
            
            if ($Force -or $PSCmdlet.ShouldProcess($NormalizedPath, $ConfirmMessage)) {
                
                # Determine content type and write accordingly
                if ($null -eq $Content) {
                    # Create empty file
                    $CreatedFile = New-Item -Path $NormalizedPath -ItemType File -Force:$Force -ErrorAction Stop
                }
                elseif ($Content -is [byte[]]) {
                    # Binary content - write bytes directly
                    [System.IO.File]::WriteAllBytes($NormalizedPath, $Content)
                    $CreatedFile = Get-Item -Path $NormalizedPath -ErrorAction Stop
                }
                elseif ($Content -is [array]) {
                    # String array - write as multiple lines
                    $Content | Out-File -FilePath $NormalizedPath -Encoding $Encoding -Force:$Force -ErrorAction Stop
                    $CreatedFile = Get-Item -Path $NormalizedPath -ErrorAction Stop
                }
                else {
                    # Single string or other content - convert to string and write
                    [string]$Content | Out-File -FilePath $NormalizedPath -Encoding $Encoding -Force:$Force -ErrorAction Stop
                    $CreatedFile = Get-Item -Path $NormalizedPath -ErrorAction Stop
                }
                
                if ($null -eq $CreatedFile) {
                    $status.msg = "Failed to create file '$NormalizedPath'. Operation returned null."
                    return $status
                }
                
                # Verify the file was created
                if (-not (Test-Path -Path $NormalizedPath -PathType Leaf)) {
                    $status.msg = "File creation reported success, but verification failed for '$NormalizedPath'"
                    return $status
                }
                
                # Get file information
                $FileInfo = Get-Item -Path $NormalizedPath -ErrorAction Stop
                $status.fullPath = $FileInfo.FullName
                $status.sizeBytes = $FileInfo.Length
                
                Write-Verbose "Successfully created file: $($status.fullPath) ($($status.sizeBytes) bytes)"
            }
            else {
                $status.msg = "Operation cancelled by user"
                return $status
            }
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied when creating file '$NormalizedPath'. Check your permissions."
            return $status
        }
        catch [System.IO.IOException] {
            $status.msg = "I/O error when creating file '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        catch {
            $status.msg = "Failed to create file '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Success - reset status object
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in CreateNewFile function: $($_.Exception.Message)"
        return $status
    }
}
