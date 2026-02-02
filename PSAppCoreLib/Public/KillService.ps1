function KillService {
    <#
    .SYNOPSIS
    Forcefully terminates a Windows service by name.
    
    .DESCRIPTION
    The KillService function checks if a Windows service exists and forcefully
    terminates it by killing its process. This is an immediate termination that
    does not allow the service to clean up. It should be used only when StopService
    fails. Reports detailed results through a standardized return object.
    Administrative privileges are required.
    
    .PARAMETER Name
    The name of the Windows service to kill. This is the service name, not the
    display name. Case-insensitive. Example: "wuauserv" for Windows Update.
    
    .PARAMETER KillDependentServices
    Optional switch parameter. When specified, also kills dependent services.
    Default is $false.
    
    .PARAMETER PassThru
    Optional switch parameter. When specified, returns the service object in the
    serviceObject property. Default is $false.
    
    .EXAMPLE
    KillService -Name "Spooler"
    Forcefully kills the Print Spooler service process.
    
    .EXAMPLE
    $result = KillService -Name "wuauserv"
    if ($result.code -eq 0) {
        Write-Host "Service killed successfully"
        Write-Host "Killed processes: $($result.killedProcessCount)"
        Write-Host "Termination time: $($result.terminationDurationMs) ms"
    }
    
    .NOTES
    - Requires administrative privileges
    - This is a forceful termination that does NOT allow cleanup
    - Use StopService for graceful shutdown whenever possible
    - May cause data loss or corruption if service is writing data
    - Use with extreme caution on critical system services
    - The service can be restarted after killing
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
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
        previousStatus = $null
        killedProcessCount = 0
        terminationDurationMs = 0
        killedDependentServices = @()
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
        
        Write-Verbose "Attempting to kill service: $ServiceName"
        
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
        
        Write-Verbose "Service information:"
        Write-Verbose "  Name: $($status.serviceName)"
        Write-Verbose "  Display Name: $($status.displayName)"
        Write-Verbose "  Current Status: $($status.previousStatus)"
        
        # Check if service is already stopped
        $Service.Refresh()
        if ($Service.Status -eq 'Stopped') {
            $status.code = 0
            $status.msg = ""
            $status.status = "Stopped"
            if ($PassThru) { $status.serviceObject = $Service }
            Write-Verbose "Service is already stopped"
            return $status
        }
        
        # Check for dependent services
        $DependentServices = $Service.DependentServices | Where-Object { $_.Status -ne 'Stopped' }
        if ($DependentServices.Count -gt 0) {
            Write-Verbose "Found $($DependentServices.Count) running dependent service(s):"
            foreach ($DepService in $DependentServices) {
                Write-Verbose "  - $($DepService.DisplayName) ($($DepService.Name))"
            }
            
            if ($KillDependentServices) {
                Write-Verbose "KillDependentServices is enabled - dependent services will be killed"
            }
        }
        
        # Confirmation prompt
        $ConfirmMessage = "FORCEFULLY kill service '$($status.displayName)' ($ServiceName) - This will immediately terminate the service process"
        if ($DependentServices.Count -gt 0 -and $KillDependentServices) {
            $ConfirmMessage += " and $($DependentServices.Count) dependent service(s)"
        }
        
        if (-not $PSCmdlet.ShouldProcess($status.displayName, $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Kill dependent services first if requested
        if ($DependentServices.Count -gt 0 -and $KillDependentServices) {
            Write-Verbose "Killing dependent services first..."
            foreach ($DepService in $DependentServices) {
                try {
                    Write-Verbose "  Killing: $($DepService.Name)"
                    
                    # Get process ID for dependent service
                    $DepServiceWMI = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($DepService.Name)'" -ErrorAction SilentlyContinue
                    if ($DepServiceWMI -and $DepServiceWMI.ProcessId -gt 0) {
                        Stop-Process -Id $DepServiceWMI.ProcessId -Force -ErrorAction Stop
                        $status.killedProcessCount++
                        $status.killedDependentServices += $DepService.Name
                        Write-Verbose "  Killed: $($DepService.Name) (PID: $($DepServiceWMI.ProcessId))"
                    }
                }
                catch {
                    Write-Verbose "  Warning: Failed to kill dependent service '$($DepService.Name)': $($_.Exception.Message)"
                }
            }
        }
        
        # Get service process ID
        try {
            $ServiceWMI = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
            $ProcessId = $ServiceWMI.ProcessId
            
            if ($ProcessId -and $ProcessId -gt 0) {
                Write-Verbose "Service process ID: $ProcessId"
                
                # Kill the service process
                try {
                    Write-Verbose "Killing service process..."
                    Stop-Process -Id $ProcessId -Force -ErrorAction Stop
                    $status.killedProcessCount++
                    
                    $StopWatch.Stop()
                    $status.terminationDurationMs = $StopWatch.ElapsedMilliseconds
                    
                    Write-Verbose "Killed service process (PID: $ProcessId) in $($status.terminationDurationMs) ms"
                    
                    # Wait a moment and verify
                    Start-Sleep -Milliseconds 500
                    
                    $Service.Refresh()
                    $status.status = $Service.Status.ToString()
                    
                    Write-Verbose "Service terminated successfully"
                    Write-Verbose "  Killed processes: $($status.killedProcessCount)"
                    if ($status.killedDependentServices.Count -gt 0) {
                        Write-Verbose "  Also killed $($status.killedDependentServices.Count) dependent service(s)"
                    }
                    
                    # Success
                    $status.code = 0
                    $status.msg = ""
                    if ($PassThru) { $status.serviceObject = $Service }
                    return $status
                }
                catch {
                    $status.msg = "Failed to kill service process (PID: $ProcessId): $($_.Exception.Message)"
                    return $status
                }
            }
            else {
                $status.msg = "Service '$ServiceName' does not have an active process (ProcessId: $ProcessId)"
                return $status
            }
        }
        catch {
            $status.msg = "Failed to retrieve service process information: $($_.Exception.Message)"
            return $status
        }
    }
    catch {
        $status.msg = "Unexpected error in KillService function: $($_.Exception.Message)"
        return $status
    }
}
