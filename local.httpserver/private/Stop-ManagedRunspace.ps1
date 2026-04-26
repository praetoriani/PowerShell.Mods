<#
.SYNOPSIS
    Gracefully signals, waits for and fully disposes a managed Runspace.

.DESCRIPTION
    Stop-ManagedRunspace performs a strict, ordered 8-step shutdown sequence.
    The order is not arbitrary - each step depends on the previous one having
    completed, and deviating from it causes resource leaks, unhandled .NET
    exceptions or hanging threads.

    SHUTDOWN SEQUENCE:
    ----------------------------------------------------------------------
    Step 1  Set the CancelToken
            ManualResetEventSlim.Set() flips IsSet to $true. The server
            loop inside the Runspace checks this flag after every
            BeginGetContext() poll cycle (max. 500 ms) and exits cleanly
            when it sees $true. This is a cooperative, non-violent stop.

    Step 2  Stop the HttpListener
            BeginGetContext() blocks the background thread while waiting
            for an incoming HTTP request. Calling HttpListener.Stop() forces
            the pending BeginGetContext() to complete immediately with a
            HttpListenerException (ErrorCode 995). The server loop catches
            this specific exception and breaks out of the while loop.
            Without this step, a quiet server (no incoming requests) could
            take indefinitely long to stop even after the CancelToken is set.

    Step 3  Wait for clean exit (AsyncWaitHandle.WaitOne)
            Blocks the calling thread for up to TimeoutMs milliseconds while
            waiting for BeginInvoke() to complete. If the server loop exits
            cleanly (Steps 1 + 2 worked), WaitOne() returns $true well within
            the timeout. If TimeoutMs = 0 (Force mode), this step is skipped.

    Step 4  EndInvoke()
            MUST be called after every BeginInvoke(), regardless of whether
            we care about the return value. Skipping EndInvoke() causes:
              - The IAsyncResult handle to remain live (memory leak)
              - Any unhandled exception from the background thread to be
                silently swallowed instead of surfaced as a warning
            EndInvoke() is wrapped in try/catch because the server loop may
            have thrown before producing any output.

    Step 5  PowerShell.Dispose()
            Releases the pipeline, the command collection and the internal
            error/output buffers of the PowerShell shell object.

    Step 6  Runspace.Close() + Runspace.Dispose()
            Close() transitions the Runspace to Closed state and releases
            the OS thread. Dispose() frees the remaining .NET handles.
            Both must be called: Close() alone does not free all resources.

    Step 7  CancelToken.Dispose()
            Releases the underlying WaitHandle of the ManualResetEventSlim.

    Step 8  Remove from $script:RunspaceStore
            The store slot is freed. A subsequent call to New-ManagedRunspace
            with the same name will succeed.
    ----------------------------------------------------------------------

    Each step is wrapped in its own try/catch so that a failure in one step
    does not prevent the remaining cleanup steps from running.

.PARAMETER RunspaceName
    The key under which the target Runspace is registered in
    $script:RunspaceStore. Must match the Name used in New-ManagedRunspace.

.PARAMETER TimeoutMs
    Maximum time in milliseconds to wait (Step 3) for the background code
    to exit before proceeding with forced cleanup.

    Default : 5000 (5 seconds). Usually the server loop exits within 500 ms
              after the CancelToken is set and the listener is stopped.
    Minimum : 0   - skips Step 3 entirely (immediate force-close).
    Maximum : 30000 (30 seconds, sanity cap).

    Pass 0 (or use the -Force switch on Stop-LocalHttpServer) when you need
    an immediate shutdown and do not care about in-flight requests.

.OUTPUTS
    [bool]
    $true  - the runspace was found and the shutdown sequence completed
             (even if individual cleanup steps produced non-fatal warnings).
    $false - the runspace was not found in $script:RunspaceStore.

