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

        Status codes per check:
        PASS  - Requirement fully met.
        FAIL  - Requirement not met; no known automated fix exists.
        INFO  - Requirement not currently met but CAN be resolved automatically
                (e.g. by calling InitializeEnvironment). No manual action needed.
        WARN  - Requirement not met; resolution requires manual action by the user
                (e.g. re-running the script elevated, upgrading PowerShell).

        Overall result logic:
        - code  0 : No FAIL entries - all checks are PASS, INFO, or WARN.
        - code -1 : At least one FAIL entry that cannot be resolved automatically.

        All per-check results are written to $script:appverify so they are available
        globally throughout the module after the function returns.

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
        Version:   1.00.05
        Requires:  AppScope, WinISOcore, OPSreturn, PowerShell 5.1+, Windows OS.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, 1)]
        [int]$Export = 0
    )

    # Import global vars using getter-functionality
    $appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read' -Unwrap
    $appenv  = WinISOcore -Scope 'env' -GlobalVar 'appenv'  -Permission 'read' -Unwrap
    $appcore = WinISOcore -Scope 'env' -GlobalVar 'appcore' -Permission 'read' -Unwrap

    $Results   = [System.Collections.Generic.List[PSCustomObject]]::new()
    $FailCount = 0

    # Inline helper - adds one result entry and simultaneously writes it to $script:appverify
    # Parameters: CheckName (display), Status (PASS/FAIL/INFO/WARN), Detail (string),
    #             VerifyKey (the $script:appverify key to update, or '' to skip)
    $AddResult = {
        param([string]$Name, [string]$Status, [string]$Detail = '', [string]$VerifyKey = '')
        $StatusUpper = $Status.ToUpper()
        $Results.Add([PSCustomObject]@{
            CheckName = $Name
            Status    = $StatusUpper
            Detail    = $Detail
        })
        # Persist into module-scope appverify if a valid key was provided
        if (-not [string]::IsNullOrWhiteSpace($VerifyKey)) {
            $null = WinISOcore -Scope 'env' -GlobalVar 'appverify' -Permission 'write' `
                               -VarKeyID $VerifyKey -SetNewVal $StatusUpper
        }
    }

    # CHECK 1: Operating System (Windows only)
    # Failure cannot be resolved - not running Windows is a hard FAIL.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $OSPlatform = [System.Environment]::OSVersion.Platform
        if ($OSPlatform -eq 'Win32NT') {
            $CimOS      = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $OSCaption  = $CimOS.Caption
            $OSBuild    = $CimOS.BuildNumber
            $OSVersion  = $CimOS.Version
            $DetailStr  = "$OSCaption (Build $OSBuild, v$OSVersion)"
            & $AddResult 'Operating System' 'PASS' $DetailStr 'checkosversion'
        } else {
            & $AddResult 'Operating System' 'FAIL' "Windows required. Detected: $OSPlatform" 'checkosversion'
            $FailCount++
        }
    } catch {
        & $AddResult 'Operating System' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkosversion'
        $FailCount++
    }

    # CHECK 2: PowerShell version (5.1 minimum)
    # Failure cannot be resolved automatically - user must install a newer PowerShell -> WARN.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $PSver = $PSVersionTable.PSVersion
        if ($PSver.Major -gt 5 -or ($PSver.Major -eq 5 -and $PSver.Minor -ge 1)) {
            & $AddResult 'PowerShell Version' 'PASS' "PowerShell $($PSver.Major).$($PSver.Minor)" 'checkpowershell'
        } else {
            & $AddResult 'PowerShell Version' 'WARN' "Requires 5.1+. Found: $($PSver.Major).$($PSver.Minor). Please upgrade PowerShell: https://github.com/PowerShell/PowerShell/releases" 'checkpowershell'
        }
    } catch {
        & $AddResult 'PowerShell Version' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkpowershell'
        $FailCount++
    }

    # CHECK 3: .NET Framework / .NET Runtime
    # Failure cannot be resolved automatically - user must install the framework -> WARN.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            $RegPath = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
            if (Test-Path $RegPath) {
                $Rel = (Get-ItemProperty -Path $RegPath -Name Release -ErrorAction Stop).Release
                # 461808 = .NET Framework 4.7.2
                if ($Rel -ge 461808) {
                    & $AddResult '.NET Framework' 'PASS' ".NET 4.7.2+ present (Release key: $Rel)" 'checkdotnet'
                } else {
                    & $AddResult '.NET Framework' 'WARN' ".NET 4.7.2+ required. Release key: $Rel. Install from: https://dotnet.microsoft.com/en-us/download/dotnet-framework" 'checkdotnet'
                }
            } else {
                & $AddResult '.NET Framework' 'WARN' "Registry key not found. .NET 4.7.2+ required. Install from: https://dotnet.microsoft.com/en-us/download/dotnet-framework" 'checkdotnet'
            }
        } else {
            $FwDesc = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
            & $AddResult '.NET Runtime' 'PASS' $FwDesc 'checkdotnet'
        }
    } catch {
        & $AddResult '.NET Framework' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkdotnet'
        $FailCount++
    }

    # CHECK 4: Administrator privileges
    # Failure cannot be resolved automatically - user must re-run elevated -> WARN.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $WinID    = [Security.Principal.WindowsIdentity]::GetCurrent()
        $WinPrinc = New-Object Security.Principal.WindowsPrincipal($WinID)
        $IsAdmin  = $WinPrinc.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($IsAdmin) {
            & $AddResult 'Administrator Privileges' 'PASS' "Running elevated." 'checkisadmin'
        } else {
            & $AddResult 'Administrator Privileges' 'WARN' "Not elevated. DISM and Mount operations require admin rights. Please re-run this script as Administrator." 'checkisadmin'
        }
    } catch {
        & $AddResult 'Administrator Privileges' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkisadmin'
        $FailCount++
    }

    # CHECK 5: dism.exe
    # dism.exe is a Windows system component - if missing, no automated fix exists -> FAIL.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $DismExe = Join-Path $env:SystemRoot 'System32\dism.exe'
        if (Test-Path $DismExe -PathType Leaf) {
            $DismVer = (Get-Item $DismExe).VersionInfo.FileVersionRaw
            & $AddResult 'DISM.exe' 'PASS' "$DismExe (v$DismVer)" 'checkdismpath'
        } else {
            $DismCmd = Get-Command dism.exe -ErrorAction SilentlyContinue
            if ($DismCmd) {
                & $AddResult 'DISM.exe' 'PASS' "Found via PATH: $($DismCmd.Source)" 'checkdismpath'
            } else {
                & $AddResult 'DISM.exe' 'FAIL' "dism.exe not found at '$DismExe' and not in PATH. This is a required Windows component." 'checkdismpath'
                $FailCount++
            }
        }
    } catch {
        & $AddResult 'DISM.exe' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkdismpath'
        $FailCount++
    }

    # CHECK 6: DISM PowerShell cmdlets
    # Part of the Windows system - if missing, no automated fix exists -> FAIL.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $Needed  = @('Mount-WindowsImage', 'Dismount-WindowsImage', 'Get-WindowsImage')
        $Missing = @($Needed | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($Missing.Count -eq 0) {
            & $AddResult 'DISM PowerShell Cmdlets' 'PASS' "All cmdlets available: $($Needed -join ', ')" 'checkdismmods'
        } else {
            & $AddResult 'DISM PowerShell Cmdlets' 'FAIL' "Missing: $($Missing -join ', '). These are required Windows DISM PowerShell cmdlets." 'checkdismmods'
            $FailCount++
        }
    } catch {
        & $AddResult 'DISM PowerShell Cmdlets' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkdismmods'
        $FailCount++
    }

    # CHECK 7: robocopy.exe
    # Windows system component - if missing, no automated fix exists -> FAIL.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $RobocopyExe = Join-Path $env:SystemRoot 'System32\robocopy.exe'
        if (Test-Path $RobocopyExe -PathType Leaf) {
            & $AddResult 'robocopy.exe' 'PASS' $RobocopyExe 'checkrobocopy'
        } else {
            $RobocopyCmd = Get-Command robocopy.exe -ErrorAction SilentlyContinue
            if ($RobocopyCmd) {
                & $AddResult 'robocopy.exe' 'PASS' "Found via PATH: $($RobocopyCmd.Source)" 'checkrobocopy'
            } else {
                & $AddResult 'robocopy.exe' 'FAIL' "robocopy.exe not found. Required by ExtractUUPDiso. This is a standard Windows tool and should always be present." 'checkrobocopy'
                $FailCount++
            }
        }
    } catch {
        & $AddResult 'robocopy.exe' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkrobocopy'
        $FailCount++
    }

    # CHECK 8: cmd.exe
    # Windows system component - if missing, no automated fix exists -> FAIL.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $CmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
        if (Test-Path $CmdExe -PathType Leaf) {
            & $AddResult 'cmd.exe' 'PASS' $CmdExe 'checkcmd'
        } else {
            & $AddResult 'cmd.exe' 'FAIL' "cmd.exe not found at '$CmdExe'. Required by CreateUUPDiso. This is a required Windows component." 'checkcmd'
            $FailCount++
        }
    } catch {
        & $AddResult 'cmd.exe' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkcmd'
        $FailCount++
    }

    # CHECK 9: oscdimg.exe
    # NOT found = INFO because InitializeEnvironment can automatically download it.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $OscdimgPath = $appenv.OscdimgExe
        if (-not [string]::IsNullOrWhiteSpace($OscdimgPath) -and (Test-Path $OscdimgPath -PathType Leaf)) {
            $OscdimgVer = (Get-Item $OscdimgPath).VersionInfo.FileVersionRaw
            & $AddResult 'oscdimg.exe' 'PASS' "$OscdimgPath (v$OscdimgVer)" 'checkoscdimg'
        } else {
            & $AddResult 'oscdimg.exe' 'INFO' "Not found at: '$OscdimgPath'. Run InitializeEnvironment to download it automatically." 'checkoscdimg'
        }
    } catch {
        & $AddResult 'oscdimg.exe' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkoscdimg'
        $FailCount++
    }

    # CHECK 10: WinISO environment directories
    # NOT found = INFO because InitializeEnvironment can create them automatically.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $DirChecks = [ordered]@{
            'ISOroot'    = $appenv.ISOroot
            'ISOdata'    = $appenv.ISOdata
            'MountPoint' = $appenv.MountPoint
            'LogfileDir' = $appenv.LogfileDir
            'UUPDumpDir' = $appenv.UUPDumpDir
            'OscdimgDir' = $appenv.OscdimgDir
        }
        $MissingDirs = @()
        foreach ($Entry in $DirChecks.GetEnumerator()) {
            if (-not (Test-Path -Path $Entry.Value -PathType Container)) {
                $MissingDirs += "$($Entry.Key)='$($Entry.Value)'"
            }
        }
        if ($MissingDirs.Count -eq 0) {
            & $AddResult 'WinISO Environment Dirs' 'PASS' "All key directories exist." 'checkenvdirs'
        } else {
            & $AddResult 'WinISO Environment Dirs' 'INFO' "Missing directories (run InitializeEnvironment to create them): $($MissingDirs -join ' | ')" 'checkenvdirs'
        }
    } catch {
        & $AddResult 'WinISO Environment Dirs' 'FAIL' "Check failed: $($_.Exception.Message)" 'checkenvdirs'
        $FailCount++
    }

    # CHECK 11: Internet connectivity
    # No automated fix - user must resolve network issues -> WARN.
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
        $FailedConns = @($ConnLines | Where-Object { $_ -match 'FAIL' })
        if ($FailedConns.Count -eq 0) {
            & $AddResult 'Internet Connectivity' 'PASS' ($ConnLines -join ' | ') 'checkinternet'
        } else {
            & $AddResult 'Internet Connectivity' 'WARN' "Some targets unreachable - check your network connection: $($ConnLines -join ' | ')" 'checkinternet'
        }
    } catch {
        & $AddResult 'Internet Connectivity' 'WARN' "Connectivity check failed: $($_.Exception.Message)" 'checkinternet'
    }

    # Write result counters into $script:appverify['result']
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $PassCount = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $InfoCount = @($Results | Where-Object { $_.Status -eq 'INFO' }).Count
    $WarnCount = @($Results | Where-Object { $_.Status -eq 'WARN' }).Count
    $FinalFail = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count

    $null = WinISOcore -Scope 'env' -GlobalVar 'appverify' -Permission 'write' `
                       -VarKeyID 'result' -SetNewVal @{
                           pass = $PassCount
                           fail = $FinalFail
                           info = $InfoCount
                           warn = $WarnCount
                       }

    # EXPORT results to text file (if Export=1)
    if ($Export -eq 1) {
        try {
            $ExportDir  = $appenv.LogfileDir
            $ExportFile = Join-Path $ExportDir "$($appcore.ReqResLog)"

            if (-not (Test-Path -Path $ExportDir -PathType Container)) {
                $null = New-Item -Path $ExportDir -ItemType Directory -Force -ErrorAction Stop
            }

            $ExportContent = [System.Collections.Generic.List[string]]::new()
            $ExportContent.Add("WinISO.ScriptFXLib - Requirements Check Result")
            $ExportContent.Add("+" * 80)
            $ExportContent.Add("Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
            $ExportContent.Add("Module    : $($appinfo.AppName) v$($appinfo.AppVers)")
            $ExportContent.Add("+" * 80)
            $ExportContent.Add("WinISO.ScriptFXLib written by $($appinfo.AppDevName)")
            $ExportContent.Add("URL: $($appinfo.AppWebsite)")
            $ExportContent.Add("+" * 80)
            $ExportContent.Add("Created on:   $($appinfo.DateCreate)")
            $ExportContent.Add("Last updated: $($appinfo.LastUpdate)")
            $ExportContent.Add("+" * 80)
            $ExportContent.Add("")

            foreach ($Row in $Results) {
                $ExportContent.Add(("[{0,-7}] {1,-32} {2}" -f $Row.Status, $Row.CheckName, $Row.Detail))
            }

            $ExportContent.Add("")
            $ExportContent.Add("+" * 80)
            $ExportContent.Add("PASS: $PassCount | INFO: $InfoCount | WARN: $WarnCount | FAIL: $FinalFail")
            $ExportContent.Add("")
            $ExportContent.Add("")

            if ($FinalFail -gt 0) {
                $ExportContent.Add("One or more checks have FAILED with no known automated fix.")
                $ExportContent.Add("Please visit $($appinfo.AppWebsite) for more information and support.")
                $ExportContent.Add("")
                $ExportContent.Add("Official Download Sources:")
                $ExportContent.Add("- PowerShell 7.x        https://github.com/PowerShell/PowerShell/releases")
                $ExportContent.Add("- .NET Framework 4.8    https://dotnet.microsoft.com/en-us/download/dotnet-framework")
                $ExportContent.Add("- Windows ADK           https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install")
            } elseif ($WarnCount -gt 0 -or $InfoCount -gt 0) {
                $ExportContent.Add("All checks passed or have known remediation steps.")
                $ExportContent.Add("- INFO items: Run InitializeEnvironment to resolve them automatically.")
                $ExportContent.Add("- WARN items: Manual action required (see detail column above).")
                $ExportContent.Add("")
                $ExportContent.Add("Please visit $($appinfo.AppWebsite) for more information and support.")
            } else {
                $ExportContent.Add("All checks passed. Thanks for using $($appinfo.AppName) :)")
                $ExportContent.Add("Please visit $($appinfo.AppWebsite) for more information and support.")
            }
            $ExportContent.Add("")

            $ExportContent | Out-File -FilePath $ExportFile -Encoding UTF8 -Force -ErrorAction Stop
            Write-Verbose "CheckModuleRequirements: Results exported to '$ExportFile'."
        } catch {
            Write-Warning "CheckModuleRequirements: Export failed: $($_.Exception.Message)"
        }
    }

    # Build final summary and return
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $Summary = "CheckModuleRequirements: $PassCount passed | $InfoCount informational | $WarnCount warnings | $FinalFail failed."

    if ($FinalFail -gt 0) {
        return (OPSreturn -Code -1 -Message "$Summary ($FinalFail critical failure(s) with no known automated fix)." -Data $Results)
    }

    return (OPSreturn -Code 0 -Message $Summary -Data $Results)
}
