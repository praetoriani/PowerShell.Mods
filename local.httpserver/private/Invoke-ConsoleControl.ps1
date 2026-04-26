<#
.SYNOPSIS
    Private: P/Invoke wrappers for Windows console window visibility control.

.DESCRIPTION
    Invoke-ConsoleControl.ps1 exposes four private functions that wrap the
    Win32 API calls needed to show, hide, minimise and restore the console
    window that hosts the PowerShell session running local.httpserver.

    These functions are used exclusively by Start-HTTPserver when the module
    is started in 'hidden' mode (Mode = 'hidden' in SetCoreConfig), where
    the server is expected to run completely in the background without a
    visible console window.

    WHY P/INVOKE?

    PowerShell has no native cmdlet to hide its own console window.
    The only reliable way to control the console window at runtime 
    from within the same process is to call the Win32 API directly 
    via Platform Invocation Services (P/Invoke).                   

    The three Win32 functions used here are:                       

    kernel32.dll!GetConsoleWindow()                                
        Returns the HWND (window handle) of the console window     
        associated with the current process. Returns IntPtr.Zero   
        if no console is attached (e.g. when running as a service  
        or via Start-Process -WindowStyle Hidden).                 

    user32.dll!ShowWindow(HWND, nCmdShow)                          
        Changes the visibility and state of the specified window.  
        Returns $true on success, $false if the HWND is invalid or 
        the operation failed. nCmdShow constants:                  
            0  = SW_HIDE      - completely invisible, no taskbar entry
            5  = SW_SHOW      - show at current size and position  
            6  = SW_MINIMIZE  - minimise to taskbar                
            9  = SW_RESTORE   - restore from minimised/maximised   

    kernel32.dll!FreeConsole()
        Detaches the current process from its console entirely.
        After this call, all Write-Host output is silently discarded.
        Used by Disconnect-Console for the 'completely headless' mode
        where even hiding is not enough.

    TYPE REGISTRATION (Add-Type guard):
    ----------------------------------------------------------------------
    Add-Type compiles the C# P/Invoke declaration at module load time.
    Because a .NET type can only be defined ONCE per AppDomain (the entire
    PowerShell process), we guard the Add-Type call with a type existence
    check:

        if (-not ([System.Management.Automation.PSTypeName]'WinConsoleControl').Type)

    Without this guard, re-importing the module (Import-Module -Force) or
    dot-sourcing the file a second time would throw:
        "Cannot add type. The type name 'WinConsoleControl' already exists."

    The PSTypeName accelerator checks the AppDomain's type table without
    throwing an exception - it returns $null for unknown types, which
    evaluates to $false in the condition above.

    COMPATIBILITY:
    ----------------------------------------------------------------------
    These P/Invoke declarations are compatible with:
      - PowerShell 5.1  (Windows PowerShell, .NET Framework 4.x)
      - PowerShell 7.x  (PowerShell Core, .NET 6/8)
      - Windows 10 / 11 / Server 2016 / 2019 / 2022
      - x64 and x86 architectures

    NOT compatible with:
      - PowerShell on Linux / macOS (kernel32.dll and user32.dll do not
        exist on those platforms). All four functions in this file check
        for Windows before calling any P/Invoke method and return $false
        gracefully on non-Windows platforms.

    FUNCTIONS PROVIDED:
    ----------------------------------------------------------------------
    Hide-ConsoleWindow    - SW_HIDE   (0): invisible, no taskbar entry
    Show-ConsoleWindow    - SW_SHOW   (5): restore to visible state
    Minimize-ConsoleWindow - SW_MINIMIZE (6): collapse to taskbar
    Disconnect-Console    - FreeConsole(): full console detach (headless)

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x (Windows only)
    File          : private/Invoke-ConsoleControl.ps1
#>


# ══════════════════════════════════════════════════════════════════════════════
# P/INVOKE TYPE REGISTRATION
# Compiled once per AppDomain (process lifetime).
# The guard prevents "type already exists" errors on module re-import.
# ══════════════════════════════════════════════════════════════════════════════

