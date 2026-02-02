function RemoveFile {
    <#
    .SYNOPSIS
    Deletes a single file permanently.
    
    .DESCRIPTION
    The RemoveFile function permanently deletes a single file from the filesystem.
    It validates the file path, implements safety checks to prevent accidental deletion
    of critical files, handles read-only and hidden files, and reports results through
    a standardized return object. This operation is IRREVERSIBLE - deleted files cannot
    be recovered from the Recycle Bin.
    
    .PARAMETER Path
    The full path of the file to delete. Must be an existing file.
    Can be a local path (e.g., "C:\Temp\file.txt") or UNC path (e.g., "\\Server\Share\file.txt").
    
    .PARAMETER Force
    Optional switch parameter. When specified, removes read-only and hidden files
    without prompting and suppresses confirmation. Use with caution. Default is $false.
    
    .EXAMPLE
    RemoveFile -Path "C:\Temp\oldfile.txt"
    Deletes the file with confirmation prompt.
    
    .EXAMPLE
    RemoveFile -Path "C:\Data\readonly.dat" -Force
    Deletes a read-only file without confirmation.
    
    .EXAMPLE
    $result = RemoveFile -Path "C:\Logs\old.log" -Force
    if ($result.code -eq 0) {
        Write-Host "File deleted: $($result.data.DeletedPath)"
        Write-Host "Size: $($result.data.SizeBytes) bytes"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to delete the file
    - This operation is IRREVERSIBLE - files are deleted permanently, not moved to Recycle Bin
    - Protected system files in critical directories are blocked from deletion
    - Read-only attribute must be removed before deletion (automatic with -Force)
    - Hidden and system files can only be deleted with -Force parameter
    - Returns deleted file path and size in the data field on success
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty"
    }
    
    try {
        # Normalize path
        $NormalizedPath = $Path.Replace('/', '\\').TrimEnd('\\')
        
        # Check if file exists
        if (-not (Test-Path -Path $NormalizedPath -PathType Leaf)) {
            return OPSreturn -Code -1 -Message "File '$NormalizedPath' does not exist or is not a file"
        }
        
        # Check if path is a directory instead of file
        if (Test-Path -Path $NormalizedPath -PathType Container) {
            return OPSreturn -Code -1 -Message "Path '$NormalizedPath' is a directory, not a file. Use RemoveDir for directories."
        }
        
        # Get file information
        try {
            $FileInfo = Get-Item -Path $NormalizedPath -Force -ErrorAction Stop
            $DeletedPath = $FileInfo.FullName
            $FileSizeBytes = $FileInfo.Length
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to access file '$NormalizedPath': $($_.Exception.Message)"
        }
        
        # Critical safety check - prevent deletion of system files in critical directories
        $CriticalDirs = @(
            "$env:SystemRoot\\System32",
            "$env:SystemRoot\\SysWOW64",
            "$env:SystemRoot",
            "$env:ProgramFiles",
            "${env:ProgramFiles(x86)}"
        )
        
        $FileDirectory = $FileInfo.DirectoryName.ToLower()
        $IsInCriticalDir = $false
        
        foreach ($criticalDir in $CriticalDirs) {
            if ($criticalDir -and $FileDirectory.StartsWith($criticalDir.ToLower())) {
                $IsInCriticalDir = $true
                break
            }
        }
        
        if ($IsInCriticalDir) {
            # Check if it's a critical system file
            if ($FileInfo.Attributes -band [System.IO.FileAttributes]::System) {
                return OPSreturn -Code -1 -Message "Cannot delete system file '$NormalizedPath' in critical directory. This operation is blocked for system protection."
            }
        }
        
        # Check for read-only or hidden attributes
        $IsReadOnly = $FileInfo.Attributes -band [System.IO.FileAttributes]::ReadOnly
        $IsHidden = $FileInfo.Attributes -band [System.IO.FileAttributes]::Hidden
        $IsSystem = $FileInfo.Attributes -band [System.IO.FileAttributes]::System
        
        if (($IsReadOnly -or $IsHidden -or $IsSystem) -and -not $Force) {
            $attributes = @()
            if ($IsReadOnly) { $attributes += "ReadOnly" }
            if ($IsHidden) { $attributes += "Hidden" }
            if ($IsSystem) { $attributes += "System" }
            
            return OPSreturn -Code -1 -Message "File '$NormalizedPath' has special attributes ($($attributes -join ', ')). Use -Force parameter to delete."
        }
        
        # Prepare confirmation message
        $ConfirmMessage = "Permanently delete file '$NormalizedPath' ($FileSizeBytes bytes) - THIS CANNOT BE UNDONE"
        
        # Attempt to delete the file
        try {
            Write-Verbose "Deleting file: $NormalizedPath"
            
            if ($Force) {
                # Remove read-only attribute if present
                if ($IsReadOnly) {
                    try {
                        $FileInfo.Attributes = $FileInfo.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                        Write-Verbose "Removed ReadOnly attribute"
                    }
                    catch {
                        Write-Verbose "Warning: Could not remove ReadOnly attribute: $($_.Exception.Message)"
                    }
                }
                
                # Force deletion without confirmation
                Remove-Item -Path $NormalizedPath -Force -ErrorAction Stop
            }
            else {
                # With confirmation (ShouldProcess)
                if ($PSCmdlet.ShouldProcess($NormalizedPath, $ConfirmMessage)) {
                    Remove-Item -Path $NormalizedPath -ErrorAction Stop
                }
                else {
                    return OPSreturn -Code -1 -Message "Operation cancelled by user"
                }
            }
            
            # Verify the file was deleted
            if (Test-Path -Path $NormalizedPath) {
                return OPSreturn -Code -1 -Message "File deletion reported success, but file '$NormalizedPath' still exists"
            }
            
            Write-Verbose "Successfully deleted file: $DeletedPath ($FileSizeBytes bytes)"
            
            # Prepare return data object with deletion information
            $ReturnData = [PSCustomObject]@{
                DeletedPath = $DeletedPath
                SizeBytes   = $FileSizeBytes
            }
        }
        catch [System.UnauthorizedAccessException] {
            return OPSreturn -Code -1 -Message "Access denied when deleting file '$NormalizedPath'. Check your permissions or try running as administrator."
        }
        catch [System.IO.IOException] {
            return OPSreturn -Code -1 -Message "I/O error when deleting file '$NormalizedPath': $($_.Exception.Message). The file may be in use."
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to delete file '$NormalizedPath': $($_.Exception.Message)"
        }
        
        # Success - return with deletion information in data field
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in RemoveFile function: $($_.Exception.Message)"
    }
}
