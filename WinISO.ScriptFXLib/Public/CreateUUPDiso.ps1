function CreateUUPDiso {
    <#
    .SYNOPSIS
        Runs uup_download_windows.cmd and monitors the full ISO creation process.

    .DESCRIPTION
        CreateUUPDiso is the central orchestration function for ISO creation from a UUPDump
        package. It performs the following steps in sequence:

        1.  Validates UUPDdir (must exist, must not be empty, warns on spaces in path).
        2.  Ensures no pre-existing .iso files are present in UUPDdir — this is a hard
            requirement for the ISO-presence monitoring to work correctly.
        3.  Locates uup_download_windows.cmd (recursively, to support sub-folder layouts).
        4.  Initialises a runtime log file with automatic rotation (keeps KeepCount old logs).
        5.  Launches uup_download_windows.cmd via cmd.exe with all output (stdout + stderr)
            redirected to the runtime log.
        6.  Enters a multi-layer monitoring loop that runs until the process exits or a
            timeout/kill condition is reached:
            a) Primary heartbeat    : LastWriteTime of the runtime log
            b) Secondary heartbeat  : aria2_download.log (download phase only)
            c) ISO-presence watch   : polls for a .iso file appearing on disk (this is the
                                      improvement over the original script which had a
                                      race condition here)
            d) Conversion-phase     : detects transition from download to DISM/oscdimg phase
            e) Prompt detection     : auto-sends "0" to stdin when completion prompt appears
            f) Soft-idle warning    : logged when no heartbeat for SoftIdleMinutes
            g) Hard-idle / kill     : KillOnHardIdle terminates the process tree after
                                      HardIdleMinutes of inactivity
            h) Global timeout       : absolute safety net (GlobalTimeoutMinutes)
        7.  Locates the final ISO file after the process ends.
        8.  Optionally cleans up all files/dirs in UUPDdir except the ISO (CleanUp=1).
        9.  Optionally renames the ISO to the name specified in ISOname (delegates to
            RenameUUPDiso).

    .PARAMETER UUPDdir
        Full path to the UUPDump working directory. Must exist and must not be empty.
        NOTE: The path MUST NOT contain spaces — uup_download_windows.cmd cannot handle
        paths with spaces.

    .PARAMETER CleanUp
        0 = no cleanup  |  1 = delete all files/dirs except the ISO (default).

    .PARAMETER ISOname
        New base name for the ISO file (without .iso extension). A .iso extension in the
        provided string is automatically stripped to prevent double extensions.
        When provided, the ISO is renamed after successful creation.

    .PARAMETER SoftIdleMinutes
        Minutes of log inactivity before a soft-idle warning is emitted. Default: 3.

    .PARAMETER HardIdleMinutes
        Minutes of log inactivity before a hard-idle event is triggered. Default: 30.

    .PARAMETER GlobalTimeoutMinutes
        Maximum total allowed runtime in minutes. Default: 360 (6 hours).

    .PARAMETER PollSeconds
        Polling interval of the monitoring loop in seconds. Default: 2.

    .PARAMETER KillOnHardIdle
        When specified, the process tree is forcefully killed when hard-idle is reached.

    .OUTPUTS
        PSCustomObject with fields:
        .code  >>  0 = Success | -1 = Error
        .msg   >>  Result description or error message
        .data  >>  Full path to the final ISO file on success, $null on failure

    .EXAMPLE
        $r = CreateUUPDiso -UUPDdir 'C:\WinISO\uupdump' -CleanUp 1 -ISOname 'Win11_24H2_Pro'
        if ($r.code -eq 0) { Write-Host "ISO created: $($r.data)" }

    .EXAMPLE
        $r = CreateUUPDiso -UUPDdir 'C:\WinISO\uupdump' `
                           -HardIdleMinutes 60 `
                           -GlobalTimeoutMinutes 480 `
                           -KillOnHardIdle

    .NOTES
        Dependencies:
        - Private: Invoke-UUPRuntimeLog, Get-UUPLogTail, Test-UUPConversionPhase,
                   Invoke-UUPProcessKill, Get-UUPNewestISO
        - Public:  RenameUUPDiso (used when ISOname is specified)
        - AppScope, OPSreturn (WinISO.ScriptFXLib.psm1)
        - Requires PowerShell 5.1 or higher
        - Requires administrator privileges (#requires -RunAsAdministrator in calling script)
        - uup_download_windows.cmd must be present (extracted from UUPDump ZIP)
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true,  HelpMessage = "Full path to the UUPDump working directory (must exist, must not be empty).")]
        [ValidateNotNullOrEmpty()]
        [string]$UUPDdir,

        [Parameter(Mandatory = $false, HelpMessage = "0 = no cleanup | 1 = delete all except ISO after creation (default: 1).")]
        [ValidateSet(0, 1)]
        [int]$CleanUp = 1,

        [Parameter(Mandatory = $false, HelpMessage = "New base name for the ISO (without .iso extension).")]
        [string]$ISOname = '',

        [Parameter(Mandatory = $false, HelpMessage = "Minutes of log inactivity before soft-idle warning. Default: 5.")]
        [int]$SoftIdleMinutes = 5,

        [Parameter(Mandatory = $false, HelpMessage = "Minutes of log inactivity before hard-idle event. Default: 30.")]
        [int]$HardIdleMinutes = 30,

        [Parameter(Mandatory = $false, HelpMessage = "Maximum total runtime in minutes. Default: 180.")]
        [int]$GlobalTimeoutMinutes = 180,

        [Parameter(Mandatory = $false, HelpMessage = "Monitoring poll interval in seconds. Default: 5.")]
        [int]$PollSeconds = 5,

        [Parameter(Mandatory = $false, HelpMessage = "Kill the process tree when hard-idle is reached.")]
        [switch]$KillOnHardIdle
    )

    # Module-scope variables
    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData  = AppScope -KeyID 'appenv'

    # Process object (used in finally block for cleanup)
    $CmdProcess = $null

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 1 >> Validate UUPDdir
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if (-not (Test-Path -Path $UUPDdir -PathType Container)) {
            return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! UUPDdir does not exist: '$UUPDdir'")
        }

        $DirContent = Get-ChildItem -Path $UUPDdir -Force -ErrorAction SilentlyContinue
        if (-not $DirContent -or $DirContent.Count -eq 0) {
            return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! UUPDdir is empty: '$UUPDdir'")
        }

        if ($UUPDdir -match '\s') {
            Write-Warning "CreateUUPDiso: UUPDdir path contains spaces which may cause uup_download_windows.cmd to fail: '$UUPDdir'"
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! Error validating UUPDdir: $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 2 >> Ensure no pre-existing .iso files (required for ISO-presence monitoring)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $ExistingISOs = Get-ChildItem -Path $UUPDdir -Filter '*.iso' -File -Recurse -ErrorAction SilentlyContinue
        if ($ExistingISOs -and $ExistingISOs.Count -gt 0) {
            $ExistingList = ($ExistingISOs | Select-Object -ExpandProperty Name) -join ', '
            return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! Pre-existing .iso file(s) detected in '$UUPDdir': $ExistingList. Remove them before running CreateUUPDiso to ensure clean ISO-presence monitoring.")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! Error checking for pre-existing ISO files: $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 3 >> Locate uup_download_windows.cmd
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $UUPcmd = $null
    try {
        $UUPcmd = Get-ChildItem -Path $UUPDdir -Filter 'uup_download_windows.cmd' -Recurse -File -ErrorAction SilentlyContinue |
                  Select-Object -First 1

        if (-not $UUPcmd) {
            return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! 'uup_download_windows.cmd' not found anywhere in '$UUPDdir'. Ensure the UUPDump ZIP was extracted correctly.")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! Error searching for uup_download_windows.cmd: $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 4 >> Initialise runtime log (with rotation)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $RuntimeLogPath = $null
    try {
        $RuntimeLogPath = Invoke-UUPRuntimeLog -WorkingDir $UUPDdir -LogName 'uup.runtime.log' -KeepCount 5
        if (-not $RuntimeLogPath) {
            return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! Could not initialise the runtime log in '$UUPDdir'.")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! Error initialising runtime log: $($_.Exception.Message)")
    }

    Write-Verbose "CreateUUPDiso: Runtime log: '$RuntimeLogPath'"
    Write-Verbose "CreateUUPDiso: Launching '$($UUPcmd.FullName)' ..."

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 5 >> Launch uup_download_windows.cmd via cmd.exe
    #           All output (stdout + stderr) is redirected into the runtime log.
    #           stdin is kept open so we can auto-send the "0" exit key.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        # Build the command line: cmd /d /c "call "<script>" >> "<log>" 2>&1"
        $CmdArgs = '/d /c "call "{0}" >> "{1}" 2>&1"' -f $UUPcmd.FullName, $RuntimeLogPath

        $PSI                          = New-Object System.Diagnostics.ProcessStartInfo
        $PSI.FileName                 = "$env:SystemRoot\System32\cmd.exe"
        $PSI.Arguments                = $CmdArgs
        $PSI.WorkingDirectory         = $UUPDdir
        $PSI.UseShellExecute          = $false
        $PSI.RedirectStandardInput    = $true
        $PSI.CreateNoWindow           = $false    # keep visible so user sees activity

        $CmdProcess                   = New-Object System.Diagnostics.Process
        $CmdProcess.StartInfo         = $PSI
        $null                         = $CmdProcess.Start()

        Write-Verbose "CreateUUPDiso: Process started (PID: $($CmdProcess.Id))"
    }
    catch {
        return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! Could not start cmd.exe / uup_download_windows.cmd: $($_.Exception.Message)")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 6 >> Multi-layer monitoring loop
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $SpanSoft      = New-TimeSpan -Minutes $SoftIdleMinutes
    $SpanHard      = New-TimeSpan -Minutes $HardIdleMinutes
    $SpanGlobal    = New-TimeSpan -Minutes $GlobalTimeoutMinutes

    $Stopwatch     = [System.Diagnostics.Stopwatch]::StartNew()
    $LastActivity  = Get-Date
    $InConversion  = $false
    $SentExitKey   = $false
    $WasKilled     = $false
    $SoftWarnLogged = $false

    # Seed initial heartbeat from log file mtime
    try { $LastActivity = (Get-Item $RuntimeLogPath -ErrorAction Stop).LastWriteTime } catch { }

    try {
        while (-not $CmdProcess.HasExited) {

            # -- Global timeout --
            if ($Stopwatch.Elapsed -gt $SpanGlobal) {
                Write-Warning "CreateUUPDiso: Global timeout ($GlobalTimeoutMinutes min) reached."
                try { Add-Content -Path $RuntimeLogPath -Value "[WARN] Global timeout at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding Default -EA SilentlyContinue } catch { }
                if ($KillOnHardIdle) { $WasKilled = Invoke-UUPProcessKill -ProcessId $CmdProcess.Id }
                break
            }

            # -- Detect conversion phase (latches permanently once detected) --
            if (-not $InConversion) {
                try {
                    if (Test-UUPConversionPhase -WorkingDir $UUPDdir -RuntimeLog $RuntimeLogPath) {
                        $InConversion = $true
                        Write-Verbose "CreateUUPDiso: Conversion phase detected."
                        try { Add-Content -Path $RuntimeLogPath -Value "[INFO] Conversion phase detected at $(Get-Date -Format 'HH:mm:ss')" -Encoding Default -EA SilentlyContinue } catch { }
                    }
                } catch { }
            }

            # -- Primary heartbeat: runtime log LastWriteTime --
            try {
                if (Test-Path $RuntimeLogPath) {
                    $LogMTime = (Get-Item $RuntimeLogPath -ErrorAction Stop).LastWriteTime
                    if ($LogMTime -gt $LastActivity) { $LastActivity = $LogMTime }
                }
            } catch { }

            # -- Secondary heartbeat: aria2_download.log (download phase only) --
            if (-not $InConversion) {
                try {
                    foreach ($Aria2Name in @('aria2_download.log', 'aria2download.log')) {
                        $Aria2Path = Join-Path $UUPDdir $Aria2Name
                        if (Test-Path $Aria2Path) {
                            $Aria2MTime = (Get-Item $Aria2Path -ErrorAction Stop).LastWriteTime
                            if ($Aria2MTime -gt $LastActivity) { $LastActivity = $Aria2MTime }
                            break
                        }
                    }
                } catch { }
            }

            # -- ISO-presence heartbeat (improvement: once ISO appears, creation is done) --
            try {
                $ISO = Get-UUPNewestISO -WorkingDir $UUPDdir
                if ($null -ne $ISO) {
                    if ($ISO.LastWriteTime -gt $LastActivity) { $LastActivity = $ISO.LastWriteTime }
                    $LastActivity = Get-Date   # ISO present = guaranteed activity
                }
            } catch { }

            $IdleSpan = (Get-Date) - $LastActivity

            # -- Soft-idle: scan log for completion prompt and auto-send "0" --
            if ($IdleSpan -gt $SpanSoft) {
                try {
                    $Tail     = Get-UUPLogTail -Path $RuntimeLogPath -MaxBytes 65536 -MaxLines 200
                    $TailText = $Tail -join "`n"

                    if (-not $SentExitKey -and $TailText -match '(?i)Press 0 or q to exit') {
                        Write-Verbose "CreateUUPDiso: Completion prompt detected — sending '0' to process stdin."
                        try { Add-Content -Path $RuntimeLogPath -Value "[INFO] Auto-sending exit key at $(Get-Date -Format 'HH:mm:ss')" -Encoding Default -EA SilentlyContinue } catch { }
                        try {
                            $CmdProcess.StandardInput.WriteLine('0')
                            $CmdProcess.StandardInput.Flush()
                            $SentExitKey   = $true
                            $LastActivity  = Get-Date
                            Start-Sleep -Seconds 2
                        } catch {
                            Write-Warning "CreateUUPDiso: Failed to send '0' to stdin: $($_.Exception.Message)"
                        }
                    }
                    elseif (-not $SoftWarnLogged) {
                        Write-Verbose ("CreateUUPDiso: Soft-idle ({0:mm\:ss} no activity)." -f $IdleSpan)
                        $SoftWarnLogged = $true
                    }
                } catch { }
            }
            else {
                $SoftWarnLogged = $false   # reset soft-warn flag when activity resumes
            }

            # -- Hard-idle: warn and optionally kill --
            if ($IdleSpan -gt $SpanHard) {
                Write-Warning ("CreateUUPDiso: Hard-idle threshold reached ({0} min)." -f $HardIdleMinutes)
                try { Add-Content -Path $RuntimeLogPath -Value "[WARN] Hard-idle at $(Get-Date -Format 'HH:mm:ss')" -Encoding Default -EA SilentlyContinue } catch { }

                if ($KillOnHardIdle) {
                    Write-Warning "CreateUUPDiso: Killing process tree (KillOnHardIdle)."
                    try { Add-Content -Path $RuntimeLogPath -Value "[ERROR] KillOnHardIdle triggered at $(Get-Date -Format 'HH:mm:ss')" -Encoding Default -EA SilentlyContinue } catch { }
                    $WasKilled = Invoke-UUPProcessKill -ProcessId $CmdProcess.Id
                    break
                }

                # Reset LastActivity to avoid flooding hard-idle warnings on every iteration
                $LastActivity = Get-Date
            }

            Start-Sleep -Seconds $PollSeconds
        }

        # Allow the process a brief grace window to fully exit
        try { $null = $CmdProcess.WaitForExit(15000) } catch { }
        $Stopwatch.Stop()
        Write-Verbose ("CreateUUPDiso: Monitoring ended. Total duration: {0}" -f $Stopwatch.Elapsed.ToString('hh\:mm\:ss'))
    }
    finally {
        # Always close stdin and dispose the process — runs even if we break/throw
        try {
            if ($null -ne $CmdProcess) {
                if ($CmdProcess.StartInfo.RedirectStandardInput) {
                    try { $CmdProcess.StandardInput.Close() } catch { }
                }
                $CmdProcess.Close()
                $CmdProcess.Dispose()
            }
        } catch { }
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 7 >> Locate the generated ISO file
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $CreatedISO = $null
    try { $CreatedISO = Get-UUPNewestISO -WorkingDir $UUPDdir } catch { }

    if (-not $CreatedISO) {
        $KillNote = if ($WasKilled) { ' The process was forcefully terminated.' } else { '' }
        return (OPSreturn -Code -1 -Message "CreateUUPDiso failed! No .iso file found in '$UUPDdir' after conversion.$KillNote Check runtime log: '$RuntimeLogPath'")
    }

    $ISOpath = $CreatedISO.FullName
    Write-Verbose "CreateUUPDiso: ISO found: '$ISOpath' ($([math]::Round($CreatedISO.Length / 1GB, 2)) GB)"

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 8 >> Optional cleanup (CleanUp = 1) — remove everything except .iso
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ($CleanUp -eq 1) {
        try {
            # Remove all subdirectories recursively
            Get-ChildItem -Path $UUPDdir -Directory -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try   { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop }
                    catch { Write-Warning "CreateUUPDiso: Could not remove directory '$($_.FullName)': $($_.Exception.Message)" }
                }

            # Remove all non-ISO files from root
            Get-ChildItem -Path $UUPDdir -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension.ToLower() -ne '.iso' } |
                ForEach-Object {
                    try   { Remove-Item -Path $_.FullName -Force -ErrorAction Stop }
                    catch { Write-Warning "CreateUUPDiso: Could not remove file '$($_.FullName)': $($_.Exception.Message)" }
                }

            Write-Verbose "CreateUUPDiso: Cleanup complete — only the ISO remains in '$UUPDdir'."
        }
        catch {
            Write-Warning "CreateUUPDiso: Cleanup phase encountered an error: $($_.Exception.Message)"
        }
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # STEP 9 >> Optional rename (ISOname parameter provided)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $FinalISOpath = $ISOpath

    if (-not [string]::IsNullOrWhiteSpace($ISOname)) {
        try {
            $RenameResult = RenameUUPDiso -UUPDdir $UUPDdir -ISOname $ISOname
            if ($RenameResult.code -eq 0) {
                $FinalISOpath = $RenameResult.data
                Write-Verbose "CreateUUPDiso: ISO renamed to '$FinalISOpath'."
            }
            else {
                Write-Warning "CreateUUPDiso: ISO rename failed: $($RenameResult.msg) — original path kept."
            }
        }
        catch {
            Write-Warning "CreateUUPDiso: Exception during ISO rename: $($_.Exception.Message) — original path kept."
        }
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # SUCCESS
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $FinalName = [System.IO.Path]::GetFileName($FinalISOpath)
    return (OPSreturn -Code 0 `
        -Message "CreateUUPDiso successful! ISO: '$FinalName' in '$UUPDdir'. Runtime log: '$RuntimeLogPath'." `
        -Data $FinalISOpath)
}
