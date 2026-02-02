function ReadTextFile {
    <#
    .SYNOPSIS
    Reads complete text content from a file with specified encoding.
    
    .DESCRIPTION
    The ReadTextFile function reads the entire content of a text-based file with
    comprehensive validation and error handling. It validates that the file exists,
    checks if it's text-based (not binary), detects or uses specified encoding,
    reads the complete file content, and reports detailed results through a
    standardized return object.
    
    .PARAMETER Path
    The full path of the file to read. Must be an existing file with read permissions.
    Supports both local and UNC paths.
    
    .PARAMETER Encoding
    Optional parameter. The text encoding to use when reading the file.
    Valid values: 'UTF8', 'UTF8BOM', 'UTF8NoBOM', 'UTF32', 'Unicode', 'ASCII', 'ANSI', 'OEM', 'BigEndianUnicode', 'Auto'
    Default is 'Auto' (automatically detects encoding based on BOM or defaults to UTF-8).
    
    .PARAMETER Raw
    Optional switch parameter. When specified, returns content as a single string
    instead of array of lines. Preserves original line endings. Default is $false.
    
    .PARAMETER MaxSizeBytes
    Optional parameter. Maximum file size in bytes to read. Files larger than this
    value will return an error. Default is 100MB (104857600 bytes).
    Use this to prevent accidentally reading very large files into memory.
    
    .PARAMETER ValidateText
    Optional switch parameter. When specified, validates that file contains only
    text (no null bytes or binary content). Default is $true.
    
    .EXAMPLE
    ReadTextFile -Path "C:\Logs\app.log"
    Reads the complete log file with automatic encoding detection.
    
    .EXAMPLE
    $result = ReadTextFile -Path "C:\Config\settings.ini" -Encoding "UTF8NoBOM"
    $settings = $result.content
    Reads configuration file with specific UTF-8 encoding without BOM.
    
    .EXAMPLE
    $result = ReadTextFile -Path "C:\Data\large.txt" -Raw
    $fullText = $result.content
    Reads the entire file as a single string preserving line endings.
    
    .EXAMPLE
    $result = ReadTextFile -Path "C:\Data\file.txt" -MaxSizeBytes 1MB
    if ($result.code -eq 0) {
        Write-Host "Read $($result.lineCount) lines ($($result.sizeBytes) bytes)"
        Write-Host "Detected encoding: $($result.encoding)"
        foreach ($line in $result.content) {
            Write-Host $line
        }
    }
    
    .NOTES
    - Requires read permissions on the file
    - Automatically detects UTF-8, UTF-16 LE, UTF-16 BE, UTF-32 based on BOM
    - For files without BOM, defaults to UTF-8 when encoding is 'Auto'
    - Binary files (containing null bytes) are rejected by default
    - Large files can consume significant memory - use MaxSizeBytes to prevent issues
    - Returns content as array of lines by default, or single string with -Raw
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('UTF8', 'UTF8BOM', 'UTF8NoBOM', 'UTF32', 'Unicode', 'ASCII', 'ANSI', 'OEM', 'BigEndianUnicode', 'Auto')]
        [string]$Encoding = 'Auto',
        
        [Parameter(Mandatory = $false)]
        [switch]$Raw,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [long]::MaxValue)]
        [long]$MaxSizeBytes = 104857600,  # 100 MB default
        
        [Parameter(Mandatory = $false)]
        [bool]$ValidateText = $true
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        path = $null
        content = $null
        lineCount = 0
        sizeBytes = 0
        encoding = $null
        detectedEncoding = $null
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $status.msg = "Parameter 'Path' is required but was not provided or is empty"
        return $status
    }
    
    try {
        # Normalize path
        $NormalizedPath = $Path.Replace('/', '\')
        
        # Check if file exists
        if (-not (Test-Path -Path $NormalizedPath -PathType Leaf)) {
            $status.msg = "File '$NormalizedPath' does not exist or is not a file"
            return $status
        }
        
        # Check if path is a directory instead of file
        if (Test-Path -Path $NormalizedPath -PathType Container) {
            $status.msg = "Path '$NormalizedPath' is a directory, not a file"
            return $status
        }
        
        # Get file information
        try {
            $FileItem = Get-Item -Path $NormalizedPath -ErrorAction Stop
            $status.path = $FileItem.FullName
            $status.sizeBytes = $FileItem.Length
        }
        catch {
            $status.msg = "Failed to access file '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Check file size
        if ($FileItem.Length -gt $MaxSizeBytes) {
            $status.msg = "File size ($($FileItem.Length) bytes) exceeds maximum allowed size ($MaxSizeBytes bytes). Use larger MaxSizeBytes value if needed."
            return $status
        }
        
        # Check for empty file
        if ($FileItem.Length -eq 0) {
            Write-Verbose "File is empty: $NormalizedPath"
            $status.content = if ($Raw) { "" } else { @() }
            $status.lineCount = 0
            $status.encoding = $Encoding
            $status.code = 0
            $status.msg = ""
            return $status
        }
        
        # Detect encoding if Auto is specified
        $DetectedEncoding = $null
        if ($Encoding -eq 'Auto') {
            Write-Verbose "Auto-detecting file encoding..."
            
            try {
                # Read first few bytes to check for BOM
                $FileStream = [System.IO.File]::OpenRead($FileItem.FullName)
                $BOMBytes = New-Object byte[] 4
                $BytesRead = $FileStream.Read($BOMBytes, 0, 4)
                $FileStream.Close()
                
                # Check for BOM signatures
                if ($BytesRead -ge 3 -and $BOMBytes[0] -eq 0xEF -and $BOMBytes[1] -eq 0xBB -and $BOMBytes[2] -eq 0xBF) {
                    $DetectedEncoding = 'UTF8BOM'
                    Write-Verbose "Detected UTF-8 with BOM"
                }
                elseif ($BytesRead -ge 4 -and $BOMBytes[0] -eq 0xFF -and $BOMBytes[1] -eq 0xFE -and $BOMBytes[2] -eq 0x00 -and $BOMBytes[3] -eq 0x00) {
                    $DetectedEncoding = 'UTF32'
                    Write-Verbose "Detected UTF-32 LE"
                }
                elseif ($BytesRead -ge 2 -and $BOMBytes[0] -eq 0xFF -and $BOMBytes[1] -eq 0xFE) {
                    $DetectedEncoding = 'Unicode'
                    Write-Verbose "Detected UTF-16 LE (Unicode)"
                }
                elseif ($BytesRead -ge 2 -and $BOMBytes[0] -eq 0xFE -and $BOMBytes[1] -eq 0xFF) {
                    $DetectedEncoding = 'BigEndianUnicode'
                    Write-Verbose "Detected UTF-16 BE"
                }
                else {
                    # No BOM detected - default to UTF-8 without BOM
                    $DetectedEncoding = 'UTF8NoBOM'
                    Write-Verbose "No BOM detected, defaulting to UTF-8"
                }
                
                $Encoding = $DetectedEncoding
                $status.detectedEncoding = $DetectedEncoding
            }
            catch {
                Write-Verbose "Warning: Could not detect encoding, defaulting to UTF-8: $($_.Exception.Message)"
                $Encoding = 'UTF8'
                $status.detectedEncoding = 'UTF8 (fallback)'
            }
        }
        
        $status.encoding = $Encoding
        
        # Validate file is text-based if requested
        if ($ValidateText) {
            Write-Verbose "Validating file contains text data..."
            try {
                # Read a sample of the file to check for null bytes
                $SampleSize = [Math]::Min(8192, $FileItem.Length)  # Read first 8KB or entire file
                $FileStream = [System.IO.File]::OpenRead($FileItem.FullName)
                $SampleBytes = New-Object byte[] $SampleSize
                $BytesRead = $FileStream.Read($SampleBytes, 0, $SampleSize)
                $FileStream.Close()
                
                # Check for null bytes (strong indicator of binary content)
                $NullByteCount = ($SampleBytes | Where-Object { $_ -eq 0 }).Count
                if ($NullByteCount -gt 0) {
                    $status.msg = "File '$NormalizedPath' appears to be binary (contains $NullByteCount null bytes in first $BytesRead bytes). Set -ValidateText `$false to read anyway."
                    return $status
                }
                
                Write-Verbose "File validation passed (no null bytes detected)"
            }
            catch {
                Write-Verbose "Warning: Could not validate file content: $($_.Exception.Message)"
            }
        }
        
        # Map encoding names to .NET encoding
        $EncodingMap = @{
            'UTF8' = if ($PSVersionTable.PSVersion.Major -ge 6) { [System.Text.UTF8Encoding]::new($false) } else { [System.Text.Encoding]::UTF8 }
            'UTF8BOM' = [System.Text.UTF8Encoding]::new($true)
            'UTF8NoBOM' = [System.Text.UTF8Encoding]::new($false)
            'UTF32' = [System.Text.Encoding]::UTF32
            'Unicode' = [System.Text.Encoding]::Unicode
            'ASCII' = [System.Text.Encoding]::ASCII
            'ANSI' = [System.Text.Encoding]::Default
            'OEM' = [System.Text.Encoding]::GetEncoding(850)
            'BigEndianUnicode' = [System.Text.Encoding]::BigEndianUnicode
        }
        
        # Attempt to read the file
        try {
            Write-Verbose "Reading file: $NormalizedPath (Encoding: $Encoding, Raw: $Raw)"
            
            # Build parameters for Get-Content
            $ReadParams = @{
                Path = $NormalizedPath
                ErrorAction = 'Stop'
            }
            
            if ($Raw) {
                $ReadParams['Raw'] = $true
            }
            
            # Handle encoding parameter based on PowerShell version
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                # PowerShell 6+
                if ($Encoding -eq 'UTF8NoBOM') {
                    $ReadParams['Encoding'] = 'utf8NoBOM'
                }
                elseif ($Encoding -eq 'UTF8BOM') {
                    $ReadParams['Encoding'] = 'utf8BOM'
                }
                elseif ($Encoding -eq 'ANSI') {
                    $ReadParams['Encoding'] = 'default'
                }
                elseif ($Encoding -eq 'OEM') {
                    $ReadParams['Encoding'] = 'oem'
                }
                else {
                    $ReadParams['Encoding'] = $Encoding.ToLower()
                }
            }
            else {
                # PowerShell 5.1
                if ($Encoding -eq 'UTF8NoBOM' -or $Encoding -eq 'UTF8BOM' -or $Encoding -eq 'UTF8') {
                    $ReadParams['Encoding'] = 'utf8'
                }
                elseif ($Encoding -eq 'ANSI') {
                    $ReadParams['Encoding'] = 'default'
                }
                elseif ($Encoding -eq 'OEM') {
                    $ReadParams['Encoding'] = 'oem'
                }
                else {
                    $ReadParams['Encoding'] = $Encoding.ToLower()
                }
            }
            
            # Read content from file
            $FileContent = Get-Content @ReadParams
            
            $status.content = $FileContent
            
            # Count lines if not raw
            if ($Raw) {
                $status.lineCount = ($FileContent -split "`r`n|`r|`n").Count
            }
            else {
                $status.lineCount = if ($FileContent -is [array]) { $FileContent.Count } else { 1 }
            }
            
            Write-Verbose "Successfully read $($status.sizeBytes) bytes from file: $($status.path)"
            Write-Verbose "Lines: $($status.lineCount), Encoding: $($status.encoding)"
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied reading file '$NormalizedPath'. Check file permissions."
            return $status
        }
        catch [System.IO.IOException] {
            $status.msg = "I/O error reading file: $($_.Exception.Message)"
            return $status
        }
        catch {
            $status.msg = "Failed to read file '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Success
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in ReadTextFile function: $($_.Exception.Message)"
        return $status
    }
}
