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
    data.ServiceObject property. Default is $false.
    
    .EXAMPLE
    SetServiceState -Name "wuauserv" -StartupType "Manual"
    Sets Windows Update service to manual start.
    
    .EXAMPLE
    $result = SetServiceState -Name "Spooler" -StartupType "Automatic"
    if ($result.code -eq 0) {
        Write-Host "Print Spooler startup type changed"
        Write-Host "Previous: $($result.data.PreviousStartType)"
        Write-Host "Current: $($result.data.CurrentStartType)"
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
    - Returns comprehensive configuration change details in the data field
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
        
        Write-Verbose "Attempting to configure service: $ServiceName"
        Write-Verbose "Target startup type: $StartupType"
        
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
        $CurrentStatus = $Service.Status.ToString()
        $PreviousStartType = $Service.StartType.ToString()
        
        Write-Verbose "Service information:"
        Write-Verbose "  Name: $ServiceName"
        Write-Verbose "  Display Name: $DisplayName"
        Write-Verbose "  Current Status: $CurrentStatus"
        Write-Verbose "  Current Startup Type: $PreviousStartType"
        
        # Check if startup type is already set to the desired value
        if ($PreviousStartType -eq $StartupType) {
            $ReturnData = [PSCustomObject]@{
                ServiceName        = $ServiceName
                DisplayName        = $DisplayName
                CurrentStatus      = $CurrentStatus
                PreviousStartType  = $PreviousStartType
                CurrentStartType   = $StartupType
            }
            
            if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
            
            Write-Verbose "Service startup type is already set to '$StartupType'"
            return OPSreturn -Code 0 -Message "" -Data $ReturnData
        }
        
        # Confirmation prompt
        $ConfirmMessage = "Change startup type of service '$DisplayName' from '$PreviousStartType' to '$StartupType'"
        
        if (-not $PSCmdlet.ShouldProcess($DisplayName, $ConfirmMessage)) {
            return OPSreturn -Code -1 -Message "Operation cancelled by user"
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
            $NewStartType = $Service.StartType.ToString()
            
            Write-Verbose "Startup type changed successfully"
            Write-Verbose "  Previous: $PreviousStartType"
            Write-Verbose "  Current: $NewStartType"
            
            $ReturnData = [PSCustomObject]@{
                ServiceName        = $ServiceName
                DisplayName        = $DisplayName
                CurrentStatus      = $CurrentStatus
                PreviousStartType  = $PreviousStartType
                CurrentStartType   = $NewStartType
            }
            
            if ($PassThru) { $ReturnData | Add-Member -NotePropertyName ServiceObject -NotePropertyValue $Service }
            
            return OPSreturn -Code 0 -Message "" -Data $ReturnData
        }
        catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
            return OPSreturn -Code -1 -Message "Service command error: $($_.Exception.Message)"
        }
        catch [System.InvalidOperationException] {
            return OPSreturn -Code -1 -Message "Cannot change startup type: $($_.Exception.Message)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to set startup type for service '$ServiceName': $($_.Exception.Message)"
        }
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in SetServiceState function: $($_.Exception.Message)"
    }
}
