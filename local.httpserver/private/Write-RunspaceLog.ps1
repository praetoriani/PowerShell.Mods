<#
.SYNOPSIS
    Runspace-safe console output function with foreground and background color support.

.DESCRIPTION
    Write-RunspaceLog is the ONLY correct way to write colored text to the console
    from within a PowerShell Runspace.

    BACKGROUND - WHY WRITE-HOST FAILS IN A RUNSPACE:
    --------------------------------------------------
    Standard PowerShell output cmdlets (Write-Host, Write-Warning, Write-Error,
    Write-Verbose) write to named streams (Information, Warning, Error, Verbose)
    of the PowerShell shell instance ($ps) that owns the Runspace.

    When a Runspace is started with BeginInvoke(), these streams accumulate silently
    inside $ps.Streams.Warning, $ps.Streams.Error, etc. They are NEVER forwarded
    to the host process automatically. The streams would only become visible if
    code called $ps.EndInvoke() and then iterated over $ps.Streams - which never
    happens in a long-running background Runspace.

    Result: every Write-Host / Write-Warning / Write-Error call inside a Runspace
    is silently discarded.

    THE SOLUTION - [Console]::Write* METHODS:
    ------------------------------------------
    The System.Console class writes directly to the process's stdout handle via
    native Win32 / .NET I/O calls. This bypasses PowerShell's stream system entirely.
    Because the Runspace and the host process share the same stdout handle (they
    are threads of the SAME process), output from [Console]::Write() appears
    immediately in the console window, regardless of which thread calls it.

    Write-RunspaceLog wraps [Console]::ForegroundColor and [Console]::BackgroundColor
    to provide full color support while guaranteeing thread-safe color restoration
    via a try/finally block.

    THREAD SAFETY NOTE:
    -------------------
    [Console]::ForegroundColor and BackgroundColor are process-global properties.
    If two threads change them simultaneously, a race condition could produce
    incorrect colors on one or both lines. In practice this is not a problem for
    local.httpserver because:
      1. Only one Runspace (the HTTP server) calls Write-RunspaceLog.
      2. The host thread's Write-Host calls are rare (only during start/stop).
    If multiple Runspaces are added in a future phase, a [Console] lock via
    [System.Threading.Monitor] can be added around the color-change block.

    PARAMETER REFERENCE:
    ---------------------
    See parameter documentation below.

.PARAMETER Message
    The text to write to the console.
    Accepts any string, including empty strings (which produce a blank line).

.PARAMETER ForegroundColor
    The text (foreground) color.
    Must be a value from the [System.ConsoleColor] enum.
    Default: [System.ConsoleColor]::White

    Available values (case-insensitive when passing as string):
      Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta,
      DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta,
      Yellow, White

.PARAMETER BackgroundColor
    The background color for this line.
    Must be a value from the [System.ConsoleColor] enum.
    Default: $null (= no change, uses the current console background color)

    Pass $null explicitly (or omit the parameter) to leave the background
    unchanged - this is the correct default for most log lines.
    Only set a background color for visually distinct messages like banners,
    critical errors, or status blocks.

.PARAMETER NoNewline
    If specified, the message is written WITHOUT a trailing newline.
    The next Write-RunspaceLog call (or any [Console]::Write call) will
    continue on the same line. Useful for building progress lines.

.PARAMETER Prefix
    An optional label prepended to $Message before output.
    The prefix is wrapped in square brackets: "[Prefix] Message"
    If omitted, the message is written as-is.

    Recommended standard prefixes for local.httpserver:
      "INFO"    - informational messages (server start, variable injection, etc.)
      "OK"      - successful operations
      "WARN"    - warnings that do not abort processing
      "ERROR"   - errors that caused an operation to fail or be skipped
      "REQUEST" - per-request log lines (method, path, status)
      "DEBUG"   - verbose/diagnostic output (only when $DebugOutput is true)

.EXAMPLE
    # Basic usage - white text, no prefix
    Write-RunspaceLog "Server loop starting..."

.EXAMPLE
    # Server started - green with [OK] prefix
    Write-RunspaceLog "HTTP server is listening on http://localhost:8080/" `
                      -ForegroundColor Green `
                      -Prefix "OK"
    # Output: [OK] HTTP server is listening on http://localhost:8080/

.EXAMPLE
    # Warning - yellow text
    Write-RunspaceLog "BeginGetContext() failed - code 995. Retrying..." `
                      -ForegroundColor Yellow `
                      -Prefix "WARN"

