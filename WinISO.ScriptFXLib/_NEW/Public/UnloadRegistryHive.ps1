﻿function UnloadRegistryHive {
    <#
    .SYNOPSIS
        Unloads one or all currently loaded offline registry hives from the live registry.

    .DESCRIPTION
        UnloadRegistryHive uses 'reg.exe UNLOAD' to cleanly unmount hives that were
        previously loaded by LoadRegistryHive.

        The function operates in two modes determined by the -HiveID parameter:

        EXPLICIT mode   : -HiveID 'SOFTWARE'
            Unloads the specified hive only. If the hive is not currently tracked as
            loaded, the function returns a failure immediately (nothing to unload).

        AUTO-DISCOVERY mode : -HiveID not supplied (omit the parameter)
            Reads the current LoadedHives tracking hashtable via WinISOcore and attempts
            to unload all registered hives. Useful as a cleanup call at the end of a
            WIM customisation session.

        Before calling reg.exe UNLOAD, a forced garbage-collection pass is performed to
        flush any .NET handles that might still reference the hive, reducing the risk of
        "access denied" errors from open handles.

        On success for each hive, the corresponding WinISOcore LoadedHives entry is removed
        via WinISOcore (GlobalVar='LoadedHives', Permission='write', SetNewVal=$null).

    .PARAMETER HiveID
        [OPTIONAL] The name of the hive to unload (SOFTWARE, SYSTEM, DEFAULT, NTUSER).
        If omitted, all currently tracked hives are unloaded automatically.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [List[PSCustomObject]] per-hive result with:
                HiveName, Status, RegMountKey, Detail

    .EXAMPLE
        # Unload only the SOFTWARE hive
        $r = UnloadRegistryHive -HiveID 'SOFTWARE'
        if ($r.code -eq 0) { Write-Host "SOFTWARE hive unloaded." }

    .EXAMPLE
        # Unload all currently tracked hives (auto-discovery)
        $r = UnloadRegistryHive
        $r.data | Format-Table HiveName, Status -AutoSize

    .NOTES
        - Requires administrator privileges.
        - Call this BEFORE UnMountWIMimage to avoid open-handle errors.
        - Dependencies: WinISOcore, OPSreturn, PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Hive to unload: SOFTWARE | SYSTEM | DEFAULT | NTUSER. Omit to unload all tracked hives.")]
        [string]$HiveID = ''
    )

    # Results collector
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $Results      = [System.Collections.Generic.List[PSCustomObject]]::new()
    $FailureCount = 0

    $AddResult = {
        param([string]$HiveName, [string]$Status, [string]$RegMountKey = '', [string]$Detail = '')
        $Results.Add([PSCustomObject]@{
            HiveName    = $HiveName
            Status      = $Status.ToUpper()
            RegMountKey = $RegMountKey
            Detail      = $Detail
        })
    }

    # =========================================================================
    # STEP 1: Flush GC handles (reduces open-handle errors on UNLOAD)
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    # =========================================================================
    # STEP 2: Read current LoadedHives state via WinISOcore
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $LoadedHivesRef = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'read' -Unwrap
    if ($null -eq $LoadedHivesRef) {
        return (OPSreturn -Code -1 -Message "UnloadRegistryHive failed! Could not retrieve LoadedHives tracking table via WinISOcore.")
    }

    # =========================================================================
    # STEP 3: Determine which hives to unload
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveIDNorm    = $HiveID.Trim().ToUpper()
    $IsAutoDiscover = [string]::IsNullOrWhiteSpace($HiveIDNorm)

    if ($IsAutoDiscover) {
        # AUTO-DISCOVERY: resolve from the tracking table
        if ($LoadedHivesRef.Count -eq 0) {
            return (OPSreturn -Code 0 -Message "UnloadRegistryHive: No hives are currently tracked as loaded. Nothing to unload." -Data $Results)
        }
        $HivesToUnload = @($LoadedHivesRef.Keys)
    }
    else {
        # EXPLICIT: validate the name first
        $ValidNames = @('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER')
        if ($HiveIDNorm -notin $ValidNames) {
            return (OPSreturn -Code -1 -Message "UnloadRegistryHive failed! Unknown HiveID '$HiveID'. Valid values: $($ValidNames -join ', ').")
        }

        if (-not $LoadedHivesRef.ContainsKey($HiveIDNorm)) {
            return (OPSreturn -Code -1 -Message "UnloadRegistryHive failed! Hive '$HiveIDNorm' is not currently tracked as loaded. Cannot unload a hive that was not registered by LoadRegistryHive.")
        }
        $HivesToUnload = @($HiveIDNorm)
    }

    # =========================================================================
    # STEP 4: Unload each hive
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    foreach ($Name in $HivesToUnload) {
        $RegMountKey = $LoadedHivesRef[$Name]

        if ([string]::IsNullOrWhiteSpace($RegMountKey)) {
            & $AddResult $Name 'FAIL' $RegMountKey "Mount key for '$Name' is empty in LoadedHives tracking table. Cannot unload."
            $FailureCount++
            continue
        }

        try {
            $RegResult = & reg.exe UNLOAD $RegMountKey 2>&1
            $ExitCode  = $LASTEXITCODE

            if ($ExitCode -eq 0) {
                # Remove from LoadedHives tracking via WinISOcore (SetNewVal=$null = remove entry)
                $null = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'write' `
                                   -VarKeyID $Name -SetNewVal $null

                & $AddResult $Name 'PASS' $RegMountKey "Unloaded successfully."
            }
            else {
                & $AddResult $Name 'FAIL' $RegMountKey "reg.exe UNLOAD exited with code $ExitCode. Output: $($RegResult -join ' ')"
                $FailureCount++
            }
        }
        catch {
            & $AddResult $Name 'FAIL' $RegMountKey "Exception during UNLOAD: $($_.Exception.Message)"
            $FailureCount++
        }
    }

    # =========================================================================
    # FINAL SUMMARY
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $PassCount = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $FailCount = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $Summary   = "UnloadRegistryHive: $PassCount unloaded | $FailCount failed."

    if ($FailureCount -gt 0) {
        return (OPSreturn -Code -1 -Message "$Summary One or more hives could not be unloaded." -Data $Results)
    }

    return (OPSreturn -Code 0 -Message $Summary -Data $Results)
}
