<#
.SYNOPSIS
    VPDLX - Virtual PowerShell Data-Logger eXtension
    Root module file: initialises the module, loads all class and function files,
    registers TypeAccelerators, and exposes the VPDLXcore accessor.

.DESCRIPTION
    VPDLX provides a fully class-based virtual logging system that allows callers
    to create, manage, and query multiple in-memory log files simultaneously,
    and export them to disk in multiple formats when needed.

    Architecture overview (v1.02.05):

      Classes/
          VPDLXClasses.ps1  — consolidated class file containing all three classes:
                               FileDetails  (metadata companion)
                               FileStorage  (central registry with DestroyAll)
                               Logfile      (core user-facing class)

      Private/
          VPDLXreturn.ps1   — factory function for standardised { code, msg, data }
                               return objects used by all Public Wrapper functions

      Public/
          VPDLXnewlogfile.ps1      — create a new virtual log file
          VPDLXislogfile.ps1       — check whether a named log file exists
          VPDLXdroplogfile.ps1     — permanently delete a named log file
          VPDLXreadlogfile.ps1     — read a specific line from a log file
          VPDLXwritelogfile.ps1    — append a new entry to a log file
          VPDLXexportlogfile.ps1   — export a virtual log file to disk (txt/log/csv/json)
          VPDLXgetalllogfiles.ps1  — list all active log files with metadata (v1.02.05)
          VPDLXresetlogfile.ps1    — clear all entries from a log file (v1.02.05)
          VPDLXfilterlogfile.ps1   — filter log entries by level (v1.02.05)

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
        $script:export   — supported export file extension definitions

    VPDLXcore:
        A thin accessor function that returns module-scope variables in a
        controlled, read-only fashion. Required by Public Wrapper functions
        that are dot-sourced and therefore cannot directly access $script:*
        variables from the root module scope.

