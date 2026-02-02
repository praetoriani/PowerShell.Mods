function WriteTextToFile {
    <#
    .SYNOPSIS
    Writes text content to a file with specified encoding.
    
    .DESCRIPTION
    The WriteTextToFile function writes text content to a file with comprehensive
    validation and error handling. It checks if the content is text-based (not binary),
    validates the encoding, creates parent directories if needed, handles existing
    files based on the append/overwrite mode, and reports detailed results through
    a standardized return object.
    
    .PARAMETER Path
    The full path of the file to write to. If the file doesn't exist, it will be
    created. Parent directories are created automatically if they don't exist.
    
    .PARAMETER Content
    The text content to write to the file. Can be a string or array of strings.
    If an array is provided, each element is written as a separate line.
    
    .PARAMETER Encoding
    Optional parameter. The text encoding to use when writing the file.
    Valid values: 'UTF8', 'UTF8BOM', 'UTF8NoBOM', 'UTF32', 'Unicode', 'ASCII', 'ANSI', 'OEM', 'BigEndianUnicode'
    Default is 'UTF8' (UTF-8 with BOM in PowerShell 5.1, without BOM in PowerShell 7+).
    
    .PARAMETER Append
    Optional switch parameter. When specified, appends content to existing file
    instead of overwriting. If file doesn't exist, creates new file. Default is $false.
    
    .PARAMETER Force
    Optional switch parameter. When specified, overwrites readonly files and
    creates the file even if parent directory doesn't exist. Default is $false.
    
    .PARAMETER NoNewline
    Optional switch parameter. When specified, doesn't add a newline character
    at the end of the content. Default is $false (newline is added).
    
    .EXAMPLE
    WriteTextToFile -Path "C:\Logs\app.log" -Content "Application started"
    Writes a single line to the log file (overwrites if exists).
    
    .EXAMPLE
    WriteTextToFile -Path "C:\Data\report.txt" -Content "Error occurred" -Append
    Appends the text to the existing file.
    
    .EXAMPLE
    $lines = @("Line 1", "Line 2", "Line 3")
    WriteTextToFile -Path "C:\Output\data.txt" -Content $lines -Encoding "UTF8NoBOM"
    Writes multiple lines to file with UTF-8 encoding without BOM.
    
    .EXAMPLE
    $result = WriteTextToFile -Path "C:\Config\settings.ini" -Content $configText -Force
    if ($result.code -eq 0) {
        Write-Host "Successfully wrote $($result.bytesWritten) bytes to file"
        Write-Host "Lines written: $($result.lineCount)"
    }
    
    .NOTES
    - Requires write permissions on the file and parent directory
    - Parent directories are created automatically if they don't exist
    - Content is validated to ensure it's text-based (not binary)
    - BOM (Byte Order Mark) behavior depends on PowerShell version and encoding
    - In PowerShell 5.1, UTF8 encoding includes BOM by default
    - In PowerShell 7+, UTF8 encoding excludes BOM by default (use UTF8BOM to include)
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        $Content,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('UTF8', 'UTF8BOM', 'UTF8NoBOM', 'UTF32', 'Unicode', 'ASCII', 'ANSI', 'OEM', 'BigEndianUnicode')]
        [string]$Encoding = 'UTF8',
        
        [Parameter(Mandatory = $false)]
        [switch]$Append,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoNewline
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        path = $null
        bytesWritten = 0
        lineCount = 0
        encoding = $null
        wasAppended = $false
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $status.msg = "Parameter 'Path' is required but was not provided or is empty"
        return $status
    }
    
    if ($null -eq $Content) {
        $status.msg = "Parameter 'Content' is required but was not provided"
        return $status
    }
    
    try {
        # Normalize path
        $NormalizedPath = $Path.Replace('/', '\')
        
        # Validate content is text-based (not binary)
        try {
            # Convert content to string array if it's not already
            if ($Content -is [array]) {
                $TextContent = $Content
                $status.lineCount = $Content.Count
            }
            else {
                $TextContent = $Content.ToString()
                # Count lines in string content
                $status.lineCount = ($TextContent -split "`r`n|`r|`n").Count
            }
            
            # Check for null bytes (indicator of binary content)
            $ContentString = if ($TextContent -is [array]) { $TextContent -join "`n" } else { $TextContent }
            if ($ContentString -match [char]0x00) {
                $status.msg = "Content appears to be binary data. Use Set-Content or [System.IO.File]::WriteAllBytes for binary files."
                return $status
            }
        }
        catch {
            $status.msg = "Failed to validate content: $($_.Exception.Message)"
            return $status
        }
        
        # Check if path points to an existing directory
        if (Test-Path -Path $NormalizedPath -PathType Container) {
            $status.msg = "Path '$NormalizedPath' is an existing directory, not a file"
            return $status
        }
        
        # Ensure parent directory exists
        $ParentDirectory = Split-Path -Path $NormalizedPath -Parent
        if ($ParentDirectory -and -not (Test-Path -Path $ParentDirectory -PathType Container)) {
            try {
                Write-Verbose "Creating parent directory: $ParentDirectory"
                New-Item -Path $ParentDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            catch {
                $status.msg = "Failed to create parent directory '$ParentDirectory': $($_.Exception.Message)"
                return $status
            }
        }
        
        # Check if file exists and is readonly
        if ((Test-Path -Path $NormalizedPath -PathType Leaf) -and -not $Force) {
            $ExistingFile = Get-Item -Path $NormalizedPath -ErrorAction SilentlyContinue
            if ($ExistingFile -and $ExistingFile.IsReadOnly) {
                $status.msg = "File '$NormalizedPath' is readonly. Use -Force to overwrite readonly files."
                return $status
            }
        }
        
        # Prepare confirmation message
        $FileExists = Test-Path -Path $NormalizedPath -PathType Leaf
        $ActionMessage = if ($Append -and $FileExists) { "Append to" } elseif ($FileExists) { "Overwrite" } else { "Create" }
        $ConfirmMessage = "$ActionMessage file '$NormalizedPath' with text content"
        
        # Map encoding names to .NET encoding (PowerShell version compatibility)
        $EncodingMap = @{
            'UTF8' = if ($PSVersionTable.PSVersion.Major -ge 6) { [System.Text.UTF8Encoding]::new($false) } else { [System.Text.Encoding]::UTF8 }
            'UTF8BOM' = [System.Text.UTF8Encoding]::new($true)
            'UTF8NoBOM' = [System.Text.UTF8Encoding]::new($false)
            'UTF32' = [System.Text.Encoding]::UTF32
            'Unicode' = [System.Text.Encoding]::Unicode
            'ASCII' = [System.Text.Encoding]::ASCII
            'ANSI' = [System.Text.Encoding]::Default
            'OEM' = [System.Text.Encoding]::GetEncoding(850)  # DOS/OEM encoding
            'BigEndianUnicode' = [System.Text.Encoding]::BigEndianUnicode
        }
        
        $SelectedEncoding = $EncodingMap[$Encoding]
        $status.encoding = $Encoding
        
        # Attempt to write the file
        try {
            Write-Verbose "Writing text to file: $NormalizedPath (Encoding: $Encoding, Append: $Append)"
            
            if ($PSCmdlet.ShouldProcess($NormalizedPath, $ConfirmMessage)) {
                
                # Build parameters for Out-File or Set-Content
                $WriteParams = @{
                    Path = $NormalizedPath
                    Force = $Force
                    ErrorAction = 'Stop'
                }
                
                # Use Out-File for better control over encoding and newlines
                if ($NoNewline) {
                    $WriteParams['NoNewline'] = $true
                }
                
                if ($Append) {
                    $WriteParams['Append'] = $true
                    $status.wasAppended = $true
                }
                
                # Handle encoding parameter based on PowerShell version
                if ($PSVersionTable.PSVersion.Major -ge 6) {
                    # PowerShell 6+ supports Encoding parameter directly
                    if ($Encoding -eq 'UTF8NoBOM') {
                        $WriteParams['Encoding'] = 'utf8NoBOM'
                    }
                    elseif ($Encoding -eq 'UTF8BOM') {
                        $WriteParams['Encoding'] = 'utf8BOM'
                    }
                    elseif ($Encoding -eq 'ANSI') {
                        $WriteParams['Encoding'] = 'default'
                    }
                    elseif ($Encoding -eq 'OEM') {
                        $WriteParams['Encoding'] = 'oem'
                    }
                    else {
                        $WriteParams['Encoding'] = $Encoding.ToLower()
                    }
                }
                else {
                    # PowerShell 5.1
                    if ($Encoding -eq 'UTF8NoBOM') {
                        # UTF8 without BOM requires special handling in PS 5.1
                        $WriteParams['Encoding'] = 'utf8'
                    }
                    elseif ($Encoding -eq 'UTF8BOM' -or $Encoding -eq 'UTF8') {
                        $WriteParams['Encoding'] = 'utf8'
                    }
                    elseif ($Encoding -eq 'ANSI') {
                        $WriteParams['Encoding'] = 'default'
                    }
                    elseif ($Encoding -eq 'OEM') {
                        $WriteParams['Encoding'] = 'oem'
                    }
                    else {
                        $WriteParams['Encoding'] = $Encoding.ToLower()
                    }
                }
                
                # Write content to file
                $TextContent | Out-File @WriteParams
                
                # For UTF8NoBOM in PowerShell 5.1, remove BOM manually
                if ($Encoding -eq 'UTF8NoBOM' -and $PSVersionTable.PSVersion.Major -lt 6) {
                    try {
                        $FileContent = [System.IO.File]::ReadAllBytes($NormalizedPath)
                        # Check if file starts with UTF-8 BOM (EF BB BF)
                        if ($FileContent.Length -ge 3 -and $FileContent[0] -eq 0xEF -and $FileContent[1] -eq 0xBB -and $FileContent[2] -eq 0xBF) {
                            # Remove BOM
                            $ContentWithoutBOM = $FileContent[3..($FileContent.Length - 1)]
                            [System.IO.File]::WriteAllBytes($NormalizedPath, $ContentWithoutBOM)
                            Write-Verbose "Removed UTF-8 BOM from file"
                        }
                    }
                    catch {
                        Write-Verbose "Warning: Could not remove UTF-8 BOM: $($_.Exception.Message)"
                    }
                }
                
                # Verify file was written
                if (-not (Test-Path -Path $NormalizedPath -PathType Leaf)) {
                    $status.msg = "Write operation reported success, but file '$NormalizedPath' was not created"
                    return $status
                }
                
                # Get file information
                $WrittenFile = Get-Item -Path $NormalizedPath -ErrorAction Stop
                $status.path = $WrittenFile.FullName
                $status.bytesWritten = $WrittenFile.Length
                
                Write-Verbose "Successfully wrote $($status.bytesWritten) bytes to file: $($status.path)"
                Write-Verbose "Lines written: $($status.lineCount), Encoding: $($status.encoding), Appended: $($status.wasAppended)"
            }
            else {
                $status.msg = "Operation cancelled by user"
                return $status
            }
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied writing to file '$NormalizedPath'. Check file and directory permissions."
            return $status
        }
        catch [System.IO.IOException] {
            $status.msg = "I/O error writing to file: $($_.Exception.Message)"
            return $status
        }
        catch {
            $status.msg = "Failed to write text to file '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Success
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in WriteTextToFile function: $($_.Exception.Message)"
        return $status
    }
}
