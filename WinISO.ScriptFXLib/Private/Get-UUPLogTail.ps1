function Get-UUPLogTail {
    <#
    .SYNOPSIS
        Returns the last N lines (or last MaxBytes bytes) of a log file.

    .DESCRIPTION
        Efficiently reads the tail of a potentially large log file by seeking to
        the end of the file and reading backwards. Returns up to MaxLines lines
        from the last MaxBytes of file content.

    .PARAMETER Path
        Full path to the log file.

    .PARAMETER MaxBytes
        Maximum number of bytes to read from the end of the file. Default: 65536 (64 KB).

    .PARAMETER MaxLines
        Maximum number of lines to return. Default: 200.

    .OUTPUTS
        [string[]] Array of lines from the tail of the file, or empty array on failure.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][long]$MaxBytes = 65536,
        [Parameter(Mandatory = $false)][int]$MaxLines  = 200
    )

    try {
        if (-not (Test-Path $Path -PathType Leaf)) { return @() }

        $FileSize = (Get-Item $Path -ErrorAction Stop).Length
        if ($FileSize -eq 0) { return @() }

        $ReadBytes = [Math]::Min($MaxBytes, $FileSize)
        $Offset    = $FileSize - $ReadBytes

        $FS     = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $null   = $FS.Seek($Offset, [System.IO.SeekOrigin]::Begin)
        $Buffer = New-Object byte[] $ReadBytes
        $null   = $FS.Read($Buffer, 0, $ReadBytes)
        $FS.Close()
        $FS.Dispose()

        $Text  = [System.Text.Encoding]::Default.GetString($Buffer)
        $Lines = $Text -split "`r?`n"

        # Return last MaxLines lines
        if ($Lines.Count -gt $MaxLines) {
            return $Lines[($Lines.Count - $MaxLines)..($Lines.Count - 1)]
        }
        return $Lines
    }
    catch {
        Write-Verbose "Get-UUPLogTail: Could not read tail of '$Path': $($_.Exception.Message)"
        return @()
    }
}
