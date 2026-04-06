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

    ── Supported log levels ─────────────────────────────────────────────────
    info, debug, verbose, trace, warning, error, critical, fatal

    ── Public write methods ──────────────────────────────────────────────────
    Write(level, message)     — Appends a single formatted log line.
    Print(level, messages[])  — Appends an array of messages in one call.

    ── Public read methods ───────────────────────────────────────────────────
    Read(line)    — Returns the formatted log line at the given 1-based index.
    SoakUp()      — Returns the complete log content as a string array.
    Filter(level) — Returns only lines that match the specified log level.

    ── Public utility methods ────────────────────────────────────────────────
    IsEmpty()     — Returns $true if the log contains no entries.
    HasEntries()  — Returns $true if the log contains at least one entry.
    EntryCount()  — Returns the current number of entries.
    Reset()       — Clears all log data (irreversible).
    Destroy()     — Removes this instance from FileStorage and frees memory.

    ── Shortcut write methods ────────────────────────────────────────────────
    Info(msg) / Debug(msg) / Verbose(msg) / Trace(msg) / Warning(msg) /
    Error(msg) / Critical(msg) / Fatal(msg)

    ── Inspection ────────────────────────────────────────────────────────────
    GetDetails()  — Returns the [FileDetails] companion object.
    ToString()    — Returns a one-line summary string.

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.00
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 05.04.2026
    Updated : 06.04.2026

    KNOWN LIMITATIONS:
      - VPDLX is NOT designed for parallel execution.
        Using Logfile instances inside ForEach-Object -Parallel or
        Start-ThreadJob without external synchronisation may lead to
        race conditions on the internal List<string> and Dictionary.
        See README.md section 'Known Limitations' for details.

    DEPENDENCIES (must be dot-sourced before this file):
      - Classes/FileDetails.ps1
      - Classes/FileStorage.ps1
    The module root (VPDLX.psm1) ensures correct load order.
#>

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

        $name = $name.Trim()

        # ── Validate: length 3–64 characters ────────────────────────────────
        if ($name.Length -lt 3 -or $name.Length -gt 64) {
            throw [System.ArgumentException]::new(
                "Parameter 'name' must be between 3 and 64 characters. " +
                "Provided length: $($name.Length).",
                'name'
            )
        }

        # ── Validate: allowed characters only ────────────────────────────────
        # Only alphanumeric characters plus underscore, hyphen, and dot are allowed.
        if ($name -notmatch '^[a-zA-Z0-9_\-\.]+$') {
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
        if ($script:storage.Contains($name)) {
            throw [System.InvalidOperationException]::new(
                "A Logfile named '$name' already exists. " +
                "Call .Destroy() on the existing instance before creating a new one."
            )
        }

        # ── Initialise internal fields ────────────────────────────────────────
        $this.Name     = $name
        $this._data    = [System.Collections.Generic.List[string]]::new()
        $this._details = [FileDetails]::new()

        # ── Register in the module-level FileStorage ──────────────────────────
        $script:storage.Add($name, $this)
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
        foreach ($msg in $messages) {
            $this.ValidateMessage($msg)
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
        if ($line -lt 1)                     { $line = 1 }
        if ($line -gt $this._data.Count)     { $line = $this._data.Count }

        # Convert to 0-based index and retrieve the entry.
        [string] $entry = $this._data[$line - 1]
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


    # ── Filter ───────────────────────────────────────────────────────────────

    # Returns only the log lines whose level marker matches the given level.
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
    #   - _details.RecordFilter() is called  -> updates 'lastacc', 'acctype', 'axcount'
    [string[]] Filter([string] $level) {
        $this.GuardDestroyed()
        [string] $normalizedLevel = $this.ValidateLevel($level)
        [string] $marker          = "[$($normalizedLevel.ToUpper())]"

        $this._details.RecordFilter()

        # Use a typed List and a direct foreach loop with .Contains() instead
        # of Where-Object pipeline — avoids regex overhead and pipeline cost.
        $results = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $this._data) {
            if ($line.Contains($marker)) {
                $results.Add($line)
            }
        }
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
    [void] Destroy() {
        if ($null -ne $this._data) {
            $script:storage.Remove($this.Name)
            $this._data.Clear()
        }
        $this._data    = $null
        $this._details = $null
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
    [string] ToString() {
        [int] $count = if ($null -ne $this._data) { $this._data.Count } else { 0 }
        return "Logfile: '$($this.Name)' | Entries: $count | Created: $($this._details.GetCreated())"
    }
}
