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
        Write-Host "File deleted: $($result.deletedPath)"
        Write-Host "Size: $($result.sizeBytes) bytes"
    } else {
        Write-Host "Error: $($result.msg)"
    }
    
    .NOTES
    - Requires appropriate permissions to delete the file
    - This operation is IRREVERSIBLE - files are deleted permanently, not moved to Recycle Bin
    - Protected system files in critical directories are blocked from deletion
    - Read-only attribute must be removed before deletion (automatic with -Force)
    - Hidden and system files can only be deleted with -Force parameter
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        deletedPath = $null
        sizeBytes = 0
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $status.msg = "Parameter 'Path' is required but was not provided or is empty"
        return $status
    }
    
    try {
        # Normalize path
        $NormalizedPath = $Path.Replace('/', '\').TrimEnd('\')
        
        # Check if file exists
        if (-not (Test-Path -Path $NormalizedPath -PathType Leaf)) {
            $status.msg = "File '$NormalizedPath' does not exist or is not a file"
            return $status
        }
        
        # Check if path is a directory instead of file
        if (Test-Path -Path $NormalizedPath -PathType Container) {
            $status.msg = "Path '$NormalizedPath' is a directory, not a file. Use RemoveDir for directories."
            return $status
        }
        
        # Get file information
        try {
            $FileInfo = Get-Item -Path $NormalizedPath -Force -ErrorAction Stop
            $status.deletedPath = $FileInfo.FullName
            $status.sizeBytes = $FileInfo.Length
        }
        catch {
            $status.msg = "Failed to access file '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Critical safety check - prevent deletion of system files in critical directories
        $CriticalDirs = @(
            "$env:SystemRoot\System32",
            "$env:SystemRoot\SysWOW64",
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
                $status.msg = "Cannot delete system file '$NormalizedPath' in critical directory. This operation is blocked for system protection."
                return $status
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
            
            $status.msg = "File '$NormalizedPath' has special attributes ($($attributes -join ', ')). Use -Force parameter to delete."
            return $status
        }
        
        # Prepare confirmation message
        $ConfirmMessage = "Permanently delete file '$NormalizedPath' ($($status.sizeBytes) bytes) - THIS CANNOT BE UNDONE"
        
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
                    $status.msg = "Operation cancelled by user"
                    return $status
                }
            }
            
            # Verify the file was deleted
            if (Test-Path -Path $NormalizedPath) {
                $status.msg = "File deletion reported success, but file '$NormalizedPath' still exists"
                return $status
            }
            
            Write-Verbose "Successfully deleted file: $($status.deletedPath) ($($status.sizeBytes) bytes)"
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied when deleting file '$NormalizedPath'. Check your permissions or try running as administrator."
            return $status
        }
        catch [System.IO.IOException] {
            $status.msg = "I/O error when deleting file '$NormalizedPath': $($_.Exception.Message). The file may be in use."
            return $status
        }
        catch {
            $status.msg = "Failed to delete file '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Success - reset status object
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in RemoveFile function: $($_.Exception.Message)"
        return $status
    }
}