if (-not ([System.Management.Automation.PSTypeName]'WinConsoleControl').Type) {

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

/// <summary>
/// P/Invoke wrapper for Win32 console and window management functions.
/// Provides the minimum surface needed to control console window visibility
/// from within a PowerShell session without requiring an external binary.
/// </summary>
public class WinConsoleControl
{
    // ---------------------------------------------------------------------
    // kernel32.dll imports
    // ---------------------------------------------------------------------

    /// <summary>
    /// Returns the HWND of the console window attached to the calling process.
    /// Returns IntPtr.Zero when the process has no console (e.g. service, -NoNewWindow).
    /// </summary>
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetConsoleWindow();

    /// <summary>
    /// Detaches the calling process from its console.
    /// All subsequent console I/O (Write-Host, Write-Error, etc.) is silently
    /// discarded. This is NOT reversible within the same process - once detached,
    /// the process cannot re-attach to a console without starting a new one.
    /// Returns true on success, false if the process was not attached to a console.
    /// </summary>
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FreeConsole();

    // ---------------------------------------------------------------------
    // user32.dll imports
    // ---------------------------------------------------------------------

    /// <summary>
    /// Sets the show state of the specified window.
    /// Returns true if the window was previously visible, false if it was hidden.
    /// The return value does NOT indicate success/failure of the operation itself.
    /// Call GetLastError() (Marshal.GetLastWin32Error()) for error details.
    /// </summary>
    /// <param name="hWnd">Window handle returned by GetConsoleWindow().</param>
    /// <param name="nCmdShow">
    ///   0 = SW_HIDE       Hide completely (no taskbar entry)
    ///   5 = SW_SHOW       Show at current size and position
    ///   6 = SW_MINIMIZE   Minimize to taskbar
    ///   9 = SW_RESTORE    Restore from minimized or maximized state
    /// </param>
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    // ---------------------------------------------------------------------
    // ShowWindow nCmdShow constants
    // ---------------------------------------------------------------------

    /// <summary>Hides the window completely. No taskbar button is shown.</summary>
    public const int SW_HIDE     = 0;

    /// <summary>Activates and displays the window at its current size and position.</summary>
    public const int SW_SHOW     = 5;

    /// <summary>Minimizes the window and activates the next top-level window.</summary>
    public const int SW_MINIMIZE = 6;

    /// <summary>
    /// Activates and displays the window. If minimized or maximized, restores
    /// it to its original size and position.
    /// </summary>
    public const int SW_RESTORE  = 9;
}
'@ -Language CSharp -ErrorAction Stop

    Write-Verbose "[Invoke-ConsoleControl] WinConsoleControl type registered in AppDomain."
}


# ══════════════════════════════════════════════════════════════════════════════
# FUNCTION: Hide-ConsoleWindow
# ══════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Hides the PowerShell console window completely (SW_HIDE = 0).

.DESCRIPTION
    The window becomes invisible and its taskbar button is removed.
    The process continues running normally - all code, timers and Runspaces
    keep executing. Only the visual representation is gone.

    To make the window reappear, call Show-ConsoleWindow. The window handle
    remains valid while the process is alive, so Show-ConsoleWindow will
    always be able to restore it.

    This function is called by Start-HTTPserver when Mode = 'hidden'.

.OUTPUTS
    [bool] $true if ShowWindow() succeeded, $false if no console window
    was found or the platform is not Windows.

.EXAMPLE
    Hide-ConsoleWindow

.EXAMPLE
    # Show after 10 seconds (e.g. for debugging)
    Hide-ConsoleWindow
    Start-Sleep -Seconds 10
    Show-ConsoleWindow
#>
function Hide-ConsoleWindow {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Guard: P/Invoke calls only make sense on Windows
    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        Write-Verbose "[Hide-ConsoleWindow] Non-Windows platform detected - skipping (no-op)."
        return $false
    }

    $hwnd = [WinConsoleControl]::GetConsoleWindow()

    if ($hwnd -eq [IntPtr]::Zero) {
        # No console window exists. This happens when PowerShell was launched
        # with -WindowStyle Hidden or as a Windows service. There is nothing
        # to hide - return $true because the desired state (no visible window)
        # is already achieved.
        Write-Verbose "[Hide-ConsoleWindow] No console window found (IntPtr.Zero). Process may have been started headless."
        return $true
    }

    $result = [WinConsoleControl]::ShowWindow($hwnd, [WinConsoleControl]::SW_HIDE)

    # ShowWindow returns the PREVIOUS visibility state ($true = was visible,
    # $false = was already hidden). We always return $true here because the
    # operation itself does not fail for a valid HWND.
    Write-Verbose "[Hide-ConsoleWindow] Console window hidden. HWND=0x$($hwnd.ToString('X')), previous state was visible: $result"
    return $true
}


# ══════════════════════════════════════════════════════════════════════════════
# FUNCTION: Show-ConsoleWindow
# ══════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Makes the PowerShell console window visible again (SW_SHOW = 5).

.DESCRIPTION
    Restores the console window to its previous size and position and adds
    its taskbar button back. Used to reverse Hide-ConsoleWindow, for example
    when Stop-LocalHttpServer is called in hidden mode and the user needs
    to see final status output.

    Also useful as a diagnostic recovery command: if you have accidentally
    hidden the window of a session you still need, call this from another
    PowerShell window that knows the PID:

        (Get-Process -Id <PID>).MainWindowHandle
        # Then in the hidden session (via a scheduled task or pipe):
        Show-ConsoleWindow

.OUTPUTS
    [bool] $true on success, $false if no console window was found.

.EXAMPLE
    Show-ConsoleWindow
#>
function Show-ConsoleWindow {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        Write-Verbose "[Show-ConsoleWindow] Non-Windows platform detected - skipping (no-op)."
        return $false
    }

    $hwnd = [WinConsoleControl]::GetConsoleWindow()

    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Verbose "[Show-ConsoleWindow] No console window found. Cannot show."
        return $false
    }

    $result = [WinConsoleControl]::ShowWindow($hwnd, [WinConsoleControl]::SW_SHOW)
    Write-Verbose "[Show-ConsoleWindow] Console window shown. HWND=0x$($hwnd.ToString('X'))"
    return $true
}


