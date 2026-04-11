<#
.SYNOPSIS
    VPDLXClasses — All VPDLX class definitions in a single file.

.DESCRIPTION
    This file consolidates the three VPDLX classes (FileDetails, FileStorage,
    Logfile) into a single script that is dot-sourced by VPDLX.psm1 at module
    load time.

    Combining all classes into one file eliminates the PowerShell 5.1
    forward-reference limitation: when classes are split across multiple files
    and dot-sourced sequentially, a class loaded earlier cannot reference a
    class loaded later in its type annotations. This forced FileStorage to
    declare its dictionary and Get() return type as [object] instead of
    [Logfile], because [Logfile] was defined in a separate file loaded after
    FileStorage.

    With all three classes in a single file, PowerShell parses them together
    and resolves all cross-class type references at parse time. FileStorage
    can now use [Logfile] as the dictionary value type and as the Get()
    return type, providing full type safety and IntelliSense support.

    Class definition order (dependency chain):
      1. FileDetails  — no dependencies
      2. FileStorage  — references [Logfile] (now resolved within the same file)
      3. Logfile      — references [FileDetails] and [FileStorage]

    PREVIOUS STRUCTURE (v1.02.03 and earlier):
      Classes/FileDetails.ps1   — loaded 1st
      Classes/FileStorage.ps1   — loaded 2nd (could NOT reference [Logfile])
      Classes/Logfile.ps1       — loaded 3rd

    CURRENT STRUCTURE (this file):
      Classes/VPDLXClasses.ps1  — single file, all three classes

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.04
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 05.04.2026
    Updated : 11.04.2026

    QUALITY (11.04.2026, v1.02.04 — Priorität 9):
      Added configurable maximum message length to ValidateMessage().
      Default limit is 8192 characters, configurable via the static
      property [Logfile]::MaxMessageLength. Messages exceeding the limit
      are rejected with a descriptive ArgumentException that includes
      the actual length and the configured maximum. This protects against
      accidental memory flooding from extremely long strings.

    CONSOLIDATION (11.04.2026, Issue #9):
      Merged FileDetails.ps1, FileStorage.ps1, and Logfile.ps1 into this
      single file to resolve the forward-reference problem. FileStorage now
      uses Dictionary[string, Logfile] and returns [Logfile] from Get().
      Add() accepts [Logfile] instead of [object], providing compile-time
      type safety.

    FEATURE (11.04.2026, Issue #10):
      Added DestroyAll() method to FileStorage. Iterates over all registered
      Logfile instances, calls Destroy() on each, and clears the registry.

    IMPROVEMENT (11.04.2026, Issue #7):
      Print() pre-validation loop now tracks the element index and enriches
      ArgumentException messages with the 0-based index and a safe preview
      of the offending value.

    DEPENDENCIES:
      - $script:storage must be initialised after this file is dot-sourced
        (done in VPDLX.psm1 Section 3)
#>


# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  CLASS 1 — FileDetails                                                    ║
# ║  Metadata container for a single Logfile instance.                         ║
# ╚════════════════════════════════════════════════════════════════════════════╝

class FileDetails {

    # ── Hidden (internal) fields ──────────────────────────────────────────────
    # All fields are marked hidden so they do not surface in IntelliSense or
    # Get-Member output for the caller. VPDLX class methods write these fields
    # via the internal helper methods defined below.

    # Timestamp when the Logfile instance was first created.
    hidden [string] $_created

    # Timestamp of the most recent Write, Print, or Reset call.
    hidden [string] $_updated

    # Timestamp of the most recent Read, SoakUp, or Filter call.
    hidden [string] $_lastAccessed

    # Human-readable label describing the type of the most recent interaction.
    # Possible values: 'Write', 'Print', 'Read', 'SoakUp', 'FilterByLevel', 'Reset'
    hidden [string] $_lastAccessType

    # Current number of log lines stored in the Logfile's data list.
    # This is set explicitly (not incremented) so that Print(array) always
    # produces an accurate count regardless of batch size.
    hidden [int]    $_entries

    # Running counter of ALL interactions since the Logfile instance was created.
    # This counter is NEVER reset during the lifetime of the instance — it is
    # only zeroed when the Logfile is destroyed via Destroy().
    hidden [int]    $_axcount


    # ── Constructor ───────────────────────────────────────────────────────────
    # Called by [Logfile]::new() during instance creation.
    # Captures the creation timestamp and zeros all counters.
    FileDetails() {
        [string] $ts          = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._created        = $ts
        $this._updated        = $ts
        $this._lastAccessed   = $ts
        $this._lastAccessType = 'Created'
        $this._entries        = 0
        $this._axcount        = 0
    }


    # ── Internal update methods (called by Logfile methods only) ──────────────

    # Records a Write interaction.
    # Updates _updated, sets _lastAccessType to 'Write', increments _axcount.
    hidden [void] RecordWrite() {
        $this._updated        = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._lastAccessType = 'Write'
        $this._axcount++
    }

    # Records a Print interaction.
    # Updates _updated, sets _lastAccessType to 'Print', increments _axcount.
    hidden [void] RecordPrint() {
        $this._updated        = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._lastAccessType = 'Print'
        $this._axcount++
    }

    # Records a Read interaction.
    # Updates _lastAccessed, sets _lastAccessType to 'Read', increments _axcount.
    hidden [void] RecordRead() {
        $this._lastAccessed   = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._lastAccessType = 'Read'
        $this._axcount++
    }

    # Records a SoakUp interaction.
    # Updates _lastAccessed, sets _lastAccessType to 'SoakUp', increments _axcount.
    hidden [void] RecordSoakUp() {
        $this._lastAccessed   = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._lastAccessType = 'SoakUp'
        $this._axcount++
    }

    # Records a FilterByLevel interaction.
    # Updates _lastAccessed, sets _lastAccessType to 'FilterByLevel', increments _axcount.
    #
    # BUGFIX v1.02.03 (Issue #4):
    #   Renamed from RecordFilter() to RecordFilterByLevel() and updated the
    #   _lastAccessType label from 'Filter' to 'FilterByLevel'. The old label
    #   was a stale leftover from the v1.01.00 rename of Filter() to
    #   FilterByLevel(). The single call site in Logfile.FilterByLevel() has
    #   been updated accordingly.
    hidden [void] RecordFilterByLevel() {
        $this._lastAccessed   = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._lastAccessType = 'FilterByLevel'
        $this._axcount++
    }

    # Sets the absolute entry count after any write or reset operation.
    # An absolute set is used (not an increment) so that Print(array) can
    # reflect the exact final count in a single call.
    hidden [void] SetEntryCount([int] $count) {
        $this._entries = $count
    }

    # Resets mutable metadata fields to their post-reset state.
    # _created and _axcount are intentionally preserved:
    #   _created  — reflects the original instantiation time and must survive Reset()
    #   _axcount  — must never be reset during the Logfile lifetime
    hidden [void] ApplyReset() {
        [string] $ts          = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._updated        = $ts
        $this._lastAccessed   = $ts
        $this._lastAccessType = 'Reset'
        $this._axcount++    # Reset itself counts as one interaction
        $this._entries      = 0
    }


    # ── Public getter methods ─────────────────────────────────────────────────
    # These are the only methods the caller should use. They return copies of
    # the internal field values, preventing accidental mutation via reference.

    # Returns the creation timestamp string.
    [string] GetCreated()       { return $this._created }

    # Returns the last-write (Write/Print/Reset) timestamp string.
    [string] GetUpdated()       { return $this._updated }

    # Returns the last-read (Read/SoakUp/Filter) timestamp string.
    [string] GetLastAccessed()  { return $this._lastAccessed }

    # Returns the type of the most recent interaction (e.g. 'Write', 'Read').
    [string] GetLastAccessType() { return $this._lastAccessType }

    # Returns the current number of entries in the associated Logfile.
    [int]    GetEntries()       { return $this._entries }

    # Returns the total interaction count since instance creation.
    # This value is never reset during the lifetime of the Logfile.
    [int]    GetAxcount()       { return $this._axcount }

    # Returns a formatted one-line summary — useful for quick console inspection.
    [string] ToString() {
        return (
            "FileDetails | Created: $($this._created) | " +
            "Updated: $($this._updated) | " +
            "LastAccessed: $($this._lastAccessed) | " +
            "LastAccessType: $($this._lastAccessType) | " +
            "Entries: $($this._entries) | " +
            "Axcount: $($this._axcount)"
        )
    }

    # Returns all metadata as an ordered dictionary — useful for export or JSON.
    [System.Collections.Specialized.OrderedDictionary] ToHashtable() {
        $ht = [ordered] @{
            created        = $this._created
            updated        = $this._updated
            lastacc        = $this._lastAccessed
            acctype        = $this._lastAccessType
            entries        = $this._entries
            axcount        = $this._axcount
        }
        return $ht
    }
}


# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  CLASS 2 — FileStorage                                                    ║
# ║  Central registry for all active Logfile instances.                        ║
# ╚════════════════════════════════════════════════════════════════════════════╝

class FileStorage {

    # ── Hidden (internal) fields ──────────────────────────────────────────────

    # Maps name (case-insensitive) -> [Logfile] instance.
    # OrdinalIgnoreCase comparer means 'MyLog' and 'mylog' refer to the same slot.
    #
    # FIX v1.02.03 (Issue #9):
    #   Changed value type from [object] to [Logfile]. This is now possible
    #   because all three classes are defined in the same file, so the forward-
    #   reference to [Logfile] is resolved at parse time. This provides full
    #   type safety: inserting a non-Logfile object into the registry now causes
    #   a type error at the insertion point instead of silently succeeding.
    hidden [System.Collections.Generic.Dictionary[string, Logfile]] $_registry

    # Preserves original (case-as-provided) filenames in insertion order.
    # Used by GetNames() so the caller sees the names they chose, not normalised.
    hidden [System.Collections.Generic.List[string]] $_names


    # ── Constructor ───────────────────────────────────────────────────────────
    FileStorage() {
        $this._registry = [System.Collections.Generic.Dictionary[string, Logfile]]::new(
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
    #
    # FIX v1.02.03 (Issue #9):
    #   Parameter type changed from [object] to [Logfile]. Combined with the
    #   typed Dictionary, this guarantees compile-time type safety — passing a
    #   non-Logfile object to Add() is now a type error instead of silently
    #   inserting the wrong type into the registry.
    [void] Add([string] $name, [Logfile] $instance) {
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


    # ── DestroyAll ────────────────────────────────────────────────────────────

    # Destroys all registered [Logfile] instances and clears the registry.
    #
    # Equivalent to calling Destroy() on every instance individually, but in a
    # single, safe operation. After this call, Count() returns 0 and GetNames()
    # returns an empty array. Any caller-held variable references to destroyed
    # instances will correctly throw ObjectDisposedException on subsequent
    # method calls (via GuardDestroyed).
    #
    # Implementation details:
    #   - A snapshot of the registry keys is taken BEFORE iteration to avoid
    #     modifying the dictionary while enumerating it (Destroy() calls
    #     Remove() internally, which would invalidate the enumerator).
    #   - Each Destroy() call is wrapped in try/catch so that a failure on one
    #     instance does not prevent cleanup of the remaining instances.
    #   - A final Clear() on both _registry and _names is performed as a safety
    #     measure — individual Destroy() calls already remove entries via
    #     Remove(), but Clear() ensures no orphaned references remain if an
    #     exception occurred during iteration.
    #
    # NEW v1.02.03 (Issue #10):
    #   This method was added to support batch cleanup of all active Logfile
    #   instances. It is called by the OnRemove handler in VPDLX.psm1 during
    #   module unload, and is also accessible via VPDLXcore -KeyID 'destroyall'.
    [void] DestroyAll() {
        if ($this._registry.Count -eq 0) {
            return   # nothing to do
        }

        # Take a snapshot of the keys to avoid modifying the dictionary
        # while iterating over it (Destroy() -> Remove() would invalidate
        # the enumerator).
        [string[]] $names = @($this._registry.Keys)

        foreach ($name in $names) {
            $instance = $this._registry[$name]
            if ($null -ne $instance) {
                try {
                    # Call Destroy() on the [Logfile] instance.
                    # Destroy() internally calls storage.Remove() which deregisters
                    # the instance. It also nulls _data and _details on the instance.
                    $instance.Destroy()
                }
                catch {
                    # If Destroy() fails for any reason (e.g. already destroyed,
                    # or an unexpected runtime error), log a verbose warning but
                    # continue to the next instance — one failure must not prevent
                    # cleanup of the remaining instances.
                    Write-Verbose (
                        "VPDLX: DestroyAll() could not destroy logfile '$name': " +
                        $_.Exception.Message
                    )
                }
            }
        }

        # Final safety clear: individual Destroy() calls already removed entries
        # via Remove(), but a final Clear() ensures no orphaned references remain
        # if any Destroy() call threw an exception before completing.
        $this._registry.Clear()
        $this._names.Clear()
    }


    # ── Public query methods ──────────────────────────────────────────────────

    # Returns $true if a logfile with the given name is registered.
    [bool] Contains([string] $name) {
        return $this._registry.ContainsKey($name)
    }

    # Returns the [Logfile] instance for the given name, or $null if not found.
    #
    # FIX v1.02.03 (Issue #9):
    #   Return type changed from [object] to [Logfile]. Callers no longer need
    #   to cast the result — IntelliSense and static type checking work
    #   correctly on the returned reference. The previous [object] return type
    #   was a workaround for the PowerShell 5.1 forward-reference limitation
    #   (FileStorage was loaded before Logfile). With all classes in a single
    #   file, the forward reference is resolved at parse time.
    [Logfile] Get([string] $name) {
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


# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  CLASS 3 — Logfile                                                         ║
# ║  Core user-facing class of the VPDLX module.                              ║
# ╚════════════════════════════════════════════════════════════════════════════╝

class Logfile {

    # ── Public (read) properties ────────────────────────────────────────────

    # The original name as provided by the caller (case-preserved).
    [string] $Name


    # ── Hidden (internal) fields ────────────────────────────────────────────

    # In-memory log line storage. List<string> is used instead of a plain
    # PowerShell array because List.Add() is O(1) amortised, whereas
    # array += creates a full copy on every append (O(n) total cost).
    hidden [System.Collections.Generic.List[string]] $_data

    # Companion object that tracks all metadata for this logfile.
    hidden [FileDetails] $_details


    # ── Static definitions ───────────────────────────────────────────────────

    # Configurable upper bound for message length in ValidateMessage().
    # Default: 8192 characters. Any message exceeding this limit is rejected
    # with a descriptive ArgumentException before it reaches the data list.
    # Callers can adjust this value at any time:
    #   [Logfile]::MaxMessageLength = 16384   # double the default
    #   [Logfile]::MaxMessageLength = 1024    # stricter limit
    # The minimum accepted value is 10 — setting it lower than 10 would
    # conflict with the existing "at least 3 non-whitespace characters" rule
    # and make the validator confusing.
    #
    # NEW v1.02.04 (Priorität 9):
    #   Introduced to protect against memory flooding from extremely long
    #   strings being passed to Write() or Print(). Without a limit, a caller
    #   could accidentally pass a multi-megabyte string (e.g. the contents of
    #   an entire file) as a single log message.
    static [int] $MaxMessageLength = 8192


    # All supported log levels and their formatted output prefixes.
    # Keys are lowercase identifiers; values are fixed-width prefix strings
    # that appear in each log line after the timestamp.
    # Column alignment is intentional — all prefixes share the same total width.
    static [hashtable] $LogLevels = @{
        info     = '  [INFO]      ->  '
        debug    = '  [DEBUG]     ->  '
        verbose  = '  [VERBOSE]   ->  '
        trace    = '  [TRACE]     ->  '
        warning  = '  [WARNING]   ->  '
        error    = '  [ERROR]     ->  '
        critical = '  [CRITICAL]  ->  '
        fatal    = '  [FATAL]     ->  '
    }


    # ── Constructor ───────────────────────────────────────────────────────────

    Logfile([string] $name) {

        # ── Validate: not null / empty / whitespace ──────────────────────────
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [System.ArgumentException]::new(
                "Parameter 'name' must not be null, empty, or whitespace-only.",
                'name'
            )
        }

        # BUGFIX: PowerShell 5.1 does not allow direct reassignment of a
        # constructor parameter variable ($name = $name.Trim()) — the parser
        # misinterprets this as a property-set attempt and raises:
        #   'The property cannot be set. Use "$this.Name"'
        # Solution: assign the trimmed value to a new local variable.
        [string] $trimmedName = $name.Trim()

        # ── Validate: length 3–64 characters ────────────────────────────────
        if ($trimmedName.Length -lt 3 -or $trimmedName.Length -gt 64) {
            throw [System.ArgumentException]::new(
                "Parameter 'name' must be between 3 and 64 characters. " +
                "Provided length: $($trimmedName.Length).",
                'name'
            )
        }

        # ── Validate: allowed characters only ────────────────────────────────
        # Only alphanumeric characters plus underscore, hyphen, and dot are allowed.
        if ($trimmedName -notmatch '^[a-zA-Z0-9_\-\.]+$') {
            throw [System.ArgumentException]::new(
                "Parameter 'name' contains invalid characters. " +
                'Only alphanumeric characters and the symbols _ - . are allowed.',
                'name'
            )
        }

        # ── Duplicate check via FileStorage ──────────────────────────────────
        # $script:storage is the module-level [FileStorage] singleton.
        # It is accessible here because this file is dot-sourced into the
        # VPDLX.psm1 module scope.
        if ($script:storage.Contains($trimmedName)) {
            throw [System.InvalidOperationException]::new(
                "A Logfile named '$trimmedName' already exists. " +
                "Call .Destroy() on the existing instance before creating a new one."
            )
        }

        # ── Initialise internal fields ────────────────────────────────────────
        $this.Name     = $trimmedName
        $this._data    = [System.Collections.Generic.List[string]]::new()
        $this._details = [FileDetails]::new()

        # ── Register in the module-level FileStorage ──────────────────────────
        $script:storage.Add($trimmedName, $this)
    }


    # ── Private helpers ──────────────────────────────────────────────────────

    # Builds a single formatted log line from a level + message pair.
    # Called by both Write() and Print() to guarantee a consistent line format.
    #
    # Format: [dd.MM.yyyy | HH:mm:ss]  [LEVEL]  ->  MESSAGE
    #
    # Each call captures a fresh timestamp so individual entries reflect the
    # exact moment they were written, even inside a Print() batch.
    hidden [string] BuildEntry([string] $level, [string] $message) {
        [string] $ts     = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        [string] $prefix = [Logfile]::LogLevels[$level]
        return "$ts$prefix$message"
    }

    # Validates a log level string and returns the normalised (lowercase) key.
    # Throws [System.ArgumentException] if the level is not supported.
    hidden [string] ValidateLevel([string] $level) {
        if ([string]::IsNullOrWhiteSpace($level)) {
            throw [System.ArgumentException]::new(
                "Parameter 'level' must not be null, empty, or whitespace-only.",
                'level'
            )
        }
        [string] $normalized = $level.Trim().ToLower()
        if (-not [Logfile]::LogLevels.ContainsKey($normalized)) {
            # Build a sorted, comma-separated list of valid levels for the error message.
            [string] $valid = ([Logfile]::LogLevels.Keys | Sort-Object) -join ', '
            throw [System.ArgumentException]::new(
                "Unknown log level '$level'. Valid levels are: $valid.",
                'level'
            )
        }
        return $normalized
    }

    # Validates a message string.
    # Rules:
    #   1. Must not be null, empty, or whitespace-only.
    #   2. Must contain at least 3 non-whitespace characters (no trivial entries).
    #   3. Must not contain newline characters (prevents log-injection attacks).
    #   4. Must not exceed [Logfile]::MaxMessageLength characters (memory protection).
    #
    # IMPROVEMENT v1.02.04 (Priorität 9):
    #   Added rule 4 — configurable maximum message length. The default limit
    #   is 8192 characters (see [Logfile]::MaxMessageLength). Messages that
    #   exceed the limit are rejected with a descriptive ArgumentException
    #   that includes the actual length and the configured maximum, so the
    #   caller knows both what happened and what the boundary is.
    hidden [void] ValidateMessage([string] $message) {
        if ([string]::IsNullOrWhiteSpace($message)) {
            throw [System.ArgumentException]::new(
                "Parameter 'message' must not be null, empty, or whitespace-only.",
                'message'
            )
        }
        if (($message -replace '\s', '').Length -lt 3) {
            throw [System.ArgumentException]::new(
                "Parameter 'message' must contain at least 3 non-whitespace characters.",
                'message'
            )
        }
        # Newline characters would break the single-line log format and could
        # be used to inject fake log entries into exported files.
        if ($message -match '[\r\n]') {
            throw [System.ArgumentException]::new(
                "Parameter 'message' must not contain newline characters (CR or LF).",
                'message'
            )
        }
        # Maximum length check — protects against accidental memory flooding.
        # The limit is configurable via [Logfile]::MaxMessageLength (default: 8192).
        # NEW v1.02.04 (Priorität 9).
        [int] $maxLen = [Logfile]::MaxMessageLength
        if ($message.Length -gt $maxLen) {
            throw [System.ArgumentException]::new(
                ("Parameter 'message' exceeds the maximum allowed length. " +
                 "Length: $($message.Length) characters; limit: $maxLen characters. " +
                 "Adjust [Logfile]::MaxMessageLength to increase the limit."),
                'message'
            )
        }
    }

    # Guard that throws a descriptive ObjectDisposedException if this instance
    # has already been destroyed via Destroy(). Call at the top of every
    # method that accesses _data or _details.
    hidden [void] GuardDestroyed() {
        if ($null -eq $this._data) {
            throw [System.ObjectDisposedException]::new(
                $this.Name,
                "Logfile '$($this.Name)' has been destroyed. " +
                'Set the variable holding this reference to $null.'
            )
        }
    }


    # ── Write ────────────────────────────────────────────────────────────────

    # Appends a single formatted log entry to the internal data list.
    #
    # Parameters:
    #   level   — One of the supported log levels (case-insensitive)
    #   message — The human-readable log message (min 3 non-whitespace chars,
    #             no newline characters)
    #
    # Side-effects:
    #   - _data list grows by one entry
    #   - _details.RecordWrite() is called  -> updates 'updated', 'acctype', 'axcount'
    #   - _details.SetEntryCount() is called -> updates 'entries'
    [void] Write([string] $level, [string] $message) {
        $this.GuardDestroyed()
        [string] $normalizedLevel = $this.ValidateLevel($level)
        $this.ValidateMessage($message)

        $this._data.Add($this.BuildEntry($normalizedLevel, $message))
        $this._details.RecordWrite()
        $this._details.SetEntryCount($this._data.Count)
    }


    # ── Print ────────────────────────────────────────────────────────────────

    # Appends multiple log entries sharing the same log level in a single call.
    #
    # All messages are validated individually BEFORE any are written, so a
    # validation failure on any message leaves the log in its prior consistent
    # state (transactional semantics).
    #
    # Parameters:
    #   level    — One of the supported log levels (case-insensitive)
    #   messages — Non-empty array of message strings; each must pass
    #              ValidateMessage()
    #
    # Side-effects (only after ALL messages pass validation):
    #   - _data list grows by messages.Count entries
    #   - _details.RecordPrint() is called ONCE  -> one interaction for the batch
    #   - _details.SetEntryCount() is called ONCE -> accurate final entry count
    #
    # IMPROVEMENT v1.02.03 (Issue #7):
    #   The pre-validation loop now tracks the 0-based element index. When
    #   ValidateMessage() throws ArgumentException, the exception is caught,
    #   enriched with the index and a safe preview of the offending value,
    #   and re-thrown as a new ArgumentException. This allows callers to
    #   identify exactly which element in a large batch caused the failure
    #   without manual bisection or debug output.
    [void] Print([string] $level, [string[]] $messages) {
        $this.GuardDestroyed()
        [string] $normalizedLevel = $this.ValidateLevel($level)

        if ($null -eq $messages -or $messages.Count -eq 0) {
            throw [System.ArgumentException]::new(
                "Parameter 'messages' must not be null or empty.",
                'messages'
            )
        }

        # Pre-validate every message before writing any entry.
        # Track the index so that validation failures identify the exact
        # offending element in the batch.
        [int] $idx = 0
        foreach ($msg in $messages) {
            try {
                $this.ValidateMessage($msg)
            }
            catch [System.ArgumentException] {
                # Build a safe preview of the offending value for the error message.
                # Truncate to 40 characters to avoid overwhelming the output;
                # escape control characters so newlines / CRs are visible as literals.
                [string] $preview = if ($null -eq $msg) {
                    '(null)'
                } elseif ($msg.Length -eq 0) {
                    '(empty string)'
                } else {
                    $escaped = $msg -replace "`r", '\r' -replace "`n", '\n'
                    if ($escaped.Length -gt 40) { $escaped = $escaped.Substring(0, 40) + '...' }
                    "'$escaped'"
                }

                throw [System.ArgumentException]::new(
                    "messages[$idx]: $($_.Exception.Message) Offending value: $preview",
                    'messages'
                )
            }
            $idx++
        }

        # All validation passed — append all entries.
        foreach ($msg in $messages) {
            $this._data.Add($this.BuildEntry($normalizedLevel, $msg))
        }

        # Record as a single batch interaction and set the accurate entry count.
        $this._details.RecordPrint()
        $this._details.SetEntryCount($this._data.Count)
    }


    # ── Read ─────────────────────────────────────────────────────────────────

    # Returns the formatted log line at the specified 1-based line number.
    #
    # Line-number clamping:
    #   - Values below 1 are treated as 1 (first entry)
    #   - Values above the entry count are treated as the last entry
    # The internal List is 0-based; the method converts automatically.
    #
    # Throws [System.InvalidOperationException] if the log is empty.
    #
    # Side-effects:
    #   - _details.RecordRead() is called  -> updates 'lastacc', 'acctype', 'axcount'
    [string] Read([int] $line) {
        $this.GuardDestroyed()

        if ($this._data.Count -eq 0) {
            throw [System.InvalidOperationException]::new(
                "Logfile '$($this.Name)' contains no entries."
            )
        }

        # Clamp to valid 1-based range.
        [int] $clampedLine = $line
        if ($clampedLine -lt 1)                  { $clampedLine = 1 }
        if ($clampedLine -gt $this._data.Count)  { $clampedLine = $this._data.Count }

        # Convert to 0-based index and retrieve the entry.
        [string] $entry = $this._data[$clampedLine - 1]
        $this._details.RecordRead()
        return $entry
    }


    # ── SoakUp ───────────────────────────────────────────────────────────────

    # Returns the complete log content as a string array.
    # An empty log returns an empty array (never $null).
    # Intended as the primary data source for export operations.
    #
    # Side-effects:
    #   - _details.RecordSoakUp() is called  -> updates 'lastacc', 'acctype', 'axcount'
    [string[]] SoakUp() {
        $this.GuardDestroyed()
        $this._details.RecordSoakUp()
        if ($this._data.Count -eq 0) {
            return @()
        }
        return $this._data.ToArray()
    }


    # ── FilterByLevel ────────────────────────────────────────────────────────

    # Returns only the log lines whose level marker matches the given level.
    #
    # IMPORTANT NAMING NOTE:
    #   This method is intentionally named FilterByLevel() and NOT Filter().
    #   'filter' is a reserved keyword in PowerShell (it defines a special
    #   pipeline filter function, similar to 'function'). Using 'filter' as a
    #   class method name causes a parser error that prevents the entire class
    #   file from loading. FilterByLevel() is the safe, unambiguous name.
    #
    # Matching strategy:
    #   - The normalised level is converted to its uppercase bracket notation
    #     (e.g. 'warning' -> '[WARNING]').
    #   - Each line is checked with String.Contains() — faster than a regex
    #     pipeline for simple fixed-string searches and avoids PowerShell
    #     pipeline overhead on large logs.
    #
    # Returns an empty array (never $null) if no matching lines are found.
    #
    # Parameters:
    #   level — One of the supported log levels (case-insensitive)
    #
    # Side-effects:
    #   - _details.RecordFilterByLevel() is called  -> updates 'lastacc', 'acctype', 'axcount'
    #
    # BUGFIX v1.02.03 (Issue #2 + Issue #4):
    #   - RecordFilter() call moved from BEFORE the filter loop to AFTER it,
    #     consistent with all other methods (Write, Print, Read, Reset) that
    #     record metadata only after the core operation has completed.
    #   - Call site updated from RecordFilter() to RecordFilterByLevel() to
    #     match the renamed method in FileDetails (Issue #4).
    [string[]] FilterByLevel([string] $level) {
        $this.GuardDestroyed()
        [string] $normalizedLevel = $this.ValidateLevel($level)
        [string] $marker          = "[$($normalizedLevel.ToUpper())]"

        # Use a typed List and a direct foreach loop with .Contains() instead
        # of Where-Object pipeline — avoids regex overhead and pipeline cost.
        $results = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $this._data) {
            if ($line.Contains($marker)) {
                $results.Add($line)
            }
        }

        # Record the interaction AFTER the filter operation completes successfully,
        # consistent with Write(), Print(), Read(), and all other methods.
        $this._details.RecordFilterByLevel()
        return $results.ToArray()
    }


    # ── Reset ────────────────────────────────────────────────────────────────

    # Clears all log data and resets the entry-count metadata.
    # The creation timestamp, filename, and axcount are preserved.
    # The Reset call itself increments axcount (it is an interaction).
    #
    # WARNING: This operation is destructive and cannot be undone.
    #
    # Side-effects:
    #   - _data is cleared to an empty list
    #   - _details.ApplyReset() is called  -> updates 'updated', 'lastacc',
    #     'acctype', 'axcount', zeroes 'entries'
    [void] Reset() {
        $this.GuardDestroyed()
        $this._data.Clear()
        $this._details.ApplyReset()
    }


    # ── Destroy ──────────────────────────────────────────────────────────────

    # Permanently removes this logfile from the [FileStorage] registry and
    # releases its internal data. After calling this method, the variable
    # holding the reference should be explicitly set to $null by the caller.
    #
    # WARNING: All log data is lost. This operation cannot be undone.
    # Subsequent method calls on the same reference will throw
    # [System.ObjectDisposedException] (via GuardDestroyed).
    #
    # Side-effects:
    #   - This instance is removed from $script:storage
    #   - _data list is cleared and set to $null
    #   - _details is set to $null
    #
    # BUGFIX v1.02.03 (Issue #1 + Issue #6):
    #   - GuardDestroyed() is now called first, preventing silent double-
    #     destroy. The previous 'if ($null -ne $this._data)' guard has been
    #     removed — GuardDestroyed() makes it redundant.
    #   - storage.Remove() is wrapped in try/catch/finally. The finally block
    #     unconditionally clears _data and sets both _data and _details to
    #     $null, guaranteeing consistent cleanup even if Remove() throws
    #     (e.g. due to state desynchronisation via VPDLXcore).
    [void] Destroy() {
        # Guard against double-destroy, consistent with all other public methods.
        # Throws ObjectDisposedException if this instance was already destroyed.
        $this.GuardDestroyed()

        try {
            # Attempt to deregister from FileStorage.
            # Remove() throws InvalidOperationException if the name is not found
            # (e.g. due to state desynchronisation via VPDLXcore or a prior error).
            $script:storage.Remove($this.Name)
        }
        catch [System.InvalidOperationException] {
            # The instance was not (or no longer) registered in FileStorage.
            # Log a verbose diagnostic but do not re-throw: the caller invoked
            # Destroy() with the intent to release this instance, and we honour
            # that intent regardless of the registry state.
            Write-Verbose (
                "VPDLX: Destroy() could not remove '$($this.Name)' from FileStorage " +
                "(already removed or registry inconsistency): $($_.Exception.Message)"
            )
        }
        finally {
            # Unconditional cleanup: always runs, even if Remove() threw.
            # Sets _data and _details to $null so that GuardDestroyed() works
            # correctly on any subsequent method call (including a second Destroy()).
            $this._data.Clear()
            $this._data    = $null
            $this._details = $null
        }
    }


    # ── Convenience: IsEmpty / HasEntries / EntryCount ───────────────────────

    # Returns $true if the logfile currently contains no entries.
    # Use this to guard calls to Read() without needing try/catch.
    [bool] IsEmpty() {
        $this.GuardDestroyed()
        return ($this._data.Count -eq 0)
    }

    # Returns $true if the logfile contains at least one entry.
    [bool] HasEntries() {
        $this.GuardDestroyed()
        return ($this._data.Count -gt 0)
    }

    # Returns the current number of log entries.
    # Equivalent to GetDetails().GetEntries() but without the accessor chain.
    [int] EntryCount() {
        $this.GuardDestroyed()
        return $this._data.Count
    }


    # ── Shortcut write methods ───────────────────────────────────────────────
    # Convenience wrappers that call Write() with the appropriate fixed level.
    # They eliminate boilerplate when logging at a known, constant level:
    #   $log.Info('Application started.')   is equivalent to
    #   $log.Write('info', 'Application started.')

    [void] Info([string] $message)     { $this.Write('info',     $message) }
    [void] Debug([string] $message)    { $this.Write('debug',    $message) }
    [void] Verbose([string] $message)  { $this.Write('verbose',  $message) }
    [void] Trace([string] $message)    { $this.Write('trace',    $message) }
    [void] Warning([string] $message)  { $this.Write('warning',  $message) }
    [void] Error([string] $message)    { $this.Write('error',    $message) }
    [void] Critical([string] $message) { $this.Write('critical', $message) }
    [void] Fatal([string] $message)    { $this.Write('fatal',    $message) }


    # ── Inspection / utility ─────────────────────────────────────────────────

    # Returns the [FileDetails] companion object for this logfile.
    # Callers can inspect metadata via the public getter methods:
    #   GetCreated(), GetUpdated(), GetLastAccessed(), GetLastAccessType(),
    #   GetEntries(), GetAxcount()
    [FileDetails] GetDetails() {
        return $this._details
    }

    # Returns a one-line summary string — shown automatically when the object
    # is output to the console without a method call.
    #
    # BUGFIX v1.02.03 (Issue #3):
    #   GuardDestroyed() is now called at the top, consistent with all other
    #   public methods. The previous partial null-check for _data has been
    #   removed — with GuardDestroyed() in place, _data and _details are
    #   guaranteed non-null. Calling ToString() on a destroyed instance now
    #   throws ObjectDisposedException instead of a misleading
    #   NullReferenceException from the unguarded _details.GetCreated() call.
    [string] ToString() {
        # Guard against post-destroy access, consistent with all other public methods.
        # Throws ObjectDisposedException with a descriptive message if _data is $null.
        $this.GuardDestroyed()

        return "Logfile: '$($this.Name)' | Entries: $($this._data.Count) | Created: $($this._details.GetCreated())"
    }
}