.EXAMPLE
    # Fatal error - white text on red background
    Write-RunspaceLog "Fatal: listener could not be started. Port already in use." `
                      -ForegroundColor White `
                      -BackgroundColor Red `
                      -Prefix "ERROR"

.EXAMPLE
    # Request log line - timestamp + method + path
    Write-RunspaceLog "[2026-04-26 20:00:00] #42 GET /index.html  [from 127.0.0.1]" `
                      -ForegroundColor Cyan `
                      -Prefix "REQUEST"

.EXAMPLE
    # Blank separator line between sections
    Write-RunspaceLog ""

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/Write-RunspaceLog.ps1

    This function MUST be injected into the Runspace via
    Invoke-RunspaceFunctionInjection BEFORE New-RunspaceJob starts the
    server loop. Add 'Write-RunspaceLog' to the FunctionNames array in
    the Invoke-RunspaceFunctionInjection call inside Start-HTTPserver.

    | Level   | ForegroundColor | BackgroundColor | Verwendung                                 |
    | ------- | --------------- | --------------- | ------------------------------------------ |
    | OK      | Green           | (keiner)        | Erfolgreiche Operationen, Server gestartet |
    | INFO    | DarkGray        | (keiner)        | Neutrale Statusmeldungen                   |
    | REQUEST | Cyan            | (keiner)        | Jeder eingehende HTTP-Request              |
    | WARN    | Yellow          | (keiner)        | Warnungen, nicht-fatale Fehler             |
    | ERROR   | White           | Red             | Fatale Fehler, Exceptions                  |
    | DEBUG   | DarkGray        | (keiner)        | Nur bei aktivem Debug-Flag                 |
#>
function Write-RunspaceLog {
    [CmdletBinding()]
    param(
        # The text to write. Empty string produces a blank line.
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowEmptyString()]
        [string]$Message = "",

        # Foreground (text) color. Defaults to White.
        [Parameter(Mandatory = $false)]
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::White,

        # Background color. $null = leave unchanged (default for most log lines).
        [Parameter(Mandatory = $false)]
        [Nullable[System.ConsoleColor]]$BackgroundColor = $null,

        # If set, suppress the trailing newline so the next output continues on
        # the same line. Useful for inline progress indicators.
        [Parameter(Mandatory = $false)]
        [switch]$NoNewline,

        # Optional label prepended as "[Prefix] ".
        # Use standard labels: INFO, OK, WARN, ERROR, REQUEST, DEBUG
        [Parameter(Mandatory = $false)]
        [string]$Prefix = ""
    )

    # ------------------------------------------------------------------
    # Build the final output string
    # ------------------------------------------------------------------
    # If a Prefix is provided, wrap it in square brackets and prepend.
    # An empty Prefix means no label - the message is written as-is.
    # This keeps the function flexible: structured logs with labels
    # AND raw formatted lines (banners, separators) both work correctly.
    $outputText = if ([string]::IsNullOrEmpty($Prefix)) {
        $Message
    } else {
        "[$Prefix] $Message"
    }

    # ------------------------------------------------------------------
    # Save current console colors so we can restore them in finally.
    # This is the KEY to correct behavior: if we crash between setting
    # a new color and writing the text, finally ALWAYS restores the
    # original colors, preventing the terminal from being "stuck" in
    # the wrong color after an exception.
    # ------------------------------------------------------------------
    $savedForeground = [Console]::ForegroundColor
    $savedBackground = [Console]::BackgroundColor

    try {
        # Apply foreground color
        [Console]::ForegroundColor = $ForegroundColor

        # Apply background color ONLY if explicitly requested.
        # $null means "don't change" - this is the correct default so that
        # most log lines don't alter the terminal background at all.
        if ($null -ne $BackgroundColor) {
            [Console]::BackgroundColor = $BackgroundColor.Value
        }

        # Write the output
        # [Console]::Write()     → no trailing newline (used when -NoNewline)
        # [Console]::WriteLine() → appends newline (default behavior)
        #
        # Both methods write directly to stdout via native I/O, bypassing
        # PowerShell's stream system. This is what makes them Runspace-safe.
        if ($NoNewline) {
            [Console]::Write($outputText)
        } else {
            [Console]::WriteLine($outputText)
        }
    }
    finally {
        # Always restore the original colors, even if an exception occurred
        # during the write. This guarantees the terminal is never left in
        # an unintended color state after Write-RunspaceLog returns.
        [Console]::ForegroundColor = $savedForeground
        [Console]::BackgroundColor = $savedBackground
    }
}
