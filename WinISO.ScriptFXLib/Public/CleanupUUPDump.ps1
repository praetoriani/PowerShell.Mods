function CleanupUUPDump {
    <#
    .SYNOPSIS
        Cleans up the UUPDump working directory, retaining only the ISO file.

    .DESCRIPTION
        CleanupUUPDump removes all files and subdirectories from the specified UUPDump
        working directory – with the sole exception of any .iso file that may be present.

        This function is typically called after the uup_download_windows.cmd conversion
        script has completed and the ISO file has been built. It reclaims the disk space
        that was occupied by the downloaded UUP files, binary tools, batch scripts, and
        temporary conversion artifacts.

        The function:
        - Validates that the provided directory path exists
        - Detects and protects any .iso file(s) found in the root of the directory
        - Recursively deletes all subdirectories
        - Deletes all non-ISO files from the directory root
        - Reports how many items were removed

    .PARAMETER UUPDdir
        Full path to the UUPDump working directory. The directory must exist.

    .OUTPUTS
        PSCustomObject with fields:
        .code  »  0 = Success | -1 = Error
        .msg   »  Description of the result or error
        .data  »  Number of items (files + directories) removed as [int], or $null on failure

    .EXAMPLE
        $result = CleanupUUPDump -UUPDdir 'C:\WinISO\uupdump'
        if ($result.code -eq 0) { Write-Host "Removed $($result.data) items." }

    .NOTES
        Dependencies:
        - Private function OPSreturn must be available (loaded via module)
        - Requires PowerShell 5.1 or higher
        - The UUPDdir path must point to a directory that already exists
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Full path to the UUPDump working directory (must exist).")]
        [ValidateNotNullOrEmpty()]
        [string]$UUPDdir
    )

    # Retrieve module-scope variables via the AppScope getter
    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData  = AppScope -KeyID 'appenv'

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 1 » Validate that the UUPDump directory exists
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if (-not (Test-Path -Path $UUPDdir -PathType Container)) {
            return (OPSreturn -Code -1 -Message "Function CleanupUUPDump failed! Directory does not exist: '$UUPDdir'")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function CleanupUUPDump failed! Error validating directory '$UUPDdir': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 2 » Identify any ISO file(s) in the directory root to protect them
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ProtectedISOFiles = @()

    try {
        # Search only the root of UUPDdir (not recursively) for ISO files
        $ISOcandidates = Get-ChildItem -Path $UUPDdir -Filter '*.iso' -File -ErrorAction SilentlyContinue

        if ($ISOcandidates -and $ISOcandidates.Count -gt 0) {
            $ProtectedISOFiles = $ISOcandidates | Select-Object -ExpandProperty FullName
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function CleanupUUPDump failed! Error scanning for ISO files in '$UUPDdir': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 3 » Remove all subdirectories recursively
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    [int]$RemovedCount = 0

    try {
        $SubDirectories = Get-ChildItem -Path $UUPDdir -Directory -ErrorAction SilentlyContinue

        foreach ($SubDir in $SubDirectories) {
            try {
                Remove-Item -Path $SubDir.FullName -Recurse -Force -ErrorAction Stop
                $RemovedCount++
            }
            catch {
                # Log individual removal failures but continue with remaining items
                # This prevents one locked file from aborting the entire cleanup
                Write-Warning "CleanupUUPDump: Could not remove directory '$($SubDir.FullName)': $($_.Exception.Message)"
            }
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function CleanupUUPDump failed! Error enumerating subdirectories in '$UUPDdir': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 4 » Remove all non-ISO files from the directory root
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $RootFiles = Get-ChildItem -Path $UUPDdir -File -ErrorAction SilentlyContinue

        foreach ($RootFile in $RootFiles) {
            # Skip protected ISO files
            if ($ProtectedISOFiles -contains $RootFile.FullName) {
                continue
            }

            try {
                Remove-Item -Path $RootFile.FullName -Force -ErrorAction Stop
                $RemovedCount++
            }
            catch {
                # Log individual removal failures but continue with remaining items
                Write-Warning "CleanupUUPDump: Could not remove file '$($RootFile.FullName)': $($_.Exception.Message)"
            }
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function CleanupUUPDump failed! Error enumerating root files in '$UUPDdir': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # SUCCESS » Cleanup completed
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ISOinfo = if ($ProtectedISOFiles.Count -gt 0) {
        " | $($ProtectedISOFiles.Count) ISO file(s) retained: $(($ProtectedISOFiles | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ', ')"
    } else {
        " | No ISO file found in directory."
    }

    return (OPSreturn -Code 0 -Message "CleanupUUPDump successfully finished! Removed $RemovedCount item(s) from '$UUPDdir'.$ISOinfo" -Data $RemovedCount)
}
