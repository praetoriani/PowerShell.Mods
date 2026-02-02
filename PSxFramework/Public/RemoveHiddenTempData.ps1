function RemoveHiddenTempData {
    <#
    .SYNOPSIS
    Completely removes the temporary data directory including all contents.
    
    .DESCRIPTION
    The RemoveHiddenTempData function locates the PSx Composer installation directory,
    checks for the tmpdata directory, and completely removes it including all contents.
    Unlike CleanHiddenTempData which preserves the directory structure, this function
    removes everything including the directory itself.
    
    .EXAMPLE
    $result = RemoveHiddenTempData
    if ($result.code -eq 0) {
        Write-Host "Temporary data directory removed successfully"
    }
    Completely removes the tmpdata directory and all its contents.
    
    .NOTES
    The tmpdata directory location: {INSTALLDIR}\tmpdata\
    
    All contents and the directory itself are removed recursively and forcefully.
    The operation cannot be undone.
    
    This function is typically called during cleanup operations or uninstallation.
    After successful execution, the tmpdata directory will no longer exist.
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        # Get PSx Composer installation directory
        $InstallDirResult = GetInstallDir
        
        # Check if installation was found
        if ($InstallDirResult.code -ne 0) {
            return (OPSreturn -Code -1 -Message "Cannot remove temp data directory: $($InstallDirResult.msg)")
        }
        
        # Build tmpdata directory path
        $InstallDir = $InstallDirResult.data
        $TempDataDir = Join-Path -Path $InstallDir -ChildPath "tmpdata"
        
        # Check if tmpdata directory exists
        if (-not (Test-Path -Path $TempDataDir -PathType Container)) {
            # Directory doesn't exist - nothing to remove
            return (OPSreturn -Code 0 -Message "Temporary data directory does not exist - nothing to remove")
        }
        
        # Remove the entire tmpdata directory recursively and forcefully
        try {
            # First, try to remove any read-only or system attributes that might prevent deletion
            try {
                $AllItems = Get-ChildItem -Path $TempDataDir -Recurse -Force -ErrorAction SilentlyContinue
                foreach ($Item in $AllItems) {
                    if ($Item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                        $Item.Attributes = $Item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                    }
                }
            }
            catch {
                # Non-critical - continue with deletion even if attribute removal fails
                Write-Verbose "Warning: Could not remove all file attributes: $($_.Exception.Message)"
            }
            
            # Remove the directory and all its contents
            Remove-Item -Path $TempDataDir -Recurse -Force -ErrorAction Stop
            
            # Verify directory is removed
            if (Test-Path -Path $TempDataDir) {
                return (OPSreturn -Code -1 -Message "Failed to completely remove temporary data directory - it still exists after deletion attempt")
            }
            
            return (OPSreturn -Code 0 -Message "Temporary data directory removed successfully")
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to remove tmpdata directory at '$TempDataDir': $($_.Exception.Message)")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in RemoveHiddenTempData function: $($_.Exception.Message)")
    }
}
