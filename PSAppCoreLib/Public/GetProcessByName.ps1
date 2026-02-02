function GetProcessByName {
    <#
    .SYNOPSIS
    Gets a process by exact name match and returns the process ID.
    
    .DESCRIPTION
    The GetProcessByName function searches for a process by its exact name
    (case-insensitive) and returns detailed information including the process ID.
    It requires an exact match of the process name and handles multiple instances
    of the same process. Returns detailed process information through OPSreturn
    standardized return pattern.
    
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
    $result = GetProcessByName -Name "notepad"
    if ($result.code -eq 0) {
        Write-Host "Found Notepad with PID: $($result.data.ProcessId)"
    }
    
    .EXAMPLE
    $result = GetProcessByName -Name "chrome" -SelectFirst
    if ($result.code -eq 0) {
        Write-Host "Found Chrome with PID: $($result.data.ProcessId)"
        Write-Host "Memory: $($result.data.WorkingSetMB) MB"
        Write-Host "Started: $($result.data.StartTime)"
    }
    
    .EXAMPLE
    $result = GetProcessByName -Name "svchost.exe" -IncludeExtension -SelectAll
    if ($result.code -eq 0) {
        Write-Host "Found $($result.data.ProcessCount) svchost processes"
        foreach ($proc in $result.data.Processes) {
            Write-Host "PID: $($proc.Id), Memory: $([Math]::Round($proc.WorkingSet64/1MB,2)) MB"
        }
    }
    
    .EXAMPLE
    # Check if process exists
    $result = GetProcessByName -Name "myapp"
    if ($result.code -eq 0) {
        Write-Host "Process is running with PID: $($result.data.ProcessId)"
    } else {
        Write-Host "Process not found: $($result.msg)"
    }
    
    .NOTES
    - Process name search is case-insensitive
    - Requires exact name match (no wildcards)
    - Returns error if multiple processes exist (unless -SelectFirst or -SelectAll)
    - Does not require .exe extension by default
    - Returns comprehensive process information in the data field
    - Use .data.ProcessHandle to access the Process object for further operations
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
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return OPSreturn -Code -1 -Message "Parameter 'Name' is required but was not provided or is empty"
    }
    
    # Validate parameter combinations
    if ($SelectFirst -and $SelectAll) {
        return OPSreturn -Code -1 -Message "Cannot specify both -SelectFirst and -SelectAll"
    }
    
    try {
        # Normalize process name
        $SearchName = $Name.Trim()
        
        # Remove .exe extension if not expected
        if (-not $IncludeExtension -and $SearchName -match '\\.exe$') {
            $SearchName = $SearchName -replace '\\.exe$', ''
            Write-Verbose "Removed .exe extension from search name: $SearchName"
        }
        
        Write-Verbose "Searching for process: $SearchName (Exact match required)"
        
        # Search for processes
        try {
            $MatchingProcesses = @(Get-Process -Name $SearchName -ErrorAction SilentlyContinue)
            
            if ($MatchingProcesses.Count -eq 0) {
                return OPSreturn -Code -1 -Message "No process found with name '$SearchName'"
            }
            
            $ProcessCount = $MatchingProcesses.Count
            Write-Verbose "Found $ProcessCount matching process(es)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Error searching for process '$SearchName': $($_.Exception.Message)"
        }
        
        # Initialize data variables
        $ProcessId = 0
        $ProcessHandle = $null
        $StartTime = $null
        $WorkingSetMB = 0
        $ProcessPath = $null
        $ProcessesList = @()
        
        # Handle multiple processes
        if ($MatchingProcesses.Count -gt 1) {
            if ($SelectAll) {
                # Return all matching processes
                $ProcessesList = $MatchingProcesses
                
                # Set first process as primary for backward compatibility
                $PrimaryProcess = $MatchingProcesses[0]
                $ProcessId = $PrimaryProcess.Id
                $ProcessHandle = $PrimaryProcess
                
                try {
                    $StartTime = $PrimaryProcess.StartTime
                    $WorkingSetMB = [Math]::Round($PrimaryProcess.WorkingSet64 / 1MB, 2)
                    $ProcessPath = $PrimaryProcess.Path
                }
                catch {
                    Write-Verbose "Warning: Could not retrieve all process details: $($_.Exception.Message)"
                }
                
                Write-Verbose "Returning all $ProcessCount processes (primary PID: $ProcessId)"
            }
            elseif ($SelectFirst) {
                # Return only the first process
                $SelectedProcess = $MatchingProcesses[0]
                $ProcessId = $SelectedProcess.Id
                $ProcessHandle = $SelectedProcess
                $ProcessesList = @($SelectedProcess)
                
                try {
                    $StartTime = $SelectedProcess.StartTime
                    $WorkingSetMB = [Math]::Round($SelectedProcess.WorkingSet64 / 1MB, 2)
                    $ProcessPath = $SelectedProcess.Path
                }
                catch {
                    Write-Verbose "Warning: Could not retrieve all process details: $($_.Exception.Message)"
                }
                
                Write-Verbose "Selected first process: PID $ProcessId (out of $ProcessCount total)"
            }
            else {
                # Multiple processes found but no selection mode specified
                $PIDs = ($MatchingProcesses | ForEach-Object { $_.Id }) -join ', '
                
                $ReturnData = [PSCustomObject]@{
                    ProcessName  = $SearchName
                    ProcessCount = $ProcessCount
                    Processes    = $MatchingProcesses
                    PIDs         = $PIDs
                }
                
                return OPSreturn -Code -1 -Message "Multiple processes found with name '$SearchName' (PIDs: $PIDs). Use -SelectFirst to get the first one or -SelectAll to get all." -Data $ReturnData
            }
        }
        else {
            # Single process found
            $SingleProcess = $MatchingProcesses[0]
            $ProcessId = $SingleProcess.Id
            $ProcessHandle = $SingleProcess
            $ProcessesList = @($SingleProcess)
            
            try {
                $StartTime = $SingleProcess.StartTime
                $WorkingSetMB = [Math]::Round($SingleProcess.WorkingSet64 / 1MB, 2)
                $ProcessPath = $SingleProcess.Path
            }
            catch {
                Write-Verbose "Warning: Could not retrieve all process details: $($_.Exception.Message)"
            }
            
            Write-Verbose "Found single process: PID $ProcessId"
        }
        
        Write-Verbose "Process details: Name=$SearchName, PID=$ProcessId, Memory=$WorkingSetMB MB"
        
        # Prepare return data object with comprehensive process details
        $ReturnData = [PSCustomObject]@{
            ProcessName    = $SearchName
            ProcessId      = $ProcessId
            ProcessHandle  = $ProcessHandle
            ProcessCount   = $ProcessCount
            Processes      = $ProcessesList
            StartTime      = $StartTime
            WorkingSetMB   = $WorkingSetMB
            Path           = $ProcessPath
        }
        
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in GetProcessByName function: $($_.Exception.Message)"
    }
}
