function StopService {
    <#
    .SYNOPSIS
    Stops a Windows service by name.
    
    .DESCRIPTION
    The StopService function checks if a Windows service exists, validates its
    current state, and stops it gracefully if running. It waits for the service
    to reach the stopped state within a specified timeout period and reports
    detailed results through a standardized return object. Administrative
    privileges are required to stop services.
    
    .PARAMETER Name
    The name of the Windows service to stop. This is the service name, not the
    display name. Case-insensitive. Example: "wuauserv" for Windows Update.
    
    .PARAMETER TimeoutSeconds
    Optional timeout in seconds to wait for the service to stop. Default is 30 seconds.
    If the service doesn't reach stopped state within this time, returns an error.
    
    .PARAMETER Force
    Optional switch parameter. When specified, also stops dependent services
    that are running. Default is $false (fails if dependent services are running).
    
    .PARAMETER PassThru
    Optional switch parameter. When specified, returns the service object in the
    serviceObject property. Default is $false.
    
    .EXAMPLE
    StopService -Name "wuauserv"
    Stops the Windows Update service gracefully.
    
    .EXAMPLE
    $result = StopService -Name "Spooler" -TimeoutSeconds 60
    if ($result.code -eq 0) {
        Write-Host "Print Spooler stopped successfully"
        Write-Host "Stop duration: $($result.stopDurationSeconds) seconds"
    }
    
    .EXAMPLE
    # Stop service and its dependents
    StopService -Name "LanmanServer" -Force
    
    .NOTES
    - Requires administrative privileges
    - Service must exist
    - If service is already stopped, returns success immediately
    - By default, fails if dependent services are running (use -Force to stop them)
    - This is a graceful stop that allows the service to clean up
    - If graceful stop fails, use KillService for forced termination
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
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
        stoppedDependentServices = @()
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
        
        Write-Verbose "Attempting to stop service: $ServiceName"
        
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
        
        # Check if service is already stopped
        if ($Service.Status -eq 'Stopped') {
            $status.code = 0
            $status.msg = ""
            $status.status = "Stopped"
            if ($PassThru) { $status.serviceObject = $Service }
            Write-Verbose "Service is already stopped"
            return $status
        }
        
        # Check for dependent services that are running
        $DependentServices = $Service.DependentServices | Where-Object { $_.Status -eq 'Running' }
        if ($DependentServices.Count -gt 0) {
            Write-Verbose "Found $($DependentServices.Count) running dependent service(s):"
            foreach ($DepService in $DependentServices) {
                Write-Verbose "  - $($DepService.DisplayName) ($($DepService.Name))"
            }
            
            if (-not $Force) {
                $DepNames = ($DependentServices | ForEach-Object { $_.Name }) -join ', '
                $status.msg = "Cannot stop service '$ServiceName' because the following dependent services are running: $DepNames. Use -Force to stop dependent services."
                return $status
            }
            else {
                Write-Verbose "Force mode enabled - will stop dependent services first"
            }
        }
        
        # Confirmation prompt
        $ConfirmMessage = "Stop service '$($status.displayName)' ($ServiceName)"
        if ($DependentServices.Count -gt 0 -and $Force) {
            $ConfirmMessage += " and $($DependentServices.Count) dependent service(s)"
        }
        
        if (-not $PSCmdlet.ShouldProcess($status.displayName, $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Stop dependent services first if Force is specified
        if ($DependentServices.Count -gt 0 -and $Force) {
            Write-Verbose "Stopping dependent services first..."
            foreach ($DepService in $DependentServices) {
                try {
                    Write-Verbose "  Stopping: $($DepService.Name)"
                    $DepService.Stop()
                    $DepService.WaitForStatus('Stopped', (New-TimeSpan -Seconds $TimeoutSeconds))
                    $status.stoppedDependentServices += $DepService.Name
                    Write-Verbose "  Stopped: $($DepService.Name)"
                }
                catch {
                    Write-Verbose "  Warning: Failed to stop dependent service '$($DepService.Name)': $($_.Exception.Message)"
                }
            }
        }
        
        # Stop the main service
        try {
            Write-Verbose "Stopping service..."
            $Service.Stop()
            
            # Wait for service to reach stopped state
            Write-Verbose "Waiting for service to reach stopped state (timeout: $TimeoutSeconds seconds)..."
            $Service.WaitForStatus('Stopped', (New-TimeSpan -Seconds $TimeoutSeconds))
            
            $StopWatch.Stop()
            $status.stopDurationSeconds = [Math]::Round($StopWatch.Elapsed.TotalSeconds, 2)
            
            # Refresh service object
            $Service.Refresh()
            $status.status = $Service.Status.ToString()
            
            if ($Service.Status -eq 'Stopped') {
                Write-Verbose "Service stopped successfully"
                Write-Verbose "  Duration: $($status.stopDurationSeconds) seconds"
                if ($status.stoppedDependentServices.Count -gt 0) {
                    Write-Verbose "  Also stopped $($status.stoppedDependentServices.Count) dependent service(s)"
                }
                
                # Success
                $status.code = 0
                $status.msg = ""
                if ($PassThru) { $status.serviceObject = $Service }
                return $status
            }
            else {
                $status.msg = "Service stop command was sent but service did not reach stopped state. Current status: $($Service.Status)"
                return $status
            }
        }
        catch [System.ServiceProcess.TimeoutException] {
            $StopWatch.Stop()
            $Service.Refresh()
            $status.status = $Service.Status.ToString()
            $status.msg = "Service did not stop within timeout period of $TimeoutSeconds seconds. Current status: $($status.status). Use KillService for forced termination."
            return $status
        }
        catch [System.InvalidOperationException] {
            $status.msg = "Cannot stop service '$ServiceName': $($_.Exception.Message)"
            return $status
        }
        catch {
            $status.msg = "Failed to stop service '$ServiceName': $($_.Exception.Message)"
            return $status
        }
    }
    catch {
        $status.msg = "Unexpected error in StopService function: $($_.Exception.Message)"
        return $status
    }
}
