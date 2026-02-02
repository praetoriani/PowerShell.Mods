function GetProcessByID {
    <#
    .SYNOPSIS
    Gets a process by process ID and returns a handle to the process.
    
    .DESCRIPTION
    The GetProcessByID function retrieves detailed information about a process
    using its process ID. It validates that the process exists, retrieves
    comprehensive process information, and returns a handle to the process
    through OPSreturn standardized return pattern. Requires exact match of the process ID.
    
    .PARAMETER ProcessId
    The process ID (PID) of the process to retrieve. Must be a valid positive integer
    representing an existing process.
    
    .PARAMETER IncludeModules
    Optional switch parameter. When specified, includes information about all
    loaded modules (DLLs) in the process. This can be resource-intensive for
    processes with many modules. Default is $false.
    
    .PARAMETER IncludeThreads
    Optional switch parameter. When specified, includes information about all
    threads in the process. Default is $false.
    
    .EXAMPLE
    $result = GetProcessByID -ProcessId 1234
    if ($result.code -eq 0) {
        Write-Host "Process Name: $($result.data.ProcessName)"
        Write-Host "Path: $($result.data.Path)"
        Write-Host "Memory: $($result.data.WorkingSetMB) MB"
    }
    
    .EXAMPLE
    $result = GetProcessByID -ProcessId $pid
    if ($result.code -eq 0) {
        Write-Host "Process Name: $($result.data.ProcessName)"
        Write-Host "Path: $($result.data.Path)"
        Write-Host "Memory: $($result.data.WorkingSetMB) MB"
        Write-Host "Threads: $($result.data.ThreadCount)"
        Write-Host "Start Time: $($result.data.StartTime)"
    }
    
    .EXAMPLE
    $result = GetProcessByID -ProcessId 5678 -IncludeModules
    if ($result.code -eq 0) {
        Write-Host "Loaded $($result.data.Modules.Count) modules:"
        foreach ($module in $result.data.Modules) {
            Write-Host "  $($module.ModuleName) - $($module.FileName)"
        }
    }
    
    .EXAMPLE
    # Check if process is still running
    $result = GetProcessByID -ProcessId 9999
    if ($result.code -eq 0 -and -not $result.data.HasExited) {
        Write-Host "Process is running"
    } else {
        Write-Host "Process not found or has exited"
    }
    
    .NOTES
    - Requires that the process exists and is accessible
    - Some process details may not be accessible due to permissions
    - System processes may require administrative privileges to access
    - Returns process handle that can be used for further operations
    - Process handle should be disposed when no longer needed
    - Returns comprehensive process information in the data field
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ProcessId,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeModules,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeThreads
    )
    
    # Validate mandatory parameters
    if ($ProcessId -le 0) {
        return OPSreturn -Code -1 -Message "Parameter 'ProcessId' must be a positive integer"
    }
    
    try {
        Write-Verbose "Retrieving process with PID: $ProcessId"
        
        # Get process by ID
        try {
            $Process = Get-Process -Id $ProcessId -ErrorAction Stop
            
            if ($null -eq $Process) {
                return OPSreturn -Code -1 -Message "Process with ID $ProcessId was not found"
            }
        }
        catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
            return OPSreturn -Code -1 -Message "Process with ID $ProcessId does not exist"
        }
        catch {
            return OPSreturn -Code -1 -Message "Error retrieving process with ID $ProcessId`: $($_.Exception.Message)"
        }
        
        # Initialize data collection variables
        $ProcessName = $Process.ProcessName
        $ProcessPath = $null
        $CommandLine = $null
        $WorkingSetMB = 0
        $PrivateMemoryMB = 0
        $VirtualMemoryMB = 0
        $ThreadCount = 0
        $HandleCount = 0
        $StartTime = $null
        $TotalProcessorTime = $null
        $HasExited = $Process.HasExited
        $ExitCode = $null
        $ModulesList = @()
        $ThreadsList = @()
        $ModuleCount = 0
        
        Write-Verbose "Found process: $ProcessName (PID: $ProcessId)"
        
        # Get detailed information (some may fail for system processes)
        try {
            $ProcessPath = $Process.Path
        }
        catch {
            Write-Verbose "Warning: Could not retrieve process path: $($_.Exception.Message)"
        }
        
        try {
            $CommandLine = $Process.CommandLine
        }
        catch {
            Write-Verbose "Warning: Could not retrieve command line"
        }
        
        try {
            $WorkingSetMB = [Math]::Round($Process.WorkingSet64 / 1MB, 2)
            $PrivateMemoryMB = [Math]::Round($Process.PrivateMemorySize64 / 1MB, 2)
            $VirtualMemoryMB = [Math]::Round($Process.VirtualMemorySize64 / 1MB, 2)
        }
        catch {
            Write-Verbose "Warning: Could not retrieve memory information: $($_.Exception.Message)"
        }
        
        try {
            $ThreadCount = $Process.Threads.Count
            $HandleCount = $Process.HandleCount
        }
        catch {
            Write-Verbose "Warning: Could not retrieve thread/handle count: $($_.Exception.Message)"
        }
        
        try {
            $StartTime = $Process.StartTime
            $TotalProcessorTime = $Process.TotalProcessorTime
        }
        catch {
            Write-Verbose "Warning: Could not retrieve timing information: $($_.Exception.Message)"
        }
        
        # Check if process has exited
        if ($HasExited) {
            try {
                $ExitCode = $Process.ExitCode
                Write-Verbose "Process has exited with code: $ExitCode"
            }
            catch {
                Write-Verbose "Warning: Could not retrieve exit code"
            }
        }
        
        # Include modules if requested
        if ($IncludeModules) {
            Write-Verbose "Retrieving loaded modules..."
            try {
                $ModulesList = @($Process.Modules)
                $ModuleCount = $ModulesList.Count
                Write-Verbose "Found $ModuleCount loaded modules"
            }
            catch {
                Write-Verbose "Warning: Could not retrieve modules: $($_.Exception.Message)"
            }
        }
        
        # Include threads if requested
        if ($IncludeThreads) {
            Write-Verbose "Retrieving thread information..."
            try {
                $ThreadsList = @($Process.Threads)
                Write-Verbose "Found $($ThreadsList.Count) threads"
            }
            catch {
                Write-Verbose "Warning: Could not retrieve threads: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "Process details retrieved successfully"
        Write-Verbose "  Name: $ProcessName"
        Write-Verbose "  Path: $ProcessPath"
        Write-Verbose "  Working Set: $WorkingSetMB MB"
        Write-Verbose "  Threads: $ThreadCount"
        Write-Verbose "  Handles: $HandleCount"
        
        # Prepare return data object with comprehensive process details
        $ReturnData = [PSCustomObject]@{
            ProcessId           = $ProcessId
            ProcessName         = $ProcessName
            ProcessHandle       = $Process
            Path                = $ProcessPath
            CommandLine         = $CommandLine
            WorkingSetMB        = $WorkingSetMB
            PrivateMemoryMB     = $PrivateMemoryMB
            VirtualMemoryMB     = $VirtualMemoryMB
            ThreadCount         = $ThreadCount
            HandleCount         = $HandleCount
            StartTime           = $StartTime
            TotalProcessorTime  = $TotalProcessorTime
            HasExited           = $HasExited
            ExitCode            = $ExitCode
            ModuleCount         = $ModuleCount
            Modules             = $ModulesList
            Threads             = $ThreadsList
        }
        
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in GetProcessByID function: $($_.Exception.Message)"
    }
}
