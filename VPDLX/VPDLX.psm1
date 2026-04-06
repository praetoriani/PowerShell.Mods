<#
.SYNOPSIS
    VPDLX - Virtual PowerShell Data-Logger eXtension
    Root module file: initialises the module, loads all class and function files,
    registers TypeAccelerators, and exposes the VPDLXcore accessor.

.DESCRIPTION
    VPDLX provides a fully class-based virtual logging system that allows callers
    to create, manage, and query multiple in-memory log files simultaneously.

    Architecture overview (v1.01.00):

      Classes/
          FileDetails.ps1   — metadata companion for each Logfile instance
          FileStorage.ps1   — central registry that tracks all Logfile instances
          Logfile.ps1       — core user-facing class (Write/Print/Read/SoakUp/
                               FilterByLevel/Reset/Destroy + shortcut methods)

      Private/
          VPDLXreturn.ps1   — factory function for standardised return objects

      (Public/ directory reserved for future wrapper functions)

    TypeAccelerators:
        [FileDetails], [FileStorage], and [Logfile] are registered as
        TypeAccelerators on module load so that callers can use the class
        syntax directly after a normal 'Import-Module VPDLX':

            $log = [Logfile]::new('MyLog')
            $log.Info('Application started.')

        TypeAccelerators are removed cleanly when the module is unloaded
        (OnRemove handler at the bottom of this file).

        IMPORTANT: TypeAccelerators must be registered using the short class
        name (e.g. 'Logfile'), NOT the fully-qualified name. Using the
        FullName (e.g. 'VPDLX.Logfile') would require callers to write
        [VPDLX.Logfile]::new(), not [Logfile]::new().

    Module-scope variables:
        $script:appinfo  — read-only module metadata hashtable
        $script:storage  — the single [FileStorage] instance; managed by
                           VPDLX internals; not directly exposed to callers
        $script:export   — supported file extension definitions for future
                           export functionality

    VPDLXcore:
        A thin accessor function that returns module-scope variables in a
        controlled, read-only fashion. Primarily used by future public
        functions that are dot-sourced and therefore cannot directly access
        $script:* variables from this root module scope.

.NOTES
    Creation Date : 05.04.2026
    Last Update   : 06.04.2026
    Version       : 1.01.00
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Website       : https://github.com/praetoriani/PowerShell.Mods

    REQUIREMENTS:
    - PowerShell 5.1 or higher
    - No external dependencies

    BUGFIXES (06.04.2026):
      TypeAccelerators are now registered using the short class Name
      (e.g. 'Logfile') instead of the FullName (e.g. 'VPDLX.Logfile').
      Using FullName required callers to write [VPDLX.Logfile]::new()
      rather than the documented [Logfile]::new(), causing TypeNotFound
      errors in the demo and any real caller code.
#>

# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 1 — Module-scope metadata and configuration
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# Read-only module metadata. Accessible externally via VPDLXcore -KeyID 'appinfo'.
$script:appinfo = @{
    appname    = 'VPDLX'
    appvers    = '1.01.00'
    appdevname = 'Praetoriani'
    appdevmail = 'mr.praetoriani{at}gmail.com'
    appwebsite = 'https://github.com/praetoriani/PowerShell.Mods'
    datecreate = '05.04.2026'
    lastupdate = '06.04.2026'
}

# Supported file extensions for future export functionality.
$script:export = @{
    txt  = '.txt'
    csv  = '.csv'
    json = '.json'
    log  = '.log'
}


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 2 — Class loading (order is critical)
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# PowerShell requires classes to be defined before they are referenced.
# [FileDetails] and [FileStorage] must be dot-sourced before [Logfile] because
# [Logfile] declares a [FileDetails] typed property and calls $script:storage
# (a [FileStorage] instance) in its constructor.
#
# IMPORTANT: Do NOT change this load order without carefully verifying that
# no forward-reference would break class resolution on PowerShell 5.1.
$script:ClassFiles = @(
    "$PSScriptRoot\Classes\FileDetails.ps1",
    "$PSScriptRoot\Classes\FileStorage.ps1",
    "$PSScriptRoot\Classes\Logfile.ps1"
)

foreach ($ClassFile in $script:ClassFiles) {
    if (-not (Test-Path -LiteralPath $ClassFile)) {
        Write-Error "VPDLX: Required class file not found: $ClassFile"
        return
    }
    try {
        . $ClassFile
        Write-Verbose "VPDLX: Loaded class file: $($ClassFile | Split-Path -Leaf)"
    }
    catch {
        Write-Error "VPDLX: Failed to load class file '$ClassFile': $($_.Exception.Message)"
        return
    }
}


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 3 — Module-level FileStorage singleton
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# This singleton is the single source of truth for all active Logfile instances.
# Initialised here (after the class files are loaded) so that the [Logfile]
# constructor can call $script:storage.Add() / Contains() immediately.
$script:storage = [FileStorage]::new()


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 4 — Private and Public function loading
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

