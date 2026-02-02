function RemoveDir {
    <#
    .SYNOPSIS
    Deletes a complete directory with all its contents recursively.
    
    .DESCRIPTION
    The RemoveDir function removes a directory and all its contents (files and
    subdirectories) recursively. It validates the path, implements safety checks
    to prevent accidental deletion of critical directories, provides progress
    information, and reports results through a standardized return object.
    Use with extreme caution as this operation is irreversible.
    
    .PARAMETER Path
    The full path of the directory to delete. Must be an existing directory.
    Can be a local path (e.g., "C:\TempFolder") or UNC path (e.g., "\\Server\Share\TempFolder").
    
    .PARAMETER Force
    Optional switch parameter. When specified, suppresses confirmation prompts and
    removes read-only and hidden files without asking. Required for non-interactive
    deletion. Default is $false.
    
    .PARAMETER Recurse
    Optional switch parameter. Must be specified to delete directories with content.
    Without this parameter, only empty directories can be deleted. This is a safety
    feature to prevent accidental data loss. Default is $false.
    
    .EXAMPLE
    RemoveDir -Path "C:\Temp\OldData"
    Attempts to delete the directory (only works if empty, will prompt for confirmation).
    
    .EXAMPLE
    RemoveDir -Path "C:\Temp\OldProject" -Recurse -Force
    Deletes the directory and all contents without confirmation (use with caution).
    
    .EXAMPLE
    RemoveDir -Path "D:\Backup\2023" -Recurse
    Deletes the directory and contents with confirmation prompt.
    
    .EXAMPLE
    $result = RemoveDir -Path "C:\Temp\TestFolder" -Recurse -Force
    if ($result.code -eq 0) {
        Write-Host "Deleted $($result.data.FilesDeleted) files and $($result.data.DirectoriesDeleted) directories"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to delete the directory and its contents
    - This operation is IRREVERSIBLE - deleted files cannot be recovered from Recycle Bin
    - Protected system directories are blocked from deletion for safety
    - Use -Recurse parameter to delete non-empty directories
    - Use -Force parameter to suppress confirmations (dangerous!)
    - Large directory operations may take significant time
    - Progress information is written to Verbose stream
    - Critical paths (C:\Windows, C:\Program Files, etc.) are protected
    - Returns deletion statistics in the data field on success
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [switch]$Recurse
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty"
    }
    
    try {
        # Normalize path
        $NormalizedPath = $Path.TrimEnd('\\', '/')
        
        # Check if directory exists
        if (-not (Test-Path -Path $NormalizedPath -PathType Container)) {
            return OPSreturn -Code -1 -Message "Directory '$NormalizedPath' does not exist or is not a directory"
        }
        
        # Check if path is a file instead of directory
        if (Test-Path -Path $NormalizedPath -PathType Leaf) {
            return OPSreturn -Code -1 -Message "Path '$NormalizedPath' is a file, not a directory. Use Remove-Item for files."
        }
        
        # Critical safety check - prevent deletion of system directories
        $CriticalPaths = @(
            'C:\Windows',
            'C:\Program Files',
            'C:\Program Files (x86)',
            'C:\ProgramData',
            'C:\Users',
            "$env:SystemRoot",
            "$env:ProgramFiles",
            "${env:ProgramFiles(x86)}",
            "$env:SystemDrive\\",
            'C:\\'
        )
        
        # Normalize critical paths for comparison
        $NormalizedCriticalPaths = $CriticalPaths | ForEach-Object { 
            if ($_) { $_.TrimEnd('\\', '/').ToLower() }
        } | Where-Object { $_ }
        
        $NormalizedPathLower = $NormalizedPath.ToLower().TrimEnd('\\', '/')
        
        # Check if attempting to delete a critical system directory
        foreach ($criticalPath in $NormalizedCriticalPaths) {
            if ($NormalizedPathLower -eq $criticalPath -or 
                $NormalizedPathLower.StartsWith("$criticalPath\\")) {
                return OPSreturn -Code -1 -Message "Cannot delete critical system directory '$NormalizedPath'. This operation is blocked for system protection."
            }
        }
        
        # Additional check for drive root
        if ($NormalizedPath -match '^[A-Za-z]:\\\\?$') {
            return OPSreturn -Code -1 -Message "Cannot delete drive root '$NormalizedPath'. This operation is blocked for safety."
        }
        
        # Check if directory is empty (if Recurse is not specified)
        if (-not $Recurse) {
            $DirContents = Get-ChildItem -Path $NormalizedPath -Force -ErrorAction SilentlyContinue
            if ($DirContents -and $DirContents.Count -gt 0) {
                return OPSreturn -Code -1 -Message "Directory '$NormalizedPath' is not empty (contains $($DirContents.Count) item(s)). Use -Recurse parameter to delete the directory and all its contents."
            }
        }
        
        # Count items before deletion (for statistics)
        $FileCount = 0
        $DirCount = 0
        
        if ($Recurse) {
            try {
                Write-Verbose "Counting items to delete..."
                $AllFiles = Get-ChildItem -Path $NormalizedPath -File -Recurse -Force -ErrorAction SilentlyContinue
                $AllDirs = Get-ChildItem -Path $NormalizedPath -Directory -Recurse -Force -ErrorAction SilentlyContinue
                
                $FileCount = if ($AllFiles) { $AllFiles.Count } else { 0 }
                $DirCount = if ($AllDirs) { $AllDirs.Count } else { 0 }
                
                Write-Verbose "Found $FileCount files and $DirCount subdirectories to delete"
            }
            catch {
                Write-Verbose "Warning: Could not count all items: $($_.Exception.Message)"
            }
        }
        
        # Prepare confirmation message
        $ConfirmMessage = if ($Recurse) {
            "Delete directory '$NormalizedPath' and ALL its contents ($FileCount files, $DirCount subdirectories) - THIS CANNOT BE UNDONE"
        } else {
            "Delete empty directory '$NormalizedPath'"
        }
        
        # Attempt to delete the directory
        try {
            Write-Verbose "Deleting directory: $NormalizedPath (Recurse: $Recurse, Force: $Force)"
            
            if ($Force) {
                # Force deletion without confirmation
                if ($Recurse) {
                    Remove-Item -Path $NormalizedPath -Recurse -Force -ErrorAction Stop
                } else {
                    Remove-Item -Path $NormalizedPath -Force -ErrorAction Stop
                }
            }
            else {
                # With confirmation (ShouldProcess)
                if ($PSCmdlet.ShouldProcess($NormalizedPath, $ConfirmMessage)) {
                    if ($Recurse) {
                        Remove-Item -Path $NormalizedPath -Recurse -ErrorAction Stop
                    } else {
                        Remove-Item -Path $NormalizedPath -ErrorAction Stop
                    }
                }
                else {
                    return OPSreturn -Code -1 -Message "Operation cancelled by user"
                }
            }
            
            # Verify the directory was deleted
            if (Test-Path -Path $NormalizedPath) {
                return OPSreturn -Code -1 -Message "Directory deletion reported success, but directory '$NormalizedPath' still exists"
            }
            
            Write-Verbose "Successfully deleted directory: $NormalizedPath ($FileCount files, $DirCount subdirectories)"
            
            # Prepare return data object with deletion statistics
            $ReturnData = [PSCustomObject]@{
                FilesDeleted       = $FileCount
                DirectoriesDeleted = $DirCount + 1  # +1 for the main directory itself
            }
        }
        catch [System.UnauthorizedAccessException] {
            return OPSreturn -Code -1 -Message "Access denied when deleting directory '$NormalizedPath'. Check your permissions or try running as administrator."
        }
        catch [System.IO.IOException] {
            return OPSreturn -Code -1 -Message "I/O error when deleting directory '$NormalizedPath': $($_.Exception.Message). The directory may be in use."
        }
        catch [System.IO.DirectoryNotFoundException] {
            return OPSreturn -Code -1 -Message "Directory '$NormalizedPath' was not found during deletion operation"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to delete directory '$NormalizedPath': $($_.Exception.Message)"
        }
        
        # Success - return with deletion statistics in data field
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in RemoveDir function: $($_.Exception.Message)"
    }
}
