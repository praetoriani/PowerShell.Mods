<#
.SYNOPSIS
    Demo-002 - Buffer limit and continuous append to physical log files (VPDLX v1.02.07)

.DESCRIPTION
    Non-interactive demonstration of the v1.02.07 features:
        01 - Ring buffer (no target): MaxEntries drops the oldest entries
        02 - Auto-flush: buffer is APPENDED to a file at MaxEntries
        03 - Print() in chunks and flush on Destroy()
        04 - CSV and NDJSON targets, one file per day (-DailyFile)
        05 - Manual append with VPDLXattachlogfile (-Clear)
        06 - Export (snapshot) vs. attach (append)
    All files are written to a temporary folder that is removed at the end.

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.07
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 30.10.2026

    Usage:
        .\VPDLX\Examples\Demo-002.ps1
#>

$ErrorActionPreference = 'Stop'

function Show-Step { param([string] $Text) Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }

$moduleManifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'VPDLX.psd1'
Import-Module $moduleManifest -Force

$target = Join-Path ([System.IO.Path]::GetTempPath()) ('VPDLX-Demo002-' + [guid]::NewGuid().ToString('N'))
New-Item -Path $target -ItemType Directory | Out-Null

try {
    Show-Step '01 - Ring buffer: MaxEntries 5 without a target'
    $ring = (VPDLXnewlogfile -Logfile 'DemoRing' -MaxEntries 5).data
    1..8 | ForEach-Object { $ring.Info("Ring entry $_") }
    Write-Host "EntryCount (buffer size): $($ring.EntryCount())  -> first entry: $($ring.Read(1))"
    $ring.Destroy()

    Show-Step '02 - Auto-flush: append to a txt file every 5 entries'
    $app = (VPDLXnewlogfile -Logfile 'DemoApp' -MaxEntries 5 -AttachPath $target -AttachAs txt).data
    1..4 | ForEach-Object { $app.Info("App entry $_") }
    Write-Host "After 4 entries - file exists: $(Test-Path (Join-Path $target 'DemoApp.txt'))"
    $app.Info('App entry 5')
    Write-Host "After 5 entries - lines in file: $((Get-Content (Join-Path $target 'DemoApp.txt')).Count), buffer: $($app.EntryCount())"
    6..12 | ForEach-Object { $app.Info("App entry $_") }
    Write-Host "After 12 entries - lines in file: $((Get-Content (Join-Path $target 'DemoApp.txt')).Count), buffer: $($app.EntryCount())"

    Show-Step '03 - Destroy() appends the remaining buffer'
    $app.Destroy()
    Write-Host "Lines in file after Destroy(): $((Get-Content (Join-Path $target 'DemoApp.txt')).Count)"

    Show-Step '04 - CSV target and one file per day'
    $csv = (VPDLXnewlogfile -Logfile 'DemoCsv' -MaxEntries 3 -AttachPath $target -AttachAs csv).data
    1..7 | ForEach-Object { $csv.Warning("CSV entry $_") }
    $csv.Destroy()
    Write-Host 'CSV content (header once, 7 rows):'
    Import-Csv (Join-Path $target 'DemoCsv.csv') | Format-Table -AutoSize | Out-String | Write-Host
    $day = (VPDLXnewlogfile -Logfile 'DemoDay' -MaxEntries 2 -AttachPath $target -DailyFile).data
    $day.Info('Daily entry 1'); $day.Info('Daily entry 2')
    Write-Host "Daily file: $($day.GetAttachFile())"
    $day.Destroy()

    Show-Step '05 - VPDLXattachlogfile: manual append with -Clear'
    $man = (VPDLXnewlogfile -Logfile 'DemoManual' -MaxEntries 0).data
    $man.Info('Manual entry 1'); $man.Error('Manual entry 2')
    $r = VPDLXattachlogfile -Logfile 'DemoManual' -LogPath $target -AttachAs ndjson -Clear
    Write-Host "Result: code=$($r.code) | $($r.msg)"
    Write-Host "Buffer after -Clear: $($man.EntryCount())"
    $r = VPDLXattachlogfile -Logfile 'DemoManual' -LogPath $target -AttachAs json
    Write-Host "json is not appendable -> code=$($r.code)"
    $man.Destroy()

    Show-Step '06 - Export (snapshot) vs. attach (append)'
    $exp = (VPDLXnewlogfile -Logfile 'DemoExport' -MaxEntries 0).data
    $exp.Info('Snapshot entry')
    $e = VPDLXexportlogfile -Logfile 'DemoExport' -LogPath $target -ExportAs html
    Write-Host "Export: code=$($e.code) -> $($e.data)"
    $exp.Destroy()

    Write-Host ''
    Write-Host 'Files created:' -ForegroundColor Green
    Get-ChildItem $target | Select-Object Name, Length | Format-Table -AutoSize | Out-String | Write-Host
}
finally {
    Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $target) { Write-Warning "Temporary demo folder could not be removed: $target" }
    else { Write-Host 'Temporary demo folder removed.' }
}
