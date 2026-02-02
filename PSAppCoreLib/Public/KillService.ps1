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
    data.ServiceObject property. Default is $false.
    
    .EXAMPLE
    KillService -Name "Spooler"
    Forcefully kills the Print Spooler service process.
    
    .EXAMPLE
    $result = KillService -Name "wuauserv"
    if ($result.code -eq 0) {
        Write-Host "Service killed successfully"
        Write-Host "Killed processes: $($result.data.KilledProcessCount)"
        Write-Host "Termination time: $($result.data.TerminationDurationMs) ms"
    }
    
    .NOTES
    - Requires administrative privileges
    - This is a forceful termination that does NOT allow cleanup
    - Use StopService for graceful shutdown whenever possible
    - May cause data loss or corruption if service is writing data
    - Use with extreme caution on critical system services
    - The service can be restarted after killing
    - Returns comprehensive kill details including dependent services in the data field
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
        
        Write-Verbose "Attempting to kill service: $ServiceName"
        
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
        
        Write-Verbose "Service information:"
        Write-Verbose "  Name: $ServiceName"
        Write-Verbose "  Display Name: $DisplayName"
        Write-Verbose "  Current Status: $PreviousStatus"
        
        # Check if service is already stopped
        $Service.Refresh()
        if ($Service.Status -eq 'Stopped') {
            $ReturnData = [PSCustomObject]@{
                ServiceName             = $ServiceName
                DisplayName             = $DisplayName
                Status                  = "Stopped"
                PreviousStatus          = $PreviousStatus
                KilledProcessCount      = 0
                TerminationDurationMs   = 0
                KilledDependentServices = @()
            }
            
            if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
            
            Write-Verbose "Service is already stopped"
            return OPSreturn -Code 0 -Message "" -Data $ReturnData
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
        $ConfirmMessage = "FORCEFULLY kill service '$DisplayName' ($ServiceName) - This will immediately terminate the service process"
        if ($DependentServices.Count -gt 0 -and $KillDependentServices) {
            $ConfirmMessage += " and $($DependentServices.Count) dependent service(s)"
        }
        
        if (-not $PSCmdlet.ShouldProcess($DisplayName, $ConfirmMessage)) {
            return OPSreturn -Code -1 -Message "Operation cancelled by user"
        }
        
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $KilledProcessCount = 0
        $KilledDependentServices = @()
        
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
                        $KilledProcessCount++
                        $KilledDependentServices += $DepService.Name
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
                    $KilledProcessCount++
                    
                    $StopWatch.Stop()
                    $TerminationDuration = $StopWatch.ElapsedMilliseconds
                    
                    Write-Verbose "Killed service process (PID: $ProcessId) in $TerminationDuration ms"
                    
                    # Wait a moment and verify
                    Start-Sleep -Milliseconds 500
                    
                    $Service.Refresh()
                    $CurrentStatus = $Service.Status.ToString()
                    
                    Write-Verbose "Service terminated successfully"
                    Write-Verbose "  Killed processes: $KilledProcessCount"
                    if ($KilledDependentServices.Count -gt 0) {
                        Write-Verbose "  Also killed $($KilledDependentServices.Count) dependent service(s)"
                    }
                    
                    $ReturnData = [PSCustomObject]@{
                        ServiceName             = $ServiceName
                        DisplayName             = $DisplayName
                        Status                  = $CurrentStatus
                        PreviousStatus          = $PreviousStatus
                        KilledProcessCount      = $KilledProcessCount
                        TerminationDurationMs   = $TerminationDuration
                        KilledDependentServices = $KilledDependentServices
                    }
                    
                    if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
                    
                    return OPSreturn -Code 0 -Message "" -Data $ReturnData
                }
                catch {
                    return OPSreturn -Code -1 -Message "Failed to kill service process (PID: $ProcessId): $($_.Exception.Message)"
                }
            }
            else {
                return OPSreturn -Code -1 -Message "Service '$ServiceName' does not have an active process (ProcessId: $ProcessId)"
            }
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to retrieve service process information: $($_.Exception.Message)"
        }
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in KillService function: $($_.Exception.Message)"
    }
}
