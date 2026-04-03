﻿function RegistryHiveExport {
    <#
    .SYNOPSIS
        Exports a registry key branch from a loaded offline hive to a .reg file.

    .DESCRIPTION
        RegistryHiveExport uses 'reg.exe EXPORT' to export a specified key path (including
        all sub-keys and values) from a loaded offline registry hive into a standard
        Windows .reg file (Registry Editor Version 5.00 format, UTF-16 LE).

        The exported file can later be re-imported using RegistryHiveImport into the same
        or a different offline image.

        By default the function will not overwrite an existing .reg file at the target path.
        Use -Force to allow overwriting.

    .PARAMETER HiveID
        [MANDATORY] The name of the loaded hive to export from (e.g. 'SOFTWARE', 'SYSTEM').

    .PARAMETER KeyPath
        [MANDATORY] The sub-path inside the hive to export, relative to the hive root.
        Example: 'Microsoft\Windows NT\CurrentVersion'
        All sub-keys and values beneath this path are included in the export.

    .PARAMETER OutputFile
        [MANDATORY] Full path for the output .reg file, including filename.
        Example: 'C:\Backup\SOFTWARE_CurrentVersion.reg'

    .PARAMETER Force
        [OPTIONAL] When specified, an existing file at OutputFile is overwritten.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = PSCustomObject { ExportedKeyPath, OutputFile, FileSizeBytes }

    .EXAMPLE
        $r = RegistryHiveExport -HiveID 'SOFTWARE' `
                                 -KeyPath 'Microsoft\Windows NT\CurrentVersion' `
                                 -OutputFile 'C:\Backup\CurrentVersion.reg'
        if ($r.code -eq 0) { Write-Host "Exported to: $($r.data.OutputFile)" }

    .EXAMPLE
        # Overwrite existing file
        $r = RegistryHiveExport -HiveID 'SYSTEM' -KeyPath 'ControlSet001' `
                                 -OutputFile 'C:\Backup\ControlSet001.reg' -Force

    .NOTES
        - Requires administrator privileges.
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

        [Parameter(Mandatory = $true, HelpMessage = "Full path for the output .reg file")]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile,

        [Parameter(Mandatory = $false, HelpMessage = "Overwrite an existing output file")]
        [switch]$Force
    )

    # STEP 1: Validate that the hive is loaded
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveIDNorm = $HiveID.Trim().ToUpper()

    if (-not (Get-Variable -Name 'LoadedHives' -Scope Script -ErrorAction SilentlyContinue)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveExport failed! No hives are currently loaded. Use LoadRegistryHive first.")
    }
    if (-not $script:LoadedHives.ContainsKey($HiveIDNorm)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveExport failed! Hive '$HiveID' is not loaded. Available: $($script:LoadedHives.Keys -join ', ')")
    }

    # STEP 2: Validate output file path and extension
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $OutputExt = [System.IO.Path]::GetExtension($OutputFile).ToLower()
    if ($OutputExt -ne '.reg') {
        return (OPSreturn -Code -1 -Message "RegistryHiveExport failed! OutputFile must have a .reg extension. Got: '$OutputExt'")
    }

    if ((Test-Path -Path $OutputFile -PathType Leaf) -and -not $Force.IsPresent) {
        return (OPSreturn -Code -1 -Message "RegistryHiveExport failed! Output file '$OutputFile' already exists. Use -Force to overwrite.")
    }

    # Ensure the output directory exists
    try {
        $OutputDir = [System.IO.Path]::GetDirectoryName($OutputFile)
        if (-not [string]::IsNullOrWhiteSpace($OutputDir) -and -not (Test-Path -Path $OutputDir -PathType Container)) {
            $null = New-Item -Path $OutputDir -ItemType Directory -Force -ErrorAction Stop
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "RegistryHiveExport failed! Could not create output directory '$OutputDir': $($_.Exception.Message)")
    }

    # STEP 3: Build full registry path and verify the key exists
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $HiveMountKey  = $script:LoadedHives[$HiveIDNorm]              # e.g. HKLM\WinISO_SOFTWARE
    $RegExportPath = "$HiveMountKey\$($KeyPath.TrimStart('\\/'))"    # e.g. HKLM\WinISO_SOFTWARE\Microsoft\...

    $PSCheckPath   = $HiveMountKey -replace 'HKLM\\\\', 'HKLM:\\'
    $PSCheckPath   = Join-Path $PSCheckPath $KeyPath.TrimStart('\\/')

    if (-not (Test-Path -Path $PSCheckPath)) {
        return (OPSreturn -Code -1 -Message "RegistryHiveExport failed! Key '$PSCheckPath' does not exist in the loaded hive.")
    }

    # STEP 4: Execute reg.exe EXPORT
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        # reg.exe EXPORT always prompts if the file exists unless /y is appended
        $RegArgs = @('EXPORT', $RegExportPath, $OutputFile)
        if ($Force.IsPresent) { $RegArgs += '/y' }

        $RegOutput = & reg.exe @RegArgs 2>&1
        $ExitCode  = $LASTEXITCODE

        if ($ExitCode -ne 0) {
            return (OPSreturn -Code -1 -Message "RegistryHiveExport failed! reg.exe EXPORT exited with code $ExitCode. Output: $($RegOutput -join ' ')")
        }

        # Verify the output file was written
        if (-not (Test-Path -Path $OutputFile -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "RegistryHiveExport failed! reg.exe EXPORT reported success but the output file was not found: '$OutputFile'")
        }

        $FileSizeBytes = (Get-Item -Path $OutputFile).Length

        $ResultData = [PSCustomObject]@{
            ExportedKeyPath = $RegExportPath
            OutputFile      = $OutputFile
            FileSizeBytes   = $FileSizeBytes
        }

        return (OPSreturn -Code 0 -Message "RegistryHiveExport: Key '$RegExportPath' exported to '$OutputFile' ($FileSizeBytes bytes)." -Data $ResultData)
    }
    catch {
        return (OPSreturn -Code -1 -Message "RegistryHiveExport failed! Exception: $($_.Exception.Message)")
    }
}
