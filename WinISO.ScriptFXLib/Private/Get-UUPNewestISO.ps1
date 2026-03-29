function Get-UUPNewestISO {
    <#
    .SYNOPSIS
        Locates the newest .iso file in a UUPDump working directory.

    .DESCRIPTION
        Searches first in the root of the specified directory for *.iso files.
        If none are found at the root level, a recursive search is performed to handle
        cases where uup_download_windows.cmd places the ISO in a sub-folder.

        Returns the most recently written .iso file as a FileInfo object, or $null.

    .PARAMETER WorkingDir
        Full path to the directory to search.

    .OUTPUTS
        [System.IO.FileInfo] The newest ISO FileInfo object, or $null if none found.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDir
    )

    try {
        # Root-level search first (fastest, most common)
        $RootISOs = Get-ChildItem -Path $WorkingDir -Filter '*.iso' -File -ErrorAction SilentlyContinue
        if ($RootISOs -and $RootISOs.Count -gt 0) {
            return ($RootISOs | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        }

        # Fallback: recursive (uup_download_windows.cmd sometimes creates a sub-folder)
        $AllISOs = Get-ChildItem -Path $WorkingDir -Filter '*.iso' -File -Recurse -ErrorAction SilentlyContinue
        if ($AllISOs -and $AllISOs.Count -gt 0) {
            return ($AllISOs | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        }

        return $null
    }
    catch {
        Write-Verbose "Get-UUPNewestISO: Search failed in '$WorkingDir': $($_.Exception.Message)"
        return $null
    }
}
