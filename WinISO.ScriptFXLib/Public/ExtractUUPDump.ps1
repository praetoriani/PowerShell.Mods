function ExtractUUPDump {
    <#
    .SYNOPSIS
        Extracts the contents of a UUPDump ZIP archive to a specified target directory.

    .DESCRIPTION
        ExtractUUPDump extracts a previously downloaded UUPDump ZIP file (created by
        DownloadUUPDump or manually obtained from uupdump.net) completely into the
        specified target directory.

        The function provides the following capabilities:
        - Creates the target directory structure automatically if it does not exist
        - Verifies that the ZIP file exists and is accessible before extraction
        - Optional post-extraction integrity check (Verify=1): confirms that the number
          of entries in the ZIP matches the number of files extracted to disk
        - Optional cleanup of the source ZIP file after successful extraction (Cleanup=1)

    .PARAMETER ZIPfile
        Full path to the UUPDump ZIP file. The file must exist and be a valid ZIP archive.

    .PARAMETER Target
        Full path to the destination directory where the ZIP contents will be extracted.
        The directory (including any parent directories) will be created if it does not exist.

    .PARAMETER Verify
        Controls post-extraction integrity verification.
        0 = No verification (faster)
        1 = Verify that all entries from the ZIP were extracted (default)

    .PARAMETER Cleanup
        Controls whether the source ZIP file is deleted after successful extraction.
        0 = Keep the ZIP file (default)
        1 = Delete the ZIP file after successful extraction

    .OUTPUTS
        PSCustomObject with fields:
        .code  »  0 = Success | -1 = Error
        .msg   »  Description of the result or error
        .data  »  Full path to the extraction target directory on success, $null on failure

    .EXAMPLE
        $result = ExtractUUPDump -ZIPfile 'C:\WinISO\uupdump\Win11_24H2.zip' `
                                 -Target  'C:\WinISO\uupdump' `
                                 -Verify  1 `
                                 -Cleanup 0
        if ($result.code -eq 0) { Write-Host "Extracted to: $($result.data)" }

    .EXAMPLE
        # Extract, verify and delete ZIP afterwards
        $result = ExtractUUPDump -ZIPfile 'C:\WinISO\uupdump\Win11_24H2.zip' `
                                 -Target  'C:\WinISO\uupdump' `
                                 -Verify  1 `
                                 -Cleanup 1

    .NOTES
        Dependencies:
        - Private function OPSreturn must be available (loaded via module)
        - Requires .NET 4.5+ for System.IO.Compression.ZipFile
        - Requires PowerShell 5.1 or higher
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Full path to the UUPDump ZIP file (must exist).")]
        [ValidateNotNullOrEmpty()]
        [string]$ZIPfile,

        [Parameter(Mandatory = $true, HelpMessage = "Full path to the target extraction directory.")]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

        [Parameter(Mandatory = $true, HelpMessage = "0 = no verification | 1 = verify completeness (default)")]
        [ValidateSet(0, 1)]
        [int]$Verify,

        [Parameter(Mandatory = $true, HelpMessage = "0 = keep ZIP file (default) | 1 = delete ZIP after extraction")]
        [ValidateSet(0, 1)]
        [int]$Cleanup
    )

    # Retrieve module-scope variables via the AppScope getter
    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData  = AppScope -KeyID 'appenv'

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 1 » Validate that the source ZIP file exists and has a .zip extension
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if ([System.IO.Path]::GetExtension($ZIPfile).ToLower() -ne '.zip') {
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! Parameter 'ZIPfile' must point to a .zip file. Provided: '$ZIPfile'")
        }

        if (-not (Test-Path -Path $ZIPfile -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! ZIP file does not exist: '$ZIPfile'")
        }

        # Verify the file is not empty
        $ZipSize = (Get-Item -Path $ZIPfile).Length
        if ($ZipSize -eq 0) {
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! ZIP file is empty (0 bytes): '$ZIPfile'")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! Error validating ZIP file '$ZIPfile': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 2 » Create target directory if it does not exist
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if (-not (Test-Path -Path $Target -PathType Container)) {
            $null = New-Item -Path $Target -ItemType Directory -Force -ErrorAction Stop
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! Could not create target directory '$Target': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 3 » Load .NET ZipFile class and read the entry count for verification
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    
    [int]$ExpectedEntryCount = 0

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! Could not load System.IO.Compression.FileSystem assembly: $($_.Exception.Message)")
    }
    
    # Count entries in the ZIP before extraction (used for Verify=1 check later)
    if ($Verify -eq 1) {
        try {
            $ZipArchive = [System.IO.Compression.ZipFile]::OpenRead($ZIPfile)
            $ExpectedEntryCount = $ZipArchive.Entries.Count
            $ZipArchive.Dispose()
        }
        catch {
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! Could not open ZIP file to count entries: $($_.Exception.Message)")
        }
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 4 » Extract the complete ZIP archive to the target directory
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        # ExtractToDirectory extracts ALL entries, preserving directory structure.
        # Overwrite flag (true) is only available in .NET 6+; for PS 5.1 compatibility
        # we use the basic overload which throws if a file already exists.
        # To handle re-extraction scenarios we use a manual entry loop instead.
        $ZipArchive = [System.IO.Compression.ZipFile]::OpenRead($ZIPfile)

        foreach ($Entry in $ZipArchive.Entries) {
            $DestinationPath = [System.IO.Path]::Combine($Target, $Entry.FullName)

            # If the entry represents a directory (name ends with '/'), create it
            if ($Entry.FullName.EndsWith('/') -or $Entry.FullName.EndsWith('\')) {
                if (-not (Test-Path -Path $DestinationPath -PathType Container)) {
                    $null = New-Item -Path $DestinationPath -ItemType Directory -Force
                }
                continue
            }

            # Ensure parent directory of the file entry exists
            $EntryDir = [System.IO.Path]::GetDirectoryName($DestinationPath)
            if (-not (Test-Path -Path $EntryDir -PathType Container)) {
                $null = New-Item -Path $EntryDir -ItemType Directory -Force
            }

            # Extract the file entry (overwrite if already present)
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $DestinationPath, $true)
        }

        $ZipArchive.Dispose()
    }
    catch {
        # Dispose archive handle safely if an error occurred mid-extraction
        if ($null -ne $ZipArchive) { try { $ZipArchive.Dispose() } catch { } }
        return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! Error during extraction to '$Target': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 5 » Optional: Verify completeness of extraction
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ($Verify -eq 1) {
        try {
            # Count all files in the target directory (recursively, excluding directories)
            $ExtractedFiles = Get-ChildItem -Path $Target -Recurse -File -ErrorAction Stop
            $ExtractedCount  = $ExtractedFiles.Count

            # ZIP entries include both files and directories; compare only file entries
            # Re-open the archive to count only file entries (not directory entries)
            $ZipArchive      = [System.IO.Compression.ZipFile]::OpenRead($ZIPfile)
            $FileEntryCount  = ($ZipArchive.Entries | Where-Object {
                -not ($_.FullName.EndsWith('/') -or $_.FullName.EndsWith('\'))
            }).Count
            $ZipArchive.Dispose()

            if ($ExtractedCount -lt $FileEntryCount) {
                return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! Extraction appears incomplete. ZIP contains $FileEntryCount file entries but only $ExtractedCount files were found in '$Target'.")
            }
        }
        catch {
            if ($null -ne $ZipArchive) { try { $ZipArchive.Dispose() } catch { } }
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDump failed! Error during extraction verification: $($_.Exception.Message)")
        }
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 6 » Optional: Delete source ZIP file after successful extraction
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ($Cleanup -eq 1) {
        try {
            Remove-Item -Path $ZIPfile -Force -ErrorAction Stop
        }
        catch {
            # Cleanup failure is non-fatal; report as warning within the success message
            return (OPSreturn -Code 0 -Message "ExtractUUPDump completed successfully but could not delete ZIP file '$ZIPfile': $($_.Exception.Message)" -Data $Target)
        }
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # SUCCESS » Extraction (and optional cleanup) completed
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $CleanupInfo = if ($Cleanup -eq 1) { " | ZIP file deleted." } else { " | ZIP file kept." }
    $VerifyInfo  = if ($Verify  -eq 1) { " | Extraction verified." } else { " | No verification performed." }
    return (OPSreturn -Code 0 -Message "ExtractUUPDump successfully finished! Contents extracted to '$Target'.$VerifyInfo$CleanupInfo" -Data $Target)
}
