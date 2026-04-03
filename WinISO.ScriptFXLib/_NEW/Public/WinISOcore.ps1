﻿function WinISOcore {
    <#
    .SYNOPSIS
        Unified read/write accessor for WinISO module-scope (script-scope) variables.

    .DESCRIPTION
        WinISOcore provides controlled, type-safe access to the module-scope hashtable
        variables defined in WinISO.ScriptFXLib.psm1.

        Background:
        AppScope() returns a live reference to a PowerShell hashtable ($script:appenv,
        $script:appinfo). Because PS hashtables are reference types, a caller can technically
        write directly to the returned reference — but this is unintentional write access
        without type checking, validation, or audit logging.

        WinISOcore formalises this by:
        - Providing explicit Permission='read' (safe, audit-friendly) and
          Permission='write' (type-safe write with validation)
        - Enforcing that the new value's type matches the existing key's type
          (with a conversion attempt before rejecting)
        - Returning a structured OPSreturn object for all operations
        - Keeping the door open for future Scope extensions (e.g. 'ext' for external
          JSON config) without changing the interface

        Supported GlobalVar values (Permission='read' and 'write' where applicable):
        - appinfo     : module metadata (read/write)
        - appenv      : working directory paths (read/write)
        - appcore     : core configuration / download URLs (read-only)
        - exit        : exit code/text accumulator (read-only)
        - LoadedHives : runtime hashtable of currently loaded offline registry hives
                        (read/write — managed by LoadRegistryHive / UnloadRegistryHive)

    .PARAMETER Scope
        The access scope. Currently only 'env' is supported.

    .PARAMETER GlobalVar
        Which module-scope variable to access. Required when Scope='env'.
        Accepted values: 'appinfo' | 'appenv' | 'appcore' | 'exit' | 'LoadedHives'

    .PARAMETER Permission
        Access type: 'read' (default, read-only) | 'write' (validated read+write).

    .PARAMETER VarKeyID
        Required when Permission='write'. The key inside the GlobalVar hashtable to update.
        For LoadedHives: the HiveName (e.g. 'SOFTWARE').
        For all other vars: the key must already exist — WinISOcore does not create new keys,
        EXCEPT for LoadedHives where new hive entries may be added or removed by the
        registry hive management functions.

    .PARAMETER SetNewVal
        Required when Permission='write'. The new value to assign to VarKeyID.
        For LoadedHives write: pass the RegMountKey string (e.g. 'HKLM\WinISO_SOFTWARE')
        to add a new tracking entry, OR pass $null to remove an existing entry.

    .PARAMETER Unwrap
        Switch-Parameter. When specified, 'read' returns the hashtable directly instead
        of the OPSreturn wrapper. Significantly simplifies calling code.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        READ  : .data = the live hashtable reference
        WRITE : .data = the newly written value (or $null if entry was removed)

    .EXAMPLE
        # Read the full appenv hashtable
        $r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'read'
        Write-Host $r.data['ISOroot']   # >> C:\WinISO

    .EXAMPLE
        # Read LoadedHives directly (unwrapped)
        $hives = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'read' -Unwrap
        $hives | Format-Table   # shows all currently loaded hives

    .EXAMPLE
        # Add a new hive tracking entry (called internally by LoadRegistryHive)
        $r = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'write' `
                        -VarKeyID 'SOFTWARE' -SetNewVal 'HKLM\WinISO_SOFTWARE'

    .EXAMPLE
        # Remove a hive tracking entry (called internally by UnloadRegistryHive)
        $r = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'write' `
                        -VarKeyID 'SOFTWARE' -SetNewVal $null

    .EXAMPLE
        # Write a new string value into appenv
        $r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' `
                        -VarKeyID 'MountPoint' -SetNewVal 'D:\WIMmount'
        if ($r.code -eq 0) { Write-Host "Updated." }

    .NOTES
        Dependencies: AppScope, OPSreturn (WinISO.ScriptFXLib.psm1), PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true,  HelpMessage = "Access scope. Currently only 'env' is supported.")]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $false, HelpMessage = "Module variable: 'appinfo' | 'appenv' | 'appcore' | 'exit' | 'LoadedHives'")]
        [string]$GlobalVar = '',

        [Parameter(Mandatory = $true,  HelpMessage = "Access type: 'read' (default) | 'write'")]
        [ValidateNotNullOrEmpty()]
        [string]$Permission = 'read',

        [Parameter(Mandatory = $false, HelpMessage = "Key to update (write only). Must exist in GlobalVar (except LoadedHives — new keys allowed).")]
        [string]$VarKeyID = '',

        [Parameter(Mandatory = $false, HelpMessage = "New value (write only). Pass \$null to remove a LoadedHives entry.")]
        $SetNewVal = $null,

        [Parameter(Mandatory = $false, HelpMessage = "If set, read returns the hashtable directly instead of OPSreturn wrapper.")]
        [switch]$Unwrap
    )

    # Normalise all string inputs for consistent comparisons
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ScopeNorm      = $Scope.Trim().ToLower()
    $PermissionNorm = $Permission.Trim().ToLower()
    $GlobalVarNorm  = $GlobalVar.Trim().ToLower()
    $VarKeyIDNorm   = $VarKeyID.Trim()   # preserve original casing for key lookup

    # -- Validate Scope --
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ValidScopes = @('env')
    if ($ScopeNorm -notin $ValidScopes) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Invalid Scope '$Scope'. Allowed: $($ValidScopes -join ', ').")
    }

    # -- Validate Permission --
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ValidPermissions = @('read', 'write')
    if ($PermissionNorm -notin $ValidPermissions) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Invalid Permission '$Permission'. Allowed: 'read' | 'write'.")
    }

    # -- Validate GlobalVar (required for scope 'env') --
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ValidVars = @('appinfo', 'appenv', 'appcore', 'exit', 'appexit', 'loadedhives')
    if ([string]::IsNullOrWhiteSpace($GlobalVarNorm)) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Parameter 'GlobalVar' is required when Scope='env'.")
    }
    if ($GlobalVarNorm -notin $ValidVars) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Invalid GlobalVar '$GlobalVar'. Allowed: $($ValidVars -join ', ').")
    }

    # -- Enforce read-only vars --
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ReadOnlyVars = @('appcore', 'exit')
    if ($PermissionNorm -eq 'write' -and $GlobalVarNorm -in $ReadOnlyVars) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! '$GlobalVar' is read-only and cannot be modified. Write access is only allowed for: appinfo, appenv, LoadedHives.")
    }

    # -- Resolve the target hashtable --
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $TargetHashtable = $null
    try {
        switch ($GlobalVarNorm) {
            'appinfo' {
                $AppInfoVar = Get-Variable -Name 'appinfo' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $AppInfoVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:appinfo could not be resolved.")
                }
                $TargetHashtable = $AppInfoVar.Value
            }
            'appenv' {
                $AppEnvVar = Get-Variable -Name 'appenv' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $AppEnvVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:appenv could not be resolved.")
                }
                $TargetHashtable = $AppEnvVar.Value
            }
            'appcore' {
                $AppCoreVar = Get-Variable -Name 'appcore' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $AppCoreVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:appcore could not be resolved.")
                }
                $TargetHashtable = $AppCoreVar.Value
            }
            { $_ -in @('exit', 'appexit') } {
                $ExitVar = Get-Variable -Name 'exit' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $ExitVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:exit could not be resolved.")
                }
                $TargetHashtable = $ExitVar.Value
            }
            'loadedhives' {
                $LoadedHivesVar = Get-Variable -Name 'LoadedHives' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $LoadedHivesVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:LoadedHives could not be resolved. Ensure the module was loaded correctly.")
                }
                $TargetHashtable = $LoadedHivesVar.Value
            }
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Error resolving module variable '$GlobalVar': $($_.Exception.Message)")
    }

    if ($null -eq $TargetHashtable) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Module variable '$GlobalVar' resolved to null. Has the module been loaded correctly?")
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # READ
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ($PermissionNorm -eq 'read') {
        if ($Unwrap.IsPresent) {
            return $TargetHashtable
        }
        return (OPSreturn -Code 0 -Message "WinISOcore: Read access granted for '$GlobalVar'." -Data $TargetHashtable)
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # WRITE — validate VarKeyID first
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ([string]::IsNullOrWhiteSpace($VarKeyIDNorm)) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Parameter 'VarKeyID' is required for write access.")
    }

    # =========================================================================
    # WRITE: LoadedHives — special handling (add/remove dynamic entries)
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ($GlobalVarNorm -eq 'loadedhives') {
        $HiveKey = $VarKeyIDNorm.ToUpper()

        if ($null -eq $SetNewVal) {
            # Remove mode: $null as value signals entry deletion
            if ($TargetHashtable.ContainsKey($HiveKey)) {
                $TargetHashtable.Remove($HiveKey)
                return (OPSreturn -Code 0 -Message "WinISOcore: LoadedHives entry '$HiveKey' removed." -Data $null)
            }
            else {
                return (OPSreturn -Code 0 -Message "WinISOcore: LoadedHives entry '$HiveKey' not found — nothing to remove." -Data $null)
            }
        }
        else {
            # Add/Update mode: value must be a non-empty string (the RegMountKey)
            if ($SetNewVal -isnot [string] -or [string]::IsNullOrWhiteSpace($SetNewVal)) {
                return (OPSreturn -Code -1 -Message "WinISOcore failed! SetNewVal for LoadedHives must be a non-empty string (the registry mount key, e.g. 'HKLM\WinISO_SOFTWARE').")
            }
            $TargetHashtable[$HiveKey] = $SetNewVal
            return (OPSreturn -Code 0 -Message "WinISOcore: LoadedHives['$HiveKey'] set to '$SetNewVal'." -Data $SetNewVal)
        }
    }

    # =========================================================================
    # WRITE: appinfo / appenv — standard key-must-exist + type-safety logic
    # =========================================================================
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ResolvedKey = $TargetHashtable.Keys | Where-Object { $_ -eq $VarKeyIDNorm } | Select-Object -First 1
    if (-not $ResolvedKey) {
        $ResolvedKey = $TargetHashtable.Keys | Where-Object { $_.ToLower() -eq $VarKeyIDNorm.ToLower() } | Select-Object -First 1
    }
    if (-not $ResolvedKey) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Key '$VarKeyIDNorm' does not exist in '$GlobalVar'. Available keys: $($TargetHashtable.Keys -join ', ').")
    }

    if ($null -eq $SetNewVal) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Parameter 'SetNewVal' must not be null for write access to '$GlobalVar'.")
    }

    # Type safety check with implicit conversion attempt
    $ExistingValue = $TargetHashtable[$ResolvedKey]
    $ExistingType  = if ($null -ne $ExistingValue) { $ExistingValue.GetType() } else { $null }
    $NewType       = $SetNewVal.GetType()

    if ($null -ne $ExistingType -and $NewType -ne $ExistingType) {
        $ConvertedValue = $null
        $Converted      = $false
        try {
            $ConvertedValue = [System.Convert]::ChangeType($SetNewVal, $ExistingType)
            $Converted = $true
        }
        catch { }

        if (-not $Converted) {
            return (OPSreturn -Code -1 -Message "WinISOcore failed! Type mismatch for key '$ResolvedKey': expected $($ExistingType.Name), got $($NewType.Name). Value was NOT changed.")
        }

        $SetNewVal = $ConvertedValue
    }

    # Perform the write
    try {
        $TargetHashtable[$ResolvedKey] = $SetNewVal
    }
    catch {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Error writing '$GlobalVar[$ResolvedKey]': $($_.Exception.Message)")
    }

    # Write verification
    if ($TargetHashtable[$ResolvedKey] -ne $SetNewVal) {
        return (OPSreturn -Code -1 -Message "WinISOcore: Write verification failed for '$GlobalVar[$ResolvedKey]'.")
    }

    return (OPSreturn -Code 0 -Message "WinISOcore: Write successful. '$GlobalVar[$ResolvedKey]' updated to: '$SetNewVal'." -Data $SetNewVal)
}
