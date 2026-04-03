﻿function ValidateRegFile {
    <#
    .SYNOPSIS
        (Private) Validates that a .reg file is syntactically correct and optionally
        targets a specific registry hive.

    .DESCRIPTION
        ValidateRegFile is an internal helper function used by RegistryHiveImport to ensure
        that a .reg file is correctly formatted before any import attempt is made.

        The following checks are performed:
        1.  File existence and .reg extension.
        2.  File is not empty (minimum 1 non-blank line).
        3.  The first non-blank line is the standard Windows Registry Editor header
            (Windows Registry Editor Version 5.00).
        4.  At least one registry key header line is present (starts with '[').
        5.  No line contains a bare NUL character (common sign of binary corruption).
        6.  [OPTIONAL] If a HivePrefix is specified (e.g. 'WinISO_SOFTWARE'), every
            key header in the file must begin with [HKEY_LOCAL_MACHINE\WinISO_SOFTWARE
            to confirm the file targets the correct hive.

    .PARAMETER RegFilePath
        Full path to the .reg file to validate.

    .PARAMETER HivePrefix
        [Optional] The registry key prefix that every key header must match
        (e.g. 'WinISO_SOFTWARE'). When empty or omitted the hive-target check is skipped.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = [List[PSCustomObject]] where each item has: Check, Status, Detail

    .EXAMPLE
        $v = ValidateRegFile -RegFilePath 'C:\temp\settings.reg'
        if ($v.code -ne 0) { Write-Warning $v.msg }

    .EXAMPLE
        $v = ValidateRegFile -RegFilePath 'C:\temp\settings.reg' -HivePrefix 'WinISO_SOFTWARE'
        $v.data | Format-Table Check, Status, Detail -AutoSize

    .NOTES
        This is a private function. It is not exported and is only called internally
        by RegistryHiveImport.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RegFilePath,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$HivePrefix = ''
    )

    $Results      = [System.Collections.Generic.List[PSCustomObject]]::new()
    $FailureCount = 0

    $AddResult = {
        param([string]$Check, [string]$Status, [string]$Detail = '')
        $Results.Add([PSCustomObject]@{
            Check  = $Check
            Status = $Status.ToUpper()
            Detail = $Detail
        })
    }

    # CHECK 1: File exists and has .reg extension
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        if (-not (Test-Path -Path $RegFilePath -PathType Leaf)) {
            & $AddResult '.reg File Existence' 'FAIL' "File not found: '$RegFilePath'"
            return (OPSreturn -Code -1 -Message "ValidateRegFile failed! File not found: '$RegFilePath'" -Data $Results)
        }

        $FileExt = [System.IO.Path]::GetExtension($RegFilePath).ToLower()
        if ($FileExt -ne '.reg') {
            & $AddResult '.reg File Extension' 'FAIL' "Expected .reg extension, got '$FileExt'"
            return (OPSreturn -Code -1 -Message "ValidateRegFile failed! Invalid file extension '$FileExt'. Only .reg files are accepted." -Data $Results)
        }

        & $AddResult '.reg File Existence' 'PASS' "File found: '$RegFilePath'"
    }
    catch {
        & $AddResult '.reg File Existence' 'FAIL' "Exception: $($_.Exception.Message)"
        return (OPSreturn -Code -1 -Message "ValidateRegFile failed! $($_.Exception.Message)" -Data $Results)
    }

    # CHECK 2–5: Read file content and validate structure
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    try {
        # Read with Unicode detection (reg files may be UTF-16 LE with BOM)
        $RawLines = [System.IO.File]::ReadAllLines($RegFilePath, [System.Text.Encoding]::Unicode)

        # If Unicode read yielded mostly empty/garbled content, retry with UTF-8
        $NonBlank = @($RawLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($NonBlank.Count -lt 2) {
            $RawLines = [System.IO.File]::ReadAllLines($RegFilePath, [System.Text.Encoding]::UTF8)
            $NonBlank = @($RawLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        # CHECK 2: Not empty
        if ($NonBlank.Count -eq 0) {
            & $AddResult '.reg File Content' 'FAIL' "File is empty or contains only whitespace."
            $FailureCount++
        }
        else {
            & $AddResult '.reg File Content' 'PASS' "$($NonBlank.Count) non-blank lines found."
        }

        # CHECK 3: Correct header line
        $FirstLine = $NonBlank[0].Trim()
        if ($FirstLine -eq 'Windows Registry Editor Version 5.00') {
            & $AddResult '.reg Header Line' 'PASS' "Valid header: '$FirstLine'"
        }
        else {
            & $AddResult '.reg Header Line' 'FAIL' "Expected 'Windows Registry Editor Version 5.00', found: '$FirstLine'"
            $FailureCount++
        }

        # CHECK 4: At least one key header line (starts with '[')
        $KeyHeaders = @($NonBlank | Where-Object { $_.TrimStart().StartsWith('[') })
        if ($KeyHeaders.Count -gt 0) {
            & $AddResult '.reg Key Headers' 'PASS' "$($KeyHeaders.Count) registry key header(s) found."
        }
        else {
            & $AddResult '.reg Key Headers' 'FAIL' "No registry key headers (lines starting with '[') found."
            $FailureCount++
        }

        # CHECK 5: No NUL characters (binary corruption indicator)
        $NulLine = $NonBlank | Where-Object { $_ -match '\x00' } | Select-Object -First 1
        if ($null -eq $NulLine) {
            & $AddResult '.reg Binary Integrity' 'PASS' "No NUL characters detected."
        }
        else {
            & $AddResult '.reg Binary Integrity' 'FAIL' "NUL character found — file may be corrupted or is not a text .reg file."
            $FailureCount++
        }

        # CHECK 6 (Optional): Hive target prefix validation
        if (-not [string]::IsNullOrWhiteSpace($HivePrefix)) {
            $ExpectedStart = "[HKEY_LOCAL_MACHINE\$HivePrefix"
            $MismatchedKeys = @($KeyHeaders | Where-Object {
                (-not $_.TrimStart('-').TrimStart().StartsWith($ExpectedStart)) -and
                (-not $_.TrimStart().StartsWith("[-HKEY_LOCAL_MACHINE\$HivePrefix"))
            })

            if ($MismatchedKeys.Count -eq 0) {
                & $AddResult '.reg Hive Target' 'PASS' "All key headers target the expected hive prefix '$HivePrefix'."
            }
            else {
                & $AddResult '.reg Hive Target' 'FAIL' "$($MismatchedKeys.Count) key header(s) do not target '$HivePrefix'. First mismatch: '$($MismatchedKeys[0])'"
                $FailureCount++
            }
        }
    }
    catch {
        & $AddResult '.reg File Read' 'FAIL' "Exception while reading/parsing file: $($_.Exception.Message)"
        $FailureCount++
    }

    # FINAL SUMMARY
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $PassCount = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $FailCount = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $Summary   = "ValidateRegFile: $PassCount checks passed | $FailCount checks failed."

    if ($FailureCount -gt 0) {
        return (OPSreturn -Code -1 -Message "$Summary File '$(Split-Path $RegFilePath -Leaf)' failed validation." -Data $Results)
    }

    return (OPSreturn -Code 0 -Message "$Summary File '$(Split-Path $RegFilePath -Leaf)' is a valid .reg file." -Data $Results)
}
