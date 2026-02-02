function ForceRestartService {
    <#
    .SYNOPSIS
    Forcefully restarts a Windows service by name.
    
    .DESCRIPTION
    The ForceRestartService function checks if a Windows service exists and restarts
    it forcefully. If the service doesn't stop gracefully, it kills the service
    process to force termination. This should be used when RestartService fails.
    Reports detailed results through a standardized return object. Administrative
    privileges are required.
    
    .PARAMETER Name
    The name of the Windows service to force restart. This is the service name,
    not the display name. Case-insensitive. Example: "wuauserv" for Windows Update.
    
    .PARAMETER TimeoutSeconds
    Optional timeout in seconds to wait for graceful stop before forcing.
    Default is 10 seconds for graceful stop attempt.
    
    .PARAMETER KillDependentServices
    Optional switch parameter. When specified, also forcefully stops dependent
    services if necessary. Default is $false.
    
    .PARAMETER PassThru
    Optional switch parameter. When specified, returns the service object in the
    serviceObject property. Default is $false.
    
    .EXAMPLE
    ForceRestartService -Name "Spooler"
    Forcefully restarts the Print Spooler service.
    
    .EXAMPLE
    $result = ForceRestartService -Name "wuauserv" -TimeoutSeconds 15
    if ($result.code -eq 0) {
        Write-Host "Service forcefully restarted"
        Write-Host "Was forced: $($result.wasForced)"
        Write-Host "Killed processes: $($result.killedProcessCount)"
    }
    
    .NOTES
    - Requires administrative privileges
    - This is a forceful restart (no cleanup, immediate termination)
    - Use only when RestartService fails
    - May cause data loss or corruption if service is writing data
    - Kills the service process if graceful stop fails
    - Use with extreme caution on critical system services
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 60)]
        [int]$TimeoutSeconds = 10,
        
        [Parameter(Mandatory = $false)]
        [switch]$KillDependentServices,
        
        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        serviceName = $null
        displayName = $null
        status = $null
        startType = $null
        previousStatus = $null
        wasForced = $false
        killedProcessCount = 0
        stopDurationSeconds = 0
        startDurationSeconds = 0
        totalDurationSeconds = 0
        serviceObject = $null
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $status.msg = "Parameter 'Name' is required but was not provided or is empty"
        return $status
    }
    
    # Check for administrative privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        $status.msg = "This function requires administrative privileges. Please run PowerShell as Administrator."
        return $status
    }
    
    try {
        $ServiceName = $Name.Trim()
        $status.serviceName = $ServiceName
        
        Write-Verbose "Attempting to force restart service: $ServiceName"
        
        # Check if service exists
        try {
            $Service = Get-Service -Name $ServiceName -ErrorAction Stop
            
            if ($null -eq $Service) {
                $status.msg = "Service '$ServiceName' was not found"
                return $status
            }
        }
        catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
            $status.msg = "Service '$ServiceName' does not exist on this system"
            return $status
        }
        catch {
            $status.msg = "Error retrieving service '$ServiceName': $($_.Exception.Message)"
            return $status
        }
        
        # Populate service information
        $status.displayName = $Service.DisplayName
        $status.previousStatus = $Service.Status.ToString()
        $status.startType = $Service.StartType.ToString()
        
        Write-Verbose "Service information:"
        Write-Verbose "  Name: $($status.serviceName)"
        Write-Verbose "  Display Name: $($status.displayName)"
        Write-Verbose "  Current Status: $($status.previousStatus)"
        Write-Verbose "  Start Type: $($status.startType)"
        
        # Check if service is disabled
        if ($Service.StartType -eq 'Disabled') {
            $status.msg = "Service '$ServiceName' is disabled. Use SetServiceState to enable it before restarting."
            return $status
        }
        
        # Confirmation prompt
        $ConfirmMessage = "FORCEFULLY restart service '$($status.displayName)' ($ServiceName) - This will kill the service process if necessary"
        
        if (-not $PSCmdlet.ShouldProcess($status.displayName, $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        # Check for dependent services
        $DependentServices = $Service.DependentServices | Where-Object { $_.Status -eq 'Running' }
        if ($DependentServices.Count -gt 0) {
            Write-Verbose "Warning: $($DependentServices.Count) dependent service(s) are running:"
            foreach ($DepService in $DependentServices) {
                Write-Verbose "  - $($DepService.DisplayName) ($($DepService.Name))"
            }
            
            if ($KillDependentServices) {
                Write-Verbose "KillDependentServices is enabled - dependent services will be stopped if necessary"
            }
        }
        
        $TotalStopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Attempt to stop service (gracefully first, then forcefully)
        if ($Service.Status -ne 'Stopped') {
            Write-Verbose "Attempting graceful stop first..."
            $StopStopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                $Service.Stop()
                $Service.WaitForStatus('Stopped', (New-TimeSpan -Seconds $TimeoutSeconds))
                
                $StopStopWatch.Stop()
                $status.stopDurationSeconds = [Math]::Round($StopStopWatch.Elapsed.TotalSeconds, 2)
                
                $Service.Refresh()
                Write-Verbose "Service stopped gracefully in $($status.stopDurationSeconds) seconds"
            }
            catch [System.ServiceProcess.TimeoutException] {
                $StopStopWatch.Stop()
                $Service.Refresh()
                
                Write-Verbose "Graceful stop failed, attempting forced termination..."
                $status.wasForced = $true
                
                # Get service process ID
                try {
                    $ServiceWMI = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
                    $ProcessId = $ServiceWMI.ProcessId
                    
                    if ($ProcessId -and $ProcessId -gt 0) {
                        Write-Verbose "Service process ID: $ProcessId"
                        
                        # Kill the service process
                        try {
                            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
                            $status.killedProcessCount++
                            Write-Verbose "Killed service process (PID: $ProcessId)"
                            
                            # Wait a moment for process to terminate
                            Start-Sleep -Milliseconds 500
                            
                            $Service.Refresh()
                            
                            # Wait for service to reach stopped state
                            $Service.WaitForStatus('Stopped', (New-TimeSpan -Seconds 5))
                            $status.stopDurationSeconds = [Math]::Round($StopStopWatch.Elapsed.TotalSeconds, 2)
                            
                            Write-Verbose "Service forcefully stopped"
                        }
                        catch {
                            $status.msg = "Failed to kill service process: $($_.Exception.Message)"
                            return $status
                        }
                    }
                    else {
                        $status.msg = "Could not determine service process ID for forced termination"
                        return $status
                    }
                }
                catch {
                    $status.msg = "Failed to retrieve service process information: $($_.Exception.Message)"
                    return $status
                }
            }
            catch {
                $status.msg = "Failed to stop service: $($_.Exception.Message)"
                return $status
            }
        }
        else {
            Write-Verbose "Service is already stopped"
        }
        
        # Wait a moment before restarting
        Start-Sleep -Milliseconds 500
        
        # Start the service
        Write-Verbose "Starting service..."
        $StartStopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $Service.Start()
            $Service.WaitForStatus('Running', (New-TimeSpan -Seconds 30))
            
            $StartStopWatch.Stop()
            $status.startDurationSeconds = [Math]::Round($StartStopWatch.Elapsed.TotalSeconds, 2)
            
            $TotalStopWatch.Stop()
            $status.totalDurationSeconds = [Math]::Round($TotalStopWatch.Elapsed.TotalSeconds, 2)
            
            $Service.Refresh()
            $status.status = $Service.Status.ToString()
            
            if ($Service.Status -eq 'Running') {
                Write-Verbose "Service restarted successfully"
                Write-Verbose "  Stop duration: $($status.stopDurationSeconds) seconds"
                Write-Verbose "  Start duration: $($status.startDurationSeconds) seconds"
                Write-Verbose "  Total duration: $($status.totalDurationSeconds) seconds"
                Write-Verbose "  Was forced: $($status.wasForced)"
                Write-Verbose "  Killed processes: $($status.killedProcessCount)"
                
                # Success
                $status.code = 0
                $status.msg = ""
                if ($PassThru) { $status.serviceObject = $Service }
                return $status
            }
            else {
                $status.msg = "Service start command was sent but service did not reach running state. Current status: $($Service.Status)"
                return $status
            }
        }
        catch [System.ServiceProcess.TimeoutException] {
            $StartStopWatch.Stop()
            $TotalStopWatch.Stop()
            $Service.Refresh()
            $status.status = $Service.Status.ToString()
            $status.msg = "Service did not start within timeout period. Current status: $($status.status)"
            return $status
        }
        catch {
            $status.msg = "Failed to start service after stopping: $($_.Exception.Message)"
            return $status
        }
    }
    catch {
        $status.msg = "Unexpected error in ForceRestartService function: $($_.Exception.Message)"
        return $status
    }
}
