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
    data.ServiceObject property. Default is $false.
    
    .EXAMPLE
    StopService -Name "wuauserv"
    Stops the Windows Update service gracefully.
    
    .EXAMPLE
    $result = StopService -Name "Spooler" -TimeoutSeconds 60
    if ($result.code -eq 0) {
        Write-Host "Print Spooler stopped successfully"
        Write-Host "Stop duration: $($result.data.StopDurationSeconds) seconds"
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
    - Returns comprehensive stop details including dependent services in the data field
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
        
        Write-Verbose "Attempting to stop service: $ServiceName"
        
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
        
        # Check if service is already stopped
        if ($Service.Status -eq 'Stopped') {
            $ReturnData = [PSCustomObject]@{
                ServiceName                = $ServiceName
                DisplayName                = $DisplayName
                Status                     = "Stopped"
                StartType                  = $StartType
                PreviousStatus             = $PreviousStatus
                StopDurationSeconds        = 0
                StoppedDependentServices   = @()
            }
            
            if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
            
            Write-Verbose "Service is already stopped"
            return OPSreturn -Code 0 -Message "" -Data $ReturnData
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
                return OPSreturn -Code -1 -Message "Cannot stop service '$ServiceName' because the following dependent services are running: $DepNames. Use -Force to stop dependent services."
            }
            else {
                Write-Verbose "Force mode enabled - will stop dependent services first"
            }
        }
        
        # Confirmation prompt
        $ConfirmMessage = "Stop service '$DisplayName' ($ServiceName)"
        if ($DependentServices.Count -gt 0 -and $Force) {
            $ConfirmMessage += " and $($DependentServices.Count) dependent service(s)"
        }
        
        if (-not $PSCmdlet.ShouldProcess($DisplayName, $ConfirmMessage)) {
            return OPSreturn -Code -1 -Message "Operation cancelled by user"
        }
        
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $StoppedDependentServices = @()
        
        # Stop dependent services first if Force is specified
        if ($DependentServices.Count -gt 0 -and $Force) {
            Write-Verbose "Stopping dependent services first..."
            foreach ($DepService in $DependentServices) {
                try {
                    Write-Verbose "  Stopping: $($DepService.Name)"
                    $DepService.Stop()
                    $DepService.WaitForStatus('Stopped', (New-TimeSpan -Seconds $TimeoutSeconds))
                    $StoppedDependentServices += $DepService.Name
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
            $StopDuration = [Math]::Round($StopWatch.Elapsed.TotalSeconds, 2)
            
            # Refresh service object
            $Service.Refresh()
            $CurrentStatus = $Service.Status.ToString()
            
            if ($Service.Status -eq 'Stopped') {
                Write-Verbose "Service stopped successfully"
                Write-Verbose "  Duration: $StopDuration seconds"
                if ($StoppedDependentServices.Count -gt 0) {
                    Write-Verbose "  Also stopped $($StoppedDependentServices.Count) dependent service(s)"
                }
                
                $ReturnData = [PSCustomObject]@{
                    ServiceName                = $ServiceName
                    DisplayName                = $DisplayName
                    Status                     = $CurrentStatus
                    StartType                  = $StartType
                    PreviousStatus             = $PreviousStatus
                    StopDurationSeconds        = $StopDuration
                    StoppedDependentServices   = $StoppedDependentServices
                }
                
                if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
                
                return OPSreturn -Code 0 -Message "" -Data $ReturnData
            }
            else {
                return OPSreturn -Code -1 -Message "Service stop command was sent but service did not reach stopped state. Current status: $($Service.Status)"
            }
        }
        catch [System.ServiceProcess.TimeoutException] {
            $StopWatch.Stop()
            $Service.Refresh()
            return OPSreturn -Code -1 -Message "Service did not stop within timeout period of $TimeoutSeconds seconds. Current status: $($Service.Status). Use KillService for forced termination."
        }
        catch [System.InvalidOperationException] {
            return OPSreturn -Code -1 -Message "Cannot stop service '$ServiceName': $($_.Exception.Message)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to stop service '$ServiceName': $($_.Exception.Message)"
        }
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in StopService function: $($_.Exception.Message)"
    }
}