.EXAMPLE
    # Normal graceful stop (waits up to 5 seconds)
    Stop-ManagedRunspace -RunspaceName 'http'

    # Immediate force-close (skips WaitOne)
    Stop-ManagedRunspace -RunspaceName 'http' -TimeoutMs 0

    # Custom timeout
    Stop-ManagedRunspace -RunspaceName 'http' -TimeoutMs 10000

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : private/Stop-ManagedRunspace.ps1
#>
function Stop-ManagedRunspace {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RunspaceName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 30000)]
        [int]$TimeoutMs = 5000
    )

    # ------------------------------------------------------------------
    # Guard: runspace must be registered
    # ------------------------------------------------------------------
    if (-not $script:RunspaceStore.ContainsKey($RunspaceName)) {
        Write-Warning "[Stop-ManagedRunspace] No runspace named '$RunspaceName' found in RunspaceStore."
        return $false
    }

    $entry = $script:RunspaceStore[$RunspaceName]
    Write-Verbose "[Stop-ManagedRunspace] Beginning shutdown sequence for runspace '$RunspaceName'..."

    # ==================================================================
    # STEP 1: Signal the CancelToken
    # ==================================================================
    # Set() is idempotent - calling it when IsSet is already $true is a
    # no-op. The null-check protects against an entry whose CancelToken
    # was never created (should not happen in normal flow, but defensive
    # coding prevents a NullReferenceException here).
    if ($null -ne $entry.CancelToken -and -not $entry.CancelToken.IsSet) {
        try {
            $entry.CancelToken.Set()
            Write-Verbose "[Stop-ManagedRunspace] Step 1/8: CancelToken set for '$RunspaceName'."
        }
        catch {
            Write-Warning "[Stop-ManagedRunspace] Step 1/8: CancelToken.Set() failed (non-fatal): $($_.Exception.Message)"
        }
    }
    else {
        Write-Verbose "[Stop-ManagedRunspace] Step 1/8: CancelToken already set or null - skipped."
    }

    # ==================================================================
    # STEP 2: Stop the HttpListener
    # ==================================================================
    # We read the $httpListener variable directly from the Runspace's
    # session state via SessionStateProxy. This is safe to call on a
    # running Runspace. If the variable does not exist (e.g. this is a
    # non-HTTP runspace like a named pipe server) GetVariable() returns
    # $null and the block is skipped without any error.
    try {
        $listener = $entry.Runspace.SessionStateProxy.GetVariable('httpListener')
        if ($null -ne $listener -and $listener.IsListening) {
            $listener.Stop()
            Write-Verbose "[Stop-ManagedRunspace] Step 2/8: HttpListener stopped for '$RunspaceName'."
        }
        else {
            Write-Verbose "[Stop-ManagedRunspace] Step 2/8: HttpListener not found or not listening - skipped."
        }
    }
    catch {
        # A RunspaceNotOpenException can occur here in a race condition
        # where the background thread has already closed itself between
        # Step 1 and Step 2. This is non-fatal; proceed to Step 3.
        Write-Verbose "[Stop-ManagedRunspace] Step 2/8: Could not stop HttpListener (non-fatal): $($_.Exception.Message)"
    }

    # ==================================================================
    # STEP 3: Wait for the async job to finish
    # ==================================================================
    # WaitOne() with a timeout blocks this thread until either:
    #   a) The background ScriptBlock exits and the Handle is signalled.
    #   b) The TimeoutMs limit is reached.
    # TimeoutMs = 0 skips the wait entirely (immediate force-close mode).
    if ($null -ne $entry.Handle -and $TimeoutMs -gt 0) {
        try {
            $cleanExit = $entry.Handle.AsyncWaitHandle.WaitOne($TimeoutMs)
            if ($cleanExit) {
                Write-Verbose "[Stop-ManagedRunspace] Step 3/8: Runspace '$RunspaceName' exited cleanly within timeout."
            }
            else {
                Write-Warning "[Stop-ManagedRunspace] Step 3/8: Runspace '$RunspaceName' did not exit within ${TimeoutMs}ms. Proceeding with forced cleanup."
            }
        }
        catch {
            Write-Warning "[Stop-ManagedRunspace] Step 3/8: WaitOne() failed (non-fatal): $($_.Exception.Message)"
        }
    }
    else {
        Write-Verbose "[Stop-ManagedRunspace] Step 3/8: Wait skipped (TimeoutMs=0 or no handle)."
    }

    # ==================================================================
    # STEP 4: EndInvoke - collect result, surface background errors
    # ==================================================================
    # EndInvoke() is mandatory after every BeginInvoke(). It:
    #   - Returns whatever the ScriptBlock returned (we discard it here).
    #   - Re-throws any unhandled terminating exception from the background
    #     thread as a new exception on the calling thread. We catch it and
    #     log it as a Warning so cleanup continues.
    #   - Releases the internal result buffer of the PowerShell shell.
    if ($null -ne $entry.PowerShell -and $null -ne $entry.Handle) {
        try {
            $entry.PowerShell.EndInvoke($entry.Handle) | Out-Null
            Write-Verbose "[Stop-ManagedRunspace] Step 4/8: EndInvoke() completed for '$RunspaceName'."
        }
        catch {
            Write-Warning "[Stop-ManagedRunspace] Step 4/8: EndInvoke() reported a background error: $($_.Exception.Message)"
        }
    }
    else {
        Write-Verbose "[Stop-ManagedRunspace] Step 4/8: No PowerShell shell or handle - EndInvoke skipped."
    }

    # ==================================================================
    # STEP 5: Dispose the PowerShell shell
    # ==================================================================
    if ($null -ne $entry.PowerShell) {
        try {
            $entry.PowerShell.Dispose()
            Write-Verbose "[Stop-ManagedRunspace] Step 5/8: PowerShell shell disposed for '$RunspaceName'."
        }
        catch {
            Write-Verbose "[Stop-ManagedRunspace] Step 5/8: PS Dispose() (non-fatal): $($_.Exception.Message)"
        }
    }

    # ==================================================================
    # STEP 6: Close and Dispose the Runspace
    # ==================================================================
    # Close() transitions the Runspace from its current state to Closed
    # and releases the OS thread. Dispose() frees remaining .NET handles
    # and unmanaged resources. Both must be called - Close() alone leaves
    # the WaitHandle and other disposable members live.
    if ($null -ne $entry.Runspace) {
        try {
            $entry.Runspace.Close()
            Write-Verbose "[Stop-ManagedRunspace] Step 6/8: Runspace '$RunspaceName' closed."
        }
        catch {
            Write-Verbose "[Stop-ManagedRunspace] Step 6/8: Runspace.Close() (non-fatal): $($_.Exception.Message)"
        }
        try {
            $entry.Runspace.Dispose()
            Write-Verbose "[Stop-ManagedRunspace] Step 6/8: Runspace '$RunspaceName' disposed."
        }
        catch {
            Write-Verbose "[Stop-ManagedRunspace] Step 6/8: Runspace.Dispose() (non-fatal): $($_.Exception.Message)"
        }
    }

    # ==================================================================
    # STEP 7: Dispose the CancelToken
    # ==================================================================
    # ManualResetEventSlim internally holds a kernel WaitHandle that must
    # be explicitly disposed to avoid a handle leak. This is safe to call
    # even if Set() was called earlier - Dispose() after Set() is valid.
    if ($null -ne $entry.CancelToken) {
        try {
            $entry.CancelToken.Dispose()
            Write-Verbose "[Stop-ManagedRunspace] Step 7/8: CancelToken disposed for '$RunspaceName'."
        }
        catch {
            Write-Verbose "[Stop-ManagedRunspace] Step 7/8: CancelToken.Dispose() (non-fatal): $($_.Exception.Message)"
        }
    }

    # ==================================================================
    # STEP 8: Remove from the RunspaceStore
    # ==================================================================
    # After removal the slot is free. New-ManagedRunspace can create a
    # new runspace under the same name (used by Restart-LocalHttpServer).
    $script:RunspaceStore.Remove($RunspaceName)
    Write-Verbose "[Stop-ManagedRunspace] Step 8/8: Runspace '$RunspaceName' removed from RunspaceStore."

    Write-Host "[INFO] Runspace '$RunspaceName' stopped and fully cleaned up." -ForegroundColor Cyan
    return $true
}
