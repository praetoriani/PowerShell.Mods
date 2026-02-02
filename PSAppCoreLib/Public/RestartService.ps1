function RestartService {
    <#
    .SYNOPSIS
    Restarts a Windows service by name.
    
    .DESCRIPTION
    The RestartService function checks if a Windows service exists and restarts it
    gracefully. It stops the service (if running), waits for it to stop completely,
    then starts it again. This is a graceful restart that allows the service to
    clean up properly. Reports detailed results through a standardized return object.
    Administrative privileges are required.
    
    .PARAMETER Name
    The name of the Windows service to restart. This is the service name, not the
    display name. Case-insensitive. Example: "wuauserv" for Windows Update.
    
    .PARAMETER TimeoutSeconds
    Optional timeout in seconds to wait for the service to stop and start.
    Default is 60 seconds (30 for stop, 30 for start).
    
    .PARAMETER PassThru
    Optional switch parameter. When specified, returns the service object in the
    serviceObject property. Default is $false.
    
    .EXAMPLE
    RestartService -Name "Spooler"
    Restarts the Print Spooler service gracefully.
    
    .EXAMPLE
    $result = RestartService -Name "wuauserv" -TimeoutSeconds 90
    if ($result.code -eq 0) {
        Write-Host "Windows Update service restarted"
        Write-Host "Stop duration: $($result.stopDurationSeconds) seconds"
        Write-Host "Start duration: $($result.startDurationSeconds) seconds"
        Write-Host "Total duration: $($result.totalDurationSeconds) seconds"
    }
    
    .EXAMPLE
    # Restart multiple services
    $services = @("W32Time", "Dhcp", "Dnscache")
    foreach ($svc in $services) {
        $result = RestartService -Name $svc
        Write-Host "$svc`: $(if($result.code -eq 0){'Restarted'}else{$result.msg})"
    }
    
    .NOTES
    - Requires administrative privileges
    - Service must exist and not be disabled
    - This is a graceful restart (allows service to clean up)
    - If service is stopped, it will be started
    - If graceful restart fails, use ForceRestartService
    - Dependent services may be affected
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 60,
        
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
        
        Write-Verbose "Attempting to restart service: $ServiceName"
        
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
        $ConfirmMessage = "Restart service '$($status.displayName)' ($ServiceName)"
        
        if (-not $PSCmdlet.ShouldProcess($status.displayName, $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        # Check for dependent services
        $DependentServices = $Service.DependentServices | Where-Object { $_.Status -eq 'Running' }
        if ($DependentServices.Count -gt 0) {
            Write-Verbose "Warning: $($DependentServices.Count) dependent service(s) are running and may be affected:"
            foreach ($DepService in $DependentServices) {
                Write-Verbose "  - $($DepService.DisplayName) ($($DepService.Name))"
            }
        }
        
        $TotalStopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $StopTimeout = [Math]::Floor($TimeoutSeconds / 2)
        $StartTimeout = $TimeoutSeconds - $StopTimeout
        
        # Stop the service if it's running
        if ($Service.Status -ne 'Stopped') {
            Write-Verbose "Stopping service..."
            $StopStopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                $Service.Stop()
                $Service.WaitForStatus('Stopped', (New-TimeSpan -Seconds $StopTimeout))
                
                $StopStopWatch.Stop()
                $status.stopDurationSeconds = [Math]::Round($StopStopWatch.Elapsed.TotalSeconds, 2)
                
                $Service.Refresh()
                Write-Verbose "Service stopped successfully in $($status.stopDurationSeconds) seconds"
            }
            catch [System.ServiceProcess.TimeoutException] {
                $StopStopWatch.Stop()
                $Service.Refresh()
                $status.msg = "Service did not stop within timeout period of $StopTimeout seconds. Current status: $($Service.Status). Use ForceRestartService for forceful restart."
                return $status
            }
            catch {
                $status.msg = "Failed to stop service: $($_.Exception.Message)"
                return $status
            }
        }
        else {
            Write-Verbose "Service is already stopped"
        }
        
        # Start the service
        Write-Verbose "Starting service..."
        $StartStopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $Service.Start()
            $Service.WaitForStatus('Running', (New-TimeSpan -Seconds $StartTimeout))
            
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
            $status.msg = "Service did not start within timeout period of $StartTimeout seconds. Current status: $($status.status)"
            return $status
        }
        catch {
            $status.msg = "Failed to start service after stopping: $($_.Exception.Message)"
            return $status
        }
    }
    catch {
        $status.msg = "Unexpected error in RestartService function: $($_.Exception.Message)"
        return $status
    }
}
