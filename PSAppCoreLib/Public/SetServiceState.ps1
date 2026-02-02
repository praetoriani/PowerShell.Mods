function SetServiceState {
    <#
    .SYNOPSIS
    Changes the startup type of a Windows service.
    
    .DESCRIPTION
    The SetServiceState function modifies how a Windows service starts by changing
    its startup type (Automatic, Manual, Disabled, etc.). It validates the service
    exists, checks current configuration, applies the new startup type, and reports
    detailed results through a standardized return object. Administrative privileges
    are required to modify service configuration.
    
    .PARAMETER Name
    The name of the Windows service to configure. This is the service name, not the
    display name. Case-insensitive. Example: "wuauserv" for Windows Update.
    
    .PARAMETER StartupType
    The startup type to set for the service.
    Valid values:
    - 'Automatic' - Service starts automatically at boot
    - 'AutomaticDelayedStart' - Service starts automatically but delayed after boot
    - 'Manual' - Service must be started manually
    - 'Disabled' - Service cannot be started
    
    .PARAMETER PassThru
    Optional switch parameter. When specified, returns the service object in the
    serviceObject property. Default is $false.
    
    .EXAMPLE
    SetServiceState -Name "wuauserv" -StartupType "Manual"
    Sets Windows Update service to manual start.
    
    .EXAMPLE
    $result = SetServiceState -Name "Spooler" -StartupType "Automatic"
    if ($result.code -eq 0) {
        Write-Host "Print Spooler startup type changed"
        Write-Host "Previous: $($result.previousStartType)"
        Write-Host "Current: $($result.currentStartType)"
    }
    
    .EXAMPLE
    # Disable a service
    SetServiceState -Name "SysMain" -StartupType "Disabled"
    
    .EXAMPLE
    # Configure multiple services
    $services = @(
        @{Name="wuauserv"; Type="Manual"},
        @{Name="BITS"; Type="Manual"},
        @{Name="Spooler"; Type="Automatic"}
    )
    foreach ($svc in $services) {
        $result = SetServiceState -Name $svc.Name -StartupType $svc.Type
        Write-Host "$($svc.Name): $(if($result.code -eq 0){'Configured'}else{$result.msg})"
    }
    
    .NOTES
    - Requires administrative privileges
    - Service must exist
    - Does not start or stop the service, only changes startup configuration
    - AutomaticDelayedStart is supported on Windows Vista and later
    - Changing to Disabled will prevent the service from starting
    - Some system services should not be disabled
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Automatic', 'AutomaticDelayedStart', 'Manual', 'Disabled')]
        [string]$StartupType,
        
        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        serviceName = $null
        displayName = $null
        currentStatus = $null
        previousStartType = $null
        currentStartType = $null
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
        
        Write-Verbose "Attempting to configure service: $ServiceName"
        Write-Verbose "Target startup type: $StartupType"
        
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
        $status.currentStatus = $Service.Status.ToString()
        $status.previousStartType = $Service.StartType.ToString()
        
        Write-Verbose "Service information:"
        Write-Verbose "  Name: $($status.serviceName)"
        Write-Verbose "  Display Name: $($status.displayName)"
        Write-Verbose "  Current Status: $($status.currentStatus)"
        Write-Verbose "  Current Startup Type: $($status.previousStartType)"
        
        # Check if startup type is already set to the desired value
        if ($status.previousStartType -eq $StartupType) {
            $status.code = 0
            $status.msg = ""
            $status.currentStartType = $StartupType
            if ($PassThru) { $status.serviceObject = $Service }
            Write-Verbose "Service startup type is already set to '$StartupType'"
            return $status
        }
        
        # Confirmation prompt
        $ConfirmMessage = "Change startup type of service '$($status.displayName)' from '$($status.previousStartType)' to '$StartupType'"
        
        if (-not $PSCmdlet.ShouldProcess($status.displayName, $ConfirmMessage)) {
            $status.msg = "Operation cancelled by user"
            return $status
        }
        
        # Map startup type to Set-Service parameter
        $StartMode = switch ($StartupType) {
            'Automatic' { 'Automatic' }
            'AutomaticDelayedStart' { 'Automatic' }  # Will be set to delayed after
            'Manual' { 'Manual' }
            'Disabled' { 'Disabled' }
        }
        
        # Set the startup type
        try {
            Write-Verbose "Setting startup type to: $StartupType"
            
            Set-Service -Name $ServiceName -StartupType $StartMode -ErrorAction Stop
            
            # Handle AutomaticDelayedStart separately (requires registry or sc.exe)
            if ($StartupType -eq 'AutomaticDelayedStart') {
                try {
                    Write-Verbose "Configuring delayed auto-start..."
                    $null = sc.exe config $ServiceName start=delayed-auto 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        Write-Verbose "Warning: sc.exe returned exit code $LASTEXITCODE"
                    }
                }
                catch {
                    Write-Verbose "Warning: Could not set delayed auto-start: $($_.Exception.Message)"
                }
            }
            
            # Refresh service object
            Start-Sleep -Milliseconds 200
            $Service = Get-Service -Name $ServiceName -ErrorAction Stop
            $status.currentStartType = $Service.StartType.ToString()
            
            Write-Verbose "Startup type changed successfully"
            Write-Verbose "  Previous: $($status.previousStartType)"
            Write-Verbose "  Current: $($status.currentStartType)"
            
            # Success
            $status.code = 0
            $status.msg = ""
            if ($PassThru) { $status.serviceObject = $Service }
            return $status
        }
        catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
            $status.msg = "Service command error: $($_.Exception.Message)"
            return $status
        }
        catch [System.InvalidOperationException] {
            $status.msg = "Cannot change startup type: $($_.Exception.Message)"
            return $status
        }
        catch {
            $status.msg = "Failed to set startup type for service '$ServiceName': $($_.Exception.Message)"
            return $status
        }
    }
    catch {
        $status.msg = "Unexpected error in SetServiceState function: $($_.Exception.Message)"
        return $status
    }
}
