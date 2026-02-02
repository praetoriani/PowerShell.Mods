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
    data.ServiceObject property. Default is $false.
    
    .EXAMPLE
    RestartService -Name "Spooler"
    Restarts the Print Spooler service gracefully.
    
    .EXAMPLE
    $result = RestartService -Name "wuauserv" -TimeoutSeconds 90
    if ($result.code -eq 0) {
        Write-Host "Windows Update service restarted"
        Write-Host "Stop duration: $($result.data.StopDurationSeconds) seconds"
        Write-Host "Start duration: $($result.data.StartDurationSeconds) seconds"
        Write-Host "Total duration: $($result.data.TotalDurationSeconds) seconds"
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
    - Returns comprehensive restart timing in the data field
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
        
        Write-Verbose "Attempting to restart service: $ServiceName"
        
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
        $ConfirmMessage = "Restart service '$DisplayName' ($ServiceName)"
        
        if (-not $PSCmdlet.ShouldProcess($DisplayName, $ConfirmMessage)) {
            return OPSreturn -Code -1 -Message "Operation cancelled by user"
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
        
        $StopDuration = 0
        
        # Stop the service if it's running
        if ($Service.Status -ne 'Stopped') {
            Write-Verbose "Stopping service..."
            $StopStopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                $Service.Stop()
                $Service.WaitForStatus('Stopped', (New-TimeSpan -Seconds $StopTimeout))
                
                $StopStopWatch.Stop()
                $StopDuration = [Math]::Round($StopStopWatch.Elapsed.TotalSeconds, 2)
                
                $Service.Refresh()
                Write-Verbose "Service stopped successfully in $StopDuration seconds"
            }
            catch [System.ServiceProcess.TimeoutException] {
                $StopStopWatch.Stop()
                $Service.Refresh()
                return OPSreturn -Code -1 -Message "Service did not stop within timeout period of $StopTimeout seconds. Current status: $($Service.Status). Use ForceRestartService for forceful restart."
            }
            catch {
                return OPSreturn -Code -1 -Message "Failed to stop service: $($_.Exception.Message)"
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
                
                $ReturnData = [PSCustomObject]@{
                    ServiceName           = $ServiceName
                    DisplayName           = $DisplayName
                    Status                = $CurrentStatus
                    StartType             = $StartType
                    PreviousStatus        = $PreviousStatus
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
            return OPSreturn -Code -1 -Message "Service did not start within timeout period of $StartTimeout seconds. Current status: $($Service.Status)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to start service after stopping: $($_.Exception.Message)"
        }
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in RestartService function: $($_.Exception.Message)"
    }
}
