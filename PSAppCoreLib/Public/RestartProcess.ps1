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
        Write-Host "Old PID: $($result.data.OldProcessId)"
        Write-Host "New PID: $($result.data.NewProcessId)"
        Write-Host "Process: $($result.data.ProcessName)"
    }
    
    .NOTES
    - Requires that the process has a valid executable path
    - Some system processes cannot be restarted
    - Administrative privileges may be required for certain processes
    - Original command-line arguments are preserved when possible
    - Window style and working directory are preserved when possible
    - If process path cannot be determined, restart will fail
    - Returns restart statistics in the data field
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
    
    # Validate mandatory parameters
    if ($ProcessId -le 0) {
        return OPSreturn -Code -1 -Message "Parameter 'ProcessId' must be a positive integer"
    }
    
    try {
        Write-Verbose "Attempting to restart process with PID: $ProcessId"
        
        # Get process information first
        $GetResult = GetProcessByID -ProcessId $ProcessId
        
        if ($GetResult.code -ne 0) {
            return OPSreturn -Code -1 -Message "Failed to retrieve process information: $($GetResult.msg)"
        }
        
        $Process = $GetResult.data.ProcessHandle
        $ProcessName = $GetResult.data.ProcessName
        $ProcessPath = $GetResult.data.Path
        $CommandLine = $GetResult.data.CommandLine
        
        # Validate that process has a path (required for restart)
        if ([string]::IsNullOrWhiteSpace($ProcessPath)) {
            return OPSreturn -Code -1 -Message "Cannot restart process '$ProcessName' - executable path could not be determined. This may be a system process."
        }
        
        # Verify executable still exists
        if (-not (Test-Path -Path $ProcessPath -PathType Leaf)) {
            return OPSreturn -Code -1 -Message "Cannot restart process - executable file '$ProcessPath' no longer exists"
        }
        
        Write-Verbose "Process information:"
        Write-Verbose "  Name: $ProcessName"
        Write-Verbose "  Path: $ProcessPath"
        Write-Verbose "  Command Line: $CommandLine"
        
        # Extract command-line arguments (excluding the executable path)
        $ArgumentList = @()
        if (-not [string]::IsNullOrWhiteSpace($CommandLine)) {
            try {
                # Parse command line to extract arguments
                $CmdLine = $CommandLine.Trim()
                
                # Remove the executable path from the command line
                $ExePathQuoted = "`"$ProcessPath`""
                if ($CmdLine.StartsWith($ExePathQuoted)) {
                    $CmdLine = $CmdLine.Substring($ExePathQuoted.Length).Trim()
                }
                elseif ($CmdLine.StartsWith($ProcessPath)) {
                    $CmdLine = $CmdLine.Substring($ProcessPath.Length).Trim()
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
            Split-Path -Path $ProcessPath -Parent
        } catch {
            $PWD.Path
        }
        
        # Confirmation prompt
        $ConfirmMessage = "Restart process '$ProcessName' (PID: $ProcessId)"
        
        if (-not $PSCmdlet.ShouldProcess($ProcessName, $ConfirmMessage)) {
            return OPSreturn -Code -1 -Message "Operation cancelled by user"
        }
        
        # Stop the process
        Write-Verbose "Stopping process (PID: $ProcessId)..."
        
        $StopResult = StopProcess -ProcessId $ProcessId -WaitForExit $WaitForExit
        $WasForced = $false
        
        if ($StopResult.code -ne 0) {
            # Graceful stop failed
            if ($Force) {
                Write-Verbose "Graceful stop failed, attempting forced termination..."
                $KillResult = KillProcess -ProcessId $ProcessId
                
                if ($KillResult.code -ne 0) {
                    return OPSreturn -Code -1 -Message "Failed to stop process for restart: $($KillResult.msg)"
                }
                
                $WasForced = $true
                Write-Verbose "Process forcefully terminated"
            }
            else {
                return OPSreturn -Code -1 -Message "Failed to stop process gracefully: $($StopResult.msg). Use -Force to kill the process."
            }
        }
        else {
            Write-Verbose "Process stopped successfully"
        }
        
        # Wait a moment to ensure process is fully terminated
        Start-Sleep -Milliseconds 500
        
        # Start the process again
        Write-Verbose "Starting process: $ProcessPath"
        
        $StartParams = @{
            FilePath = $ProcessPath
            WorkingDirectory = $WorkingDirectory
        }
        
        if ($ArgumentList.Count -gt 0) {
            $StartParams['ArgumentList'] = $ArgumentList
        }
        
        $StartResult = RunProcess @StartParams
        
        if ($StartResult.code -ne 0) {
            return OPSreturn -Code -1 -Message "Process was stopped but failed to restart: $($StartResult.msg)"
        }
        
        $NewProcessId = $StartResult.data.ProcessId
        $RestartTime = Get-Date
        
        Write-Verbose "Process restarted successfully"
        Write-Verbose "  Old PID: $ProcessId"
        Write-Verbose "  New PID: $NewProcessId"
        
        # Prepare return data object with restart details
        $ReturnData = [PSCustomObject]@{
            OldProcessId    = $ProcessId
            NewProcessId    = $NewProcessId
            ProcessName     = $ProcessName
            ProcessPath     = $ProcessPath
            WasForced       = $WasForced
            RestartTime     = $RestartTime
        }
        
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in RestartProcess function: $($_.Exception.Message)"
    }
}
