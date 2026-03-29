function CheckModuleRequirements {
    <#
    .SYNOPSIS
        Verifies that all system dependencies required by WinISO.ScriptFXLib are present.

    .DESCRIPTION
        CheckModuleRequirements performs a comprehensive system audit to validate that every
        dependency required by the WinISO.ScriptFXLib module is correctly installed and
        accessible on the current system.

        Checks performed:
        1.  Operating System          - Windows only; reports OS version
        2.  PowerShell version        - Minimum 5.1 required
        3.  .NET Framework version    - Minimum 4.7.2 (Desktop) / any on PS7+
        4.  Administrator privileges  - DISM operations require elevation
        5.  DISM.exe availability     - System32 or PATH
        6.  DISM PowerShell module    - Mount-WindowsImage, Dismount-WindowsImage, Get-WindowsImage
        7.  robocopy.exe              - Used by ExtractUUPDiso
        8.  cmd.exe                   - Used by CreateUUPDiso
        9.  oscdimg.exe               - Expected at $EnvData['OscdimgExe']
        10. WinISO environment dirs   - Key paths from $script:appenv
        11. Internet connectivity     - HTTPS test against uupdump.net and github.com

        The function ONLY throws a terminating error on a catastrophic runtime exception.
        All individual check failures are recorded and the audit continues.

    .PARAMETER Export
        0 = no export (default) | 1 = write results to
        '<LogfileDir>\WinISO.ScriptFXLib.Requirements.Result.txt'

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [List[PSCustomObject]] where each item has: CheckName, Status, Detail

    .EXAMPLE
        $r = CheckModuleRequirements
        $r.data | Format-Table CheckName, Status, Detail -AutoSize

    .EXAMPLE
        $r = CheckModuleRequirements -Export 1
        Write-Host $r.msg

    .NOTES
        Requires: AppScope, OPSreturn, PowerShell 5.1+, Windows OS.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, 1)]
        [int]$Export = 0
    )

    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData  = AppScope -KeyID 'appenv'

    $Results       = [System.Collections.Generic.List[PSCustomObject]]::new()
    $CriticalFails = 0

    # Inline helper to append a result row
    $AddResult = {
        param([string]$Name, [string]$Status, [string]$Detail = '')
        $script:Results.Add([PSCustomObject]@{
            CheckName = $Name
            Status    = $Status.ToUpper()
            Detail    = $Detail
        })
    }

    # CHECK 1: Operating System (Windows only)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $OSPlatform = [System.Environment]::OSVersion.Platform
        $OSVersion  = [System.Environment]::OSVersion.Version
        if ($OSPlatform -eq 'Win32NT') {
            & $AddResult 'Operating System' '[✓] PASS' "Windows $OSVersion"
        } else {
            & $AddResult 'Operating System' '[✕] FAIL' "Windows required. Detected: $OSPlatform"
            $CriticalFails++
        }
    } catch {
        & $AddResult 'Operating System' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 2: PowerShell version (5.1 minimum)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $PSver = $PSVersionTable.PSVersion
        if ($PSver.Major -gt 5 -or ($PSver.Major -eq 5 -and $PSver.Minor -ge 1)) {
            & $AddResult 'PowerShell Version' '[✓] PASS' "PowerShell $($PSver.Major).$($PSver.Minor)"
        } else {
            & $AddResult 'PowerShell Version' '[✕] FAIL' "Requires 5.1+. Found: $($PSver.Major).$($PSver.Minor)"
            $CriticalFails++
        }
    } catch {
        & $AddResult 'PowerShell Version' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 3: .NET Framework / .NET Runtime
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            $RegPath = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
            if (Test-Path $RegPath) {
                $Rel = (Get-ItemProperty -Path $RegPath -Name Release -ErrorAction Stop).Release
                # 461808 = .NET Framework 4.7.2
                if ($Rel -ge 461808) {
                    & $AddResult '.NET Framework' '[✓] PASS' ".NET 4.7.2+ present (Release key: $Rel)"
                } else {
                    & $AddResult '.NET Framework' '[✕] FAIL' ".NET 4.7.2+ required. Release key: $Rel"
                    $CriticalFails++
                }
            } else {
                & $AddResult '.NET Framework' '[✕] FAIL' "Registry key not found. .NET 4.7.2+ required."
                $CriticalFails++
            }
        } else {
            $FwDesc = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
            & $AddResult '.NET Runtime' '[✓] PASS' $FwDesc
        }
    } catch {
        & $AddResult '.NET Framework' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 4: Administrator privileges
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $WinID     = [Security.Principal.WindowsIdentity]::GetCurrent()
        $WinPrinc  = New-Object Security.Principal.WindowsPrincipal($WinID)
        $IsAdmin   = $WinPrinc.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($IsAdmin) {
            & $AddResult 'Administrator Privileges' '[✓] PASS' "Running elevated."
        } else {
            & $AddResult 'Administrator Privileges' '[✕] FAIL' "Not elevated. DISM and Mount operations require admin rights."
            $CriticalFails++
        }
    } catch {
        & $AddResult 'Administrator Privileges' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 5: dism.exe
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $DismExe = Join-Path $env:SystemRoot 'System32\dism.exe'
        if (Test-Path $DismExe -PathType Leaf) {
            $DismVer = (Get-Item $DismExe).VersionInfo.FileVersionRaw
            & $AddResult 'DISM.exe' '[✓] PASS' "$DismExe (v$DismVer)"
        } else {
            $DismCmd = Get-Command dism.exe -ErrorAction SilentlyContinue
            if ($DismCmd) {
                & $AddResult 'DISM.exe' '[✓] PASS' "Found via PATH: $($DismCmd.Source)"
            } else {
                & $AddResult 'DISM.exe' '[✕] FAIL' "dism.exe not found at '$DismExe' and not in PATH."
                $CriticalFails++
            }
        }
    } catch {
        & $AddResult 'DISM.exe' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 6: DISM PowerShell cmdlets
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $Needed  = @('Mount-WindowsImage', 'Dismount-WindowsImage', 'Get-WindowsImage')
        $Missing = @($Needed | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($Missing.Count -eq 0) {
            & $AddResult 'DISM PowerShell Cmdlets' '[✓] PASS' "All cmdlets available: $($Needed -join ', ')"
        } else {
            & $AddResult 'DISM PowerShell Cmdlets' '[✕] FAIL' "Missing: $($Missing -join ', ')"
            $CriticalFails++
        }
    } catch {
        & $AddResult 'DISM PowerShell Cmdlets' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 7: robocopy.exe
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $RobocopyExe = Join-Path $env:SystemRoot 'System32\robocopy.exe'
        if (Test-Path $RobocopyExe -PathType Leaf) {
            & $AddResult 'robocopy.exe' '[✓] PASS' $RobocopyExe
        } else {
            $RobocopyCmd = Get-Command robocopy.exe -ErrorAction SilentlyContinue
            if ($RobocopyCmd) {
                & $AddResult 'robocopy.exe' '[✓] PASS' "Found via PATH: $($RobocopyCmd.Source)"
            } else {
                & $AddResult 'robocopy.exe' '[✕] FAIL' "robocopy.exe not found. Required by ExtractUUPDiso."
                $CriticalFails++
            }
        }
    } catch {
        & $AddResult 'robocopy.exe' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 8: cmd.exe
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $CmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
        if (Test-Path $CmdExe -PathType Leaf) {
            & $AddResult 'cmd.exe' '[✓] PASS' $CmdExe
        } else {
            & $AddResult 'cmd.exe' '[✕] FAIL' "cmd.exe not found at '$CmdExe'. Required by CreateUUPDiso."
            $CriticalFails++
        }
    } catch {
        & $AddResult 'cmd.exe' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 9: oscdimg.exe
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $OscdimgPath = $EnvData['OscdimgExe']
        if (-not [string]::IsNullOrWhiteSpace($OscdimgPath) -and (Test-Path $OscdimgPath -PathType Leaf)) {
            $OscdimgVer = (Get-Item $OscdimgPath).VersionInfo.FileVersionRaw
            & $AddResult 'oscdimg.exe' '[✓] PASS' "$OscdimgPath (v$OscdimgVer)"
        } else {
            & $AddResult 'oscdimg.exe' '[✕] FAIL' "Not found at: '$OscdimgPath'. Run InitializeEnvironment to download."
            $CriticalFails++
        }
    } catch {
        & $AddResult 'oscdimg.exe' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 10: WinISO environment directories
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $DirChecks = [ordered]@{
            'ISOroot'    = $EnvData['ISOroot']
            'ISOdata'    = $EnvData['ISOdata']
            'MountPoint' = $EnvData['MountPoint']
            'LogfileDir' = $EnvData['LogfileDir']
            'UUPDumpDir' = $EnvData['UUPDumpDir']
            'OscdimgDir' = $EnvData['OscdimgDir']
        }
        $MissingDirs = @()
        foreach ($Entry in $DirChecks.GetEnumerator()) {
            if (-not (Test-Path -Path $Entry.Value -PathType Container)) {
                $MissingDirs += "$($Entry.Key)='$($Entry.Value)'"
            }
        }
        if ($MissingDirs.Count -eq 0) {
            & $AddResult 'WinISO Environment Dirs' '[✓] PASS' "All key directories exist."
        } else {
            & $AddResult 'WinISO Environment Dirs' '[‼] WARNING' "Missing (run InitializeEnvironment): $($MissingDirs -join ' | ')"
        }
    } catch {
        & $AddResult 'WinISO Environment Dirs' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # CHECK 11: Internet connectivity
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $TestURLs  = @('https://uupdump.net', 'https://github.com')
        $ConnLines = @()
        foreach ($URL in $TestURLs) {
            try {
                $Resp = Invoke-WebRequest -Uri $URL -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                $ConnLines += "$URL [HTTP $($Resp.StatusCode)]"
            } catch {
                $ConnLines += "$URL [FAIL: $($_.Exception.Message)]"
            }
        }
        $FailedConns = @($ConnLines | Where-Object { $_ -match '[✕] FAIL' })
        if ($FailedConns.Count -eq 0) {
            & $AddResult 'Internet Connectivity' '[✓] PASS' ($ConnLines -join ' | ')
        } else {
            & $AddResult 'Internet Connectivity' '[‼] WARNING' ($ConnLines -join ' | ')
        }
    } catch {
        & $AddResult 'Internet Connectivity' '[‼] WARNING' "Check failed: $($_.Exception.Message)"
    }

    # EXPORT results to text file (if Export=1)
    if ($Export -eq 1) {
        try {
            $ExportDir  = $EnvData['LogfileDir']
            $ExportFile = Join-Path $ExportDir 'WinISO.ScriptFXLib.Requirements.Result.txt'

            if (-not (Test-Path -Path $ExportDir -PathType Container)) {
                $null = New-Item -Path $ExportDir -ItemType Directory -Force -ErrorAction Stop
            }

            $ExportContent = [System.Collections.Generic.List[string]]::new()
            $ExportContent.Add("WinISO.ScriptFXLib - Requirements Check Result")
            $ExportContent.Add("⋆" * 80)
            $ExportContent.Add("Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
            $ExportContent.Add("Module    : $($AppInfo['AppName']) v$($AppInfo['AppVers'])")
            $ExportContent.Add("⋆" * 80)
            $ExportContent.Add("WinISO.ScriptFXLib written by $($AppInfo['AppDevName'])")
            $ExportContent.Add("URL: $($AppInfo['AppWebsite'])")
            $ExportContent.Add("⋆" * 80)
            $ExportContent.Add("Created on:   $($AppInfo['DateCreate'])")
            $ExportContent.Add("Last updated: $($AppInfo['LastUpdate'])")
            $ExportContent.Add("⋆" * 80)
            $ExportContent.Add("")

            foreach ($Row in $Results) {
                $ExportContent.Add(("[{0,-7}] {1,-32} {2}" -f $Row.Status, $Row.CheckName, $Row.Detail))
            }

            $ExportContent.Add("")
            $ExportContent.Add("⋆" * 80)
            $P = @($Results | Where-Object { $_.Status -eq '[✓] PASS' }).Count
            $W = @($Results | Where-Object { $_.Status -eq '[‼] WARNING' }).Count
            $F = @($Results | Where-Object { $_.Status -eq '[✕] FAIL' }).Count
            $ExportContent.Add("[✓] PASS: $P | [‼] WARNING: $W | [✕] FAIL: $F")
            $ExportContent.Add("")
            $ExportContent.Add("")
            $ExportContent.Add("Please visit $($AppInfo['AppWebsite']) for more information and support.")
            $ExportContent.Add("You can find the Download URLs of some of the requirements inside the README.md file.")
            $ExportContent.Add("")

            $ExportContent | Out-File -FilePath $ExportFile -Encoding UTF8 -Force -ErrorAction Stop
            Write-Verbose "CheckModuleRequirements: Results exported to '$ExportFile'."
        } catch {
            Write-Warning "CheckModuleRequirements: Export failed: $($_.Exception.Message)"
        }
    }

    # Build summary
    $PassCount = @($Results | Where-Object { $_.Status -eq '[✓] PASS' }).Count
    $WarnCount = @($Results | Where-Object { $_.Status -eq '[‼] WARNING' }).Count
    $FailCount = @($Results | Where-Object { $_.Status -eq '[✕] FAIL' }).Count
    $Summary   = "CheckModuleRequirements: $PassCount passed | $WarnCount warnings | $FailCount failed."

    if ($CriticalFails -gt 0) {
        return (OPSreturn -Code -1 -Message "$Summary ($CriticalFails critical failure(s))." -Data $Results)
    }

    return (OPSreturn -Code 0 -Message $Summary -Data $Results)
}
