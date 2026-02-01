function PrepareSFX {
    <#
    .SYNOPSIS
    Prepares an SFX (Self-Extracting Archive) module for archive creation.
    
    .DESCRIPTION
    The PrepareSFX function copies the appropriate SFX module from the PSx Composer
    installation directory to the temporary data directory. The SFX module is used
    as the executable stub for creating self-extracting archives.
    
    .PARAMETER SFXmod
    Specifies which SFX module to prepare. Valid values are:
    - GUI-Mode: Uses 7z.sfx (graphical interface with progress dialog)
    - CMD-Mode: Uses 7zCon.sfx (console mode with text output)
    - Installer: Uses 7zS2.sfx (installer mode with configuration support)
    - Custom: Uses 7zSD.sfx (custom dialog mode with advanced configuration)
    
    This parameter is mandatory.
    
    .EXAMPLE
    $result = PrepareSFX -SFXmod "GUI-Mode"
    if ($result.code -eq 0) {
        Write-Host "GUI-Mode SFX module prepared at: $($result.data)"
    }
    Prepares the 7z.sfx module for creating a GUI-based self-extracting archive.
    
    .EXAMPLE
    PrepareSFX -SFXmod "Installer"
    Prepares the 7zS2.sfx module for creating an installer-style self-extracting archive.
    
    .NOTES
    Source location: {INSTALLDIR}\include\sfx\{module}.sfx
    Destination location: {INSTALLDIR}\tmpdata\{module}.sfx
    
    The tmpdata directory must exist before calling this function. Use CreateHiddenTempData
    to ensure it exists.
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GUI-Mode", "CMD-Mode", "Installer", "Custom", IgnoreCase = $true)]
        [string]$SFXmod
    )
    
    try {
        # Get PSx Composer installation directory
        $InstallDirResult = GetInstallDir
        
        # Check if installation was found
        if ($InstallDirResult.code -ne 0) {
            return (OPSreturn -Code -1 -Message "Cannot prepare SFX module: $($InstallDirResult.msg)")
        }
        
        $InstallDir = $InstallDirResult.data
        
        # Map SFX mode to actual filename
        $SFXFileName = switch ($SFXmod) {
            "GUI-Mode"  { "7z.sfx" }
            "CMD-Mode"  { "7zCon.sfx" }
            "Installer" { "7zS2.sfx" }
            "Custom"    { "7zSD.sfx" }
            default     { "7z.sfx" }
        }
        
        # Build source and destination paths
        $SourcePath = Join-Path -Path $InstallDir -ChildPath "include\sfx\$SFXFileName"
        $TempDataDir = Join-Path -Path $InstallDir -ChildPath "tmpdata"
        $DestinationPath = Join-Path -Path $TempDataDir -ChildPath $SFXFileName
        
        # Verify source SFX module exists
        if (-not (Test-Path -Path $SourcePath -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Source SFX module not found: $SourcePath")
        }
        
        # Verify tmpdata directory exists
        if (-not (Test-Path -Path $TempDataDir -PathType Container)) {
            return (OPSreturn -Code -1 -Message "Temporary data directory does not exist: $TempDataDir. Call CreateHiddenTempData first.")
        }
        
        # Copy SFX module to tmpdata directory
        try {
            Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
            
            # Verify the file was copied successfully
            if (-not (Test-Path -Path $DestinationPath -PathType Leaf)) {
                return (OPSreturn -Code -1 -Message "SFX module copy verification failed - file does not exist at destination: $DestinationPath")
            }
            
            # Get file info to include in success message
            $FileInfo = Get-Item -Path $DestinationPath
            $FileSizeKB = [Math]::Round($FileInfo.Length / 1KB, 2)
            
            return (OPSreturn -Code 0 -Message "SFX module '$SFXmod' ($SFXFileName, $FileSizeKB KB) prepared successfully" -Data $DestinationPath)
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to copy SFX module from '$SourcePath' to '$DestinationPath': $($_.Exception.Message)")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in PrepareSFX function: $($_.Exception.Message)")
    }
}
