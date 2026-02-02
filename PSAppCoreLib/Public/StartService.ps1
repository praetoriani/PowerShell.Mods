function StartService {
    <#
    .SYNOPSIS
    Starts a Windows service by name.
    
    .DESCRIPTION
    The StartService function checks if a Windows service exists, validates its
    current state, and starts it if not already running. It waits for the service
    to reach the running state within a specified timeout period and reports
    detailed results through a standardized return object. Administrative
    privileges are required to start services.
    
    .PARAMETER Name
    The name of the Windows service to start. This is the service name, not the
    display name. Case-insensitive. Example: "wuauserv" for Windows Update.
    
    .PARAMETER TimeoutSeconds
    Optional timeout in seconds to wait for the service to start. Default is 30 seconds.
    If the service doesn't reach running state within this time, returns an error.
    
    .PARAMETER PassThru
    Optional switch parameter. When specified, returns the service object in the
    serviceObject property. Default is $false.
    
    .EXAMPLE
    StartService -Name "wuauserv"
    Starts the Windows Update service.
    
    .EXAMPLE
    $result = StartService -Name "Spooler" -TimeoutSeconds 60
    if ($result.code -eq 0) {
        Write-Host "Print Spooler started successfully"
        Write-Host "Status: $($result.status)"
        Write-Host "Start time: $($result.startDurationSeconds) seconds"
    }
    
    .EXAMPLE
    # Start multiple services
    $services = @("wuauserv", "BITS", "CryptSvc")
    foreach ($svc in $services) {
        $result = StartService -Name $svc
        Write-Host "$svc`: $(if($result.code -eq 0){'Started'}else{$result.msg})"
    }
    
    .NOTES
    - Requires administrative privileges
    - Service must exist and not be disabled
    - If service is already running, returns success immediately
    - Checks for dependent services that must be running first
    - Some services may have startup dependencies that must be satisfied
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
        startDurationSeconds = 0
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
        
        Write-Verbose "Attempting to start service: $ServiceName"
        
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
            $status.msg = "Service '$ServiceName' is disabled. Use SetServiceState to enable it before starting."
            return $status
        }
        
        # Check if service is already running
        if ($Service.Status -eq 'Running') {
            $status.code = 0
            $status.msg = ""
            $status.status = "Running"
            if ($PassThru) { $status.serviceObject = $Service }
            Write-Verbose "Service is already running"
            return $status
        }
        
        # Check for pending states
        if ($Service.Status -in @('StartPending', 'StopPending', 'ContinuePending', 'PausePending')) {
            Write-Verbose "Service is in pending state: $($Service.Status)"
            Write-Verbose "Waiting for pending operation to complete..."
            
            try {
                $Service.WaitForStatus('Running', (New-TimeSpan -Seconds $TimeoutSeconds))
                $Service.Refresh()
                
                if ($Service.Status -eq 'Running') {
                    $status.code = 0
                    $status.msg = ""
                    $status.status = "Running"
                    if ($PassThru) { $status.serviceObject = $Service }
                    Write-Verbose "Service reached running state after pending operation"
                    return $status
                }
            }
            catch [System.ServiceProcess.TimeoutException] {
                $status.msg = "Service is stuck in '$($Service.Status)' state. Timeout waiting for state change."
                return $status
            }
        }
        
        # Confirmation prompt
        $ConfirmMessage = "Start service '$($status.displayName)' ($ServiceName)"
        
        if (-not $PSCmdlet.ShouldProcess($status.displayName, $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        # Check for dependent services that must be running
        $DependentServices = $Service.ServicesDependedOn
        if ($DependentServices.Count -gt 0) {
            Write-Verbose "Service depends on $($DependentServices.Count) other service(s)"
            
            foreach ($DepService in $DependentServices) {
                Write-Verbose "  Dependency: $($DepService.Name) - Status: $($DepService.Status)"
                
                if ($DepService.Status -ne 'Running') {
                    Write-Verbose "  Warning: Dependent service '$($DepService.Name)' is not running"
                }
            }
        }
        
        # Attempt to start the service
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            Write-Verbose "Starting service..."
            $Service.Start()
            
            # Wait for service to reach running state
            Write-Verbose "Waiting for service to reach running state (timeout: $TimeoutSeconds seconds)..."
            $Service.WaitForStatus('Running', (New-TimeSpan -Seconds $TimeoutSeconds))
            
            $StopWatch.Stop()
            $status.startDurationSeconds = [Math]::Round($StopWatch.Elapsed.TotalSeconds, 2)
            
            # Refresh service object
            $Service.Refresh()
            $status.status = $Service.Status.ToString()
            
            if ($Service.Status -eq 'Running') {
                Write-Verbose "Service started successfully"
                Write-Verbose "  Duration: $($status.startDurationSeconds) seconds"
                
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
            $StopWatch.Stop()
            $Service.Refresh()
            $status.status = $Service.Status.ToString()
            $status.msg = "Service did not start within timeout period of $TimeoutSeconds seconds. Current status: $($status.status)"
            return $status
        }
        catch [System.InvalidOperationException] {
            $status.msg = "Cannot start service '$ServiceName': $($_.Exception.Message). Check service configuration and dependencies."
            return $status
        }
        catch [System.ComponentModel.Win32Exception] {
            $status.msg = "Win32 error starting service: $($_.Exception.Message) (Error code: $($_.Exception.NativeErrorCode))"
            return $status
        }
        catch {
            $status.msg = "Failed to start service '$ServiceName': $($_.Exception.Message)"
            return $status
        }
    }
    catch {
        $status.msg = "Unexpected error in StartService function: $($_.Exception.Message)"
        return $status
    }
}
