<#
.SYNOPSIS
    FileStorage — Central registry for all active Logfile instances.

.DESCRIPTION
    FileStorage acts as the single source of truth for all [Logfile] objects
    that have been created during the current PowerShell session. It maintains
    two internal data structures:

      _registry  — A Dictionary<string, object> that maps the name (case-
                   insensitive via OrdinalIgnoreCase comparer) to its [Logfile]
                   instance. This enables O(1) lookups by name.

      _names     — A List<string> that preserves the original (case-preserved)
                   filenames in creation order. Used for listing and iteration.

    Like [FileDetails], the fields are hidden from IntelliSense/Get-Member.
    However, the Add() and Remove() management methods are intentionally NOT
    marked hidden: [Logfile] calls them directly from its constructor and
    Destroy() method. In PowerShell 5.1, 'hidden' prevents cross-class method
    calls, so management methods must be public.

    A single instance of FileStorage is held in the module-scoped variable
    $script:storage inside VPDLX.psm1 and is never exposed directly to callers.
    External consumers interact with it only through [Logfile] class methods or
    the VPDLXcore accessor, never by touching $script:storage directly.

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.00
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 05.04.2026
    Updated : 06.04.2026

    BUGFIX (06.04.2026):
      Add() and Remove() were previously marked 'hidden'. In PowerShell 5.1,
      hidden members cannot be called from outside the declaring class — this
      includes calls from [Logfile]'s constructor and Destroy() method.
      Removing 'hidden' from these two methods fixes the cross-class
      accessibility issue while preserving all other design goals.
      The remove-by-name case-insensitive search in _names was also corrected
      to use a manual loop so the original (case-preserved) entry is found
      reliably regardless of how the caller spelled the name.
#>

class FileStorage {

    # ── Hidden (internal) fields ──────────────────────────────────────────────

    # Maps name (case-insensitive) -> [Logfile] instance.
    # OrdinalIgnoreCase comparer means 'MyLog' and 'mylog' refer to the same slot.
    hidden [System.Collections.Generic.Dictionary[string, object]] $_registry

    # Preserves original (case-as-provided) filenames in insertion order.
    # Used by GetNames() so the caller sees the names they chose, not normalised.
    hidden [System.Collections.Generic.List[string]] $_names


    # ── Constructor ───────────────────────────────────────────────────────────
    FileStorage() {
        $this._registry = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $this._names = [System.Collections.Generic.List[string]]::new()
    }


    # ── Management methods ────────────────────────────────────────────────────
    # NOTE: These methods are intentionally NOT marked 'hidden'.
    # [Logfile] calls Add() from its constructor and Remove() from Destroy().
    # In PowerShell 5.1, hidden methods are inaccessible from other classes,
    # which would cause a 'method not found' runtime error.

    # Registers a new [Logfile] instance in the storage.
    # Throws if a logfile with the same name already exists (case-insensitive).
    # Called by [Logfile]::new() as its final constructor step.
    [void] Add([string] $name, [object] $instance) {
        if ($this._registry.ContainsKey($name)) {
            throw [System.InvalidOperationException]::new(
                "FileStorage: A logfile named '$name' already exists. " +
                'Remove the existing instance before creating a new one.'
            )
        }
        $this._registry[$name] = $instance
        $this._names.Add($name)
    }

    # Removes a [Logfile] instance from the storage by name.
    # Throws if the specified name does not exist.
    # Called by the [Logfile] class's own Destroy() method.
    [void] Remove([string] $name) {
        if (-not $this._registry.ContainsKey($name)) {
            throw [System.InvalidOperationException]::new(
                "FileStorage: No logfile named '$name' found in storage."
            )
        }
        $this._registry.Remove($name) | Out-Null

        # Remove from the names list using a case-insensitive search.
        # List<T>.Remove() uses Equals() which is case-sensitive for strings,
        # so we locate the matching entry manually and remove by index.
        [int] $indexToRemove = -1
        for ([int] $i = 0; $i -lt $this._names.Count; $i++) {
            if ([string]::Equals($this._names[$i], $name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $indexToRemove = $i
                break
            }
        }
        if ($indexToRemove -ge 0) {
            $this._names.RemoveAt($indexToRemove)
        }
    }


    # ── Public query methods ──────────────────────────────────────────────────

    # Returns $true if a logfile with the given name is registered.
    [bool] Contains([string] $name) {
        return $this._registry.ContainsKey($name)
    }

    # Returns the [Logfile] instance for the given name, or $null if not found.
    # The return type is [object] because [Logfile] is defined in a later
    # dot-source step; using [object] avoids a forward-reference resolution
    # error in PowerShell 5.1.
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
