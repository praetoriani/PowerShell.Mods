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
    data.ServiceObject property. Default is $false.
    
    .EXAMPLE
    StartService -Name "wuauserv"
    Starts the Windows Update service.
    
    .EXAMPLE
    $result = StartService -Name "Spooler" -TimeoutSeconds 60
    if ($result.code -eq 0) {
        Write-Host "Print Spooler started successfully"
        Write-Host "Status: $($result.data.Status)"
        Write-Host "Start time: $($result.data.StartDurationSeconds) seconds"
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
    - Returns comprehensive service start details in the data field
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
        
        Write-Verbose "Attempting to start service: $ServiceName"
        
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
            return OPSreturn -Code -1 -Message "Service '$ServiceName' is disabled. Use SetServiceState to enable it before starting."
        }
        
        # Check if service is already running
        if ($Service.Status -eq 'Running') {
            $ReturnData = [PSCustomObject]@{
                ServiceName          = $ServiceName
                DisplayName          = $DisplayName
                Status               = "Running"
                StartType            = $StartType
                PreviousStatus       = $PreviousStatus
                StartDurationSeconds = 0
            }
            
            if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
            
            Write-Verbose "Service is already running"
            return OPSreturn -Code 0 -Message "" -Data $ReturnData
        }
        
        # Check for pending states
        if ($Service.Status -in @('StartPending', 'StopPending', 'ContinuePending', 'PausePending')) {
            Write-Verbose "Service is in pending state: $($Service.Status)"
            Write-Verbose "Waiting for pending operation to complete..."
            
            try {
                $Service.WaitForStatus('Running', (New-TimeSpan -Seconds $TimeoutSeconds))
                $Service.Refresh()
                
                if ($Service.Status -eq 'Running') {
                    $ReturnData = [PSCustomObject]@{
                        ServiceName          = $ServiceName
                        DisplayName          = $DisplayName
                        Status               = "Running"
                        StartType            = $StartType
                        PreviousStatus       = $PreviousStatus
                        StartDurationSeconds = 0
                    }
                    
                    if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
                    
                    Write-Verbose "Service reached running state after pending operation"
                    return OPSreturn -Code 0 -Message "" -Data $ReturnData
                }
            }
            catch [System.ServiceProcess.TimeoutException] {
                return OPSreturn -Code -1 -Message "Service is stuck in '$($Service.Status)' state. Timeout waiting for state change."
            }
        }
        
        # Confirmation prompt
        $ConfirmMessage = "Start service '$DisplayName' ($ServiceName)"
        
        if (-not $PSCmdlet.ShouldProcess($DisplayName, $ConfirmMessage)) {
            return OPSreturn -Code -1 -Message "Operation cancelled by user"
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
            $StartDuration = [Math]::Round($StopWatch.Elapsed.TotalSeconds, 2)
            
            # Refresh service object
            $Service.Refresh()
            $CurrentStatus = $Service.Status.ToString()
            
            if ($Service.Status -eq 'Running') {
                Write-Verbose "Service started successfully"
                Write-Verbose "  Duration: $StartDuration seconds"
                
                $ReturnData = [PSCustomObject]@{
                    ServiceName          = $ServiceName
                    DisplayName          = $DisplayName
                    Status               = $CurrentStatus
                    StartType            = $StartType
                    PreviousStatus       = $PreviousStatus
                    StartDurationSeconds = $StartDuration
                }
                
                if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
                
                return OPSreturn -Code 0 -Message "" -Data $ReturnData
            }
            else {
                return OPSreturn -Code -1 -Message "Service start command was sent but service did not reach running state. Current status: $($Service.Status)"
            }
        }
        catch [System.ServiceProcess.TimeoutException] {
            $StopWatch.Stop()
            $Service.Refresh()
            return OPSreturn -Code -1 -Message "Service did not start within timeout period of $TimeoutSeconds seconds. Current status: $($Service.Status)"
        }
        catch [System.InvalidOperationException] {
            return OPSreturn -Code -1 -Message "Cannot start service '$ServiceName': $($_.Exception.Message). Check service configuration and dependencies."
        }
        catch [System.ComponentModel.Win32Exception] {
            return OPSreturn -Code -1 -Message "Win32 error starting service: $($_.Exception.Message) (Error code: $($_.Exception.NativeErrorCode))"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to start service '$ServiceName': $($_.Exception.Message)"
        }
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in StartService function: $($_.Exception.Message)"
    }
}
