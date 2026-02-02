function PrepareCFG {
    <#
    .SYNOPSIS
    Prepares an SFX configuration file for archive creation.
    
    .DESCRIPTION
    The PrepareCFG function copies the appropriate SFX configuration template from the
    PSx Composer installation directory to the temporary data directory and renames it
    to config.txt. The configuration file is then ready for customization based on the
    specific build requirements.
    
    .PARAMETER SFXmod
    Specifies which SFX module configuration to prepare. Valid values are:
    - GUI-Mode: Configuration for 7z.sfx (graphical interface)
    - CMD-Mode: Configuration for 7zCon.sfx (console mode)
    - Installer: Configuration for 7zS2.sfx (installer mode)
    - Custom: Configuration for 7zSD.sfx (custom dialog mode)
    
    This parameter is mandatory.
    
    .EXAMPLE
    $result = PrepareCFG -SFXmod "GUI-Mode"
    if ($result.code -eq 0) {
        Write-Host "GUI-Mode configuration prepared at: $($result.data)"
    }
    Prepares the configuration template for GUI-mode SFX archives.
    
    .EXAMPLE
    PrepareCFG -SFXmod "Installer"
    Prepares the configuration template for installer-mode SFX archives.
    
    .NOTES
    Source location: {INSTALLDIR}\include\sfx\{template}.txt
    Destination location: {INSTALLDIR}\tmpdata\config.txt
    
    The configuration file will be copied and renamed to config.txt regardless of the
    source template name. This ensures a consistent naming convention for the build process.
    
    Template files are expected to be named:
    - GUI-Mode: 7z_config_template.txt
    - CMD-Mode: 7zCon_config_template.txt
    - Installer: 7zS2_config_template.txt
    - Custom: 7zSD_config_template.txt
    
    The tmpdata directory must exist before calling this function. Use CreateHiddenTempData
    to ensure it exists.
    
    NOTE: Configuration file customization (replacing placeholders with actual values)
    is implemented as a placeholder for future enhancement. Currently, the template is
    copied as-is.
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
            return (OPSreturn -Code -1 -Message "Cannot prepare configuration file: $($InstallDirResult.msg)")
        }
        
        $InstallDir = $InstallDirResult.data
        
        # Map SFX mode to configuration template filename
        $TemplateFileName = switch ($SFXmod) {
            "GUI-Mode"  { "7z_config_template.txt" }
            "CMD-Mode"  { "7zCon_config_template.txt" }
            "Installer" { "7zS2_config_template.txt" }
            "Custom"    { "7zSD_config_template.txt" }
            default     { "7z_config_template.txt" }
        }
        
        # Build source and destination paths
        $SourcePath = Join-Path -Path $InstallDir -ChildPath "include\sfx\$TemplateFileName"
        $TempDataDir = Join-Path -Path $InstallDir -ChildPath "tmpdata"
        $DestinationPath = Join-Path -Path $TempDataDir -ChildPath "config.txt"
        
        # Verify source template exists
        if (-not (Test-Path -Path $SourcePath -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Configuration template not found: $SourcePath")
        }
        
        # Verify tmpdata directory exists
        if (-not (Test-Path -Path $TempDataDir -PathType Container)) {
            return (OPSreturn -Code -1 -Message "Temporary data directory does not exist: $TempDataDir. Call CreateHiddenTempData first.")
        }
        
        # Copy template to tmpdata and rename to config.txt
        try {
            Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
            
            # Verify the file was copied successfully
            if (-not (Test-Path -Path $DestinationPath -PathType Leaf)) {
                return (OPSreturn -Code -1 -Message "Configuration file copy verification failed - file does not exist at destination: $DestinationPath")
            }
            
            # TODO: Future enhancement - Configuration customization
            # This is where we would read the config.txt file and replace placeholders
            # with actual values based on user input from the PSx Composer GUI.
            # Example placeholders that could be replaced:
            # - %%TITLE%% -> Application title
            # - %%EXTRACT_PATH%% -> Extraction directory
            # - %%RUN_PROGRAM%% -> Program to execute after extraction
            # - %%BEGIN_PROMPT%% -> Custom dialog text
            # 
            # Implementation stub:
            # $ConfigContent = Get-Content -Path $DestinationPath -Raw
            # $ConfigContent = $ConfigContent -replace '%%PLACEHOLDER%%', $ActualValue
            # Set-Content -Path $DestinationPath -Value $ConfigContent -NoNewline
            
            # Get file info for success message
            $FileInfo = Get-Item -Path $DestinationPath
            $FileSizeBytes = $FileInfo.Length
            
            return (OPSreturn -Code 0 -Message "Configuration file for '$SFXmod' prepared successfully ($FileSizeBytes bytes)" -Data $DestinationPath)
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to copy configuration template from '$SourcePath' to '$DestinationPath': $($_.Exception.Message)")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in PrepareCFG function: $($_.Exception.Message)")
    }
}
