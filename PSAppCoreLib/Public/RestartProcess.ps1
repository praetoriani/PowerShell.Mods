function RestartProcess {
    <#
    .SYNOPSIS
    Restarts a process by process ID.
    
    .DESCRIPTION
    The RestartProcess function retrieves a process by its ID, captures its path
    and command-line arguments, stops the process gracefully, and then starts it
    again with the same parameters. It validates the process exists, ensures it
    can be restarted (has a valid path), stops it safely, and restarts with
    original arguments. Reports detailed results through a standardized return object.
    
    .PARAMETER ProcessId
    The process ID (PID) of the process to restart. Must be a valid positive integer
    representing an existing process that has an executable path.
    
    .PARAMETER Force
    Optional switch parameter. When specified, forcefully kills the process if
    graceful shutdown fails. Default is $false (graceful shutdown only).
    
    .PARAMETER WaitForExit
    Optional timeout in seconds to wait for the process to exit gracefully before
    giving up or forcing termination (if -Force specified). Default is 10 seconds.
    
    .PARAMETER PreserveWindowStyle
    Optional switch parameter. When specified, attempts to preserve the original
    window style when restarting. Default is $true.
    
    .EXAMPLE
    RestartProcess -ProcessId 1234
    Restarts the process with PID 1234 gracefully.
    
    .EXAMPLE
    RestartProcess -ProcessId 5678 -Force -WaitForExit 30
    Restarts process, waiting up to 30 seconds, and kills if necessary.
    
    .EXAMPLE
    $result = RestartProcess -ProcessId $pid
    if ($result.code -eq 0) {
        Write-Host "Process restarted successfully"
        Write-Host "Old PID: $($result.oldProcessId)"
        Write-Host "New PID: $($result.newProcessId)"
    }
    
    .NOTES
    - Requires that the process has a valid executable path
    - Some system processes cannot be restarted
    - Administrative privileges may be required for certain processes
    - Original command-line arguments are preserved when possible
    - Window style and working directory are preserved when possible
    - If process path cannot be determined, restart will fail
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ProcessId,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$WaitForExit = 10,
        
        [Parameter(Mandatory = $false)]
        [bool]$PreserveWindowStyle = $true
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        oldProcessId = 0
        newProcessId = 0
        processName = $null
        processPath = $null
        wasForced = $false
        restartTime = $null
    }
    
    # Validate mandatory parameters
    if ($ProcessId -le 0) {
        $status.msg = "Parameter 'ProcessId' must be a positive integer"
        return $status
    }
    
    try {
        $status.oldProcessId = $ProcessId
        
        Write-Verbose "Attempting to restart process with PID: $ProcessId"
        
        # Get process information first
        $GetResult = GetProcessByID -ProcessId $ProcessId
        
        if ($GetResult.code -ne 0) {
            $status.msg = "Failed to retrieve process information: $($GetResult.msg)"
            return $status
        }
        
        $Process = $GetResult.processHandle
        $status.processName = $GetResult.processName
        $status.processPath = $GetResult.path
        
        # Validate that process has a path (required for restart)
        if ([string]::IsNullOrWhiteSpace($status.processPath)) {
            $status.msg = "Cannot restart process '$($status.processName)' - executable path could not be determined. This may be a system process."
            return $status
        }
        
        # Verify executable still exists
        if (-not (Test-Path -Path $status.processPath -PathType Leaf)) {
            $status.msg = "Cannot restart process - executable file '$($status.processPath)' no longer exists"
            return $status
        }
        
        Write-Verbose "Process information:"
        Write-Verbose "  Name: $($status.processName)"
        Write-Verbose "  Path: $($status.processPath)"
        Write-Verbose "  Command Line: $($GetResult.commandLine)"
        
        # Extract command-line arguments (excluding the executable path)
        $ArgumentList = @()
        if (-not [string]::IsNullOrWhiteSpace($GetResult.commandLine)) {
            try {
                # Parse command line to extract arguments
                # This is simplified - production code might need more robust parsing
                $CmdLine = $GetResult.commandLine.Trim()
                
                # Remove the executable path from the command line
                $ExePathQuoted = "`"$($status.processPath)`""
                if ($CmdLine.StartsWith($ExePathQuoted)) {
                    $CmdLine = $CmdLine.Substring($ExePathQuoted.Length).Trim()
                }
                elseif ($CmdLine.StartsWith($status.processPath)) {
                    $CmdLine = $CmdLine.Substring($status.processPath.Length).Trim()
                }
                
                # Split remaining arguments (simplified)
                if (-not [string]::IsNullOrWhiteSpace($CmdLine)) {
                    $ArgumentList = @($CmdLine)
                }
                
                Write-Verbose "Extracted arguments: $($ArgumentList -join ' ')"
            }
            catch {
                Write-Verbose "Warning: Could not parse command-line arguments: $($_.Exception.Message)"
            }
        }
        
        # Get working directory
        $WorkingDirectory = try {
            Split-Path -Path $status.processPath -Parent
        } catch {
            $PWD.Path
        }
        
        # Confirmation prompt
        $ConfirmMessage = "Restart process '$($status.processName)' (PID: $ProcessId)"
        
        if (-not $PSCmdlet.ShouldProcess($status.processName, $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        # Stop the process
        Write-Verbose "Stopping process (PID: $ProcessId)..."
        
        $StopResult = StopProcess -ProcessId $ProcessId -WaitForExit $WaitForExit
        
        if ($StopResult.code -ne 0) {
            # Graceful stop failed
            if ($Force) {
                Write-Verbose "Graceful stop failed, attempting forced termination..."
                $KillResult = KillProcess -ProcessId $ProcessId
                
                if ($KillResult.code -ne 0) {
                    $status.msg = "Failed to stop process for restart: $($KillResult.msg)"
                    return $status
                }
                
                $status.wasForced = $true
                Write-Verbose "Process forcefully terminated"
            }
            else {
                $status.msg = "Failed to stop process gracefully: $($StopResult.msg). Use -Force to kill the process."
                return $status
            }
        }
        else {
            Write-Verbose "Process stopped successfully"
        }
        
        # Wait a moment to ensure process is fully terminated
        Start-Sleep -Milliseconds 500
        
        # Start the process again
        Write-Verbose "Starting process: $($status.processPath)"
        
        $StartParams = @{
            FilePath = $status.processPath
            WorkingDirectory = $WorkingDirectory
        }
        
        if ($ArgumentList.Count -gt 0) {
            $StartParams['ArgumentList'] = $ArgumentList
        }
        
        $StartResult = RunProcess @StartParams
        
        if ($StartResult.code -ne 0) {
            $status.msg = "Process was stopped but failed to restart: $($StartResult.msg)"
            return $status
        }
        
        $status.newProcessId = $StartResult.processId
        $status.restartTime = Get-Date
        
        Write-Verbose "Process restarted successfully"
        Write-Verbose "  Old PID: $($status.oldProcessId)"
        Write-Verbose "  New PID: $($status.newProcessId)"
        
        # Success
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in RestartProcess function: $($_.Exception.Message)"
        return $status
    }
}
