function ImageIndexLookup {
    <#
    .SYNOPSIS
        Searches a WIM image file for a Windows edition and returns its image index.

    .DESCRIPTION
        Uses Get-WindowsImage (DISM PowerShell module) to enumerate all images in a WIM file,
        then performs a case-insensitive substring search against ImageName.

        - Zero matches      >> fails with a list of available editions
        - Multiple matches  >> fails and lists all ambiguous matches (caller must narrow search)
        - Exactly one match >> returns the ImageIndex as [int] via .data

    .PARAMETER WIMimage
        Full path to the .wim file (must exist).

    .PARAMETER ImageLookup
        Edition search string (case-insensitive substring). E.g. 'Pro', 'Home', 'Enterprise'.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [int] ImageIndex on success, $null on failure.

    .EXAMPLE
        $r = ImageIndexLookup -WIMimage 'C:\WinISO\DATA\sources\install.wim' -ImageLookup 'Pro'
        if ($r.code -eq 0) { Write-Host "Index: $($r.data)" }

    .NOTES
        Requires: DISM PowerShell module, OPSreturn, administrator privileges.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Full path to the .wim file (must exist).")]
        [ValidateNotNullOrEmpty()]
        [string]$WIMimage,

        [Parameter(Mandatory = $true, HelpMessage = "Edition search string (case-insensitive substring).")]
        [ValidateNotNullOrEmpty()]
        [string]$ImageLookup
    )

    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData  = AppScope -KeyID 'appenv'

    $SearchTerm = $ImageLookup.Trim()

    # -- Validate WIM file --
    try {
        if ([System.IO.Path]::GetExtension($WIMimage).ToLower() -ne '.wim') {
            return (OPSreturn -Code -1 -Message "ImageIndexLookup failed! 'WIMimage' must point to a .wim file. Provided: '$WIMimage'")
        }
        if (-not (Test-Path -Path $WIMimage -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "ImageIndexLookup failed! WIM file not found: '$WIMimage'")
        }
        if ((Get-Item -Path $WIMimage).Length -eq 0) {
            return (OPSreturn -Code -1 -Message "ImageIndexLookup failed! WIM file is empty (0 bytes): '$WIMimage'")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "ImageIndexLookup failed! Error validating WIM file: $($_.Exception.Message)")
    }

    # -- Query all images --
    $AllImages = $null
    try {
        $AllImages = Get-WindowsImage -ImagePath $WIMimage -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code -1 -Message "ImageIndexLookup failed! Get-WindowsImage error for '$WIMimage': $($_.Exception.Message)")
    }

    if (-not $AllImages -or $AllImages.Count -eq 0) {
        return (OPSreturn -Code -1 -Message "ImageIndexLookup failed! No image entries found in WIM: '$WIMimage'")
    }

    $AvailableList = ($AllImages | ForEach-Object { "  [$($_.ImageIndex)] $($_.ImageName)" }) -join "`n"

    # -- Case-insensitive substring search --
    $Matches = @($AllImages | Where-Object { $_.ImageName -like "*$SearchTerm*" })

    if ($Matches.Count -eq 0) {
        return (OPSreturn -Code -1 -Message "ImageIndexLookup failed! No match for '$SearchTerm' in '$WIMimage'.`nAvailable images:`n$AvailableList")
    }

    if ($Matches.Count -gt 1) {
        $MatchList = ($Matches | ForEach-Object { "  [$($_.ImageIndex)] $($_.ImageName)" }) -join "`n"
        return (OPSreturn -Code -1 -Message "ImageIndexLookup failed! '$SearchTerm' is ambiguous ($($Matches.Count) matches). Refine your search.`nAmbiguous matches:`n$MatchList`nAll available images:`n$AvailableList")
    }

    $Found    = $Matches[0]
    $IndexInt = [int]$Found.ImageIndex
    return (OPSreturn -Code 0 -Message "ImageIndexLookup successful! '$($Found.ImageName)' at index $IndexInt in '$WIMimage'." -Data $IndexInt)
}
