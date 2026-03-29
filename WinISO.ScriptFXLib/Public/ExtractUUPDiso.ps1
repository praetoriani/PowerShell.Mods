function ExtractUUPDiso {
    <#
    .SYNOPSIS
        Extracts (copies) the full contents of a UUPDump ISO file to a target directory.

    .DESCRIPTION
        ExtractUUPDiso mounts a Windows 11 ISO image using the PowerShell Mount-DiskImage
        cmdlet, copies the entire contents of the mounted volume to the specified target
        directory, and then dismounts the image again – leaving no mounted drive behind.

        The function ensures:
        - The source ISO file exists before attempting to mount it
        - The target directory is created automatically if it does not exist
        - ALL files and directories from the ISO are copied completely (verified by
          comparing file counts between source and destination)
        - The ISO image is always dismounted in a finally-block, even on errors

        Note: This function requires administrator privileges because Mount-DiskImage
        performs a system-level disk operation.

    .PARAMETER UUPDiso
        Full path to the ISO file to extract. The file must exist and have a .iso extension.

    .PARAMETER Target
        Full path to the target directory where the ISO contents will be copied.
        The directory structure is created automatically if it does not exist.

    .OUTPUTS
        PSCustomObject with fields:
        .code  »  0 = Success | -1 = Error
        .msg   »  Description of the result or error
        .data  »  Full path to the target directory on success, $null on failure

    .EXAMPLE
        $result = ExtractUUPDiso -UUPDiso 'C:\WinISO\uupdump\Win11_24H2_Pro.iso' `
                                 -Target  'C:\WinISO\DATA'
        if ($result.code -eq 0) { Write-Host "ISO extracted to: $($result.data)" }

    .NOTES
        Dependencies:
        - Private function OPSreturn must be available (loaded via module)
        - Requires PowerShell 5.1 or higher
        - Requires administrator privileges (for Mount-DiskImage)
        - Requires Windows 8 / Windows Server 2012 or later (Mount-DiskImage availability)
        - The ISO image is always safely dismounted via a finally-block
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Full path to the ISO file (must exist).")]
        [ValidateNotNullOrEmpty()]
        [string]$UUPDiso,

        [Parameter(Mandatory = $true, HelpMessage = "Full path to the target directory for extracted ISO contents.")]
        [ValidateNotNullOrEmpty()]
        [string]$Target
    )

    # Retrieve module-scope variables via the AppScope getter
    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData  = AppScope -KeyID 'appenv'

    # Track the mounted disk image object for safe dismount in finally-block
    $MountedImage = $null

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 1 » Validate the source ISO file
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if ([System.IO.Path]::GetExtension($UUPDiso).ToLower() -ne '.iso') {
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Parameter 'UUPDiso' must point to a .iso file. Provided: '$UUPDiso'")
        }

        if (-not (Test-Path -Path $UUPDiso -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! ISO file does not exist: '$UUPDiso'")
        }

        $ISOsize = (Get-Item -Path $UUPDiso).Length
        if ($ISOsize -eq 0) {
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! ISO file is empty (0 bytes): '$UUPDiso'")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Error validating ISO file '$UUPDiso': $($_.Exception.Message)")
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
        return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Could not create target directory '$Target': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 3 » Mount the ISO image and determine the drive letter
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        # Mount-DiskImage returns the DiskImage object but does not include the drive letter yet
        $MountedImage = Mount-DiskImage -ImagePath $UUPDiso -PassThru -ErrorAction Stop

        # Get-Volume requires the disk number – retrieve it via the mounted image
        $DiskNumber  = $MountedImage.Number
        $Volume      = Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop |
                       Where-Object { $_.Type -ne 'Reserved' } |
                       Select-Object -First 1

        if (-not $Volume) {
            Dismount-DiskImage -ImagePath $UUPDiso -ErrorAction SilentlyContinue | Out-Null
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Could not determine drive letter after mounting ISO: '$UUPDiso'")
        }

        $DriveLetter = "$($Volume.DriveLetter):\"

        # Verify the drive is actually accessible
        if (-not (Test-Path -Path $DriveLetter)) {
            Dismount-DiskImage -ImagePath $UUPDiso -ErrorAction SilentlyContinue | Out-Null
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Mounted drive '$DriveLetter' is not accessible.")
        }
    }
    catch {
        # Attempt dismount if mount partially succeeded
        if ($null -ne $MountedImage) {
            try { Dismount-DiskImage -ImagePath $UUPDiso -ErrorAction SilentlyContinue | Out-Null } catch { }
        }
        return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Could not mount ISO image '$UUPDiso': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 4 » Copy all contents from the mounted ISO to the target directory
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # Use a try/finally block to guarantee the ISO is always dismounted
    try {
        # Get all items from the ISO root (files and directories, recursively)
        $SourceItems = Get-ChildItem -Path $DriveLetter -Recurse -Force -ErrorAction Stop

        # Count source files for completeness verification
        $SourceFileCount = ($SourceItems | Where-Object { -not $_.PSIsContainer }).Count

        # Copy the entire ISO contents using robocopy for reliability:
        # /E  = copy subdirectories including empty ones
        # /COPYALL = copy all file information
        # /R:3 = retry 3 times on failure
        # /W:5 = wait 5 seconds between retries
        # /NP  = no progress percentage (cleaner output)
        # /NFL = no file list in output
        # /NDL = no directory list in output
        $RobocopyArgs = @(
            $DriveLetter.TrimEnd('\'),
            $Target,
            '/E',
            '/COPYALL',
            '/R:3',
            '/W:5',
            '/NP',
            '/NFL',
            '/NDL'
        )

        $RobocopyProcess = Start-Process -FilePath 'robocopy.exe' `
                                         -ArgumentList $RobocopyArgs `
                                         -Wait -PassThru -NoNewWindow `
                                         -ErrorAction Stop

        # Robocopy exit codes: 0 = no files copied (none needed), 1 = files copied OK,
        # 2 = extra files/dirs detected (non-fatal), 3 = files copied + extras detected.
        # Exit codes >= 8 indicate errors.
        if ($RobocopyProcess.ExitCode -ge 8) {
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Robocopy reported an error (exit code $($RobocopyProcess.ExitCode)) while copying from '$DriveLetter' to '$Target'.")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Error copying ISO contents from '$DriveLetter' to '$Target': $($_.Exception.Message)")
    }
    finally {
        # Always dismount the ISO image – even if an exception occurred above
        try {
            Dismount-DiskImage -ImagePath $UUPDiso -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            # Dismount failure is non-critical at this point; the copy result already determined success/failure
        }
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 5 » Verify completeness: compare file counts
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $CopiedFiles     = Get-ChildItem -Path $Target -Recurse -File -Force -ErrorAction Stop
        $CopiedFileCount = $CopiedFiles.Count

        if ($CopiedFileCount -lt $SourceFileCount) {
            return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Copy appears incomplete. ISO contained $SourceFileCount files but only $CopiedFileCount files found in '$Target'.")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function ExtractUUPDiso failed! Error during completeness verification in '$Target': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # SUCCESS » ISO extracted and verified
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ISOname = [System.IO.Path]::GetFileName($UUPDiso)
    return (OPSreturn -Code 0 -Message "ExtractUUPDiso successfully finished! '$ISOname' extracted to '$Target' ($CopiedFileCount files)." -Data $Target)
}
