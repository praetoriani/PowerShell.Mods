function CreateDataBundle {
    <#
    .SYNOPSIS
    Creates a 7z archive from a directory for use in SFX executable creation.
    
    .DESCRIPTION
    The CreateDataBundle function uses 7-Zip to create a compressed archive from a source directory.
    This archive will later be combined with an SFX module and configuration file to create the
    final executable. The function supports custom compression levels and can use either the
    bundled 7-Zip or an external installation.
    
    .PARAMETER InputPath
    Full path to the directory whose contents should be packaged into a 7z archive.
    The directory must exist and must not be empty.
    This parameter is mandatory.
    
    .PARAMETER 7zBinary
    Full path to the 7z.exe executable to use for compression.
    If not specified, uses the bundled version at {INSTALLDIR}\include\7z\7z.exe.
    This parameter is optional.
    
    .PARAMETER Filename
    Name for the output 7z archive (without file extension).
    The .7z extension will be added automatically.
    This parameter is mandatory.
    
    .PARAMETER Output
    Full path to the output directory where the 7z archive will be saved.
    If not specified, uses {INSTALLDIR}\tmpdata\ as default.
    This parameter is optional.
    
    .PARAMETER CompLvl
    Compression level from 0 (no compression) to 9 (maximum compression).
    Default is 5 (normal compression).
    This parameter is optional.
    
    .EXAMPLE
    $result = CreateDataBundle -InputPath "C:\PSx\tmpdata\MyApp" -Filename "MyApp"
    if ($result.code -eq 0) {
        Write-Host "Archive created: $($result.data)"
    }
    Creates MyApp.7z using default compression level 5.
    
    .EXAMPLE
    CreateDataBundle -InputPath "C:\PSx\tmpdata\MyApp" -Filename "MyApp" -CompLvl 9 -Output "C:\Output"
    Creates MyApp.7z with maximum compression in C:\Output directory.
    
    .EXAMPLE
    $params = @{
        InputPath = "C:\Data\Application"
        Filename = "Application"
        7zBinary = "C:\Program Files\7-Zip\7z.exe"
        CompLvl = 7
    }
    CreateDataBundle @params
    Uses external 7-Zip installation with compression level 7.
    
    .NOTES
    The function packages only the CONTENTS of InputPath, not the directory itself.
    The resulting archive is ready to be combined with an SFX module.
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputPath,
        
        [Parameter(Mandatory = $false)]
        [Alias('SevenZipBinary')]
        [string]$7zBinary = "",
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Filename,
        
        [Parameter(Mandatory = $false)]
        [string]$Output = "",
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 9)]
        [int]$CompLvl = 5
    )
    
    try {
        # Get PSx Composer installation directory
        $InstallDirResult = GetInstallDir
        if ($InstallDirResult.code -ne 0) {
            return (OPSreturn -Code -1 -Message "Cannot create data bundle: $($InstallDirResult.msg)")
        }
        
        $InstallDir = $InstallDirResult.data
        
        # Validate InputPath
        if (-not (Test-Path -Path $InputPath -PathType Container)) {
            return (OPSreturn -Code -1 -Message "Input directory does not exist: $InputPath")
        }
        
        # Check if InputPath is empty
        $inputItems = Get-ChildItem -Path $InputPath -Force -ErrorAction SilentlyContinue
        if ($inputItems.Count -eq 0) {
            return (OPSreturn -Code -1 -Message "Input directory is empty: $InputPath")
        }
        
        # Determine 7z.exe path
        if ([string]::IsNullOrWhiteSpace($7zBinary)) {
            # Use bundled 7-Zip
            $7zBinary = Join-Path $InstallDir "include\7z\7z.exe"
        }
        
        # Verify 7z.exe exists
        $verifyResult = VerifyBinary -ExePath $7zBinary
        if ($verifyResult.code -ne 0) {
            return (OPSreturn -Code -1 -Message "7-Zip executable not found or invalid: $($verifyResult.msg)")
        }
        
        # Determine output directory
        if ([string]::IsNullOrWhiteSpace($Output)) {
            $Output = Join-Path $InstallDir "tmpdata"
        }
        
        # Verify output directory exists
        if (-not (Test-Path -Path $Output -PathType Container)) {
            return (OPSreturn -Code -1 -Message "Output directory does not exist: $Output")
        }
        
        # Build output file path
        $OutputFile = Join-Path $Output "$Filename.7z"
        
        # Delete existing archive if present
        if (Test-Path -Path $OutputFile) {
            try {
                Remove-Item -Path $OutputFile -Force -ErrorAction Stop
            }
            catch {
                return (OPSreturn -Code -1 -Message "Failed to remove existing archive '$OutputFile': $($_.Exception.Message)")
            }
        }
        
        # Build 7-Zip command arguments
        # a = add to archive
        # -t7z = archive type 7z
        # -mx{CompLvl} = compression level
        # {OutputFile} = target archive path
        # {InputPath}\* = source files (contents only, not directory itself)
        $arguments = @(
            'a',
            '-t7z',
            "-mx$CompLvl",
            "`"$OutputFile`"",
            "`"$InputPath\*`""
        )
        
        # Execute 7-Zip
        try {
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $7zBinary
            $processInfo.Arguments = $arguments -join ' '
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true
            $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            
            $process.Start() | Out-Null
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            
            $exitCode = $process.ExitCode
            
            # Check if 7-Zip operation was successful (exit code 0)
            if ($exitCode -ne 0) {
                $errorMsg = if ($stderr) { $stderr } else { "7-Zip exited with code $exitCode" }
                return (OPSreturn -Code -1 -Message "7-Zip compression failed: $errorMsg")
            }
            
            # Verify archive was created
            if (-not (Test-Path -Path $OutputFile)) {
                return (OPSreturn -Code -1 -Message "Archive creation reported success but file does not exist: $OutputFile")
            }
            
            # Get archive file size
            $archiveInfo = Get-Item -Path $OutputFile
            $archiveSizeMB = [Math]::Round($archiveInfo.Length / 1MB, 2)
            
            return (OPSreturn -Code 0 -Message "Data bundle created successfully: $($archiveInfo.Name) ($archiveSizeMB MB, compression level $CompLvl)" -Data $OutputFile)
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to execute 7-Zip compression: $($_.Exception.Message)")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in CreateDataBundle function: $($_.Exception.Message)")
    }
}
