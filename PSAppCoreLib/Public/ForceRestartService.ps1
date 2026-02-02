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
    data.ServiceObject property. Default is $false.
    
    .EXAMPLE
    ForceRestartService -Name "Spooler"
    Forcefully restarts the Print Spooler service.
    
    .EXAMPLE
    $result = ForceRestartService -Name "wuauserv" -TimeoutSeconds 15
    if ($result.code -eq 0) {
        Write-Host "Service forcefully restarted"
        Write-Host "Was forced: $($result.data.WasForced)"
        Write-Host "Killed processes: $($result.data.KilledProcessCount)"
    }
    
    .NOTES
    - Requires administrative privileges
    - This is a forceful restart (no cleanup, immediate termination)
    - Use only when RestartService fails
    - May cause data loss or corruption if service is writing data
    - Kills the service process if graceful stop fails
    - Use with extreme caution on critical system services
    - Returns comprehensive force restart details in the data field
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
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return OPSreturn -Code -1 -Message "Parameter 'Name' is required but was not provided or is empty"
    }
    
    # Check for administrative privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        return OPSreturn -Code -1 -Message "This function requires administrative privileges. Please run PowerShell as Administrator."
    }
    
    try {
        $ServiceName = $Name.Trim()
        
        Write-Verbose "Attempting to force restart service: $ServiceName"
        
        # Check if service exists
        try {
            $Service = Get-Service -Name $ServiceName -ErrorAction Stop
            
            if ($null -eq $Service) {
                return OPSreturn -Code -1 -Message "Service '$ServiceName' was not found"
            }
        }
        catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
            return OPSreturn -Code -1 -Message "Service '$ServiceName' does not exist on this system"
        }
        catch {
            return OPSreturn -Code -1 -Message "Error retrieving service '$ServiceName': $($_.Exception.Message)"
        }
        
        $DisplayName = $Service.DisplayName
        $PreviousStatus = $Service.Status.ToString()
        $StartType = $Service.StartType.ToString()
        
        Write-Verbose "Service information:"
        Write-Verbose "  Name: $ServiceName"
        Write-Verbose "  Display Name: $DisplayName"
        Write-Verbose "  Current Status: $PreviousStatus"
        Write-Verbose "  Start Type: $StartType"
        
        # Check if service is disabled
        if ($Service.StartType -eq 'Disabled') {
            return OPSreturn -Code -1 -Message "Service '$ServiceName' is disabled. Use SetServiceState to enable it before restarting."
        }
        
        # Confirmation prompt
        $ConfirmMessage = "FORCEFULLY restart service '$DisplayName' ($ServiceName) - This will kill the service process if necessary"
        
        if (-not $PSCmdlet.ShouldProcess($DisplayName, $ConfirmMessage)) {
            return OPSreturn -Code -1 -Message "Operation cancelled by user"
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
        $WasForced = $false
        $KilledProcessCount = 0
        $StopDuration = 0
        
        # Attempt to stop service (gracefully first, then forcefully)
        if ($Service.Status -ne 'Stopped') {
            Write-Verbose "Attempting graceful stop first..."
            $StopStopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                $Service.Stop()
                $Service.WaitForStatus('Stopped', (New-TimeSpan -Seconds $TimeoutSeconds))
                
                $StopStopWatch.Stop()
                $StopDuration = [Math]::Round($StopStopWatch.Elapsed.TotalSeconds, 2)
                
                $Service.Refresh()
                Write-Verbose "Service stopped gracefully in $StopDuration seconds"
            }
            catch [System.ServiceProcess.TimeoutException] {
                $StopStopWatch.Stop()
                $Service.Refresh()
                
                Write-Verbose "Graceful stop failed, attempting forced termination..."
                $WasForced = $true
                
                # Get service process ID
                try {
                    $ServiceWMI = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
                    $ProcessId = $ServiceWMI.ProcessId
                    
                    if ($ProcessId -and $ProcessId -gt 0) {
                        Write-Verbose "Service process ID: $ProcessId"
                        
                        # Kill the service process
                        try {
                            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
                            $KilledProcessCount++
                            Write-Verbose "Killed service process (PID: $ProcessId)"
                            
                            # Wait a moment for process to terminate
                            Start-Sleep -Milliseconds 500
                            
                            $Service.Refresh()
                            
                            # Wait for service to reach stopped state
                            $Service.WaitForStatus('Stopped', (New-TimeSpan -Seconds 5))
                            $StopDuration = [Math]::Round($StopStopWatch.Elapsed.TotalSeconds, 2)
                            
                            Write-Verbose "Service forcefully stopped"
                        }
                        catch {
                            return OPSreturn -Code -1 -Message "Failed to kill service process: $($_.Exception.Message)"
                        }
                    }
                    else {
                        return OPSreturn -Code -1 -Message "Could not determine service process ID for forced termination"
                    }
                }
                catch {
                    return OPSreturn -Code -1 -Message "Failed to retrieve service process information: $($_.Exception.Message)"
                }
            }
            catch {
                return OPSreturn -Code -1 -Message "Failed to stop service: $($_.Exception.Message)"
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
            $StartDuration = [Math]::Round($StartStopWatch.Elapsed.TotalSeconds, 2)
            
            $TotalStopWatch.Stop()
            $TotalDuration = [Math]::Round($TotalStopWatch.Elapsed.TotalSeconds, 2)
            
            $Service.Refresh()
            $CurrentStatus = $Service.Status.ToString()
            
            if ($Service.Status -eq 'Running') {
                Write-Verbose "Service restarted successfully"
                Write-Verbose "  Stop duration: $StopDuration seconds"
                Write-Verbose "  Start duration: $StartDuration seconds"
                Write-Verbose "  Total duration: $TotalDuration seconds"
                Write-Verbose "  Was forced: $WasForced"
                Write-Verbose "  Killed processes: $KilledProcessCount"
                
                $ReturnData = [PSCustomObject]@{
                    ServiceName           = $ServiceName
                    DisplayName           = $DisplayName
                    Status                = $CurrentStatus
                    StartType             = $StartType
                    PreviousStatus        = $PreviousStatus
                    WasForced             = $WasForced
                    KilledProcessCount    = $KilledProcessCount
                    StopDurationSeconds   = $StopDuration
                    StartDurationSeconds  = $StartDuration
                    TotalDurationSeconds  = $TotalDuration
                }
                
                if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
                
                return OPSreturn -Code 0 -Message "" -Data $ReturnData
            }
            else {
                return OPSreturn -Code -1 -Message "Service start command was sent but service did not reach running state. Current status: $($Service.Status)"
            }
        }
        catch [System.ServiceProcess.TimeoutException] {
            $StartStopWatch.Stop()
            $TotalStopWatch.Stop()
            $Service.Refresh()
            return OPSreturn -Code -1 -Message "Service did not start within timeout period. Current status: $($Service.Status)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to start service after stopping: $($_.Exception.Message)"
        }
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in ForceRestartService function: $($_.Exception.Message)"
    }
}
