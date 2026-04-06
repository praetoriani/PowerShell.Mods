<#
.SYNOPSIS
    Logfile — Core class of the VPDLX module.

.DESCRIPTION
    [Logfile] is the central, user-facing class of VPDLX. Each instance
    represents one named virtual log file that lives entirely in memory
    for the duration of the current PowerShell session.

    An instance is created with:
        $log = [Logfile]::new('MyLogfile')

    The constructor validates the name, initialises the internal data list
    and a [FileDetails] companion object, then registers itself in the
    module-level [FileStorage] instance ($script:storage).

    --- Public methods ---

    Write(level, message)
        Appends a single formatted log line.

    Print(level, messages[])
        Appends an array of messages in one call, all sharing the same level.
        The [FileDetails] entry count is updated to the exact post-call total.

    Read(line)
        Returns the formatted log line at the given 1-based line number.
        Line numbers are clamped to the valid range automatically.

    SoakUp()
        Returns the complete log content as a string array.
        Primarily intended for export operations.

    Filter(level)
        Returns only the log lines that match the specified log level.

    Reset()
        Clears all log data and resets entry-count metadata.
        The creation timestamp and filename are preserved.
        This operation cannot be undone.

    Destroy()
        Removes this instance from [FileStorage] and nulls the internal data.
        After calling Destroy() the variable holding the reference should be
        set to $null by the caller.

    --- Shortcut write methods ---
    Info(msg)  /  Debug(msg)  /  Warning(msg)  /  Error(msg)  /  Critical(msg)

    --- Detail / inspection ---
    GetDetails()  — returns the [FileDetails] companion object
    ToString()    — returns a one-line summary string

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.00
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 05.04.2026
    Updated : 06.04.2026

    DEPENDENCIES (must be dot-sourced before this file):
      - Classes/FileDetails.ps1
      - Classes/FileStorage.ps1
      - Private/VPDLXreturn.ps1  (used only if wrapper functions call Write-* helpers)
    The module root (VPDLX.psm1) ensures correct load order.
#>

class Logfile {

    # ── Public (read) properties ────────────────────────────────────────────

    # The original name as provided by the caller (case-preserved).
    [string] $Name


    # ── Hidden (internal) fields ────────────────────────────────────────────

    # In-memory log line storage. List<string> is used instead of a plain
    # PowerShell array because List.Add() is an O(1) amortised operation,
    # while array += creates a full copy on every append.
    hidden [System.Collections.Generic.List[string]] $_data

    # Companion object that tracks all metadata for this logfile.
    hidden [FileDetails] $_details


    # ── Static definitions ─────────────────────────────────────────────────

    # All supported log levels and their formatted output prefixes.
    # Keys are lowercase identifiers; values are the fixed-width prefix strings
    # that appear in each log line after the timestamp.
    static [hashtable] $LogLevels = @{
        info     = '  [INFO]      ->  '
        debug    = '  [DEBUG]     ->  '
        warning  = '  [WARNING]   ->  '
        error    = '  [ERROR]     ->  '
        critical = '  [CRITICAL]  ->  '
    }


    # ── Constructor ───────────────────────────────────────────────────────────

    Logfile([string] $name) {

        # — Validate name ——————————————————————————————————————
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [System.ArgumentException]::new(
                "Parameter 'name' must not be null, empty, or whitespace-only.",
                'name'
            )
        }

        $name = $name.Trim()

        if ($name.Length -lt 3 -or $name.Length -gt 64) {
            throw [System.ArgumentException]::new(
                "Parameter 'name' must be between 3 and 64 characters. " +
                "Provided length: $($name.Length).",
                'name'
            )
        }

        if ($name -notmatch '^[a-zA-Z0-9_\-\.]+$') {
            throw [System.ArgumentException]::new(
                "Parameter 'name' contains invalid characters. " +
                'Only alphanumeric characters and _ - . are allowed.',
                'name'
            )
        }

        # — Duplicate check via FileStorage ————————————————————————
        # $script:storage is the module-level [FileStorage] singleton.
        # It is accessible here because this class file is dot-sourced into
        # the VPDLX.psm1 module scope.
        if ($script:storage.Contains($name)) {
            throw [System.InvalidOperationException]::new(
                "A Logfile named '$name' already exists. " +
                "Call .Destroy() on the existing instance before creating a new one."
            )
        }

