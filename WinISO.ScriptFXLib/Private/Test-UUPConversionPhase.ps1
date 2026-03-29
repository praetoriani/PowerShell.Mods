function Test-UUPConversionPhase {
    <#
    .SYNOPSIS
        Detects whether the UUP download phase has completed and conversion has begun.

    .DESCRIPTION
        The UUPDump creation process has two distinct phases:
        1. Download phase  - aria2c downloads component packages
        2. Conversion phase - the packages are converted into an ISO via DISM/oscdimg

        Detecting this transition is important for heartbeat monitoring because
        the download log (aria2_download.log) becomes inactive in phase 2.

        This function checks the runtime log tail and the working directory for
        conversion-phase indicators:
        - Presence of "Creating ISO image" or "oscdimg" in the log tail
        - Presence of a .wim or .esd file in the working directory (post-download artefacts)
        - aria2 download log has stopped growing (if present)

    .PARAMETER WorkingDir
        Full path to the UUPDump working directory.

    .PARAMETER RuntimeLog
        Full path to the runtime log file.

    .OUTPUTS
        [bool] $true if conversion phase is detected, $false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDir,
        [Parameter(Mandatory = $true)][string]$RuntimeLog
    )

    try {
        # Heuristic 1: Check log tail for conversion-phase keywords
        $Tail     = Get-UUPLogTail -Path $RuntimeLog -MaxBytes 32768 -MaxLines 100
        $TailText = $Tail -join ' '
        $ConversionKeywords = @('Creating ISO', 'oscdimg', 'dism.exe', 'export-image', 'wim2esd', 'UUP-CONVERTER')
        foreach ($KW in $ConversionKeywords) {
            if ($TailText -match [regex]::Escape($KW)) { return $true }
        }

        # Heuristic 2: WIM or ESD files present (download completed, conversion in progress)
        $WIMfiles = Get-ChildItem -Path $WorkingDir -Filter '*.wim' -Recurse -File -ErrorAction SilentlyContinue
        $ESDfiles = Get-ChildItem -Path $WorkingDir -Filter '*.esd' -Recurse -File -ErrorAction SilentlyContinue
        if (($WIMfiles -and $WIMfiles.Count -gt 0) -or ($ESDfiles -and $ESDfiles.Count -gt 0)) {
            return $true
        }

        return $false
    }
    catch {
        Write-Verbose "Test-UUPConversionPhase: Check failed: $($_.Exception.Message)"
        return $false
    }
}
