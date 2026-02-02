function KillProcess {
    <#
    .SYNOPSIS
    Forcefully terminates a process by process ID.
    
    .DESCRIPTION
    The KillProcess function forcefully terminates a process using its process ID.
    This is an immediate termination that does not allow the process to clean up
    or save state. It should be used only when graceful shutdown (StopProcess) fails.
    The function validates the process exists, kills it immediately, and reports
    results through OPSreturn standardized return pattern.
    
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
    $result = KillProcess -ProcessId 1234
    if ($result.code -eq 0) {
        Write-Host "Process killed successfully"
    }
    
    .EXAMPLE
    $result = KillProcess -ProcessId 5678 -Force
    if ($result.code -eq 0) {
        Write-Host "Killed $($result.data.KilledProcessCount) process(es)"
        Write-Host "Termination took $($result.data.TerminationDurationMs) ms"
    }
    
    .EXAMPLE
    $result = KillProcess -ProcessId $pid -WaitForExit 10
    if ($result.code -eq 0) {
        Write-Host "Process killed successfully"
        Write-Host "Termination time: $($result.data.TerminationDurationMs) ms"
        Write-Host "Killed processes: $($result.data.KilledProcessCount)"
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
    - Returns termination statistics in the data field
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
    
    # Validate mandatory parameters
    if ($ProcessId -le 0) {
        return OPSreturn -Code -1 -Message "Parameter 'ProcessId' must be a positive integer"
    }
    
    try {
        Write-Verbose "Attempting to kill process with PID: $ProcessId"
        if ($Force) {
            Write-Verbose "Force mode enabled - will kill process tree"
        }
        
        # Get process
        $GetResult = GetProcessByID -ProcessId $ProcessId
        
        if ($GetResult.code -ne 0) {
            return OPSreturn -Code -1 -Message "Failed to retrieve process: $($GetResult.msg)"
        }
        
        $Process = $GetResult.data.ProcessHandle
        $ProcessName = $GetResult.data.ProcessName
        
        # Check if process has already exited
        $Process.Refresh()
        if ($Process.HasExited) {
            $ReturnData = [PSCustomObject]@{
                ProcessId             = $ProcessId
                ProcessName           = $ProcessName
                KilledProcessCount    = 0
                ChildProcessCount     = 0
                TerminationDurationMs = 0
            }
            return OPSreturn -Code 0 -Message "" -Data $ReturnData
        }
        
        Write-Verbose "Process information:"
        Write-Verbose "  Name: $ProcessName"
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
        $ConfirmMessage = "Forcefully kill process '$ProcessName' (PID: $ProcessId)"
        if ($ChildProcesses.Count -gt 0) {
            $ConfirmMessage += " and $($ChildProcesses.Count) child process(es)"
        }
        
        if (-not $PSCmdlet.ShouldProcess("$ProcessCount process(es)", $ConfirmMessage)) {
            return OPSreturn -Code -1 -Message "Operation cancelled by user"
        }
        
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $KilledCount = 0
        $ChildCount = $ChildProcesses.Count
        
        # Kill child processes first
        if ($ChildProcesses.Count -gt 0) {
            Write-Verbose "Killing child processes first..."
            foreach ($ChildProc in $ChildProcesses) {
                try {
                    $ChildPID = $ChildProc.ProcessId
                    Write-Verbose "  Killing child process: PID $ChildPID"
                    Stop-Process -Id $ChildPID -Force -ErrorAction Stop
                    $KilledCount++
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
            $KilledCount++
        }
        catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
            return OPSreturn -Code -1 -Message "Process with ID $ProcessId no longer exists"
        }
        catch [System.InvalidOperationException] {
            # Process already exited
            $StopWatch.Stop()
            
            $ReturnData = [PSCustomObject]@{
                ProcessId             = $ProcessId
                ProcessName           = $ProcessName
                KilledProcessCount    = $KilledCount
                ChildProcessCount     = $ChildCount
                TerminationDurationMs = $StopWatch.ElapsedMilliseconds
            }
            
            Write-Verbose "Process has already exited"
            return OPSreturn -Code 0 -Message "" -Data $ReturnData
        }
        catch {
            return OPSreturn -Code -1 -Message "Error killing process: $($_.Exception.Message)"
        }
        
        # Verify process has actually terminated
        Write-Verbose "Verifying process termination..."
        
        try {
            $Exited = $Process.WaitForExit($WaitForExit * 1000)
            $StopWatch.Stop()
            
            $ReturnData = [PSCustomObject]@{
                ProcessId             = $ProcessId
                ProcessName           = $ProcessName
                KilledProcessCount    = $KilledCount
                ChildProcessCount     = $ChildCount
                TerminationDurationMs = $StopWatch.ElapsedMilliseconds
            }
            
            if ($Exited) {
                Write-Verbose "Process terminated successfully"
                Write-Verbose "  Killed processes: $KilledCount (including $ChildCount child processes)"
                Write-Verbose "  Duration: $($StopWatch.ElapsedMilliseconds) ms"
                
                return OPSreturn -Code 0 -Message "" -Data $ReturnData
            }
            else {
                return OPSreturn -Code -1 -Message "Kill command was sent but process did not terminate within $WaitForExit seconds. Process may be in an unkillable state." -Data $ReturnData
            }
        }
        catch {
            # If we can't verify, assume it worked
            $StopWatch.Stop()
            
            # Double-check if process still exists
            try {
                $CheckProcess = Get-Process -Id $ProcessId -ErrorAction Stop
                return OPSreturn -Code -1 -Message "Process may still be running - verification failed: $($_.Exception.Message)"
            }
            catch {
                # Process not found = successfully killed
                $ReturnData = [PSCustomObject]@{
                    ProcessId             = $ProcessId
                    ProcessName           = $ProcessName
                    KilledProcessCount    = $KilledCount
                    ChildProcessCount     = $ChildCount
                    TerminationDurationMs = $StopWatch.ElapsedMilliseconds
                }
                
                Write-Verbose "Process terminated (verified by absence)"
                return OPSreturn -Code 0 -Message "" -Data $ReturnData
            }
        }
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in KillProcess function: $($_.Exception.Message)"
    }
}
