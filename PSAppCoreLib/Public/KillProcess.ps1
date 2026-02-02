function KillProcess {
    <#
    .SYNOPSIS
    Forcefully terminates a process by process ID.
    
    .DESCRIPTION
    The KillProcess function forcefully terminates a process using its process ID.
    This is an immediate termination that does not allow the process to clean up
    or save state. It should be used only when graceful shutdown (StopProcess) fails.
    The function validates the process exists, kills it immediately, and reports
    results through a standardized return object.
    
    .PARAMETER ProcessId
    The process ID (PID) of the process to kill. Must be a valid positive integer
    representing an existing process.
    
    .PARAMETER Force
    Optional switch parameter. When specified, kills the process tree (the process
    and all its child processes). Default is $false (kills only the specified process).
    
    .PARAMETER WaitForExit
    Optional timeout in seconds to verify the process has actually terminated.
    Default is 5 seconds. If verification fails, returns an error.
    
    .EXAMPLE
    KillProcess -ProcessId 1234
    Immediately kills the process with PID 1234.
    
    .EXAMPLE
    KillProcess -ProcessId 5678 -Force
    Kills process 5678 and all its child processes.
    
    .EXAMPLE
    $result = KillProcess -ProcessId $pid
    if ($result.code -eq 0) {
        Write-Host "Process killed successfully"
        Write-Host "Termination time: $($result.terminationDurationMs) ms"
    } else {
        Write-Host "Failed to kill process: $($result.msg)"
    }
    
    .NOTES
    - This is a forceful termination that does NOT allow cleanup
    - The process cannot prevent termination
    - Unsaved work will be lost
    - System processes may require administrative privileges
    - Use StopProcess for graceful shutdown whenever possible
    - This function should be a last resort when graceful methods fail
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ProcessId,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$WaitForExit = 5
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        processId = 0
        processName = $null
        killedProcessCount = 0
        terminationDurationMs = 0
    }
    
    # Validate mandatory parameters
    if ($ProcessId -le 0) {
        $status.msg = "Parameter 'ProcessId' must be a positive integer"
        return $status
    }
    
    try {
        $status.processId = $ProcessId
        
        Write-Verbose "Attempting to kill process with PID: $ProcessId"
        if ($Force) {
            Write-Verbose "Force mode enabled - will kill process tree"
        }
        
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
            Write-Verbose "Process has already exited"
            return $status
        }
        
        Write-Verbose "Process information:"
        Write-Verbose "  Name: $($status.processName)"
        Write-Verbose "  PID: $ProcessId"
        
        # Get child processes if Force is specified
        $ChildProcesses = @()
        if ($Force) {
            try {
                Write-Verbose "Searching for child processes..."
                $AllProcesses = Get-CimInstance Win32_Process
                $ChildProcesses = $AllProcesses | Where-Object { $_.ParentProcessId -eq $ProcessId }
                
                if ($ChildProcesses.Count -gt 0) {
                    Write-Verbose "Found $($ChildProcesses.Count) child process(es)"
                }
            }
            catch {
                Write-Verbose "Warning: Could not enumerate child processes: $($_.Exception.Message)"
            }
        }
        
        # Confirmation prompt
        $ProcessCount = 1 + $ChildProcesses.Count
        $ConfirmMessage = "Forcefully kill process '$($status.processName)' (PID: $ProcessId)"
        if ($ChildProcesses.Count -gt 0) {
            $ConfirmMessage += " and $($ChildProcesses.Count) child process(es)"
        }
        
        if (-not $PSCmdlet.ShouldProcess("$ProcessCount process(es)", $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Kill child processes first
        if ($ChildProcesses.Count -gt 0) {
            Write-Verbose "Killing child processes first..."
            foreach ($ChildProc in $ChildProcesses) {
                try {
                    $ChildPID = $ChildProc.ProcessId
                    Write-Verbose "  Killing child process: PID $ChildPID"
                    Stop-Process -Id $ChildPID -Force -ErrorAction Stop
                    $status.killedProcessCount++
                }
                catch {
                    Write-Verbose "  Warning: Could not kill child process $ChildPID`: $($_.Exception.Message)"
                }
            }
        }
        
        # Kill the main process
        try {
            Write-Verbose "Killing main process: PID $ProcessId"
            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
            $status.killedProcessCount++
        }
        catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
            $status.msg = "Process with ID $ProcessId no longer exists"
            return $status
        }
        catch [System.InvalidOperationException] {
            # Process already exited
            $StopWatch.Stop()
            $status.terminationDurationMs = $StopWatch.ElapsedMilliseconds
            $status.code = 0
            $status.msg = ""
            Write-Verbose "Process has already exited"
            return $status
        }
        catch {
            $status.msg = "Error killing process: $($_.Exception.Message)"
            return $status
        }
        
        # Verify process has actually terminated
        Write-Verbose "Verifying process termination..."
        
        try {
            $Exited = $Process.WaitForExit($WaitForExit * 1000)
            $StopWatch.Stop()
            $status.terminationDurationMs = $StopWatch.ElapsedMilliseconds
            
            if ($Exited) {
                Write-Verbose "Process terminated successfully"
                Write-Verbose "  Killed processes: $($status.killedProcessCount)"
                Write-Verbose "  Duration: $($status.terminationDurationMs) ms"
                
                # Success
                $status.code = 0
                $status.msg = ""
                return $status
            }
            else {
                $status.msg = "Kill command was sent but process did not terminate within $WaitForExit seconds. Process may be in an unkillable state."
                return $status
            }
        }
        catch {
            # If we can't verify, assume it worked
            $StopWatch.Stop()
            $status.terminationDurationMs = $StopWatch.ElapsedMilliseconds
            
            # Double-check if process still exists
            try {
                $CheckProcess = Get-Process -Id $ProcessId -ErrorAction Stop
                $status.msg = "Process may still be running - verification failed: $($_.Exception.Message)"
                return $status
            }
            catch {
                # Process not found = successfully killed
                $status.code = 0
                $status.msg = ""
                Write-Verbose "Process terminated (verified by absence)"
                return $status
            }
        }
    }
    catch {
        $status.msg = "Unexpected error in KillProcess function: $($_.Exception.Message)"
        return $status
    }
}
