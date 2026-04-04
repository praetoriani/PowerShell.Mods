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
        Accepted values: 'appinfo' | 'appenv' | 'appcore' | 'appexit' | 'exit' |
                         'loadedhives' | 'uupdump' | 'appverify' | 'appx'

    .PARAMETER Permission
        Access type: 'read' (default, read-only) | 'write' (validated read+write).

    .PARAMETER VarKeyID
        Required when Permission='write'. The key inside the GlobalVar hashtable to update.
        For 'appverify': use the check-name keys (e.g. 'checkoscdimg') or 'result' to
        write the entire result sub-hashtable at once.
        For 'appx': use 'listed', 'remove', or 'inject' to replace the corresponding array.
        For 'loadedhives': any string key is allowed (dynamic entries).
        For all other vars: the key MUST already exist.

    .PARAMETER SetNewVal
        Required when Permission='write'. The new value to assign to VarKeyID.
        Type MUST match the existing key's value type (implicit conversion is attempted).
        For 'loadedhives': pass $null to remove an entry.

    .PARAMETER Unwrap
        Switch-Parameter. When specified, 'read' returns the hashtable directly
        instead of the OPSreturn wrapper. Simplifies calling code considerably.

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
        # Write a check result into appverify
        $r = WinISOcore -Scope 'env' -GlobalVar 'appverify' -Permission 'write' `
                        -VarKeyID 'checkoscdimg' -SetNewVal 'INFO'

    .EXAMPLE
        # Write the result counter sub-hashtable into appverify
        $r = WinISOcore -Scope 'env' -GlobalVar 'appverify' -Permission 'write' `
                        -VarKeyID 'result' -SetNewVal @{ pass=8; fail=0; info=2; warn=1 }

    .EXAMPLE
        # Read the full appverify hashtable (unwrapped)
        $verify = WinISOcore -Scope 'env' -GlobalVar 'appverify' -Permission 'read' -Unwrap

    .EXAMPLE
        # Replace the appx 'listed' array
        $r = WinISOcore -Scope 'env' -GlobalVar 'appx' -Permission 'write' `
                        -VarKeyID 'listed' -SetNewVal $packageList

    .EXAMPLE
        # Read LoadedHives directly (unwrapped)
        $hives = WinISOcore -Scope 'env' -GlobalVar 'LoadedHives' -Permission 'read' -Unwrap

    .NOTES
        Version:      1.00.05
        Dependencies: AppScope, OPSreturn (WinISO.ScriptFXLib.psm1), PowerShell 5.1+.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true,  HelpMessage = "Access scope. Currently only 'env' is supported.")]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory = $false, HelpMessage = "Module variable: 'appinfo' | 'appenv' | 'appcore' | 'exit' | 'appexit' | 'loadedhives' | 'uupdump' | 'appverify' | 'appx'")]
        [string]$GlobalVar = '',

        [Parameter(Mandatory = $true,  HelpMessage = "Access type: 'read' (default) | 'write'")]
        [ValidateNotNullOrEmpty()]
        [string]$Permission = 'read',

        [Parameter(Mandatory = $false, HelpMessage = "Key to update (write only). Must exist in GlobalVar (except LoadedHives — new keys allowed).")]
        [string]$VarKeyID = '',

        [Parameter(Mandatory = $false, HelpMessage = "New value (write only). Pass null to remove a LoadedHives entry.")]
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

    # Validate Scope
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ValidScopes = @('env')
    if ($ScopeNorm -notin $ValidScopes) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Invalid Scope '$Scope'. Allowed: $($ValidScopes -join ', ').")
    }

    # Validate Permission
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ValidPermissions = @('read', 'write')
    if ($PermissionNorm -notin $ValidPermissions) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Invalid Permission '$Permission'. Allowed: 'read' | 'write'.")
    }

    # Validate GlobalVar (required for scope 'env')
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ValidVars = @('appinfo', 'appenv', 'appcore', 'exit', 'appexit', 'loadedhives', 'uupdump', 'appverify', 'appx')
    if ([string]::IsNullOrWhiteSpace($GlobalVarNorm)) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Parameter 'GlobalVar' is required when Scope='env'.")
    }
    if ($GlobalVarNorm -notin $ValidVars) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Invalid GlobalVar '$GlobalVar'. Allowed: $($ValidVars -join ', ').")
    }

    # Enforce read-only vars
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    $ReadOnlyVars = @('appcore', 'exit')
    if ($PermissionNorm -eq 'write' -and $GlobalVarNorm -in $ReadOnlyVars) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! '$GlobalVar' is read-only and cannot be modified. Write access is only allowed for: appinfo, appenv, LoadedHives, uupdump, appverify, appx.")
    }

    # Resolve the target hashtable
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
            'uupdump' {
                $UUPDumpVar = Get-Variable -Name 'uupdump' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $UUPDumpVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:uupdump could not be resolved. Ensure the module was loaded correctly.")
                }
                $TargetHashtable = $UUPDumpVar.Value
            }
            'appverify' {
                $AppVerifyVar = Get-Variable -Name 'appverify' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $AppVerifyVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:appverify could not be resolved. Ensure the module was loaded correctly.")
                }
                $TargetHashtable = $AppVerifyVar.Value
            }
            'appx' {
                $AppXVar = Get-Variable -Name 'appx' -Scope Script -ErrorAction SilentlyContinue
                if ($null -eq $AppXVar) {
                    return (OPSreturn -Code -1 -Message "WinISOcore failed! Module-scope variable `$script:appx could not be resolved. Ensure the module was loaded correctly.")
                }
                $TargetHashtable = $AppXVar.Value
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
    # WRITE - validate VarKeyID first
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ([string]::IsNullOrWhiteSpace($VarKeyIDNorm)) {
        return (OPSreturn -Code -1 -Message "WinISOcore failed! Parameter 'VarKeyID' is required for write access.")
    }

    # WRITE: LoadedHives — special handling (add/remove dynamic entries)
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

    # WRITE: appverify — special handling for status strings and nested result hashtable
    # Valid check-key names and 'result' (for the counter sub-hashtable) are accepted.
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ($GlobalVarNorm -eq 'appverify') {
        $CheckKey = $VarKeyIDNorm.ToLower()

        # Valid status-string keys
        $ValidCheckKeys = @(
            'checkosversion', 'checkpowershell', 'checkdotnet', 'checkisadmin',
            'checkdismpath', 'checkdismmods', 'checkrobocopy', 'checkcmd',
            'checkoscdimg', 'checkenvdirs', 'checkinternet'
        )

        if ($CheckKey -eq 'result') {
            # Special: replace the entire result sub-hashtable
            if ($SetNewVal -isnot [hashtable]) {
                return (OPSreturn -Code -1 -Message "WinISOcore failed! SetNewVal for appverify['result'] must be a hashtable with keys: pass, fail, info, warn.")
            }
            $TargetHashtable['result'] = $SetNewVal
            return (OPSreturn -Code 0 -Message "WinISOcore: appverify['result'] updated." -Data $SetNewVal)
        }
        elseif ($CheckKey -in $ValidCheckKeys) {
            # Validate: must be a recognised status string
            $ValidStatuses = @('PASS', 'FAIL', 'INFO', 'WARN', '')
            $StatusUpper   = if ($null -ne $SetNewVal) { [string]$SetNewVal.ToString().ToUpper() } else { '' }
            if ($StatusUpper -notin $ValidStatuses) {
                return (OPSreturn -Code -1 -Message "WinISOcore failed! SetNewVal for appverify check-keys must be one of: PASS, FAIL, INFO, WARN (or empty). Got: '$SetNewVal'.")
            }
            $TargetHashtable[$CheckKey] = $StatusUpper
            return (OPSreturn -Code 0 -Message "WinISOcore: appverify['$CheckKey'] set to '$StatusUpper'." -Data $StatusUpper)
        }
        else {
            return (OPSreturn -Code -1 -Message "WinISOcore failed! Key '$VarKeyIDNorm' is not a valid appverify key. Valid keys: $($ValidCheckKeys -join ', '), result.")
        }
    }

    # WRITE: appx — special handling for array replacement (listed, remove, inject)
    # ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
    if ($GlobalVarNorm -eq 'appx') {
        $AppxKey = $VarKeyIDNorm.ToLower()
        $ValidAppxKeys = @('listed', 'remove', 'inject')

        if ($AppxKey -notin $ValidAppxKeys) {
            return (OPSreturn -Code -1 -Message "WinISOcore failed! Key '$VarKeyIDNorm' is not a valid appx key. Valid keys: $($ValidAppxKeys -join ', ').")
        }

        # Accept arrays or single objects (wrap single objects into array for consistency)
        if ($null -eq $SetNewVal) {
            # Allow explicit reset to empty array
            $TargetHashtable[$AppxKey] = @()
            return (OPSreturn -Code 0 -Message "WinISOcore: appx['$AppxKey'] reset to empty array." -Data @())
        }

        if ($SetNewVal -is [array] -or $SetNewVal -is [System.Collections.IList]) {
            $TargetHashtable[$AppxKey] = $SetNewVal
        }
        else {
            # Wrap single value into array
            $TargetHashtable[$AppxKey] = @($SetNewVal)
        }
        return (OPSreturn -Code 0 -Message "WinISOcore: appx['$AppxKey'] updated ($($TargetHashtable[$AppxKey].Count) item(s))." -Data $TargetHashtable[$AppxKey])
    }

    # WRITE: appinfo / appenv / uupdump — standard key-must-exist + type-safety logic
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
