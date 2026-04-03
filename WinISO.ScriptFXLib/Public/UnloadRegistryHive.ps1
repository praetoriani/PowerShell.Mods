﻿function UnloadRegistryHive {
    <#
    .SYNOPSIS
        Unloads one or all previously loaded offline registry hives from the live registry.

    .DESCRIPTION
        UnloadRegistryHive removes previously mounted offline registry hives that were
        loaded by LoadRegistryHive. Each hive is unmounted via 'reg.exe UNLOAD'.

        If HiveID is specified, only that hive is unloaded. If HiveID is omitted, the
        function automatically discovers all hives currently tracked in $script:LoadedHives
        and attempts to unload each of them. This auto-discovery mode is the safest way to
        ensure a clean state before dismounting the WIM image.

        The function is considered a failure if ANY unload attempt fails, regardless of
        how many others succeeded. Successfully unloaded hives are removed from the
        $script:LoadedHives tracker so that subsequent calls can detect a clean state.

    .PARAMETER HiveID
        [OPTIONAL] The name of a single hive to unload (e.g. 'SOFTWARE', 'SYSTEM', 'DEFAULT',
        'NTUSER'). When omitted, all currently tracked loaded hives are unloaded.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [List[PSCustomObject]] where each item has: HiveName, Status, UnmountedFrom, Detail

    .EXAMPLE
        # Unload a specific hive
        $r = UnloadRegistryHive -HiveID 'SOFTWARE'
        if ($r.code -eq 0) { Write-Host "SOFTWARE hive unloaded." }

    .EXAMPLE
        # Unload all currently loaded hives (recommended before UnMountWIMimage)
        $r = UnloadRegistryHive
        $r.data | Format-Table HiveName, Status, UnmountedFrom -AutoSize

    .NOTES
        - Requires administrator privileges.
        - Always call UnloadRegistryHive BEFORE UnMountWIMimage — open registry hives
          will prevent the WIM image from being cleanly dismounted.
        - Dependencies: OPSreturn, PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Hive name to unload. Omit to unload all tracked hives.")]
        [AllowEmptyString()]
        [string]$HiveID = ''
    )

    # Results collector
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $Results      = [System.Collections.Generic.List[PSCustomObject]]::new()
    $FailureCount = 0

    $AddResult = {
        param([string]$HiveName, [string]$Status, [string]$UnmountedFrom = '', [string]$Detail = '')
        $Results.Add([PSCustomObject]@{
            HiveName      = $HiveName
            Status        = $Status.ToUpper()
            UnmountedFrom = $UnmountedFrom
            Detail        = $Detail
        })
    }

    # STEP 1: Ensure the module-scope tracker exists
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if (-not (Get-Variable -Name 'LoadedHives' -Scope Script -ErrorAction SilentlyContinue)) {
        $script:LoadedHives = @{}
    }

    # STEP 2: Resolve which hives to unload
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveIDNorm = $HiveID.Trim().ToUpper()

    if ([string]::IsNullOrWhiteSpace($HiveIDNorm)) {
        # Auto-discovery mode: unload all currently tracked hives
        if ($script:LoadedHives.Count -eq 0) {
            return (OPSreturn -Code 0 -Message "UnloadRegistryHive: No tracked hives found. Nothing to unload." -Data $Results)
        }
        # Snapshot keys to avoid modifying the collection while iterating
        $HivesToUnload = @($script:LoadedHives.Keys)
    }
    else {
        # Single hive mode — validate the name is tracked
        if (-not $script:LoadedHives.ContainsKey($HiveIDNorm)) {
            return (OPSreturn -Code -1 -Message "UnloadRegistryHive failed! Hive '$HiveID' is not tracked as loaded. Was it loaded via LoadRegistryHive?")
        }
        $HivesToUnload = @($HiveIDNorm)
    }

    # STEP 3: Unload each hive via reg.exe
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    foreach ($Name in $HivesToUnload) {
        $RegMountKey = $script:LoadedHives[$Name]

        try {
            # Force a garbage collection pass so PowerShell releases any open handles to the hive
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()

            $RegArgs   = @('UNLOAD', $RegMountKey)
            $RegResult = & reg.exe @RegArgs 2>&1
            $ExitCode  = $LASTEXITCODE

            if ($ExitCode -eq 0) {
                $script:LoadedHives.Remove($Name)
                & $AddResult $Name 'PASS' $RegMountKey "Successfully unloaded from '$RegMountKey'"
            }
            else {
                & $AddResult $Name 'FAIL' $RegMountKey "reg.exe UNLOAD exited with code $ExitCode. Output: $($RegResult -join ' '). Hive may still be in use."
                $FailureCount++
            }
        }
        catch {
            & $AddResult $Name 'FAIL' $RegMountKey "Exception during UNLOAD: $($_.Exception.Message)"
            $FailureCount++
        }
    }

    # FINAL SUMMARY
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $PassCount = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $FailCount = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $Summary   = "UnloadRegistryHive: $PassCount unloaded | $FailCount failed."

    if ($FailureCount -gt 0) {
        return (OPSreturn -Code -1 -Message "$Summary One or more hives could not be unloaded. Verify no process has open handles to the hive." -Data $Results)
    }

    return (OPSreturn -Code 0 -Message $Summary -Data $Results)
}
