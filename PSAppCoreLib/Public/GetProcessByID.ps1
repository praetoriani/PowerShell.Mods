function GetProcessByID {
    <#
    .SYNOPSIS
    Gets a process by process ID and returns a handle to the process.
    
    .DESCRIPTION
    The GetProcessByID function retrieves detailed information about a process
    using its process ID. It validates that the process exists, retrieves
    comprehensive process information, and returns a handle to the process
    through a standardized return object. Requires exact match of the process ID.
    
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
    GetProcessByID -ProcessId 1234
    Retrieves information about the process with PID 1234.
    
    .EXAMPLE
    $result = GetProcessByID -ProcessId $pid
    if ($result.code -eq 0) {
        Write-Host "Process Name: $($result.processName)"
        Write-Host "Path: $($result.path)"
        Write-Host "Memory: $($result.workingSetMB) MB"
        Write-Host "Threads: $($result.threadCount)"
        Write-Host "Start Time: $($result.startTime)"
    }
    
    .EXAMPLE
    $result = GetProcessByID -ProcessId 5678 -IncludeModules
    foreach ($module in $result.modules) {
        Write-Host "Module: $($module.ModuleName) - $($module.FileName)"
    }
    
    .EXAMPLE
    # Check if process is still running
    $result = GetProcessByID -ProcessId 9999
    if ($result.code -eq 0 -and -not $result.hasExited) {
        Write-Host "Process is running"
    }
    
    .NOTES
    - Requires that the process exists and is accessible
    - Some process details may not be accessible due to permissions
    - System processes may require administrative privileges to access
    - Returns process handle that can be used for further operations
    - Process handle should be disposed when no longer needed
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
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        processId = 0
        processName = $null
        processHandle = $null
        path = $null
        commandLine = $null
        workingSetMB = 0
        privateMemoryMB = 0
        virtualMemoryMB = 0
        threadCount = 0
        handleCount = 0
        startTime = $null
        totalProcessorTime = $null
        hasExited = $false
        exitCode = $null
        modules = @()
        threads = @()
    }
    
    # Validate mandatory parameters
    if ($ProcessId -le 0) {
        $status.msg = "Parameter 'ProcessId' must be a positive integer"
        return $status
    }
    
    try {
        $status.processId = $ProcessId
        
        Write-Verbose "Retrieving process with PID: $ProcessId"
        
        # Get process by ID
        try {
            $Process = Get-Process -Id $ProcessId -ErrorAction Stop
            
            if ($null -eq $Process) {
                $status.msg = "Process with ID $ProcessId was not found"
                return $status
            }
        }
        catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
            $status.msg = "Process with ID $ProcessId does not exist"
            return $status
        }
        catch {
            $status.msg = "Error retrieving process with ID $ProcessId`: $($_.Exception.Message)"
            return $status
        }
        
        # Populate basic process information
        try {
            $status.processHandle = $Process
            $status.processName = $Process.ProcessName
            $status.hasExited = $Process.HasExited
            
            Write-Verbose "Found process: $($status.processName) (PID: $ProcessId)"
            
            # Get detailed information (some may fail for system processes)
            try {
                $status.path = $Process.Path
            }
            catch {
                Write-Verbose "Warning: Could not retrieve process path: $($_.Exception.Message)"
                $status.path = $null
            }
            
            try {
                $status.commandLine = $Process.CommandLine
            }
            catch {
                Write-Verbose "Warning: Could not retrieve command line"
                $status.commandLine = $null
            }
            
            try {
                $status.workingSetMB = [Math]::Round($Process.WorkingSet64 / 1MB, 2)
                $status.privateMemoryMB = [Math]::Round($Process.PrivateMemorySize64 / 1MB, 2)
                $status.virtualMemoryMB = [Math]::Round($Process.VirtualMemorySize64 / 1MB, 2)
            }
            catch {
                Write-Verbose "Warning: Could not retrieve memory information: $($_.Exception.Message)"
            }
            
            try {
                $status.threadCount = $Process.Threads.Count
                $status.handleCount = $Process.HandleCount
            }
            catch {
                Write-Verbose "Warning: Could not retrieve thread/handle count: $($_.Exception.Message)"
            }
            
            try {
                $status.startTime = $Process.StartTime
                $status.totalProcessorTime = $Process.TotalProcessorTime
            }
            catch {
                Write-Verbose "Warning: Could not retrieve timing information: $($_.Exception.Message)"
            }
            
            # Check if process has exited
            if ($status.hasExited) {
                try {
                    $status.exitCode = $Process.ExitCode
                    Write-Verbose "Process has exited with code: $($status.exitCode)"
                }
                catch {
                    Write-Verbose "Warning: Could not retrieve exit code"
                }
            }
            
            # Include modules if requested
            if ($IncludeModules) {
                Write-Verbose "Retrieving loaded modules..."
                try {
                    $status.modules = @($Process.Modules)
                    Write-Verbose "Found $($status.modules.Count) loaded modules"
                }
                catch {
                    Write-Verbose "Warning: Could not retrieve modules: $($_.Exception.Message)"
                    $status.modules = @()
                }
            }
            
            # Include threads if requested
            if ($IncludeThreads) {
                Write-Verbose "Retrieving thread information..."
                try {
                    $status.threads = @($Process.Threads)
                    Write-Verbose "Found $($status.threads.Count) threads"
                }
                catch {
                    Write-Verbose "Warning: Could not retrieve threads: $($_.Exception.Message)"
                    $status.threads = @()
                }
            }
        }
        catch {
            $status.msg = "Error retrieving process details for PID $ProcessId`: $($_.Exception.Message)"
            return $status
        }
        
        # Success
        $status.code = 0
        $status.msg = ""
        
        Write-Verbose "Process details retrieved successfully"
        Write-Verbose "  Name: $($status.processName)"
        Write-Verbose "  Path: $($status.path)"
        Write-Verbose "  Working Set: $($status.workingSetMB) MB"
        Write-Verbose "  Threads: $($status.threadCount)"
        Write-Verbose "  Handles: $($status.handleCount)"
        
        return $status
    }
    catch {
        $status.msg = "Unexpected error in GetProcessByID function: $($_.Exception.Message)"
        return $status
    }
}