        # — Initialise fields ——————————————————————————————————————
        $this.Name     = $name
        $this._data    = [System.Collections.Generic.List[string]]::new()
        $this._details = [FileDetails]::new()

        # — Register in the module-level FileStorage ——————————————————
        $script:storage.Add($name, $this)
    }


    # ── Private helper ───────────────────────────────────────────────────

    # Builds a single formatted log line from a level + message pair.
    # Used by both Write() and Print() to guarantee a consistent line format.
    # Format: [dd.MM.yyyy | HH:mm:ss]<prefix>MESSAGE
    hidden [string] BuildEntry([string] $level, [string] $message) {
        [string] $ts     = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        [string] $prefix = [Logfile]::LogLevels[$level]
        return "$ts$prefix$message"
    }

    # Validates a log level string and returns the normalized (lowercase) key.
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
            [string] $valid = ([Logfile]::LogLevels.Keys | Sort-Object) -join ', '
            throw [System.ArgumentException]::new(
                "Unknown log level '$level'. Valid levels: $valid.",
                'level'
            )
        }
        return $normalized
    }

    # Validates a message string: must not be null/whitespace and must contain
    # at least 3 non-whitespace characters (prevents empty / meaningless entries).
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
    }


    # ── Write method ────────────────────────────────────────────────────

    # Appends a single formatted log entry to the internal data list.
    #
    # Parameters:
    #   level   — One of: info, debug, warning, error, critical (case-insensitive)
    #   message — The human-readable log message (min 3 non-whitespace chars)
    #
    # Side-effects:
    #   - _data list grows by one entry
    #   - _details.RecordWrite() is called (updates _updated, _totalInteractions)
    #   - _details.SetEntryCount() is called with the new list size
    [void] Write([string] $level, [string] $message) {
        [string] $normalizedLevel = $this.ValidateLevel($level)
        $this.ValidateMessage($message)

        $this._data.Add($this.BuildEntry($normalizedLevel, $message))
        $this._details.RecordWrite()
        $this._details.SetEntryCount($this._data.Count)
    }


    # ── Print method ────────────────────────────────────────────────────

    # Appends multiple log entries sharing the same log level in a single call.
    # All messages are validated individually before any are written so that
    # a validation failure leaves the log in its prior consistent state.
    #
    # Parameters:
    #   level    — One of: info, debug, warning, error, critical (case-insensitive)
    #   messages — Array of message strings; each must pass ValidateMessage()
    #
    # Side-effects (after all messages pass validation):
    #   - _data list grows by messages.Count entries
    #   - _details.RecordWrite() is called ONCE (one interaction for the batch)
    #   - _details.SetEntryCount() is called ONCE with the final list size,
    #     ensuring that the entry count is always accurate regardless of batch size
    [void] Print([string] $level, [string[]] $messages) {
        [string] $normalizedLevel = $this.ValidateLevel($level)

        if ($null -eq $messages -or $messages.Count -eq 0) {
            throw [System.ArgumentException]::new(
                "Parameter 'messages' must not be null or empty.",
                'messages'
            )
        }

        # Pre-validate all messages before writing any, so the log stays
        # in a consistent state if one message in the middle is invalid.
        foreach ($msg in $messages) {
            $this.ValidateMessage($msg)
        }

        # All validation passed — append all entries.
        foreach ($msg in $messages) {
            $this._data.Add($this.BuildEntry($normalizedLevel, $msg))
        }

        # Record as a single batch interaction and update the entry count.
        $this._details.RecordWrite()
        $this._details.SetEntryCount($this._data.Count)
    }


    # ── Read method ─────────────────────────────────────────────────────

    # Returns the formatted log line at the specified 1-based line number.
    #
    # Line number clamping:
    #   - Values < 1 are treated as 1 (first entry)
    #   - Values > entry count are treated as the last entry
    #   - The internal List is 0-based; the method converts automatically
    #
    # Throws [System.InvalidOperationException] if the log is empty.
    #
    # Side-effects:
    #   - _details.RecordRead() is called (updates _lastAccessed, _totalInteractions)
    [string] Read([int] $line) {
        if ($this._data.Count -eq 0) {
            throw [System.InvalidOperationException]::new(
                "Logfile '$($this.Name)' contains no entries."
            )
        }

        # Clamp to valid 1-based range.
        if ($line -lt 1)                     { $line = 1 }
        if ($line -gt $this._data.Count)     { $line = $this._data.Count }

        # Convert to 0-based index.
        [string] $entry = $this._data[$line - 1]
        $this._details.RecordRead()
        return $entry
    }


    # ── SoakUp method ────────────────────────────────────────────────────

    # Returns the complete log content as a string array.
    # An empty log returns an empty array (never $null).
    # This method is intended as the primary data source for export operations.
    #
    # Side-effects:
    #   - _details.RecordRead() is called (updates _lastAccessed, _totalInteractions)
    [string[]] SoakUp() {
        $this._details.RecordRead()
        if ($this._data.Count -eq 0) {
            return @()
        }
        return $this._data.ToArray()
    }


    # ── Filter method ────────────────────────────────────────────────────

    # Returns only the log lines whose level marker matches the given level.
    # Matching is performed against the uppercase bracket notation in the line
    # (e.g. '[INFO]', '[ERROR]') so it is independent of the prefix padding.
    # Returns an empty array (never $null) if no matching lines are found.
    #
    # Parameters:
    #   level — One of: info, debug, warning, error, critical (case-insensitive)
    #
    # Side-effects:
    #   - _details.RecordRead() is called (updates _lastAccessed, _totalInteractions)
    [string[]] Filter([string] $level) {
        [string] $normalizedLevel = $this.ValidateLevel($level)
        [string] $marker          = "[$($normalizedLevel.ToUpper())]"

        $this._details.RecordRead()

        $results = $this._data | Where-Object { $_ -match [regex]::Escape($marker) }
        if ($null -eq $results) {
            return @()
        }
        return @($results)
    }


    # ── Reset method ─────────────────────────────────────────────────────

    # Clears all log data and resets the entry-count / update metadata.
    # The original creation timestamp and filename are preserved.
    # The total interaction counter is incremented (the reset is itself
    # an interaction).
    #
    # WARNING: This operation is destructive and cannot be undone.
    #
    # Side-effects:
    #   - _data is cleared to an empty list
    #   - _details.ApplyReset() is called
    [void] Reset() {
        $this._data.Clear()
        $this._details.ApplyReset()
    }


    # ── Destroy method ───────────────────────────────────────────────────

    # Permanently removes this logfile from the [FileStorage] registry and
    # releases its internal data. After calling this method, the variable
    # holding the reference should be explicitly set to $null by the caller.
    #
    # WARNING: All log data is lost. This operation cannot be undone.
    #
    # Side-effects:
    #   - This instance is removed from $script:storage
    #   - _data list is cleared and set to $null
    [void] Destroy() {
        $script:storage.Remove($this.Name)
        $this._data.Clear()
        $this._data    = $null
        $this._details = $null
    }


    # ── Shortcut write methods ──────────────────────────────────────────────
    # Convenience wrappers that call Write() with the appropriate level.
    # They reduce boilerplate when logging at a fixed level:
    #   $log.Info('Application started.')   instead of
    #   $log.Write('info', 'Application started.')

    [void] Info([string] $message)     { $this.Write('info',     $message) }
    [void] Debug([string] $message)    { $this.Write('debug',    $message) }
    [void] Warning([string] $message)  { $this.Write('warning',  $message) }
    [void] Error([string] $message)    { $this.Write('error',    $message) }
    [void] Critical([string] $message) { $this.Write('critical', $message) }


    # ── Inspection / utility methods ─────────────────────────────────────────

    # Returns the [FileDetails] companion object for this logfile.
    # Callers can inspect metadata via the public getter methods on [FileDetails]
    # (GetCreated, GetUpdated, GetLastAccessed, GetTotalInteractions, GetTotalEntries).
    [FileDetails] GetDetails() {
        return $this._details
    }

    # Returns a one-line summary string — shown automatically when the variable
    # is output to the console without a method call.
    [string] ToString() {
        [int] $count = if ($null -ne $this._data) { $this._data.Count } else { 0 }
        return "Logfile: '$($this.Name)' | Entries: $count | Created: $($this._details.GetCreated())"
    }
}
