function StopProcess {
    <#
    .SYNOPSIS
    Gracefully stops a process by process ID.
    
    .DESCRIPTION
    The StopProcess function attempts to gracefully stop a process using its
    process ID. It sends a CloseMainWindow request to processes with a UI,
    or calls Close() for console applications. The function waits for the
    process to exit within a specified timeout period and reports results
    through a standardized return object.
    
    .PARAMETER ProcessId
    The process ID (PID) of the process to stop. Must be a valid positive integer
    representing an existing process.
    
    .PARAMETER WaitForExit
    Optional timeout in seconds to wait for the process to exit after sending
    the stop signal. Default is 10 seconds. If the process doesn't exit within
    this time, the function returns with a timeout error.
    
    .PARAMETER CloseMainWindow
    Optional switch parameter. When specified, attempts to close the main window
    (for GUI applications) before calling other stop methods. Default is $true.
    
    .EXAMPLE
    StopProcess -ProcessId 1234
    Gracefully stops the process with PID 1234, waiting up to 10 seconds.
    
    .EXAMPLE
    StopProcess -ProcessId 5678 -WaitForExit 30
    Stops process and waits up to 30 seconds for it to exit.
    
    .EXAMPLE
    $result = StopProcess -ProcessId $pid
    if ($result.code -eq 0) {
        Write-Host "Process stopped successfully"
        Write-Host "Exit code: $($result.exitCode)"
        Write-Host "Duration: $($result.shutdownDurationSeconds) seconds"
    } else {
        Write-Host "Failed to stop process: $($result.msg)"
    }
    
    .NOTES
    - This is a graceful shutdown that allows the process to clean up
    - Some processes may not respond to graceful shutdown requests
    - System processes and services may require administrative privileges
    - If graceful shutdown fails, use KillProcess for forced termination
    - The process can refuse to close (e.g., prompting to save unsaved work)
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ProcessId,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$WaitForExit = 10,
        
        [Parameter(Mandatory = $false)]
        [bool]$CloseMainWindow = $true
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        processId = 0
        processName = $null
        exitCode = $null
        shutdownDurationSeconds = 0
        wasGraceful = $false
    }
    
    # Validate mandatory parameters
    if ($ProcessId -le 0) {
        $status.msg = "Parameter 'ProcessId' must be a positive integer"
        return $status
    }
    
    try {
        $status.processId = $ProcessId
        
        Write-Verbose "Attempting to stop process with PID: $ProcessId"
        
        # Get process
        $GetResult = GetProcessByID -ProcessId $ProcessId
        
        if ($GetResult.code -ne 0) {
            $status.msg = "Failed to retrieve process: $($GetResult.msg)"
            return $status
        }
        
        $Process = $GetResult.processHandle
        $status.processName = $GetResult.processName
        
        # Check if process has already exited
        $Process.Refresh()
        if ($Process.HasExited) {
            $status.code = 0
            $status.msg = ""
            $status.exitCode = $Process.ExitCode
            $status.wasGraceful = $true
            Write-Verbose "Process has already exited with code: $($status.exitCode)"
            return $status
        }
        
        Write-Verbose "Process information:"
        Write-Verbose "  Name: $($status.processName)"
        Write-Verbose "  PID: $ProcessId"
        Write-Verbose "  Has Main Window: $($Process.MainWindowHandle -ne [IntPtr]::Zero)"
        
        # Confirmation prompt
        $ConfirmMessage = "Stop process '$($status.processName)' (PID: $ProcessId)"
        
        if (-not $PSCmdlet.ShouldProcess($status.processName, $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Attempt graceful shutdown
        $ShutdownSuccessful = $false
        
        try {
            # Try CloseMainWindow for GUI applications
            if ($CloseMainWindow -and $Process.MainWindowHandle -ne [IntPtr]::Zero) {
                Write-Verbose "Attempting to close main window..."
                $CloseResult = $Process.CloseMainWindow()
                
                if ($CloseResult) {
                    Write-Verbose "CloseMainWindow request sent successfully"
                    $ShutdownSuccessful = $true
                }
                else {
                    Write-Verbose "CloseMainWindow returned false (window may not have a close handler)"
                }
            }
            
            # If CloseMainWindow didn't work or not applicable, try Stop-Process
            if (-not $ShutdownSuccessful) {
                Write-Verbose "Attempting graceful stop via Stop-Process..."
                Stop-Process -Id $ProcessId -ErrorAction Stop
                $ShutdownSuccessful = $true
                Write-Verbose "Stop-Process request sent successfully"
            }
        }
        catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
            $status.msg = "Process with ID $ProcessId no longer exists"
            return $status
        }
        catch [System.InvalidOperationException] {
            $status.msg = "Process has already exited"
            $status.code = 0
            $status.msg = ""
            return $status
        }
        catch {
            $status.msg = "Error sending stop signal to process: $($_.Exception.Message)"
            return $status
        }
        
        # Wait for process to exit
        if ($ShutdownSuccessful) {
            Write-Verbose "Waiting up to $WaitForExit seconds for process to exit..."
            
            try {
                $Exited = $Process.WaitForExit($WaitForExit * 1000)
                $StopWatch.Stop()
                $status.shutdownDurationSeconds = [Math]::Round($StopWatch.Elapsed.TotalSeconds, 2)
                
                if ($Exited) {
                    $status.exitCode = $Process.ExitCode
                    $status.wasGraceful = $true
                    
                    Write-Verbose "Process exited gracefully"
                    Write-Verbose "  Exit code: $($status.exitCode)"
                    Write-Verbose "  Duration: $($status.shutdownDurationSeconds) seconds"
                    
                    # Success
                    $status.code = 0
                    $status.msg = ""
                    return $status
                }
                else {
                    $status.msg = "Process did not exit within timeout period of $WaitForExit seconds. Use KillProcess to force termination."
                    Write-Verbose "Timeout waiting for process to exit"
                    return $status
                }
            }
            catch {
                $status.msg = "Error waiting for process to exit: $($_.Exception.Message)"
                return $status
            }
        }
        else {
            $status.msg = "Failed to send stop signal to process"
            return $status
        }
    }
    catch {
        $status.msg = "Unexpected error in StopProcess function: $($_.Exception.Message)"
        return $status
    }
}
