﻿function RegistryHiveAdd {
    <#
    .SYNOPSIS
        Adds a new registry key and/or value to a loaded offline registry hive.

    .DESCRIPTION
        RegistryHiveAdd creates a new registry key and/or a new value inside a registry hive
        that was previously loaded by LoadRegistryHive. It uses the standard PowerShell
        registry provider (New-Item, New-ItemProperty) via the HKLM:\WinISO_<HiveName> path.

        Either KeyPath or both KeyPath and ValueName must be provided:
        - Supply only KeyPath to create a new empty registry key.
        - Supply KeyPath + ValueName + ValueData + ValueType to create a new value inside
          that key (the key is created automatically if it does not yet exist).

    .PARAMETER HiveID
        [MANDATORY] The name of the loaded hive to modify (e.g. 'SOFTWARE', 'SYSTEM').
        The hive must have been loaded by LoadRegistryHive before calling this function.

    .PARAMETER KeyPath
        [MANDATORY] The sub-path inside the hive, relative to the hive root.
        Example: 'Microsoft\Windows\CurrentVersion\RunOnce'

    .PARAMETER ValueName
        [OPTIONAL] The name of the registry value to create. If omitted, only the key is created.

    .PARAMETER ValueData
        [OPTIONAL] The data for the registry value. Required when ValueName is specified.

    .PARAMETER ValueType
        [OPTIONAL] The registry value type. Valid values: String, ExpandString, Binary,
        DWord, MultiString, QWord. Defaults to 'String'.

    .PARAMETER Force
        [OPTIONAL] When specified, existing values are overwritten without raising an error.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = PSCustomObject { HivePath, FullKeyPath, ValueName, ValueData, ValueType }

    .EXAMPLE
        # Create a new key only
        $r = RegistryHiveAdd -HiveID 'SOFTWARE' -KeyPath 'MyCompany\MyApp'
        if ($r.code -eq 0) { Write-Host "Key created: $($r.data.FullKeyPath)" }

    .EXAMPLE
        # Create a key and set a DWORD value
        $r = RegistryHiveAdd -HiveID 'SOFTWARE' -KeyPath 'MyCompany\MyApp' `
                              -ValueName 'EnableFeature' -ValueData 1 -ValueType 'DWord'

    .NOTES
        - Requires administrator privileges.
        - The hive must be loaded via LoadRegistryHive before this function is called.
        - Dependencies: WinISOcore, OPSreturn, PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the loaded hive (e.g. SOFTWARE, SYSTEM)")]
        [ValidateNotNullOrEmpty()]
        [string]$HiveID,

        [Parameter(Mandatory = $true, HelpMessage = "Sub-path inside the hive, relative to the hive root")]
        [ValidateNotNullOrEmpty()]
        [string]$KeyPath,

        [Parameter(Mandatory = $false, HelpMessage = "Registry value name (omit to create key only)")]
        [AllowEmptyString()]
        [string]$ValueName = '',

        [Parameter(Mandatory = $false, HelpMessage = "Value data (required when ValueName is specified)")]
        $ValueData = $null,

        [Parameter(Mandatory = $false, HelpMessage = "Registry value type")]
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
        [string]$ValueType = 'String',

        [Parameter(Mandatory = $false, HelpMessage = "Overwrite existing values without error")]
        [switch]$Force
    )

    # STEP 1: Validate that the hive is loaded
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveIDNorm = $HiveID.Trim().ToUpper()

    if (-not (Get-Variable -Name 'LoadedHives' -Scope Script -ErrorAction SilentlyContinue)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveAdd failed! No hives are currently loaded. Use LoadRegistryHive first.")
    }
    if (-not $script:LoadedHives.ContainsKey($HiveIDNorm)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveAdd failed! Hive '$HiveID' is not loaded. Available: $($script:LoadedHives.Keys -join ', ')")
    }

    # STEP 2: Build full registry path
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveMountPath = $script:LoadedHives[$HiveIDNorm]                    # e.g. HKLM\WinISO_SOFTWARE
    $PSHivePath    = $HiveMountPath -replace 'HKLM\\\\', 'HKLM:\\'       # e.g. HKLM:\WinISO_SOFTWARE
    $FullKeyPath   = Join-Path $PSHivePath $KeyPath.TrimStart('\\/')

    # STEP 3: Create the key (if it does not already exist)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if (-not (Test-Path -Path $FullKeyPath)) {
            $null = New-Item -Path $FullKeyPath -Force -ErrorAction Stop
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "RegistryHiveAdd failed! Could not create key '$FullKeyPath': $($_.Exception.Message)")
    }

    # If no ValueName was provided, key creation is the only goal — return success
    if ([string]::IsNullOrWhiteSpace($ValueName)) {
        $ResultData = [PSCustomObject]@{
            HivePath    = $HiveMountPath
            FullKeyPath = $FullKeyPath
            ValueName   = $null
            ValueData   = $null
            ValueType   = $null
        }
        return (OPSreturn -Code 0 -Message "RegistryHiveAdd: Key '$FullKeyPath' created (or already existed)." -Data $ResultData)
    }

    # STEP 4: Validate ValueData
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ($null -eq $ValueData) {
        return (OPSreturn -Code -1 -Message "RegistryHiveAdd failed! ValueData must not be null when ValueName is specified.")
    }

    # STEP 5: Create or overwrite the value
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $ExistingItem = Get-ItemProperty -Path $FullKeyPath -Name $ValueName -ErrorAction SilentlyContinue

        if ($null -ne $ExistingItem -and -not $Force.IsPresent) {
            return (OPSreturn -Code -1 -Message "RegistryHiveAdd failed! Value '$ValueName' already exists at '$FullKeyPath'. Use -Force to overwrite.")
        }

        $null = New-ItemProperty -Path $FullKeyPath -Name $ValueName -Value $ValueData `
                                  -PropertyType $ValueType -Force:$Force.IsPresent -ErrorAction Stop

        $ResultData = [PSCustomObject]@{
            HivePath    = $HiveMountPath
            FullKeyPath = $FullKeyPath
            ValueName   = $ValueName
            ValueData   = $ValueData
            ValueType   = $ValueType
        }

        return (OPSreturn -Code 0 -Message "RegistryHiveAdd: Value '$ValueName' ($ValueType) written to '$FullKeyPath'." -Data $ResultData)
    }
    catch {
        return (OPSreturn -Code -1 -Message "RegistryHiveAdd failed! Error writing value '$ValueName' to '$FullKeyPath': $($_.Exception.Message)")
    }
}
