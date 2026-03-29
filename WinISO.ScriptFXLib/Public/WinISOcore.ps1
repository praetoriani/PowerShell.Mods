function WinISOcore {
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

    .PARAMETER Scope
        The access scope. Currently only 'env' is supported.

    .PARAMETER GlobalVar
        Which module-scope variable to access. Required when Scope='env'.
        Accepted values: 'appinfo' | 'appenv' | 'appexit'

    .PARAMETER Permission
        Access type: 'read' (default, read-only) | 'write' (validated read+write).

    .PARAMETER VarKeyID
        Required when Permission='write'. The key inside the GlobalVar hashtable to update.
        The key MUST already exist — WinISOcore does not create new keys.

    .PARAMETER SetNewVal
        Required when Permission='write'. The new value to assign to VarKeyID.
        Type MUST match the existing key's value type (implicit conversion is attempted).

    .PARAMETER Unwrap
        Switch-Parameter. Wenn angegeben, gibt 'read' direkt die Hashtable zurück
        statt des OPSreturn-Objekts. Vereinfacht den aufrufenden Code erheblich.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        READ  : .data = the live hashtable reference
        WRITE : .data = the newly written value

    .EXAMPLE
        # Read the full appenv hashtable
        $r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'read'
        Write-Host $r.data['ISOroot']   # >> C:\WinISO

    .EXAMPLE
        # Write a new string value (same type)
        $r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' `
                        -VarKeyID 'MountPoint' -SetNewVal 'D:\WIMmount'
        if ($r.code -eq 0) { Write-Host "Updated." }

    .EXAMPLE
        # Type mismatch — will fail gracefully, original value untouched
        $r = WinISOcore -Scope 'env' -GlobalVar 'appenv' -Permission 'write' `
                        -VarKeyID 'MountPoint' -SetNewVal 42
        # $r.code -eq -1

    .NOTES
        Dependencies: AppScope, OPSreturn (WinISO.ScriptFXLib.psm1), PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true,  HelpMessage = "Access scope. Currently only 'env' is supported.")]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $false, HelpMessage = "Module variable: 'appinfo' | 'appenv' | 'appexit'")]
        [string]$GlobalVar = '',

        [Parameter(Mandatory = $true,  HelpMessage = "Access type: 'read' (default) | 'write'")]
        [ValidateNotNullOrEmpty()]
        [string]$Permission = 'read',

        [Parameter(Mandatory = $false, HelpMessage = "Key to update (write only). Must exist in GlobalVar.")]
        [string]$VarKeyID = '',

        [Parameter(Mandatory = $false, HelpMessage = "New value (write only). Type must match existing key's type.")]
        $SetNewVal = $null,

        [Parameter(Mandatory = $false, HelpMessage = "If set, read returns the hashtable directly instead of OPSreturn wrapper.")]
        [switch]$Unwrap
    )

    # Normalise all string inputs to lowercase for consistent comparisons
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
    $ValidVars = @('appinfo', 'appenv', 'appexit')
    if ([string]::IsNullOrWhiteSpace($GlobalVarNorm)) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Parameter 'GlobalVar' is required when Scope='env'.")
    }
    if ($GlobalVarNorm -notin $ValidVars) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Invalid GlobalVar '$GlobalVar'. Allowed: $($ValidVars -join ', ').")
    }

    # -- Enforce read-only vars --
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ReadOnlyVars = @('appcore', 'exit')
    if ($PermissionNorm -eq 'write' -and $GlobalVarNorm -in $ReadOnlyVars) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! '$GlobalVar' is read-only and cannot be modified. Write access is only allowed for: appinfo, appenv.")
    }
    
    # -- Resolve the target hashtable --
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $TargetHashtable = $null
    try {
        switch ($GlobalVarNorm) {
            'appinfo'  {
                $AppInfoVar = Get-Variable -Name 'appinfo' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $AppInfoVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:appinfo could not be resolved.")
                }
                $TargetHashtable = $AppInfoVar.Value
            }
            'appenv'  {
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
            'exit' {
                $ExitVar = Get-Variable -Name 'exit' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $ExitVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:exit could not be resolved.")
                }
                $TargetHashtable = $ExitVar.Value
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
        # With -Unwrap: directly access the hashtable
        if ($Unwrap.IsPresent) {
            return $TargetHashtable
        }
        # Standard: OPSreturn-Wrapper (backwards compatibility)
        return (OPSreturn -Code 0 -Message "WinISOcore: Read access granted for '$GlobalVar'." -Data $TargetHashtable)
    }

    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    # WRITE — additional validation
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ([string]::IsNullOrWhiteSpace($VarKeyIDNorm)) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Parameter 'VarKeyID' is required for write access.")
    }

    # Locate the key (case-insensitive lookup)
    $ResolvedKey = $TargetHashtable.Keys | Where-Object { $_ -eq $VarKeyIDNorm } | Select-Object -First 1
    if (-not $ResolvedKey) {
        # Try case-insensitive fallback
        $ResolvedKey = $TargetHashtable.Keys | Where-Object { $_.ToLower() -eq $VarKeyIDNorm.ToLower() } | Select-Object -First 1
    }
    if (-not $ResolvedKey) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Key '$VarKeyIDNorm' does not exist in '$GlobalVar'. Available keys: $($TargetHashtable.Keys -join ', ').")
    }

    if ($null -eq $SetNewVal) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Parameter 'SetNewVal' must not be null for write access.")
    }

    # -- Type safety check with implicit conversion attempt --
    $ExistingValue = $TargetHashtable[$ResolvedKey]
    $ExistingType  = if ($null -ne $ExistingValue) { $ExistingValue.GetType() } else { $null }
    $NewType       = $SetNewVal.GetType()

    if ($null -ne $ExistingType -and $NewType -ne $ExistingType) {
        $ConvertedValue = $null
        $Converted      = $false
        try {
            $ConvertedValue = [System.Convert]::ChangeType($SetNewVal, $ExistingType)
            $Converted = $true
        } catch { }

        if (-not $Converted) {
            return (OPSreturn -Code -1 -Message "WinISOcore failed! Type mismatch for key '$ResolvedKey': expected $($ExistingType.Name), got $($NewType.Name). Value was NOT changed.")
        }

        $SetNewVal = $ConvertedValue
    }

    # -- Perform the write --
    try {
        $TargetHashtable[$ResolvedKey] = $SetNewVal
    }
    catch {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Error writing '$GlobalVar[$ResolvedKey]': $($_.Exception.Message)")
    }

    # -- Write verification --
    if ($TargetHashtable[$ResolvedKey] -ne $SetNewVal) {
        return (OPSreturn -Code -1 -Message "WinISOcore: Write verification failed for '$GlobalVar[$ResolvedKey]'.")
    }

    return (OPSreturn -Code 0 -Message "WinISOcore: Write successful. '$GlobalVar[$ResolvedKey]' updated to: '$SetNewVal'." -Data $SetNewVal)
}
