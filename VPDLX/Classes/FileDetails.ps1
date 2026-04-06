<#
.SYNOPSIS
    FileDetails — Metadata container for a single Logfile instance.

.DESCRIPTION
    FileDetails is an internal companion class to [Logfile]. It stores all
    tracking metadata for a virtual log file: creation time, last update time,
    last access time, total interaction count, and current entry count.

    The class is designed to be managed exclusively by VPDLX internals (the
    [Logfile] class methods). To discourage direct manipulation by the caller,
    all mutating members are marked 'hidden'. The public surface exposes only
    read-only getters via methods, so the caller can query state without being
    able to overwrite it arbitrarily.

    IMPORTANT: PowerShell classes do not enforce true access control. 'hidden'
    merely suppresses the member from IntelliSense and Get-Member output.
    Disciplined callers should use only the provided getter methods.

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.01.00
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 05.04.2026
    Updated : 06.04.2026
#>

class FileDetails {

    # ── Hidden (internal) fields ──────────────────────────────────────────────
    # All fields are marked hidden so they do not surface in IntelliSense or
    # Get-Member output for the caller. VPDLX class methods write these fields
    # via the Update* and Increment* helper methods defined below.

    # Timestamp when the Logfile instance was first created.
    hidden [string] $_created

    # Timestamp of the most recent Write, Print, or Reset call.
    hidden [string] $_updated

    # Timestamp of the most recent Read, SoakUp, or Filter call.
    hidden [string] $_lastAccessed

    # Running counter of all interactions (Write, Print, Read, SoakUp,
    # Filter, Reset) since the Logfile instance was created.
    hidden [int]    $_totalInteractions

    # Current number of log lines stored in the Logfile's data list.
    # This is set explicitly (not incremented) so that Print(array) always
    # produces an accurate count regardless of batch size.
    hidden [int]    $_totalEntries


    # ── Constructor ───────────────────────────────────────────────────────────
    # Called by [Logfile]::new() during instance creation.
    # Captures the creation timestamp and zeros all counters.
    FileDetails() {
        [string] $ts              = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._created            = $ts
        $this._updated            = $ts
        $this._lastAccessed       = $ts
        $this._totalInteractions  = 0
        $this._totalEntries       = 0
    }


    # ── Internal update methods (called by Logfile methods only) ──────────────

    # Records a write-type interaction (Write / Print / Reset).
    # Updates the _updated timestamp and increments _totalInteractions.
    # The caller is responsible for setting _totalEntries via SetEntryCount().
    hidden [void] RecordWrite() {
        $this._updated           = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._totalInteractions++
    }

    # Records a read-type interaction (Read / SoakUp / Filter).
    # Updates the _lastAccessed timestamp and increments _totalInteractions.
    hidden [void] RecordRead() {
        $this._lastAccessed      = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._totalInteractions++
    }

    # Sets the absolute entry count after any write or reset operation.
    # This method is used instead of an increment so that Print(array)
    # can set the exact final count in a single call.
    hidden [void] SetEntryCount([int] $count) {
        $this._totalEntries = $count
    }

    # Resets mutable metadata fields to their post-reset state.
    # _created is intentionally preserved — it reflects the original
    # instantiation time and must survive a Reset() call.
    hidden [void] ApplyReset() {
        [string] $ts             = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
        $this._updated           = $ts
        $this._lastAccessed      = $ts
        $this._totalInteractions++   # Reset itself counts as one interaction
        $this._totalEntries      = 0
    }


    # ── Public getter methods ─────────────────────────────────────────────────
    # These are the only methods the caller should need. They return copies of
    # the internal field values, preventing accidental mutation via reference.

    # Returns the creation timestamp string.
    [string] GetCreated()           { return $this._created }

    # Returns the last-write timestamp string.
    [string] GetUpdated()           { return $this._updated }

    # Returns the last-read/access timestamp string.
    [string] GetLastAccessed()      { return $this._lastAccessed }

    # Returns the total interaction count since creation.
    [int]    GetTotalInteractions() { return $this._totalInteractions }

    # Returns the current number of entries in the associated Logfile.
    [int]    GetTotalEntries()      { return $this._totalEntries }

    # Returns a formatted summary string — useful for quick console inspection.
    [string] ToString() {
        return (
            "FileDetails | Created: $($this._created) | " +
            "Updated: $($this._updated) | " +
            "LastAccessed: $($this._lastAccessed) | " +
            "Interactions: $($this._totalInteractions) | " +
            "Entries: $($this._totalEntries)"
        )
    }

    # Returns all metadata as an ordered hashtable — useful for export / JSON.
    [System.Collections.Specialized.OrderedDictionary] ToHashtable() {
        $ht = [ordered] @{
            created           = $this._created
            updated           = $this._updated
            lastAccessed      = $this._lastAccessed
            totalInteractions = $this._totalInteractions
            totalEntries      = $this._totalEntries
        }
        return $ht
    }
}
