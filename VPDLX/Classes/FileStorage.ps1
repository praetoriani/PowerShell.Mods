<#
.SYNOPSIS
    FileStorage — Central registry for all active Logfile instances.

.DESCRIPTION
    FileStorage acts as the single source of truth for all [Logfile] objects
    that have been created during the current PowerShell session. It maintains
    two internal data structures:

      _registry  — A Dictionary<string, Logfile> that maps the normalized
                   (lowercase) filename key to its [Logfile] instance.
                   This enables O(1) lookups by name.

      _names     — A List<string> that preserves the original (case-preserved)
                   filenames in creation order. Used for listing and iteration.

    Like [FileDetails], all mutating members are marked 'hidden'. The public
    surface exposes only safe read operations and the controlled Add/Remove
    methods that enforce business rules (duplicate prevention, existence checks).

    A single instance of FileStorage is held in the module-scoped variable
    $script:storage inside VPDLX.psm1 and is never exposed directly to callers.
    External consumers interact with it only through [Logfile] class methods or
    future public functions, never by touching $script:storage directly.

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.00
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 05.04.2026
    Updated : 06.04.2026
#>

class FileStorage {

    # ── Hidden (internal) fields ──────────────────────────────────────────────

    # Maps normalized (lowercase) name → [Logfile] instance.
    # Hidden to prevent callers from bypassing the Add/Remove business rules.
    hidden [System.Collections.Generic.Dictionary[string, object]] $_registry

    # Preserves original (case-as-provided) filenames in insertion order.
    # Used by GetNames() so the caller sees the names they chose, not lowercase.
    hidden [System.Collections.Generic.List[string]] $_names


    # ── Constructor ───────────────────────────────────────────────────────────
    # Initializes both internal collections as empty.
    FileStorage() {
        $this._registry = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $this._names    = [System.Collections.Generic.List[string]]::new()
    }


    # ── Internal management methods (called by VPDLX internals only) ──────────

    # Registers a new [Logfile] instance in the storage.
    # Throws if a logfile with the same name already exists (case-insensitive).
    # Called by [Logfile]::new() as its final constructor step.
    hidden [void] Add([string] $name, [object] $instance) {
        if ($this._registry.ContainsKey($name)) {
            throw "FileStorage: A logfile named '$name' already exists. " +
                  "Remove the existing instance before creating a new one."
        }
        $this._registry[$name] = $instance
        $this._names.Add($name)
    }

    # Removes a [Logfile] instance from the storage by name.
    # Throws if the specified name does not exist.
    # Called by the [Logfile] class's own Destroy() method.
    hidden [void] Remove([string] $name) {
        if (-not $this._registry.ContainsKey($name)) {
            throw "FileStorage: No logfile named '$name' found in storage."
        }
        $this._registry.Remove($name)  | Out-Null
        $this._names.Remove($name)     | Out-Null
    }


    # ── Public query methods ──────────────────────────────────────────────────

    # Returns $true if a logfile with the given name is registered.
    [bool] Contains([string] $name) {
        return $this._registry.ContainsKey($name)
    }

    # Returns the [Logfile] instance for the given name, or $null if not found.
    # The return type is [object] because [Logfile] is defined in a later dot-source
    # step; using [object] avoids a forward-reference resolution error in PS 5.1.
    [object] Get([string] $name) {
        if (-not $this._registry.ContainsKey($name)) {
            return $null
        }
        return $this._registry[$name]
    }

    # Returns the number of currently registered logfile instances.
    [int] Count() {
        return $this._registry.Count
    }

    # Returns an array of all registered filenames in creation order.
    # Returns an empty array (not $null) when the storage is empty.
    [string[]] GetNames() {
        if ($this._names.Count -eq 0) {
            return @()
        }
        return $this._names.ToArray()
    }

    # Returns a human-readable summary of the current storage state.
    [string] ToString() {
        [int] $count = $this._registry.Count
        if ($count -eq 0) {
            return 'FileStorage | 0 registered logfiles'
        }
        [string] $list = $this._names -join ', '
        return "FileStorage | $count registered logfile(s): $list"
    }
}