.NOTES
    Creation Date : 05.04.2026
    Last Update   : 11.04.2026
    Version       : 1.02.04
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Website       : https://github.com/praetoriani/PowerShell.Mods

    REQUIREMENTS:
    - PowerShell 5.1 or higher
    - No external dependencies

    CHANGELOG:
    v1.02.05 (11.04.2026):
      New Public Wrapper functions (Priorität 10 der Developer ToDo-Liste):
        - VPDLXgetalllogfiles  : lists all active log files with metadata summary
        - VPDLXresetlogfile    : clears all entries from a log file (keeps it alive)
        - VPDLXfilterlogfile   : filters log entries by level, returns structured result
      New VPDLXcore key:
        - VPDLXcore -KeyID 'stats' : returns module-wide statistics (active logfiles,
          total entries, max/min entry counts, module version)
      Updated: VPDLX.psd1 (FunctionsToExport, FileList, ReleaseNotes, Version)

    v1.02.04 (11.04.2026):
      Performance & Quality improvements (Priorität 9).
      - Added VPDLX.Precheck.ps1 — validates PS >= 5.1 before module load.
        Registered via ScriptsToProcess in the module manifest.
      - Added configurable maximum message length in ValidateMessage().
        Default: 8192 characters; configurable via [Logfile]::MaxMessageLength.
        Protects against memory flooding from extremely long strings.
      - Added -NoBOM switch to VPDLXexportlogfile for BOM-free UTF-8 export.
        Uses [System.Text.UTF8Encoding]::new($false) for PS 5.1 compatibility
        with Unix-based log aggregators and web services.

    v1.02.03 (11.04.2026):
      Bugfix release: Destroy() and ToString() hardened; FilterByLevel()
      call-order and label corrected; export configuration conflict
      resolved; VPDLXreturn status code range extended; class files
      consolidated; DestroyAll() added; Print() diagnostics improved.
      - Destroy() now calls GuardDestroyed() first (Issue #1).
      - Destroy() wraps storage.Remove() in try/catch/finally (Issue #6).
      - ToString() now calls GuardDestroyed() first (Issue #3).
      - RecordFilter() call moved after foreach loop in FilterByLevel() (Issue #2).
      - RecordFilter() renamed to RecordFilterByLevel(), label updated (Issue #4).
      - Export-ModuleMember removed from Section 7; manifest is SSOT (Issue #5).
      - Print() pre-validation now reports 0-based index + value preview (Issue #7).
      - [ValidateSet(0,-1)] replaced with [ValidateRange(-99,99)] (Issue #8).
      - Three class files consolidated into Classes/VPDLXClasses.ps1 (Issue #9).
        FileStorage now uses Dictionary[string, Logfile] and typed Get()/Add().
      - FileStorage.DestroyAll() added; OnRemove calls it before cleanup (Issue #10).
        VPDLXcore -KeyID 'destroyall' exposes batch cleanup to callers.
      Affected files: VPDLXClasses.ps1 (new), VPDLXreturn.ps1,
      VPDLX.psm1, VPDLX.psd1. Old class files removed.

    v1.01.02 (06.04.2026):
      Public Wrapper Layer added (6 functions in Public\).
      Export functionality implemented: VPDLXexportlogfile supports
      txt, log, csv, and json output with automatic directory creation
      and an -Override switch for overwrite control.

    v1.01.00 (06.04.2026):
      Full architectural rewrite to class-based OOP design.
      TypeAccelerators now registered using the short class Name
      (e.g. 'Logfile') instead of the FullName (e.g. 'VPDLX.Logfile').
      GetAllEntries() replaces SoakUp(); FilterByLevel() replaces Filter()
      ('filter' is a reserved PowerShell keyword causing a parser error).
#>

# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 1 — Module-scope metadata and configuration
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# Read-only module metadata. Accessible externally via: VPDLXcore -KeyID 'appinfo'
$script:appinfo = @{
    appname    = 'VPDLX'
    appvers    = '1.02.05'
    appdevname = 'Praetoriani'
    appdevmail = 'mr.praetoriani{at}gmail.com'
    appwebsite = 'https://github.com/praetoriani/PowerShell.Mods'
    datecreate = '05.04.2026'
    lastupdate = '11.04.2026'  # v1.02.05
}

# Supported file formats for VPDLXexportlogfile.
# The ExportAs parameter is validated against the keys of this hashtable.
# To add a new format, add a key here and extend the export logic in
# Public\VPDLXexportlogfile.ps1 accordingly.
$script:export = @{
    txt  = '.txt'
    csv  = '.csv'
    json = '.json'
    log  = '.log'
}


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 2 — Class loading (order is critical)
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# All three VPDLX classes (FileDetails, FileStorage, Logfile) are defined in a
# single consolidated file. This resolves the PowerShell 5.1 forward-reference
# limitation: when classes were in separate files, FileStorage could not reference
# [Logfile] in its type annotations because [Logfile] was loaded later. With all
# classes in one file, PowerShell parses them together and resolves all cross-class
# type references at parse time.
#
# FIX v1.02.03 (Issue #9):
#   Consolidated FileDetails.ps1, FileStorage.ps1, and Logfile.ps1 into a single
#   VPDLXClasses.ps1. FileStorage now uses Dictionary[string, Logfile] and returns
#   [Logfile] from Get(), providing full type safety and IntelliSense support.
$script:ClassFiles = @(
    "$PSScriptRoot\Classes\VPDLXClasses.ps1"
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


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 3 — Module-level FileStorage singleton
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# This singleton is the single source of truth for all active Logfile instances.
# It is initialised here (after the class files are loaded) so that the [Logfile]
# constructor can call $script:storage.Add() and .Contains() immediately.
$script:storage = [FileStorage]::new()


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 4 — Private and Public function loading
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# Private functions (helpers) are loaded first so they are available
# when the Public Wrapper functions are dot-sourced immediately after.
# Both sets are dot-sourced into the module scope, giving them full
# access to $script:* variables and registered classes.
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


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 5 — VPDLXcore accessor
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

<#
.SYNOPSIS
    VPDLXcore — Read-only accessor for module-scoped VPDLX variables.

.DESCRIPTION
    Dot-sourced scripts in the Public/ directory cannot directly access
    $script:* variables that live in the root module scope (VPDLX.psm1).
    VPDLXcore bridges that gap by acting as a controlled getter:

      VPDLXcore -KeyID 'appinfo'      ->  $script:appinfo  (module metadata hashtable)
      VPDLXcore -KeyID 'storage'      ->  $script:storage  ([FileStorage] singleton)
      VPDLXcore -KeyID 'export'       ->  $script:export   (export format definitions)
      VPDLXcore -KeyID 'destroyall'   ->  calls $script:storage.DestroyAll()
      VPDLXcore -KeyID 'stats'        ->  module-wide statistics (v1.02.05)

    Callers receive a reference, not a copy, so operations on the returned
    object reflect the current live state at all times.

    IMPORTANT: Callers must NOT mutate the returned objects directly.
    All mutations must go through the appropriate class methods or wrapper
    functions to preserve internal consistency.

.PARAMETER KeyID
    The variable to access. One of: 'appinfo', 'storage', 'export', 'destroyall', 'stats'
    (case-insensitive)

.OUTPUTS
    PSCustomObject  { code [int], msg [string], data [object] }
    On success: code = 0, data = the requested object.
    On failure: code = -1, msg = error description, data = $null.

.EXAMPLE
    $meta = (VPDLXcore -KeyID 'appinfo').data
    Write-Host "VPDLX version: $($meta.appvers)"

.EXAMPLE
    $store = (VPDLXcore -KeyID 'storage').data
    $store.GetNames()   # lists all registered logfile names

.EXAMPLE
    $formats = (VPDLXcore -KeyID 'export').data
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
            'appinfo' { return VPDLXreturn -Code 0 -Message 'OK' -Data $script:appinfo }
            'storage' { return VPDLXreturn -Code 0 -Message 'OK' -Data $script:storage }
            'export'  { return VPDLXreturn -Code 0 -Message 'OK' -Data $script:export  }

            # NEW v1.02.03 (Issue #10):
            # Destroys all active Logfile instances and clears the FileStorage
            # registry. Returns a VPDLXreturn object with the count of instances
            # that were registered before the cleanup.
            'destroyall' {
                [int] $count = $script:storage.Count()
                $script:storage.DestroyAll()
                return VPDLXreturn -Code 0 -Message (
                    "DestroyAll completed. $count logfile instance(s) destroyed."
                )
            }

            # NEW v1.02.05 (Priorität 10):
            # Returns module-wide statistics as a structured PSCustomObject.
            # Collects: total active log files, sum of all entries across all
            # log files, maximum and minimum entry counts, and the module version.
            # This is a read-only operation — no log file state is modified.
            'stats' {
                [int] $logfileCount   = $script:storage.Count()
                [int] $totalEntries   = 0
                [int] $maxEntries     = 0
                [int] $minEntries     = [int]::MaxValue
                [string] $largestLog  = ''
                [string] $smallestLog = ''

                if ($logfileCount -gt 0) {
                    foreach ($logName in $script:storage.GetNames()) {
                        $logInst = $script:storage.Get($logName)
                        if ($null -ne $logInst) {
                            [int] $ec = $logInst.EntryCount()
                            $totalEntries += $ec
                            if ($ec -gt $maxEntries) {
                                $maxEntries  = $ec
                                $largestLog  = $logInst.Name
                            }
                            if ($ec -lt $minEntries) {
                                $minEntries  = $ec
                                $smallestLog = $logInst.Name
                            }
                        }
                    }
                } else {
                    $minEntries = 0
                }

                $statsPayload = [PSCustomObject] [ordered] @{
                    ActiveLogfiles = $logfileCount
                    TotalEntries   = $totalEntries
                    MaxEntries     = $maxEntries
                    MaxEntriesLog  = $largestLog
                    MinEntries     = $minEntries
                    MinEntriesLog  = $smallestLog
                    ModuleVersion  = $script:appinfo.appvers
                }

                return VPDLXreturn -Code 0 `
                    -Message "Module stats: $logfileCount logfile(s), $totalEntries total entries." `
                    -Data $statsPayload
            }

            default {
                return VPDLXreturn -Code -1 -Message (
                    "Unknown KeyID '$KeyID'. " +
                    "Valid keys: 'appinfo', 'storage', 'export', 'destroyall', 'stats'."
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


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 6 — TypeAccelerator registration
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# PowerShell classes defined inside a module are NOT automatically available
# via [ClassName]::new() after a plain 'Import-Module' call.
# Registering the types as TypeAccelerators makes them globally accessible
# in the caller's session without requiring 'using module' syntax.
#
# CRITICAL: Register using the SHORT class name (e.g. 'Logfile'), NOT the
# fully-qualified name (e.g. 'VPDLX.Logfile'). Registering the FullName
# would require callers to write [VPDLX.Logfile]::new() instead of
# [Logfile]::new(), which differs from the documented public API.

$script:ExportableTypes = @(
    [FileDetails],
    [FileStorage],
    [Logfile]
)

$script:TypeAcceleratorsClass = [psobject].Assembly.GetType(
    'System.Management.Automation.TypeAccelerators'
)

foreach ($Type in $script:ExportableTypes) {
    # Guard against duplicate registration when the module is re-imported
    # in the same session without Remove-Module first.
    if (-not $script:TypeAcceleratorsClass::Get.ContainsKey($Type.Name)) {
        $script:TypeAcceleratorsClass::Add($Type.Name, $Type)
        Write-Verbose "VPDLX: Registered TypeAccelerator: [$($Type.Name)]"
    }
}


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 7 — Module export declarations
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# FIX v1.02.03 (Issue #5):
#   The Export-ModuleMember call that was previously here has been REMOVED.
#
#   REASON: When a module manifest (.psd1) is present and its FunctionsToExport
#   key is set to an explicit list, PowerShell uses the MANIFEST as the
#   authoritative filter and silently ignores Export-ModuleMember. The dynamic
#   discovery logic below was therefore entirely inert — any function not also
#   listed in VPDLX.psd1 was silently suppressed, with no error or warning.
#
#   SINGLE SOURCE OF TRUTH: VPDLX.psd1 → FunctionsToExport
#   When adding a new Public function, add its name to the FunctionsToExport
#   array in VPDLX.psd1. No changes are needed here.
#
#   The dynamic $PublicFunctions collection in Section 4 is retained because
#   it is still needed for DOT-SOURCING the function files into the module
#   scope. It just no longer feeds into an Export-ModuleMember call.


# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
# SECTION 8 — Module OnRemove handler (cleanup)
# ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

# Executed automatically when 'Remove-Module VPDLX' is called.
# Performs two cleanup steps:
#   1. Destroys all active Logfile instances (releases memory, clears registry).
#   2. Removes the TypeAccelerators that were registered at load time.
#
# FIX v1.02.03 (Issue #10):
#   Added Step 1 — DestroyAll(). Previously, module unload only removed
#   TypeAccelerators but left all Logfile instances orphaned in memory.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {

    # Step 1: Destroy all active Logfile instances before the module unloads.
    # This ensures _data and _details are cleared and no orphaned instances
    # remain in memory after Remove-Module.
    if ($null -ne $script:storage -and $script:storage.Count() -gt 0) {
        try {
            $script:storage.DestroyAll()
            Write-Verbose "VPDLX: DestroyAll() completed — all logfile instances destroyed."
        }
        catch {
            Write-Verbose "VPDLX OnRemove: DestroyAll() encountered an error: $($_.Exception.Message)"
        }
    }

    # Step 2: Remove TypeAccelerators (unchanged from original implementation).
    foreach ($Type in $script:ExportableTypes) {
        if ($script:TypeAcceleratorsClass::Get.ContainsKey($Type.Name)) {
            $script:TypeAcceleratorsClass::Remove($Type.Name) | Out-Null
            Write-Verbose "VPDLX: Removed TypeAccelerator: [$($Type.Name)]"
        }
    }
}.GetNewClosure()


Write-Verbose "VPDLX v$($script:appinfo.appvers) loaded. TypeAccelerators: [FileDetails], [FileStorage], [Logfile]."
