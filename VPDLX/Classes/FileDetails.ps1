<#
.SYNOPSIS
    FileDetails — Metadata container for a single Logfile instance.

.DESCRIPTION
    FileDetails is an internal companion class to [Logfile]. It stores all
    tracking metadata for a virtual log file:
        - created   : timestamp when the Logfile instance was first created
        - updated   : timestamp of the most recent Write, Print, or Reset call
        - lastacc   : timestamp of the most recent Read, SoakUp, or Filter call
        - acctype   : human-readable label of the most recent interaction type
        - entries   : current number of log lines stored in the Logfile
        - axcount   : total number of all interactions since instance creation
                      (never reset — except when the Logfile itself is destroyed)

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
    Version : 1.02.03
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 05.04.2026
    Updated : 11.04.2026

    BUGFIXES (11.04.2026):
      1. Renamed RecordFilter() to RecordFilterByLevel() to match the
         public method name FilterByLevel(). The previous name was a
         leftover from the v1.01.00 Filter() -> FilterByLevel() rename.
         (Issue #4 — cosmetic internal consistency)
      2. Updated the _lastAccessType label from 'Filter' to
         'FilterByLevel' inside the renamed method. The stale label
         caused GetLastAccessType() and ToHashtable() to return a
         ghost value that no longer corresponded to any public method.
         (Issue #4)
      3. Updated field comment for _lastAccessType to list
         'FilterByLevel' instead of 'Filter' in the possible values.
#>

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
