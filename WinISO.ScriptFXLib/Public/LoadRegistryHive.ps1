﻿function LoadRegistryHive {
    <#
    .SYNOPSIS
        Mounts one or all offline registry hives from the mounted WIM image into the live registry.

    .DESCRIPTION
        LoadRegistryHive loads one or more offline registry hive files from the WIM image
        currently mounted at $script:appenv['MountPoint'] into the live registry under a
        dedicated WinISO sub-key (HKLM:\WinISO_<HiveName>).

        This enables read/write access to the offline registry of the Windows image without
        booting it. All loaded hives are tracked in the module-scope variable
        $script:LoadedHives (a hashtable keyed by hive name) so that UnloadRegistryHive
        can later clean them up reliably.

        Supported hive names:
        ┌──────────────┬──────────────────────────────────────────────────────────────────────┐
        │ Name         │ Source path inside MountPoint                                        │
        ├──────────────┼──────────────────────────────────────────────────────────────────────┤
        │ SOFTWARE     │ <MountPoint>\Windows\System32\config\SOFTWARE                      │
        │ SYSTEM       │ <MountPoint>\Windows\System32\config\SYSTEM                        │
        │ DEFAULT      │ <MountPoint>\Windows\System32\config\DEFAULT                       │
        │ NTUSER       │ <MountPoint>\Users\Default\NTUSER.DAT                              │
        └──────────────┴──────────────────────────────────────────────────────────────────────┘

        Passing 'ALL' for HiveID loads every hive listed above. Specifying a single hive name
        loads only that hive. The function fails if a specified hive is unknown or if any
        reg.exe LOAD operation returns a non-zero exit code.

    .PARAMETER HiveID
        [MANDATORY] The name of the hive to load ('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER')
        or 'ALL' to load every supported hive at once.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [List[PSCustomObject]] where each item has: HiveName, Status, MountedAt, Detail

    .EXAMPLE
        $r = LoadRegistryHive -HiveID 'SOFTWARE'
        if ($r.code -eq 0) { Write-Host "Hive loaded at HKLM:\WinISO_SOFTWARE" }

    .EXAMPLE
        $r = LoadRegistryHive -HiveID 'ALL'
        $r.data | Format-Table HiveName, Status, MountedAt -AutoSize

    .NOTES
        - Requires administrator privileges (reg.exe LOAD writes to HKLM).
        - The WIM image MUST be mounted at $script:appenv['MountPoint'] before calling this function.
        - Dependencies: WinISOcore, OPSreturn, PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Hive name (SOFTWARE|SYSTEM|DEFAULT|NTUSER) or 'ALL'")]
        [ValidateNotNullOrEmpty()]
        [string]$HiveID
    )

    # Import global vars via the type-safe accessor
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $appenv = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'read' -Unwrap

    # Results collector
    $Results      = [System.Collections.Generic.List[PSCustomObject]]::new()
    $FailureCount = 0

    $AddResult = {
        param([string]$HiveName, [string]$Status, [string]$MountedAt = '', [string]$Detail = '')
        $Results.Add([PSCustomObject]@{
            HiveName  = $HiveName
            Status    = $Status.ToUpper()
            MountedAt = $MountedAt
            Detail    = $Detail
        })
    }

    # STEP 1: Validate MountPoint — the WIM image must be mounted
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $MountPoint = $appenv['MountPoint']

    if (-not (Test-Path -Path $MountPoint -PathType Container)) {
        return (OPSreturn -Code -1 -Message "LoadRegistryHive failed! MountPoint '$MountPoint' does not exist. Mount the WIM image first (MountWIMimage).")
    }

    # Quick sanity check: a mounted Windows image should contain a 'Windows' sub-folder
    $WinDir = Join-Path $MountPoint 'Windows'
    if (-not (Test-Path -Path $WinDir -PathType Container)) {
        return (OPSreturn -Code -1 -Message "LoadRegistryHive failed! MountPoint '$MountPoint' does not appear to contain a mounted Windows image ('Windows' sub-folder not found).")
    }

    # STEP 2: Define the known hive map
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveMap = [ordered]@{
        SOFTWARE = Join-Path $MountPoint 'Windows\System32\config\SOFTWARE'
        SYSTEM   = Join-Path $MountPoint 'Windows\System32\config\SYSTEM'
        DEFAULT  = Join-Path $MountPoint 'Windows\System32\config\DEFAULT'
        NTUSER   = Join-Path $MountPoint 'Users\Default\NTUSER.DAT'
    }

    # STEP 3: Resolve which hives to load
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveIDNorm = $HiveID.Trim().ToUpper()

    if ($HiveIDNorm -eq 'ALL') {
        $HivesToLoad = $HiveMap
    }
    elseif ($HiveMap.Contains($HiveIDNorm)) {
        $HivesToLoad = [ordered]@{ $HiveIDNorm = $HiveMap[$HiveIDNorm] }
    }
    else {
        return (OPSreturn -Code -1 -Message "LoadRegistryHive failed! Unknown HiveID '$HiveID'. Valid values: ALL, $($HiveMap.Keys -join ', ')")
    }

    # STEP 4: Ensure the module-scope loaded-hive tracker exists
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if (-not (Get-Variable -Name 'LoadedHives' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:LoadedHives = @{}
    }

    # STEP 5: Load each requested hive via reg.exe
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    foreach ($HiveEntry in $HivesToLoad.GetEnumerator()) {
        $Name        = $HiveEntry.Key
        $HiveFile    = $HiveEntry.Value
        $RegMountKey = "HKLM\WinISO_$Name"

        try {
            # Verify the hive source file exists
            if (-not (Test-Path -Path $HiveFile)) {
                & $AddResult $Name 'FAIL' $RegMountKey "Hive file not found: '$HiveFile'"
                $FailureCount++
                continue
            }

            # Skip if already loaded (idempotent behavior)
            if ($script:LoadedHives.ContainsKey($Name)) {
                & $AddResult $Name 'SKIP' $RegMountKey "Hive is already loaded at '$RegMountKey'. Skipping."
                continue
            }

            # Execute: reg.exe LOAD HKLM\WinISO_<NAME> "<HiveFile>"
            $RegArgs   = @('LOAD', $RegMountKey, $HiveFile)
            $RegResult = & reg.exe @RegArgs 2>&1
            $ExitCode  = $LASTEXITCODE

            if ($ExitCode -eq 0) {
                $script:LoadedHives[$Name] = $RegMountKey
                & $AddResult $Name 'PASS' $RegMountKey "Loaded from '$HiveFile'"
            }
            else {
                & $AddResult $Name 'FAIL' $RegMountKey "reg.exe LOAD exited with code $ExitCode. Output: $($RegResult -join ' ')"
                $FailureCount++
            }
        }
        catch {
            & $AddResult $Name 'FAIL' $RegMountKey "Exception during LOAD: $($_.Exception.Message)"
            $FailureCount++
        }
    }

    # FINAL SUMMARY
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $PassCount = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $SkipCount = @($Results | Where-Object { $_.Status -eq 'SKIP' }).Count
    $FailCount = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $Summary   = "LoadRegistryHive: $PassCount loaded | $SkipCount skipped (already loaded) | $FailCount failed."

    if ($FailureCount -gt 0) {
        return (OPSreturn -Code -1 -Message "$Summary One or more hives could not be loaded." -Data $Results)
    }

    return (OPSreturn -Code 0 -Message $Summary -Data $Results)
}
