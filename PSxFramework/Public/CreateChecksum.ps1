function CreateChecksum {
    <#
    .SYNOPSIS
    Creates a SHA256 or SHA512 checksum file for a given input file.
    
    .DESCRIPTION
    The CreateChecksum function generates a cryptographic hash (SHA256 or SHA512) for a specified
    file and saves it to a .checksum.txt file. The output file contains the hash value, input file
    path, and a timestamp. This is useful for verifying file integrity and detecting tampering.
    
    .PARAMETER InputFile
    Full path to the file for which the checksum should be created.
    The file must exist.
    This parameter is mandatory.
    
    .PARAMETER SHA
    Specifies the SHA algorithm to use. Valid values are 256 or 512.
    Default is 256 (SHA256).
    This parameter is optional.
    
    .PARAMETER OutputPath
    Full path to the directory where the checksum file will be saved.
    If not specified or if the path doesn't exist, the checksum file will be created
    in the same directory as the input file.
    This parameter is optional.
    
    .EXAMPLE
    $result = CreateChecksum -InputFile "C:\Release\MyApp.exe"
    if ($result.code -eq 0) {
        Write-Host "Checksum created: $($result.data)"
    }
    Creates MyApp.checksum.txt with SHA256 hash in the same directory.
    
    .EXAMPLE
    CreateChecksum -InputFile "C:\Release\MyApp.exe" -SHA 512 -OutputPath "C:\Checksums"
    Creates MyApp.checksum.txt with SHA512 hash in C:\Checksums directory.
    
    .EXAMPLE
    $files = Get-ChildItem "C:\Release\*.exe"
    foreach ($file in $files) {
        CreateChecksum -InputFile $file.FullName -SHA 256
    }
    Creates SHA256 checksums for all .exe files in the Release directory.
    
    .NOTES
    The output file format:
    INPUT FILE: {full path to input file}
    SHA{256/512} CHECKSUM: {hash value}
    TIMESTAMP: {Weekday} {DD.MM.YYYY} {HH:mm:ss}
    
    Output filename: {InputFileBaseName}.checksum.txt
    Example: PSx-Composer.exe -> PSx-Composer.checksum.txt
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputFile,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet(256, 512)]
        [int]$SHA = 256,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = ""
    )
    
    try {
        # Validate InputFile parameter
        if ([string]::IsNullOrWhiteSpace($InputFile)) {
            return (OPSreturn -Code -1 -Message "Parameter 'InputFile' is required but was not provided or is empty")
        }
        
        # Check if input file exists
        if (-not (Test-Path -Path $InputFile -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Input file does not exist: $InputFile")
        }
        
        # Verify it's actually a file, not a directory
        $inputItem = Get-Item -Path $InputFile -ErrorAction Stop
        if ($inputItem.PSIsContainer) {
            return (OPSreturn -Code -1 -Message "Specified path is a directory, not a file: $InputFile")
        }
        
        # Get file information
        $inputFileInfo = Get-Item -Path $InputFile
        $inputFileName = $inputFileInfo.BaseName
        $inputFileDir = $inputFileInfo.DirectoryName
        
        # Determine output directory
        $outputDirectory = $inputFileDir
        
        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            # Check if specified output path exists
            if (Test-Path -Path $OutputPath -PathType Container) {
                $outputDirectory = $OutputPath
            }
            else {
                # Output path doesn't exist - use input file directory and note in message
                Write-Verbose "Specified OutputPath does not exist: $OutputPath - Using input file directory instead"
            }
        }
        
        # Build output file path
        $outputFile = Join-Path $outputDirectory "$inputFileName.checksum.txt"
        
        # Calculate hash based on SHA parameter
        try {
            $hashAlgorithm = switch ($SHA) {
                256 { 'SHA256' }
                512 { 'SHA512' }
            }
            
            $fileHash = Get-FileHash -Path $InputFile -Algorithm $hashAlgorithm -ErrorAction Stop
            $hashValue = $fileHash.Hash
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to calculate $hashAlgorithm hash for file '$InputFile': $($_.Exception.Message)")
        }
        
        # Generate timestamp in specified format: Weekday DD.MM.YYYY HH:mm:ss
        $currentDate = Get-Date
        
        # Get full weekday name in system culture
        $weekday = $currentDate.ToString('dddd')
        $dateString = $currentDate.ToString('dd.MM.yyyy')
        $timeString = $currentDate.ToString('HH:mm:ss')
        $timestamp = "$weekday $dateString $timeString"
        
        # Build checksum file content
        $checksumContent = @"
INPUT FILE: $($inputFileInfo.FullName)
SHA$SHA CHECKSUM: $hashValue
TIMESTAMP: $timestamp
"@
        
        # Write checksum file
        try {
            Set-Content -Path $outputFile -Value $checksumContent -Encoding UTF8 -Force -ErrorAction Stop
            
            # Verify file was created
            if (-not (Test-Path -Path $outputFile)) {
                return (OPSreturn -Code -1 -Message "Checksum file creation reported success but file does not exist: $outputFile")
            }
            
            return (OPSreturn -Code 0 -Message "SHA$SHA checksum file created successfully" -Data $outputFile)
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to write checksum file to '$outputFile': $($_.Exception.Message)")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in CreateChecksum function: $($_.Exception.Message)")
    }
}
