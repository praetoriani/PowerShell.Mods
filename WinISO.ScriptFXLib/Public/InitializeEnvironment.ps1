function InitializeEnvironment {
    <#
    .SYNOPSIS
        InitializeEnvironment - Creates or repairs the WinISO working environment.

    .DESCRIPTION
        InitializeEnvironment is a mandatory core function that ensures the complete
        WinISO working directory structure exists and is fully operational. It performs
        the following actions:

        1.  Determines the directory from which the calling script is executing.
        2.  Checks whether the calling script resides inside $script:appenv['ISOroot'];
            if so, ISOroot is confirmed as present. Otherwise the function verifies
            ISOroot exists (and attempts to create it if missing).
        3.  Iterates over every required directory in $script:appenv and creates any
            that are missing. The key 'installwim' is intentionally skipped because
            the WIM image is not required at environment-setup time.
        4.  Creates the sub-directories .\OEM\root and .\OEM\windir inside OEMfolder.
        5.  Verifies or downloads oscdimg.exe from the GitHub repository if absent.

        Unlike the previous implementation, this function does NOT abort on the first
        directory failure. All individual outcomes are collected (following the pattern
        established by CheckModuleRequirements) and a single comprehensive status object
        is returned at the very end. The overall result is only SUCCESS (code 0) when
        the entire environment is fully intact and oscdimg.exe is present.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [List[PSCustomObject]] where each item has: StepName, Status, Detail

    .EXAMPLE
        $r = InitializeEnvironment
        if ($r.code -eq 0) { Write-Host "Environment ready." } else { Write-Host $r.msg }

    .EXAMPLE
        $r = InitializeEnvironment
        $r.data | Format-Table StepName, Status, Detail -AutoSize

    .NOTES
        Dependencies: WinISOcore, OPSreturn, GitHubDownload, WriteLogMessage, PowerShell 5.1+.
        The function requires administrator privileges for file-system write operations
        on protected paths.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Import global vars via the type-safe accessor
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read' -Unwrap
    $appenv  = WinISOcore -Scope 'env' -GlobalVar 'appenv'  -Permission 'read' -Unwrap
    $appcore = WinISOcore -Scope 'env' -GlobalVar 'appcore' -Permission 'read' -Unwrap

    # Results collector — mirrors the CheckModuleRequirements pattern
    $Results      = [System.Collections.Generic.List[PSCustomObject]]::new()
    $FailureCount = 0

    # Inline helper: appends one result entry to $Results
    $AddResult = {
        param([string]$StepName, [string]$Status, [string]$Detail = '')
        $Results.Add([PSCustomObject]@{
            StepName = $StepName
            Status   = $Status.ToUpper()
            Detail   = $Detail
        })
    }

    # STEP 1: Determine the calling script's directory
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        # MyInvocation.PSScriptRoot works for dot-sourced scripts; PSScriptRoot for modules
        $CallerDir = $null
        if (-not [string]::IsNullOrWhiteSpace($MyInvocation.PSScriptRoot)) {
            $CallerDir = $MyInvocation.PSScriptRoot
        }
        elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            $CallerDir = $PSScriptRoot
        }
        else {
            $CallerDir = [System.IO.Directory]::GetCurrentDirectory()
        }

        & $AddResult 'Caller Script Directory' 'INFO' "Resolved: '$CallerDir'"
    }
    catch {
        & $AddResult 'Caller Script Directory' 'WARNING' "Could not resolve calling script directory: $($_.Exception.Message)"
        $CallerDir = [string]::Empty
    }

    # STEP 2: Verify or create ISOroot
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $ISOroot = $appenv['ISOroot']

        # If the calling script already lives inside ISOroot, the directory clearly exists
        $callerIsInsideRoot = (
            (-not [string]::IsNullOrWhiteSpace($CallerDir)) -and
            ($CallerDir.TrimEnd('\\/') -like "$($ISOroot.TrimEnd('\\/'))*")
        )

        if ($callerIsInsideRoot) {
            & $AddResult 'ISOroot (C:\\WinISO)' 'PASS' "Calling script resides inside ISOroot — directory confirmed: '$ISOroot'"
        }
        elseif (Test-Path -Path $ISOroot -PathType Container) {
            & $AddResult 'ISOroot (C:\\WinISO)' 'PASS' "ISOroot already exists: '$ISOroot'"
        }
        else {
            $null = New-Item -ItemType Directory -Path $ISOroot -Force -ErrorAction Stop
            if (Test-Path -Path $ISOroot -PathType Container) {
                & $AddResult 'ISOroot (C:\\WinISO)' 'PASS' "ISOroot created successfully: '$ISOroot'"
            }
            else {
                & $AddResult 'ISOroot (C:\\WinISO)' 'FAIL' "ISOroot could not be created: '$ISOroot'. All subsequent steps will likely fail."
                $FailureCount++
            }
        }
    }
    catch {
        & $AddResult 'ISOroot (C:\\WinISO)' 'FAIL' "Exception while verifying/creating ISOroot: $($_.Exception.Message)"
        $FailureCount++
    }

    # STEP 3: Verify or create all other required directories
    # The key 'installwim' is deliberately excluded — the WIM image is not
    # expected to exist at environment-setup time. It is only required when
    # MountWIMimage is called.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $DirectoryMap = [ordered]@{
        'ISOdata'    = $appenv['ISOdata']
        'MountPoint' = $appenv['MountPoint']
        'LogfileDir' = $appenv['LogfileDir']
        'AppxBundle' = $appenv['AppxBundle']
        'OEMDrivers' = $appenv['OEMDrivers']
        'OEMfolder'  = $appenv['OEMfolder']
        'ScratchDir' = $appenv['ScratchDir']
        'TempFolder' = $appenv['TempFolder']
        'Downloads'  = $appenv['Downloads']
        'UUPDumpDir' = $appenv['UUPDumpDir']
        'OscdimgDir' = $appenv['OscdimgDir']
    }

    foreach ($Entry in $DirectoryMap.GetEnumerator()) {
        try {
            if (Test-Path -Path $Entry.Value -PathType Container) {
                & $AddResult "Dir: $($Entry.Key)" 'PASS' "Already exists: '$($Entry.Value)'"
            }
            else {
                $null = New-Item -ItemType Directory -Path $Entry.Value -Force -ErrorAction Stop
                if (Test-Path -Path $Entry.Value -PathType Container) {
                    & $AddResult "Dir: $($Entry.Key)" 'PASS' "Created: '$($Entry.Value)'"
                }
                else {
                    & $AddResult "Dir: $($Entry.Key)" 'FAIL' "Creation returned no error but directory not found: '$($Entry.Value)'"
                    $FailureCount++
                }
            }
        }
        catch {
            & $AddResult "Dir: $($Entry.Key)" 'FAIL' "Exception creating '$($Entry.Value)': $($_.Exception.Message)"
            $FailureCount++
        }
    }

    # STEP 4: Create OEM sub-directories (.\OEM\root and .\OEM\windir)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $OEMSubDirs = [ordered]@{
        'OEM\root'   = Join-Path $appenv['OEMfolder'] 'root'
        'OEM\windir' = Join-Path $appenv['OEMfolder'] 'windir'
    }

    foreach ($OEMEntry in $OEMSubDirs.GetEnumerator()) {
        try {
            if (Test-Path -Path $OEMEntry.Value -PathType Container) {
                & $AddResult "Dir: $($OEMEntry.Key)" 'PASS' "Already exists: '$($OEMEntry.Value)'"
            }
            else {
                $null = New-Item -ItemType Directory -Path $OEMEntry.Value -Force -ErrorAction Stop
                if (Test-Path -Path $OEMEntry.Value -PathType Container) {
                    & $AddResult "Dir: $($OEMEntry.Key)" 'PASS' "Created: '$($OEMEntry.Value)'"
                }
                else {
                    & $AddResult "Dir: $($OEMEntry.Key)" 'FAIL' "Creation returned no error but directory not found: '$($OEMEntry.Value)'"
                    $FailureCount++
                }
            }
        }
        catch {
            & $AddResult "Dir: $($OEMEntry.Key)" 'FAIL' "Exception creating '$($OEMEntry.Value)': $($_.Exception.Message)"
            $FailureCount++
        }
    }

    # STEP 5: Verify or download oscdimg.exe
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $OscdimgPath = $appenv['OscdimgExe']

        if (Test-Path -Path $OscdimgPath -PathType Leaf) {
            # Use .FileVersion (string) — compatible with PS 5.1 / .NET Framework 4.x
            # .FileVersionRaw (System.Version object) only exists in .NET 5+ / PS 7+
            $OscdimgVer = (Get-Item -LiteralPath $OscdimgPath).VersionInfo.FileVersion
            & $AddResult 'oscdimg.exe' 'PASS' "Already present: '$OscdimgPath' (v$OscdimgVer)"
        }
        else {
            & $AddResult 'oscdimg.exe' 'INFO' "Not found at '$OscdimgPath' — attempting download from GitHub repository..."

            $DownloadURL    = $appcore['requirement']['oscdimg']
            $DownloadResult = GitHubDownload -URL $DownloadURL -SaveTo $OscdimgPath

            if ($DownloadResult.code -eq 0) {
                & $AddResult 'oscdimg.exe (Download)' 'PASS' "Downloaded successfully to '$OscdimgPath'. $($DownloadResult.msg)"
            }
            else {
                & $AddResult 'oscdimg.exe (Download)' 'FAIL' "Download failed: $($DownloadResult.msg)"
                $FailureCount++
            }
        }
    }
    catch {
        & $AddResult 'oscdimg.exe' 'FAIL' "Exception during oscdimg.exe verification/download: $($_.Exception.Message)"
        $FailureCount++
    }

    # FINAL SUMMARY — single return at the end (all results collected above)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $PassCount = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $InfoCount = @($Results | Where-Object { $_.Status -eq 'INFO' }).Count
    $WarnCount = @($Results | Where-Object { $_.Status -eq 'WARNING' }).Count
    $FailCount = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $Summary   = "InitializeEnvironment: $PassCount passed | $WarnCount warnings | $FailCount failed | $InfoCount informational."

    if ($FailureCount -gt 0) {
        return (OPSreturn -Code -1 -Message "$Summary The WinISO environment could not be fully established ($FailureCount step(s) failed)." -Data $Results)
    }

    return (OPSreturn -Code 0 -Message "$Summary WinISO environment is fully operational." -Data $Results)
}
