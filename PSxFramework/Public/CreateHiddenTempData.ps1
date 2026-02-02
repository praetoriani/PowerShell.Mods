function CreateHiddenTempData {
    <#
    .SYNOPSIS
    Creates a hidden temporary data directory for PSx Composer build operations.
    
    .DESCRIPTION
    The CreateHiddenTempData function locates the PSx Composer installation directory
    and creates a hidden temporary data directory (tmpdata) within it. This directory
    is used during the build process to store intermediate files. The directory is
    created with Hidden and System attributes to keep it out of normal view.
    
    .EXAMPLE
    $result = CreateHiddenTempData
    if ($result.code -eq 0) {
        Write-Host "Temporary data directory created successfully"
    }
    Creates the hidden tmpdata directory if it doesn't exist.
    
    .NOTES
    The tmpdata directory is created at: {INSTALLDIR}\tmpdata\
    Directory attributes set: Hidden + System
    
    This function is typically called at the beginning of a build process to ensure
    the temporary workspace exists before other operations begin.
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        # Get PSx Composer installation directory
        $InstallDirResult = GetInstallDir
        
        # Check if installation was found
        if ($InstallDirResult.code -ne 0) {
            return (OPSreturn -Code -1 -Message "Cannot create temp data directory: $($InstallDirResult.msg)")
        }
        
        # Build tmpdata directory path
        $InstallDir = $InstallDirResult.data
        $TempDataDir = Join-Path -Path $InstallDir -ChildPath "tmpdata"
        
        # Check if tmpdata directory already exists
        if (Test-Path -Path $TempDataDir -PathType Container) {
            # Directory already exists - verify it's properly hidden
            try {
                $DirItem = Get-Item -Path $TempDataDir -Force
                
                # Ensure Hidden and System attributes are set
                if (-not ($DirItem.Attributes -band [System.IO.FileAttributes]::Hidden)) {
                    $DirItem.Attributes = $DirItem.Attributes -bor [System.IO.FileAttributes]::Hidden
                }
                if (-not ($DirItem.Attributes -band [System.IO.FileAttributes]::System)) {
                    $DirItem.Attributes = $DirItem.Attributes -bor [System.IO.FileAttributes]::System
                }
                
                return (OPSreturn -Code 0 -Message "Temporary data directory already exists and is properly configured" -Data $TempDataDir)
            }
            catch {
                return (OPSreturn -Code -1 -Message "Failed to verify/update attributes of existing tmpdata directory: $($_.Exception.Message)")
            }
        }
        
        # Create tmpdata directory
        try {
            $NewDir = New-Item -ItemType Directory -Path $TempDataDir -Force -ErrorAction Stop
            
            # Set Hidden and System attributes
            $NewDir.Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
            
            return (OPSreturn -Code 0 -Message "Temporary data directory created successfully" -Data $TempDataDir)
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to create tmpdata directory at '$TempDataDir': $($_.Exception.Message)")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in CreateHiddenTempData function: $($_.Exception.Message)")
    }
}
