function RenameUUPDiso {
    <#
    .SYNOPSIS
        Renames the ISO file found in the UUPDump working directory.

    .DESCRIPTION
        RenameUUPDiso searches the specified UUPDump working directory for exactly one
        file with a .iso extension. When found, the file is renamed to the name provided
        via the ISOname parameter. The .iso extension is automatically appended (and any
        .iso extension already present in ISOname is stripped first to prevent duplication
        such as 'Win11.iso.iso').

        The function enforces that:
        - The UUPDdir directory must exist
        - Exactly one .iso file must be present (no file or multiple files causes failure)
        - The resulting renamed file must be verifiable on disk

    .PARAMETER UUPDdir
        Full path to the UUPDump working directory. The directory must exist.

    .PARAMETER ISOname
        The new base name for the ISO file (without .iso extension).
        If the value accidentally ends with '.iso', the extension is stripped automatically
        to prevent a double extension (e.g. 'Win11_24H2.iso' becomes 'Win11_24H2').

    .OUTPUTS
        PSCustomObject with fields:
        .code  »  0 = Success | -1 = Error
        .msg   »  Description of the result or error
        .data  »  Full path to the renamed ISO file on success, $null on failure

    .EXAMPLE
        $result = RenameUUPDiso -UUPDdir 'C:\WinISO\uupdump' -ISOname 'Win11_24H2_amd64_Pro_Custom'
        if ($result.code -eq 0) { Write-Host "ISO renamed to: $($result.data)" }

    .EXAMPLE
        # ISOname with accidental .iso extension – handled gracefully
        $result = RenameUUPDiso -UUPDdir 'C:\WinISO\uupdump' -ISOname 'Win11_24H2_Pro.iso'
        # Result: file is renamed to 'Win11_24H2_Pro.iso' (no double extension)

    .NOTES
        Dependencies:
        - Private function OPSreturn must be available (loaded via module)
        - Requires PowerShell 5.1 or higher
        - Exactly one .iso file must be present in UUPDdir
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Full path to the UUPDump working directory (must exist).")]
        [ValidateNotNullOrEmpty()]
        [string]$UUPDdir,

        [Parameter(Mandatory = $true, HelpMessage = "New base name for the ISO file (without .iso extension).")]
        [ValidateNotNullOrEmpty()]
        [string]$ISOname
    )

    # Retrieve module-scope variables via the AppScope getter
    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData  = AppScope -KeyID 'appenv'

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 1 » Validate that the UUPDump directory exists
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if (-not (Test-Path -Path $UUPDdir -PathType Container)) {
            return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! Directory does not exist: '$UUPDdir'")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! Error validating directory '$UUPDdir': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 2 » Strip any trailing .iso extension from ISOname (prevent duplication)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $CleanISOname = $ISOname.Trim()

    if ($CleanISOname.ToLower().EndsWith('.iso')) {
        $CleanISOname = $CleanISOname.Substring(0, $CleanISOname.Length - 4)
    }

    # Validate that the cleaned name is not empty after stripping
    if ([string]::IsNullOrWhiteSpace($CleanISOname)) {
        return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! Parameter 'ISOname' is empty or contains only the '.iso' extension.")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 3 » Find the ISO file in the UUPDump directory
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ISOfile = $null

    try {
        $ISOcandidates = Get-ChildItem -Path $UUPDdir -Filter '*.iso' -File -ErrorAction SilentlyContinue

        if (-not $ISOcandidates -or $ISOcandidates.Count -eq 0) {
            return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! No .iso file found in directory: '$UUPDdir'")
        }

        if ($ISOcandidates.Count -gt 1) {
            $ISONames = ($ISOcandidates | Select-Object -ExpandProperty Name) -join ', '
            return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! More than one .iso file found in '$UUPDdir'. Found: $ISONames. Please specify which file to rename manually.")
        }

        $ISOfile = $ISOcandidates[0]
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! Error searching for ISO file in '$UUPDdir': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 4 » Build the new full target path and check for name collision
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $NewFileName   = "$CleanISOname.iso"
    $NewFilePath   = [System.IO.Path]::Combine($UUPDdir, $NewFileName)
    $CurrentPath   = $ISOfile.FullName

    # If the ISO already has the desired name, return success immediately
    if ($CurrentPath -eq $NewFilePath) {
        return (OPSreturn -Code 0 -Message "RenameUUPDiso: ISO file already has the desired name '$NewFileName'. No rename necessary." -Data $CurrentPath)
    }

    # If a different file with the new name already exists, report a conflict
    if (Test-Path -Path $NewFilePath -PathType Leaf) {
        return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! A file named '$NewFileName' already exists in '$UUPDdir'. Please remove it first or choose a different name.")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 5 » Perform the rename operation
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        Rename-Item -Path $CurrentPath -NewName $NewFileName -Force -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! Could not rename '$($ISOfile.Name)' to '$NewFileName': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 6 » Verify that the renamed file exists on disk
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if (-not (Test-Path -Path $NewFilePath -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! Rename operation completed but the renamed file was not found at: '$NewFilePath'")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function RenameUUPDiso failed! Error verifying renamed file at '$NewFilePath': $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # SUCCESS » ISO file renamed and verified
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    return (OPSreturn -Code 0 -Message "RenameUUPDiso successful! '$($ISOfile.Name)' was renamed to '$NewFileName' in '$UUPDdir'." -Data $NewFilePath)
}
