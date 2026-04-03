﻿function RegistryHiveImport {
    <#
    .SYNOPSIS
        Imports a validated .reg file into a loaded offline registry hive.

    .DESCRIPTION
        RegistryHiveImport first validates the supplied .reg file using the private helper
        ValidateRegFile, then performs the import via 'reg.exe IMPORT' into the already
        loaded hive at HKLM:\WinISO_<HiveName>.

        Because reg.exe IMPORT writes directly into the live (currently active) registry
        using the key paths stored inside the .reg file, the import operation requires that
        the keys inside the .reg file already reference the WinISO_<HiveName> mount point
        (e.g. [HKEY_LOCAL_MACHINE\WinISO_SOFTWARE\...]). The optional -ValidateHiveTarget
        switch enforces this check before the import proceeds.

        The function aborts immediately if the .reg file fails validation.

    .PARAMETER HiveID
        [MANDATORY] The name of the loaded hive to import into (e.g. 'SOFTWARE', 'SYSTEM').

    .PARAMETER RegFilePath
        [MANDATORY] Full path to the .reg file to import.

    .PARAMETER ValidateHiveTarget
        [OPTIONAL] When specified, ValidateRegFile additionally verifies that every key
        header inside the .reg file targets the correct WinISO_<HiveName> mount path.
        Recommended for safety to prevent accidental overwrites of unrelated hive data.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = PSCustomObject { RegFilePath, HiveID, ValidationResult, ImportOutput }

    .EXAMPLE
        $r = RegistryHiveImport -HiveID 'SOFTWARE' -RegFilePath 'C:\temp\tweaks.reg'
        if ($r.code -eq 0) { Write-Host "Import successful." }

    .EXAMPLE
        # With strict hive-target validation
        $r = RegistryHiveImport -HiveID 'SOFTWARE' -RegFilePath 'C:\temp\tweaks.reg' `
                                 -ValidateHiveTarget
        if ($r.code -ne 0) { Write-Warning $r.msg }

    .NOTES
        - Requires administrator privileges.
        - The hive must be loaded via LoadRegistryHive before calling this function.
        - The .reg file MUST reference HKEY_LOCAL_MACHINE\WinISO_<HiveName> key paths
          when -ValidateHiveTarget is used.
        - Dependencies: ValidateRegFile (Private), OPSreturn, PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the loaded hive (e.g. SOFTWARE, SYSTEM)")]
        [ValidateNotNullOrEmpty()]
        [string]$HiveID,

        [Parameter(Mandatory = $true, HelpMessage = "Full path to the .reg file to import")]
        [ValidateNotNullOrEmpty()]
        [string]$RegFilePath,

        [Parameter(Mandatory = $false, HelpMessage = "Enforce that all key headers target the correct hive mount path")]
        [switch]$ValidateHiveTarget
    )

    # STEP 1: Validate that the hive is loaded
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveIDNorm = $HiveID.Trim().ToUpper()

    if (-not (Get-Variable -Name 'LoadedHives' -Scope Script -ErrorAction SilentlyContinue)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveImport failed! No hives are currently loaded. Use LoadRegistryHive first.")
    }
    if (-not $script:LoadedHives.ContainsKey($HiveIDNorm)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveImport failed! Hive '$HiveID' is not loaded. Available: $($script:LoadedHives.Keys -join ', ')")
    }

    # STEP 2: Validate the .reg file (always) — with optional hive-target check
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HivePrefix     = if ($ValidateHiveTarget.IsPresent) { "WinISO_$HiveIDNorm" } else { '' }
    $ValidationResult = ValidateRegFile -RegFilePath $RegFilePath -HivePrefix $HivePrefix

    if ($ValidationResult.code -ne 0) {
        $ResultData = [PSCustomObject]@{
            RegFilePath      = $RegFilePath
            HiveID           = $HiveIDNorm
            ValidationResult = $ValidationResult.data
            ImportOutput     = $null
        }
        return (OPSreturn -Code -1 -Message "RegistryHiveImport aborted! .reg file validation failed: $($ValidationResult.msg)" -Data $ResultData)
    }

    # STEP 3: Execute reg.exe IMPORT
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        $RegArgs      = @('IMPORT', $RegFilePath)
        $RegOutput    = & reg.exe @RegArgs 2>&1
        $ExitCode     = $LASTEXITCODE

        $ResultData = [PSCustomObject]@{
            RegFilePath      = $RegFilePath
            HiveID           = $HiveIDNorm
            ValidationResult = $ValidationResult.data
            ImportOutput     = ($RegOutput -join ' ')
        }

        if ($ExitCode -eq 0) {
            return (OPSreturn -Code 0 -Message "RegistryHiveImport: '$(Split-Path $RegFilePath -Leaf)' imported into hive '$HiveIDNorm' successfully." -Data $ResultData)
        }
        else {
            return (OPSreturn -Code -1 -Message "RegistryHiveImport failed! reg.exe IMPORT exited with code $ExitCode. Output: $($RegOutput -join ' ')" -Data $ResultData)
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "RegistryHiveImport failed! Exception during import: $($_.Exception.Message)")
    }
}
