function Invoke-UUPRuntimeLog {
    <#
    .SYNOPSIS
        Initialises the runtime log for the uup_download_windows.cmd process.

    .DESCRIPTION
        Creates a fresh, empty runtime log file in the given working directory.
        If an older log with the same name already exists, it is rotated:
        up to KeepCount old logs are kept as <name>.1.log, <name>.2.log, ...
        older ones are removed.

        Returns the full path to the newly created (empty) log file.

    .PARAMETER WorkingDir
        Directory where the log file is created.

    .PARAMETER LogName
        Base file name of the runtime log (e.g. 'uup.runtime.log').

    .PARAMETER KeepCount
        How many rotated (old) logs to keep. Defaults to 5.

    .OUTPUTS
        [string] Full path to the new empty log file, or $null on failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDir,
        [Parameter(Mandatory = $true)][string]$LogName,
        [Parameter(Mandatory = $false)][int]$KeepCount = 5
    )

    try {
        $LogPath = Join-Path $WorkingDir $LogName

        # Rotate: shift existing logs (.5 is removed, .4 -> .5, ... current -> .1)
        if (Test-Path $LogPath -PathType Leaf) {
            # Remove oldest rotated log
            $OldestPath = "$LogPath.$KeepCount"
            if (Test-Path $OldestPath -PathType Leaf) {
                Remove-Item $OldestPath -Force -ErrorAction SilentlyContinue
            }
            # Shift rotated logs: .4 -> .5, .3 -> .4, ...
            for ($i = ($KeepCount - 1); $i -ge 1; $i--) {
                $Src = "$LogPath.$i"
                $Dst = "$LogPath.$($i + 1)"
                if (Test-Path $Src -PathType Leaf) {
                    Rename-Item -Path $Src -NewName $Dst -Force -ErrorAction SilentlyContinue
                }
            }
            # Rotate current log to .1
            Rename-Item -Path $LogPath -NewName "$LogPath.1" -Force -ErrorAction SilentlyContinue
        }

        # Create fresh empty log
        $null = New-Item -Path $LogPath -ItemType File -Force -ErrorAction Stop
        return $LogPath
    }
    catch {
        Write-Warning "Invoke-UUPRuntimeLog: Failed to initialise log '$LogName': $($_.Exception.Message)"
        return $null
    }
}
