function CreateRelease {
    <#
    .SYNOPSIS
    Creates the final self-extracting executable by combining SFX module, configuration, and 7z archive.
    
    .DESCRIPTION
    The CreateRelease function is a core component that assembles the final executable file by
    combining the SFX module, configuration file (config.txt), and 7z data archive. It supports
    two creation methods (system copy command or .NET) and can optionally generate SHA checksums.
    The output is organized in versioned release directories.
    
    .PARAMETER ReleaseName
    Name for the application/program. Used for the executable filename and directory naming.
    This parameter is mandatory.
    
    .PARAMETER ReleaseVers
    Version number for the release (e.g., "v1.00.00").
    Used to create a versioned subdirectory in the release folder.
    This parameter is mandatory.
    
    .PARAMETER Method
    Specifies the method used to create the executable.
    Valid values:
    - 'system': Uses CMD internal copy command (binary mode)
    - 'dotnet': Uses .NET FileStream methods
    If not specified: tries 'system' first, falls back to 'dotnet' on failure.
    This parameter is optional.
    
    .PARAMETER OutputPath
    Full path to the output directory for the release.
    If not specified, uses {INSTALLDIR}\release\{ReleaseName}-{ReleaseVers}\
    The directory will be created if it doesn't exist.
    This parameter is optional.
    
    .PARAMETER SHAchecksum
    Specifies whether to create a checksum file for the executable.
    Valid values: $true or $false
    Default is $false.
    This parameter is optional.
    
    .PARAMETER SHAmethod
    Specifies the SHA algorithm for checksum generation.
    Valid values: 256 (SHA256) or 512 (SHA512)
    Default is 256.
    Only used when SHAchecksum is $true.
    This parameter is optional.
    
    .EXAMPLE
    $result = CreateRelease -ReleaseName "MyApp" -ReleaseVers "v1.00.00"
    if ($result.code -eq 0) {
        Write-Host "Release created: $($result.data)"
    }
    Creates MyApp.exe using default settings (auto method, no checksum).
    
    .EXAMPLE
    CreateRelease -ReleaseName "PSx-Composer" -ReleaseVers "v2.01.05" -Method "system" -SHAchecksum $true -SHAmethod 512
    Creates PSx-Composer.exe using system method with SHA512 checksum.
    
    .EXAMPLE
    $params = @{
        ReleaseName = "Application"
        ReleaseVers = "v1.50.00"
        OutputPath = "D:\Releases\Application"
        Method = "dotnet"
        SHAchecksum = $true
    }
    CreateRelease @params
    Creates release in custom output path using .NET method with SHA256 checksum.
    
    .NOTES
    Required files in {INSTALLDIR}\tmpdata\:
    - {ReleaseName}.7z (data archive)
    - config.txt (SFX configuration)
    - One SFX module: 7z.sfx, 7zCon.sfx, 7zS2.sfx, or 7zSD.sfx
    
    The function automatically detects which SFX module is present.
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ReleaseName,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ReleaseVers,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("system", "dotnet", IgnoreCase = $true)]
        [string]$Method = "",
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "",
        
        [Parameter(Mandatory = $false)]
        [bool]$SHAchecksum = $false,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet(256, 512)]
        [int]$SHAmethod = 256
    )
    
    try {
        # Get PSx Composer installation directory
        $InstallDirResult = GetInstallDir
        if ($InstallDirResult.code -ne 0) {
            return (OPSreturn -Code -1 -Message "Cannot create release: $($InstallDirResult.msg)")
        }
        
        $InstallDir = $InstallDirResult.data
        $TempDataDir = Join-Path $InstallDir "tmpdata"
        
        # Verify tmpdata directory exists
        if (-not (Test-Path -Path $TempDataDir -PathType Container)) {
            return (OPSreturn -Code -1 -Message "Temporary data directory does not exist: $TempDataDir")
        }
        
        # Look for required files in tmpdata
        $archiveFile = Join-Path $TempDataDir "$ReleaseName.7z"
        $configFile = Join-Path $TempDataDir "config.txt"
        
        # Verify archive exists
        if (-not (Test-Path -Path $archiveFile -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Data archive not found: $archiveFile")
        }
        
        # Verify config exists
        if (-not (Test-Path -Path $configFile -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Configuration file not found: $configFile")
        }
        
        # Find SFX module (check all possible variants)
        $sfxModules = @('7z.sfx', '7zCon.sfx', '7zS2.sfx', '7zSD.sfx')
        $sfxFile = $null
        
        foreach ($sfxName in $sfxModules) {
            $sfxPath = Join-Path $TempDataDir $sfxName
            if (Test-Path -Path $sfxPath -PathType Leaf) {
                $sfxFile = $sfxPath
                break
            }
        }
        
        if (-not $sfxFile) {
            return (OPSreturn -Code -1 -Message "No SFX module found in tmpdata directory. Expected one of: $($sfxModules -join ', ')")
        }
        
        # Determine output directory
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $releaseBaseDir = Join-Path $InstallDir "release"
            $OutputPath = Join-Path $releaseBaseDir "$ReleaseName-$ReleaseVers"
        }
        
        # Ensure release base directory exists
        $releaseBaseDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $releaseBaseDir -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $releaseBaseDir -Force -ErrorAction Stop | Out-Null
            }
            catch {
                return (OPSreturn -Code -1 -Message "Failed to create release base directory '$releaseBaseDir': $($_.Exception.Message)")
            }
        }
        
        # Create versioned output directory
        if (-not (Test-Path -Path $OutputPath -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop | Out-Null
            }
            catch {
                return (OPSreturn -Code -1 -Message "Failed to create output directory '$OutputPath': $($_.Exception.Message)")
            }
        }
        
        # Build output executable path
        $outputExe = Join-Path $OutputPath "$ReleaseName.exe"
        
        # Delete existing executable if present
        if (Test-Path -Path $outputExe) {
            try {
                Remove-Item -Path $outputExe -Force -ErrorAction Stop
            }
            catch {
                return (OPSreturn -Code -1 -Message "Failed to remove existing executable '$outputExe': $($_.Exception.Message)")
            }
        }
        
        # Determine which method(s) to try
        $methodsToTry = @()
        if ([string]::IsNullOrWhiteSpace($Method)) {
            # Auto mode: try system first, then dotnet
            $methodsToTry = @('system', 'dotnet')
        }
        else {
            # Specific method requested
            $methodsToTry = @($Method.ToLower())
        }
        
        $lastError = ""
        $creationSuccessful = $false
        
        foreach ($currentMethod in $methodsToTry) {
            try {
                if ($currentMethod -eq 'system') {
                    # Method 1: CMD copy command (binary mode)
                    $copyCmd = "copy /b `"$sfxFile`"+`"$configFile`"+`"$archiveFile`" `"$outputExe`""
                    
                    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                    $processInfo.FileName = 'cmd.exe'
                    $processInfo.Arguments = "/c $copyCmd"
                    $processInfo.RedirectStandardOutput = $true
                    $processInfo.RedirectStandardError = $true
                    $processInfo.UseShellExecute = $false
                    $processInfo.CreateNoWindow = $true
                    
                    $process = New-Object System.Diagnostics.Process
                    $process.StartInfo = $processInfo
                    $process.Start() | Out-Null
                    $stdout = $process.StandardOutput.ReadToEnd()
                    $stderr = $process.StandardError.ReadToEnd()
                    $process.WaitForExit()
                    
                    if ($process.ExitCode -ne 0) {
                        throw "CMD copy exited with code $($process.ExitCode): $stderr"
                    }
                }
                elseif ($currentMethod -eq 'dotnet') {
                    # Method 2: .NET FileStream
                    $outputStream = [System.IO.File]::Create($outputExe)
                    
                    try {
                        # Copy SFX module
                        $sfxBytes = [System.IO.File]::ReadAllBytes($sfxFile)
                        $outputStream.Write($sfxBytes, 0, $sfxBytes.Length)
                        
                        # Copy config file
                        $configBytes = [System.IO.File]::ReadAllBytes($configFile)
                        $outputStream.Write($configBytes, 0, $configBytes.Length)
                        
                        # Copy 7z archive
                        $archiveBytes = [System.IO.File]::ReadAllBytes($archiveFile)
                        $outputStream.Write($archiveBytes, 0, $archiveBytes.Length)
                    }
                    finally {
                        $outputStream.Close()
                        $outputStream.Dispose()
                    }
                }
                
                # Verify executable was created
                if (Test-Path -Path $outputExe -PathType Leaf) {
                    $creationSuccessful = $true
                    break
                }
                else {
                    throw "Executable creation completed but file does not exist"
                }
            }
            catch {
                $lastError = $_.Exception.Message
                # Continue to next method if available
                continue
            }
        }
        
        if (-not $creationSuccessful) {
            return (OPSreturn -Code -1 -Message "Failed to create executable using all attempted methods. Last error: $lastError")
        }
        
        # Get executable file size
        $exeInfo = Get-Item -Path $outputExe
        $exeSizeMB = [Math]::Round($exeInfo.Length / 1MB, 2)
        
        # Create checksum if requested
        $checksumFile = ""
        if ($SHAchecksum) {
            $checksumResult = CreateChecksum -InputFile $outputExe -SHA $SHAmethod -OutputPath $OutputPath
            if ($checksumResult.code -eq 0) {
                $checksumFile = $checksumResult.data
            }
            else {
                # Checksum creation failed but exe exists - return warning
                return (OPSreturn -Code 0 -Message "Release created successfully ($exeSizeMB MB) but checksum generation failed: $($checksumResult.msg)" -Data $outputExe)
            }
        }
        
        # Build success message
        $successMsg = "Release created successfully: $($exeInfo.Name) ($exeSizeMB MB)"
        if ($checksumFile) {
            $successMsg += " with SHA$SHAmethod checksum"
        }
        
        return (OPSreturn -Code 0 -Message $successMsg -Data $outputExe)
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in CreateRelease function: $($_.Exception.Message)")
    }
}