# ══════════════════════════════════════════════════════════════════════════════
# FUNCTION: Minimize-ConsoleWindow
# ══════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Minimizes the PowerShell console window to the taskbar (SW_MINIMIZE = 6).

.DESCRIPTION
    Unlike Hide-ConsoleWindow, Minimize-ConsoleWindow keeps the taskbar button
    visible and the window accessible via Alt+Tab. This is the preferred mode
    when you want the server to be unobtrusive but still discoverable by the
    user.

    Use Hide-ConsoleWindow for a fully invisible background server.
    Use Minimize-ConsoleWindow for a "stay out of the way but I know it's there"
    experience.

.OUTPUTS
    [bool] $true on success, $false if no console window was found.

.EXAMPLE
    Minimize-ConsoleWindow
#>
function Minimize-ConsoleWindow {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        Write-Verbose "[Minimize-ConsoleWindow] Non-Windows platform detected - skipping (no-op)."
        return $false
    }

    $hwnd = [WinConsoleControl]::GetConsoleWindow()

    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Verbose "[Minimize-ConsoleWindow] No console window found."
        return $false
    }

    $result = [WinConsoleControl]::ShowWindow($hwnd, [WinConsoleControl]::SW_MINIMIZE)
    Write-Verbose "[Minimize-ConsoleWindow] Console window minimized. HWND=0x$($hwnd.ToString('X'))"
    return $true
}


# ══════════════════════════════════════════════════════════════════════════════
# FUNCTION: Disconnect-Console
# ══════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Fully detaches the current process from its console via FreeConsole().

.DESCRIPTION
    ⚠️  WARNING: THIS OPERATION IS IRREVERSIBLE WITHIN THE CURRENT PROCESS.

    FreeConsole() severs the connection between the process and its console
    window. After this call:
      - The console window is closed (if this process was the only one
        attached to it - which is always the case for a normal PowerShell
        session started by the user).
      - All subsequent Write-Host, Write-Error, Write-Warning output is
        silently discarded (no visible output, no error thrown).
      - The process itself continues running normally - Runspaces, timers
        and background jobs are unaffected.
      - There is NO way to re-attach a console to an existing process
        using only PowerShell. You would need to call AllocConsole() via
        another Add-Type declaration to create a NEW console window.

    USE CASES:
    This function is appropriate when:
      1. The server is intended to run as a completely invisible background
         service with NO user interaction expected after startup.
      2. The installer or management layer will communicate with the server
         exclusively through the control routes (/sys/ctrl/*) or the status
         file - never through console output.

    DO NOT use this function if:
      - You ever need to see Write-Host output for diagnostics.
      - You might need to call Stop-LocalHttpServer interactively.
      - You are unsure - use Hide-ConsoleWindow instead, which is always
        reversible with Show-ConsoleWindow.

    RELATIONSHIP TO Hide-ConsoleWindow:
    ----------------------------------------------------------------------
    Hide-ConsoleWindow (SW_HIDE) hides the window but the process stays
    attached. The window can be shown again with Show-ConsoleWindow.

    Disconnect-Console (FreeConsole) is permanent for the process lifetime.
    It produces a truly headless process - no window, no console, nothing.

.OUTPUTS
    [bool]
    $true  - FreeConsole() succeeded (process was attached and is now detached).
    $false - FreeConsole() failed (process was not attached, or non-Windows).

.EXAMPLE
    # Hidden mode - fully headless, no recovery possible
    if ($script:config['Mode'] -eq 'hidden') {
        $detached = Disconnect-Console
        if (-not $detached) {
            Write-Warning "Could not detach console - falling back to Hide-ConsoleWindow."
            Hide-ConsoleWindow
        }
    }
#>
function Disconnect-Console {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        Write-Verbose "[Disconnect-Console] Non-Windows platform detected - skipping (no-op)."
        return $false
    }

    # Write a final visible message BEFORE detaching, because any Write-Host
    # after FreeConsole() would be silently discarded and never seen.
    Write-Host "[INFO] Detaching console. The server continues running in the background." -ForegroundColor Cyan
    Write-Host "       Use Stop-LocalHttpServer (via a new session) to shut it down."      -ForegroundColor Yellow

    $result = [WinConsoleControl]::FreeConsole()

    # At this point, if $result = $true, the console is gone.
    # Write-Verbose here would go nowhere, but we keep it for log completeness
    # (it will appear in -Verbose output only if called before FreeConsole).
    if ($result) {
        Write-Verbose "[Disconnect-Console] FreeConsole() succeeded. Console detached."
    }
    else {
        # FreeConsole() returns $false if the process was not attached to a
        # console. This is not necessarily an error - it may have already been
        # detached or started without one.
        Write-Warning "[Disconnect-Console] FreeConsole() returned false. Process may not have been attached to a console."
    }

    return $result
}
