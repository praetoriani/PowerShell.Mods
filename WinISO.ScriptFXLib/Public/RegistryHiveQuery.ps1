﻿function RegistryHiveQuery {
    <#
    .SYNOPSIS
        Queries registry keys and/or values from a loaded offline registry hive.

    .DESCRIPTION
        RegistryHiveQuery retrieves information from a registry hive that was previously
        loaded by LoadRegistryHive. It supports two modes:

        KEY mode (default, no ValueName):
        Returns all values of the specified key as a hashtable, plus an array of
        direct sub-key names. Useful for inspecting an entire key at once.

        VALUE mode (ValueName specified):
        Returns the data and type of a single named value at the specified key path.
        Wildcards in ValueName are supported (e.g. '*Foo*').

    .PARAMETER HiveID
        [MANDATORY] The name of the loaded hive to query (e.g. 'SOFTWARE', 'SYSTEM').

    .PARAMETER KeyPath
        [MANDATORY] The sub-path inside the hive, relative to the hive root.
        Example: 'Microsoft\Windows NT\CurrentVersion'

    .PARAMETER ValueName
        [OPTIONAL] The exact name of a registry value to retrieve. Supports wildcards.
        When omitted, all values of the key and the list of sub-keys are returned.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        KEY mode:
        .data = PSCustomObject {
            FullKeyPath   [string]
            Values        [hashtable]   # ValueName -> [PSCustomObject]{ Data, Type }
            SubKeys       [string[]]    # Names of direct child keys
        }
        VALUE mode:
        .data = PSCustomObject {
            FullKeyPath   [string]
            ValueName     [string]
            ValueData     [object]
            ValueType     [string]
        }

    .EXAMPLE
        # Query all values of a key
        $r = RegistryHiveQuery -HiveID 'SOFTWARE' `
                                -KeyPath 'Microsoft\Windows NT\CurrentVersion'
        $r.data.Values | Format-Table

    .EXAMPLE
        # Query a single value
        $r = RegistryHiveQuery -HiveID 'SOFTWARE' `
                                -KeyPath 'Microsoft\Windows NT\CurrentVersion' `
                                -ValueName 'CurrentBuild'
        if ($r.code -eq 0) { Write-Host "CurrentBuild = $($r.data.ValueData)" }

    .NOTES
        - The hive must be loaded via LoadRegistryHive before calling this function.
        - Dependencies: OPSreturn, PowerShell 5.1+.
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

        [Parameter(Mandatory = $false, HelpMessage = "Name of a specific value to retrieve (supports wildcards)")]
        [AllowEmptyString()]
        [string]$ValueName = ''
    )

    # STEP 1: Validate that the hive is loaded
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveIDNorm = $HiveID.Trim().ToUpper()

    if (-not (Get-Variable -Name 'LoadedHives' -Scope Script -ErrorAction SilentlyContinue)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveQuery failed! No hives are currently loaded. Use LoadRegistryHive first.")
    }
    if (-not $script:LoadedHives.ContainsKey($HiveIDNorm)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveQuery failed! Hive '$HiveID' is not loaded. Available: $($script:LoadedHives.Keys -join ', ')")
    }

    # STEP 2: Build full registry path
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveMountPath = $script:LoadedHives[$HiveIDNorm]
    $PSHivePath    = $HiveMountPath -replace 'HKLM\\\\', 'HKLM:\\'
    $FullKeyPath   = Join-Path $PSHivePath $KeyPath.TrimStart('\\/')

    # STEP 3: Verify key existence
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if (-not (Test-Path -Path $FullKeyPath)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveQuery failed! Key '$FullKeyPath' does not exist.")
    }

    # STEP 4: VALUE mode — single named value query
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if (-not [string]::IsNullOrWhiteSpace($ValueName)) {
        try {
            $Item = Get-ItemProperty -Path $FullKeyPath -Name $ValueName -ErrorAction Stop

            if ($null -eq $Item) {
                return (OPSreturn -Code -1 -Message "RegistryHiveQuery failed! Value '$ValueName' not found at '$FullKeyPath'.")
            }

            # Determine the value type via the registry key item
            $RegistryKey  = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                ($FullKeyPath -replace 'HKLM:\\\\', ''), $false
            )
            $ValueKind     = $null
            $ResolvedData  = $null

            if ($null -ne $RegistryKey) {
                $ValueKind    = $RegistryKey.GetValueKind($ValueName)
                $ResolvedData = $RegistryKey.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $RegistryKey.Close()
            }
            else {
                $ResolvedData = $Item.$ValueName
            }

            $ResultData = [PSCustomObject]@{
                FullKeyPath = $FullKeyPath
                ValueName   = $ValueName
                ValueData   = $ResolvedData
                ValueType   = if ($null -ne $ValueKind) { $ValueKind.ToString() } else { 'Unknown' }
            }

            return (OPSreturn -Code 0 -Message "RegistryHiveQuery: Value '$ValueName' found at '$FullKeyPath'." -Data $ResultData)
        }
        catch {
            return (OPSreturn -Code -1 -Message "RegistryHiveQuery failed! Error reading value '$ValueName': $($_.Exception.Message)")
        }
    }

    # STEP 5: KEY mode — return all values and direct sub-key names
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $ValuesHash = @{}
        $SubKeyList = @()

        # Open the key via .NET for accurate type information
        $RegKeyPath  = $FullKeyPath -replace 'HKLM:\\\\', ''
        $RegistryKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegKeyPath, $false)

        if ($null -ne $RegistryKey) {
            # Collect all values
            foreach ($Name in $RegistryKey.GetValueNames()) {
                $Kind = $RegistryKey.GetValueKind($Name)
                $Data = $RegistryKey.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $ValuesHash[$Name] = [PSCustomObject]@{
                    Data = $Data
                    Type = $Kind.ToString()
                }
            }
            # Collect sub-key names
            $SubKeyList = @($RegistryKey.GetSubKeyNames())
            $RegistryKey.Close()
        }

        $ResultData = [PSCustomObject]@{
            FullKeyPath = $FullKeyPath
            Values      = $ValuesHash
            SubKeys     = $SubKeyList
        }

        $ValueCount  = $ValuesHash.Count
        $SubKeyCount = $SubKeyList.Count
        return (OPSreturn -Code 0 -Message "RegistryHiveQuery: Key '$FullKeyPath' — $ValueCount value(s), $SubKeyCount sub-key(s)." -Data $ResultData)
    }
    catch {
        return (OPSreturn -Code -1 -Message "RegistryHiveQuery failed! Exception reading key '$FullKeyPath': $($_.Exception.Message)")
    }
}
