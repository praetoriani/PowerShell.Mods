function GetProcessByName {
    <#
    .SYNOPSIS
    Gets a process by exact name match and returns the process ID.
    
    .DESCRIPTION
    The GetProcessByName function searches for a process by its exact name
    (case-insensitive) and returns detailed information including the process ID.
    It requires an exact match of the process name and handles multiple instances
    of the same process. Returns detailed process information through a
    standardized return object.
    
    .PARAMETER Name
    The exact name of the process to find (without .exe extension).
    The search is case-insensitive but requires an exact match.
    Examples: "notepad", "chrome", "powershell"
    
    .PARAMETER IncludeExtension
    Optional switch parameter. When specified, expects the full process name
    including the .exe extension. Default is $false (extension not required).
    
    .PARAMETER SelectFirst
    Optional switch parameter. When multiple processes with the same name exist,
    returns only the first one. When not specified and multiple processes exist,
    returns an error. Default is $false.
    
    .PARAMETER SelectAll
    Optional switch parameter. When specified, returns information about all
    processes matching the name. The processes property will contain an array
    of all matching processes. Default is $false.
    
    .EXAMPLE
    GetProcessByName -Name "notepad"
    Finds the notepad process and returns its process ID.
    
    .EXAMPLE
    $result = GetProcessByName -Name "chrome" -SelectFirst
    if ($result.code -eq 0) {
        Write-Host "Found Chrome with PID: $($result.processId)"
        Write-Host "Memory: $([Math]::Round($result.workingSetMB, 2)) MB"
    }
    
    .EXAMPLE
    $result = GetProcessByName -Name "svchost.exe" -IncludeExtension -SelectAll
    Write-Host "Found $($result.processCount) svchost processes"
    foreach ($proc in $result.processes) {
        Write-Host "PID: $($proc.Id), Memory: $($proc.WorkingSet64)"
    }
    
    .EXAMPLE
    # Check if process exists
    $result = GetProcessByName -Name "myapp"
    if ($result.code -eq 0) {
        Write-Host "Process is running with PID: $($result.processId)"
    } else {
        Write-Host "Process not found"
    }
    
    .NOTES
    - Process name search is case-insensitive
    - Requires exact name match (no wildcards)
    - Returns error if multiple processes exist (unless -SelectFirst or -SelectAll)
    - Does not require .exe extension by default
    - Returns detailed process information including memory usage and start time
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeExtension,
        
        [Parameter(Mandatory = $false)]
        [switch]$SelectFirst,
        
        [Parameter(Mandatory = $false)]
        [switch]$SelectAll
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        processName = $null
        processId = 0
        processHandle = $null
        processCount = 0
        processes = @()
        startTime = $null
        workingSetMB = 0
        path = $null
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $status.msg = "Parameter 'Name' is required but was not provided or is empty"
        return $status
    }
    
    # Validate parameter combinations
    if ($SelectFirst -and $SelectAll) {
        $status.msg = "Cannot specify both -SelectFirst and -SelectAll"
        return $status
    }
    
    try {
        # Normalize process name
        $SearchName = $Name.Trim()
        
        # Remove .exe extension if not expected
        if (-not $IncludeExtension -and $SearchName -match '\.exe$') {
            $SearchName = $SearchName -replace '\.exe$', ''
            Write-Verbose "Removed .exe extension from search name: $SearchName"
        }
        
        $status.processName = $SearchName
        
        Write-Verbose "Searching for process: $SearchName (Exact match required)"
        
        # Search for processes
        try {
            $MatchingProcesses = @(Get-Process -Name $SearchName -ErrorAction SilentlyContinue)
            
            if ($MatchingProcesses.Count -eq 0) {
                $status.msg = "No process found with name '$SearchName'"
                return $status
            }
            
            $status.processCount = $MatchingProcesses.Count
            Write-Verbose "Found $($status.processCount) matching process(es)"
        }
        catch {
            $status.msg = "Error searching for process '$SearchName': $($_.Exception.Message)"
            return $status
        }
        
        # Handle multiple processes
        if ($MatchingProcesses.Count -gt 1) {
            if ($SelectAll) {
                # Return all matching processes
                $status.processes = $MatchingProcesses
                
                # Set first process as primary for backward compatibility
                $PrimaryProcess = $MatchingProcesses[0]
                $status.processId = $PrimaryProcess.Id
                $status.processHandle = $PrimaryProcess
                
                try {
                    $status.startTime = $PrimaryProcess.StartTime
                    $status.workingSetMB = [Math]::Round($PrimaryProcess.WorkingSet64 / 1MB, 2)
                    $status.path = $PrimaryProcess.Path
                }
                catch {
                    Write-Verbose "Warning: Could not retrieve all process details: $($_.Exception.Message)"
                }
                
                Write-Verbose "Returning all $($status.processCount) processes (primary PID: $($status.processId))"
            }
            elseif ($SelectFirst) {
                # Return only the first process
                $SelectedProcess = $MatchingProcesses[0]
                $status.processId = $SelectedProcess.Id
                $status.processHandle = $SelectedProcess
                $status.processes = @($SelectedProcess)
                
                try {
                    $status.startTime = $SelectedProcess.StartTime
                    $status.workingSetMB = [Math]::Round($SelectedProcess.WorkingSet64 / 1MB, 2)
                    $status.path = $SelectedProcess.Path
                }
                catch {
                    Write-Verbose "Warning: Could not retrieve all process details: $($_.Exception.Message)"
                }
                
                Write-Verbose "Selected first process: PID $($status.processId) (out of $($status.processCount) total)"
            }
            else {
                # Multiple processes found but no selection mode specified
                $PIDs = ($MatchingProcesses | ForEach-Object { $_.Id }) -join ', '
                $status.msg = "Multiple processes found with name '$SearchName' (PIDs: $PIDs). Use -SelectFirst to get the first one or -SelectAll to get all."
                $status.processes = $MatchingProcesses
                return $status
            }
        }
        else {
            # Single process found
            $SingleProcess = $MatchingProcesses[0]
            $status.processId = $SingleProcess.Id
            $status.processHandle = $SingleProcess
            $status.processes = @($SingleProcess)
            
            try {
                $status.startTime = $SingleProcess.StartTime
                $status.workingSetMB = [Math]::Round($SingleProcess.WorkingSet64 / 1MB, 2)
                $status.path = $SingleProcess.Path
            }
            catch {
                Write-Verbose "Warning: Could not retrieve all process details: $($_.Exception.Message)"
            }
            
            Write-Verbose "Found single process: PID $($status.processId)"
        }
        
        # Success
        $status.code = 0
        $status.msg = ""
        
        Write-Verbose "Process details: Name=$($status.processName), PID=$($status.processId), Memory=$($status.workingSetMB) MB"
        
        return $status
    }
    catch {
        $status.msg = "Unexpected error in GetProcessByName function: $($_.Exception.Message)"
        return $status
    }
}
