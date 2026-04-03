﻿function RegistryHiveRem {
    <#
    .SYNOPSIS
        Removes an existing registry key and/or value from a loaded offline registry hive.

    .DESCRIPTION
        RegistryHiveRem deletes a registry key (including all its sub-keys and values) or a
        single named value from a hive that was previously loaded by LoadRegistryHive.

        Behavior:
        - When only KeyPath is specified, the key and all of its sub-keys/values are deleted.
        - When KeyPath AND ValueName are specified, only that specific value is removed
          from the key; the key itself is retained.

        By default the function returns a failure if the specified path or value does not
        exist. Use -IgnoreMissing to suppress this error and return success instead (useful
        for idempotent clean-up scripts).

    .PARAMETER HiveID
        [MANDATORY] The name of the loaded hive to modify (e.g. 'SOFTWARE', 'SYSTEM').

    .PARAMETER KeyPath
        [MANDATORY] The sub-path inside the hive, relative to the hive root.
        Example: 'Microsoft\Windows\CurrentVersion\RunOnce'

    .PARAMETER ValueName
        [OPTIONAL] The name of a specific registry value to remove. When omitted, the
        entire key (and all its sub-keys) is deleted.

    .PARAMETER IgnoreMissing
        [OPTIONAL] When specified, the function returns success (code 0) even if the
        key or value does not exist, rather than returning code -1.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }

    .EXAMPLE
        # Remove an entire key tree
        $r = RegistryHiveRem -HiveID 'SOFTWARE' -KeyPath 'MyCompany\MyApp'
        if ($r.code -eq 0) { Write-Host "Key removed." }

    .EXAMPLE
        # Remove only a specific value, leave the key intact
        $r = RegistryHiveRem -HiveID 'SOFTWARE' -KeyPath 'MyCompany\MyApp' `
                              -ValueName 'ObsoleteValue'

    .NOTES
        - Requires administrator privileges.
        - The hive must be loaded via LoadRegistryHive before this function is called.
        - Dependencies: OPSreturn, PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the loaded hive (e.g. SOFTWARE, SYSTEM)")]
        [ValidateNotNullOrEmpty()]
        [string]$HiveID,

        [Parameter(Mandatory = $true, HelpMessage = "Sub-path inside the hive, relative to hive root")]
        [ValidateNotNullOrEmpty()]
        [string]$KeyPath,

        [Parameter(Mandatory = $false, HelpMessage = "Name of a specific value to remove (omit to delete the entire key)")]
        [AllowEmptyString()]
        [string]$ValueName = '',

        [Parameter(Mandatory = $false, HelpMessage = "Return success even if the key/value does not exist")]
        [switch]$IgnoreMissing
    )

    # STEP 1: Validate that the hive is loaded
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveIDNorm = $HiveID.Trim().ToUpper()

    if (-not (Get-Variable -Name 'LoadedHives' -Scope Script -ErrorAction SilentlyContinue)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveRem failed! No hives are currently loaded. Use LoadRegistryHive first.")
    }
    if (-not $script:LoadedHives.ContainsKey($HiveIDNorm)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveRem failed! Hive '$HiveID' is not loaded. Available: $($script:LoadedHives.Keys -join ', ')")
    }

    # STEP 2: Build full registry path
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveMountPath = $script:LoadedHives[$HiveIDNorm]
    $PSHivePath    = $HiveMountPath -replace 'HKLM\\\\', 'HKLM:\\'
    $FullKeyPath   = Join-Path $PSHivePath $KeyPath.TrimStart('\\/')

    # STEP 3: Remove value or entire key
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if (-not [string]::IsNullOrWhiteSpace($ValueName)) {
            # -- VALUE removal mode --
            if (-not (Test-Path -Path $FullKeyPath)) {
                if ($IgnoreMissing.IsPresent) {
                    return (OPSreturn -Code 0 -Message "RegistryHiveRem: Key '$FullKeyPath' does not exist (IgnoreMissing active). Nothing removed.")
                }
                return (OPSreturn -Code -1 -Message "RegistryHiveRem failed! Key '$FullKeyPath' does not exist.")
            }

            $ExistingProp = Get-ItemProperty -Path $FullKeyPath -Name $ValueName -ErrorAction SilentlyContinue
            if ($null -eq $ExistingProp) {
                if ($IgnoreMissing.IsPresent) {
                    return (OPSreturn -Code 0 -Message "RegistryHiveRem: Value '$ValueName' not found at '$FullKeyPath' (IgnoreMissing active). Nothing removed.")
                }
                return (OPSreturn -Code -1 -Message "RegistryHiveRem failed! Value '$ValueName' does not exist at '$FullKeyPath'.")
            }

            Remove-ItemProperty -Path $FullKeyPath -Name $ValueName -Force -ErrorAction Stop
            return (OPSreturn -Code 0 -Message "RegistryHiveRem: Value '$ValueName' removed from '$FullKeyPath'.")
        }
        else {
            # -- KEY removal mode (recursive) --
            if (-not (Test-Path -Path $FullKeyPath)) {
                if ($IgnoreMissing.IsPresent) {
                    return (OPSreturn -Code 0 -Message "RegistryHiveRem: Key '$FullKeyPath' does not exist (IgnoreMissing active). Nothing removed.")
                }
                return (OPSreturn -Code -1 -Message "RegistryHiveRem failed! Key '$FullKeyPath' does not exist.")
            }

            Remove-Item -Path $FullKeyPath -Recurse -Force -ErrorAction Stop
            return (OPSreturn -Code 0 -Message "RegistryHiveRem: Key '$FullKeyPath' and all sub-keys/values removed.")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "RegistryHiveRem failed! Error during removal: $($_.Exception.Message)")
    }
}
