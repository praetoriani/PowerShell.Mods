function CleanHiddenTempData {
    <#
    .SYNOPSIS
    Cleans the temporary data directory by removing all contents while preserving the directory.
    
    .DESCRIPTION
    The CleanHiddenTempData function locates the PSx Composer installation directory,
    checks for the tmpdata directory, and recursively removes all its contents while
    keeping the directory structure intact. This is useful for cleaning up after a build
    process without having to recreate the hidden directory.
    
    .EXAMPLE
    $result = CleanHiddenTempData
    if ($result.code -eq 0) {
        Write-Host "Temporary data directory cleaned successfully"
    }
    Removes all files and subdirectories from tmpdata while keeping the directory itself.
    
    .NOTES
    The tmpdata directory location: {INSTALLDIR}\tmpdata\
    
    All contents are removed recursively and forcefully. The operation cannot be undone.
    After successful execution, the tmpdata directory will exist but be completely empty.
    
    This function is typically called after a build process to clean up intermediate files.
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    try {
        # Get PSx Composer installation directory
        $InstallDirResult = GetInstallDir
        
        # Check if installation was found
        if ($InstallDirResult.code -ne 0) {
            return (OPSreturn -Code -1 -Message "Cannot clean temp data directory: $($InstallDirResult.msg)")
        }
        
        # Build tmpdata directory path
        $InstallDir = $InstallDirResult.data
        $TempDataDir = Join-Path -Path $InstallDir -ChildPath "tmpdata"
        
        # Check if tmpdata directory exists
        if (-not (Test-Path -Path $TempDataDir -PathType Container)) {
            # Directory doesn't exist - nothing to clean
            return (OPSreturn -Code 0 -Message "Temporary data directory does not exist - nothing to clean")
        }
        
        # Get all items in tmpdata directory (including hidden and system files)
        try {
            $Items = Get-ChildItem -Path $TempDataDir -Force -ErrorAction Stop
            
            # Check if directory is already empty
            if ($Items.Count -eq 0) {
                return (OPSreturn -Code 0 -Message "Temporary data directory is already empty")
            }
            
            # Remove all items recursively and forcefully
            foreach ($Item in $Items) {
                try {
                    # Remove item (works for both files and directories)
                    Remove-Item -Path $Item.FullName -Recurse -Force -ErrorAction Stop
                }
                catch {
                    # If any item fails to delete, abort the operation and report error
                    return (OPSreturn -Code -1 -Message "Failed to remove item '$($Item.FullName)' during cleanup: $($_.Exception.Message)")
                }
            }
            
            # Verify directory is now empty
            $RemainingItems = Get-ChildItem -Path $TempDataDir -Force -ErrorAction SilentlyContinue
            if ($RemainingItems.Count -gt 0) {
                return (OPSreturn -Code -1 -Message "Cleanup incomplete: $($RemainingItems.Count) items remain in temporary data directory")
            }
            
            return (OPSreturn -Code 0 -Message "Temporary data directory cleaned successfully" -Data $TempDataDir)
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to enumerate or clean tmpdata directory contents: $($_.Exception.Message)")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in CleanHiddenTempData function: $($_.Exception.Message)")
    }
}
