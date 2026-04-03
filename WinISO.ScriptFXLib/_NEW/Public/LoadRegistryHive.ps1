﻿function LoadRegistryHive {
    <#
    .SYNOPSIS
        Loads one or all offline registry hives from the mounted WIM image into the
        live registry under HKLM\WinISO_<HiveName>.

    .DESCRIPTION
        LoadRegistryHive uses 'reg.exe LOAD' to mount offline hive files from the
        WIM image that was previously mounted by MountWIMimage. After successful loading,
        each hive is accessible via the PowerShell registry provider at:

            HKLM:\WinISO_<HiveName>

        The WinISO_ prefix ensures no collision with system hives.

        Supported hive names and their source paths (relative to $appenv['MountPoint']):
        ┌──────────────────┬────────────────────────────────────────────────────────────┐
        │ HiveName         │ Source file inside MountPoint                              │
        ├──────────────────┼────────────────────────────────────────────────────────────┤
        │ SOFTWARE         │ Windows\System32\config\SOFTWARE                          │
        │ SYSTEM           │ Windows\System32\config\SYSTEM                            │
        │ DEFAULT          │ Windows\System32\config\DEFAULT                           │
        │ NTUSER           │ Users\Default\NTUSER.DAT                                  │
        └──────────────────┴────────────────────────────────────────────────────────────┘

        Tracking: each successfully loaded hive is registered via WinISOcore
        (GlobalVar='LoadedHives', Permission='write') so that UnloadRegistryHive and
        all RegistryHive* functions can resolve mount paths without additional parameters.

    .PARAMETER HiveID
        [MANDATORY] The name of a single hive to load (SOFTWARE, SYSTEM, DEFAULT, NTUSER)
        or the special value ALL to load all four hives at once.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [List[PSCustomObject]] where each item has:
                HiveName, Status, HiveFile, RegMountKey, Detail

    .EXAMPLE
        # Load only the SOFTWARE hive
        $r = LoadRegistryHive -HiveID 'SOFTWARE'
        if ($r.code -eq 0) { Write-Host "SOFTWARE hive loaded." }

    .EXAMPLE
        # Load all four hives at once
        $r = LoadRegistryHive -HiveID 'ALL'
        $r.data | Format-Table HiveName, Status, RegMountKey -AutoSize

    .NOTES
        - Requires administrator privileges.
        - MountWIMimage must have been called before LoadRegistryHive.
        - Always call UnloadRegistryHive before UnMountWIMimage to prevent
          open registry handles that would block the WIM dismount.
        - Dependencies: WinISOcore, OPSreturn, PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Hive name to load: SOFTWARE | SYSTEM | DEFAULT | NTUSER | ALL")]
        [ValidateNotNullOrEmpty()]
        [string]$HiveID
    )

    # Results collector
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $Results      = [System.Collections.Generic.List[PSCustomObject]]::new()
    $FailureCount = 0

    $AddResult = {
        param([string]$HiveName, [string]$Status, [string]$HiveFile = '', [string]$RegMountKey = '', [string]$Detail = '')
        $Results.Add([PSCustomObject]@{
            HiveName    = $HiveName
            Status      = $Status.ToUpper()
            HiveFile    = $HiveFile
            RegMountKey = $RegMountKey
            Detail      = $Detail
        })
    }

    # =========================================================================
    # STEP 1: Retrieve appenv via WinISOcore
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $appenv = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'read' -Unwrap
    if ($null -eq $appenv) {
        return (OPSreturn -Code -1 -Message "LoadRegistryHive failed! Could not retrieve appenv via WinISOcore.")
    }

    # =========================================================================
    # STEP 2: Verify MountPoint contains a mounted Windows image
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $MountPoint = $appenv['MountPoint']
    $WindowsDir = Join-Path $MountPoint 'Windows'
    if (-not (Test-Path -Path $WindowsDir -PathType Container)) {
        return (OPSreturn -Code -1 -Message "LoadRegistryHive failed! No mounted Windows image detected at '$MountPoint\Windows'. Call MountWIMimage first.")
    }

    # =========================================================================
    # STEP 3: Define the hive map
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveMap = [ordered]@{
        'SOFTWARE' = Join-Path $MountPoint 'Windows\System32\config\SOFTWARE'
        'SYSTEM'   = Join-Path $MountPoint 'Windows\System32\config\SYSTEM'
        'DEFAULT'  = Join-Path $MountPoint 'Windows\System32\config\DEFAULT'
        'NTUSER'   = Join-Path $MountPoint 'Users\Default\NTUSER.DAT'
    }

    # =========================================================================
    # STEP 4: Resolve which hives to load
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveIDNorm = $HiveID.Trim().ToUpper()

    if ($HiveIDNorm -eq 'ALL') {
        $HivesToLoad = $HiveMap.Keys
    }
    elseif ($HiveMap.ContainsKey($HiveIDNorm)) {
        $HivesToLoad = @($HiveIDNorm)
    }
    else {
        return (OPSreturn -Code -1 -Message "LoadRegistryHive failed! Unknown HiveID '$HiveID'. Valid values: ALL, $($HiveMap.Keys -join ', ').")
    }

    # =========================================================================
    # STEP 5: Load each hive via reg.exe LOAD, track via WinISOcore
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # Read current LoadedHives state once via WinISOcore
    $LoadedHivesRef = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'read' -Unwrap

    foreach ($Name in $HivesToLoad) {
        $HiveFile    = $HiveMap[$Name]
        $RegMountKey = "HKLM\WinISO_$Name"

        # Skip if already tracked (idempotent)
        if ($null -ne $LoadedHivesRef -and $LoadedHivesRef.ContainsKey($Name)) {
            & $AddResult $Name 'SKIP' $HiveFile $RegMountKey "Hive is already tracked as loaded. Skipping duplicate load."
            continue
        }

        # Verify hive file exists in the mounted image
        if (-not (Test-Path -Path $HiveFile -PathType Leaf)) {
            & $AddResult $Name 'FAIL' $HiveFile $RegMountKey "Hive file not found: '$HiveFile'."
            $FailureCount++
            continue
        }

        try {
            $RegArgs   = @('LOAD', $RegMountKey, $HiveFile)
            $RegResult = & reg.exe @RegArgs 2>&1
            $ExitCode  = $LASTEXITCODE

            if ($ExitCode -eq 0) {
                # Register in LoadedHives via WinISOcore
                $null = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'write' `
                                   -VarKeyID $Name -SetNewVal $RegMountKey

                # Refresh ref after write
                $LoadedHivesRef = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'read' -Unwrap

                & $AddResult $Name 'PASS' $HiveFile $RegMountKey "Loaded successfully. Accessible at 'HKLM:\WinISO_$Name'."
            }
            else {
                & $AddResult $Name 'FAIL' $HiveFile $RegMountKey "reg.exe LOAD exited with code $ExitCode. Output: $($RegResult -join ' ')"
                $FailureCount++
            }
        }
        catch {
            & $AddResult $Name 'FAIL' $HiveFile $RegMountKey "Exception during LOAD: $($_.Exception.Message)"
            $FailureCount++
        }
    }

    # =========================================================================
    # FINAL SUMMARY
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $PassCount = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $SkipCount = @($Results | Where-Object { $_.Status -eq 'SKIP' }).Count
    $FailCount = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $Summary   = "LoadRegistryHive: $PassCount loaded | $SkipCount skipped | $FailCount failed."

    if ($FailureCount -gt 0) {
        return (OPSreturn -Code -1 -Message "$Summary One or more hives could not be loaded." -Data $Results)
    }

    return (OPSreturn -Code 0 -Message $Summary -Data $Results)
}
