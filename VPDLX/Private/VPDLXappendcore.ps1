<#
.SYNOPSIS
    VPDLXappendcore - Private helper: appends log lines to a physical file.

.DESCRIPTION
    Shared append logic used by the [Logfile] auto-flush and by the public
    VPDLXattachlogfile function. Lines are serialised in the requested format
    and APPENDED to the target file - existing content is never overwritten.

    Supported formats (append-capable only):
      txt, log  - raw log lines
      csv       - "Timestamp","Level","Message"; header only if the file is
                  new or empty
      ndjson    - one compact JSON object per line
    json and html are NOT appendable and are rejected (use VPDLXexportlogfile).

    Encoding: UTF-8. A BOM is written only when the file is created (the .NET
    AppendAllText behaviour), unless -NoBOM is given.
    The target directory is created if missing. Nothing is thrown; the result
    is returned via VPDLXreturn (code 0 = success, -1 = failure, data = path).

.PARAMETER FilePath   Full path of the target file.
.PARAMETER Lines      Formatted log lines to append.
.PARAMETER Format     txt | log | csv | ndjson
.PARAMETER NoBOM      Write new files as BOM-free UTF-8.

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.07
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 30.10.2026
    Scope   : Private - dot-sourced by VPDLX.psm1, not exported
#>

function VPDLXappendcore {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Lines,

        [Parameter(Mandatory = $true)]
        [string] $Format,

        [switch] $NoBOM
    )

    try {
        [string] $fmt = $Format.Trim().ToLower()
        if ($fmt -notin @('txt', 'log', 'csv', 'ndjson')) {
            return VPDLXreturn -Code -1 -Message (
                "VPDLXappendcore: Format '$Format' is not appendable. " +
                'Valid formats: txt, log, csv, ndjson.'
            )
        }

        if ($null -eq $Lines -or $Lines.Count -eq 0) {
            return VPDLXreturn -Code 0 -Message 'VPDLXappendcore: Nothing to append.' -Data $FilePath
        }

        # Ensure the target directory exists.
        [string] $dir = [System.IO.Path]::GetDirectoryName($FilePath)
        if (-not [string]::IsNullOrEmpty($dir) -and
            -not [System.IO.Directory]::Exists($dir)) {
            [void][System.IO.Directory]::CreateDirectory($dir)
        }

        # New or empty file? (decides about the CSV header)
        [bool] $isNew = (-not [System.IO.File]::Exists($FilePath)) -or
                        (([System.IO.FileInfo]::new($FilePath)).Length -eq 0)

        $out = [System.Collections.Generic.List[string]]::new()

        switch ($fmt) {
            { $_ -in 'txt', 'log' } {
                foreach ($l in $Lines) { $out.Add($l) }
            }
            'csv' {
                if ($isNew) { $out.Add('"Timestamp","Level","Message"') }
                foreach ($l in $Lines) {
                    $p = VPDLXparseentry -Line $l
                    $out.Add(('"{0}","{1}","{2}"' -f
                        ($p.Timestamp -replace '"', '""'),
                        ($p.Level     -replace '"', '""'),
                        ($p.Message   -replace '"', '""')))
                }
            }
            'ndjson' {
                foreach ($l in $Lines) {
                    $p = VPDLXparseentry -Line $l
                    $out.Add(([ordered]@{
                        Timestamp = $p.Timestamp
                        Level     = $p.Level
                        Message   = $p.Message
                    } | ConvertTo-Json -Compress))
                }
            }
        }

        [string] $text = ($out -join [System.Environment]::NewLine) + [System.Environment]::NewLine
        $encoding = [System.Text.UTF8Encoding]::new(-not $NoBOM.IsPresent)
        [System.IO.File]::AppendAllText($FilePath, $text, $encoding)

        return VPDLXreturn -Code 0 -Data $FilePath -Message (
            "VPDLXappendcore: $($Lines.Count) line(s) appended to '$FilePath' as '$fmt'."
        )
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            "VPDLXappendcore: Failed to append to '$FilePath'. Error: $($_.Exception.Message)"
        )
    }
}