$PrivateFunctions = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)
$PublicFunctions  = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1"  -ErrorAction SilentlyContinue)

foreach ($FuncFile in @($PrivateFunctions + $PublicFunctions)) {
    try {
        . $FuncFile.FullName
        Write-Verbose "VPDLX: Loaded function file: $($FuncFile.Name)"
    }
    catch {
        Write-Error "VPDLX: Failed to load function file '$($FuncFile.FullName)': $($_.Exception.Message)"
    }
}


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 5 — VPDLXcore accessor
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

<#
.SYNOPSIS
    VPDLXcore — Read-only accessor for module-scoped VPDLX variables.

.DESCRIPTION
    Dot-sourced scripts in the Public/ directory cannot directly access
    $script:* variables that live in the root module scope (VPDLX.psm1).
    VPDLXcore bridges that gap by acting as a controlled getter:

      VPDLXcore -KeyID 'appinfo'   ->  $script:appinfo  (module metadata)
      VPDLXcore -KeyID 'storage'   ->  $script:storage  ([FileStorage] instance)
      VPDLXcore -KeyID 'export'    ->  $script:export   (export format definitions)

    Callers receive a reference, not a copy, so read operations on the returned
    object reflect the current live state. Callers must NOT mutate the returned
    object directly; all mutations must go through the appropriate class methods.

.PARAMETER KeyID
    One of: 'appinfo', 'storage', 'export'  (case-insensitive)

.OUTPUTS
    The requested module-scoped object, or a [PSCustomObject] error carrier
    (code = -1, msg = <description>, data = $null) on failure.

.EXAMPLE
    $meta = VPDLXcore -KeyID 'appinfo'
    Write-Host "VPDLX version: $($meta.appvers)"

.EXAMPLE
    $store = VPDLXcore -KeyID 'storage'
    $store.GetNames()   # lists all registered logfile names

.EXAMPLE
    $formats = VPDLXcore -KeyID 'export'
    $formats.Keys       # txt, csv, json, log
#>
function VPDLXcore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $KeyID
    )

    try {
        switch ($KeyID.Trim().ToLower()) {
            'appinfo' { return $script:appinfo }
            'storage' { return $script:storage }
            'export'  { return $script:export  }
            default {
                return VPDLXreturn -Code -1 -Message (
                    "Unknown KeyID '$KeyID'. " +
                    "Valid keys: 'appinfo', 'storage', 'export'."
                )
            }
        }
    }
    catch {
        return VPDLXreturn -Code -1 -Message (
            "Unexpected error in VPDLXcore: $($_.Exception.Message)"
        )
    }
}


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 6 — TypeAccelerator registration
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# PowerShell classes defined inside a module are NOT automatically available
# via [ClassName]::new() after a plain 'Import-Module' call.
# Registering the types as TypeAccelerators makes them globally accessible
# in the caller's session without requiring 'using module' syntax.
#
# CRITICAL: Register the SHORT class name (e.g. 'Logfile'), NOT the fully-
# qualified name (e.g. 'VPDLX.Logfile'). Registering FullName would require
# callers to write [VPDLX.Logfile]::new() instead of [Logfile]::new().

$script:ExportableTypes = @(
    [FileDetails],
    [FileStorage],
    [Logfile]
)

$script:TypeAcceleratorsClass = [psobject].Assembly.GetType(
    'System.Management.Automation.TypeAccelerators'
)

foreach ($Type in $script:ExportableTypes) {
    # Use the short Name as the accelerator key so callers write [Logfile],
    # not [VPDLX.Logfile]. Guard against duplicate registration (e.g. if the
    # module is re-imported in the same session without Remove-Module first).
    if (-not $script:TypeAcceleratorsClass::Get.ContainsKey($Type.Name)) {
        $script:TypeAcceleratorsClass::Add($Type.Name, $Type)
        Write-Verbose "VPDLX: Registered TypeAccelerator: [$($Type.Name)]"
    }
}


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 7 — Module export declarations
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

[string[]] $FunctionsToExport = @('VPDLXcore')
if ($PublicFunctions.Count -gt 0) {
    $FunctionsToExport += $PublicFunctions.BaseName
}

Export-ModuleMember -Function $FunctionsToExport


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 8 — Module OnRemove handler (cleanup)
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# Executed automatically when 'Remove-Module VPDLX' is called.
# Removes the TypeAccelerators that were registered at load time so they
# do not persist after unload and cannot cause type conflicts on re-import.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    foreach ($Type in $script:ExportableTypes) {
        if ($script:TypeAcceleratorsClass::Get.ContainsKey($Type.Name)) {
            $script:TypeAcceleratorsClass::Remove($Type.Name) | Out-Null
            Write-Verbose "VPDLX: Removed TypeAccelerator: [$($Type.Name)]"
        }
    }
}.GetNewClosure()


Write-Verbose "VPDLX v$($script:appinfo.appvers) loaded. Classes available: [FileDetails], [FileStorage], [Logfile]."
