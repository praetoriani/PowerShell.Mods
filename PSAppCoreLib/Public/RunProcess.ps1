function RunProcess {
    <#
    .SYNOPSIS
    Starts a new process and returns the process ID on success.
    
    .DESCRIPTION
    The RunProcess function starts a new process (typically an executable file) with
    comprehensive options for arguments, working directory, window style, credentials,
    and more. It validates the executable path, handles process creation with detailed
    error handling, and reports results through a standardized return object including
    the process ID, handle, and exit code (if waited for completion).
    
    .PARAMETER FilePath
    The full path to the executable file to start. Must be an existing file.
    Supports .exe, .bat, .cmd, .ps1, and other executable file types.
    Can be a local path or UNC path.
    
    .PARAMETER ArgumentList
    Optional array of arguments to pass to the process. Each argument should be
    a separate array element. Arguments containing spaces are automatically quoted.
    
    .PARAMETER WorkingDirectory
    Optional working directory for the new process. If not specified, uses the
    current directory. Must be an existing directory.
    
    .PARAMETER WindowStyle
    Optional window style for the new process.
    Valid values: 'Normal', 'Hidden', 'Minimized', 'Maximized'
    Default is 'Normal'.
    
    .PARAMETER Wait
    Optional switch parameter. When specified, waits for the process to exit
    before returning. Returns the exit code in the status object. Default is $false.
    
    .PARAMETER TimeoutSeconds
    Optional timeout in seconds when using -Wait. If the process doesn't exit
    within this time, the function returns with a timeout error. Default is no timeout.
    Only applies when -Wait is specified.
    
    .PARAMETER Credential
    Optional PSCredential object to run the process as a different user.
    Requires the username and password of the target user account.
    
    .PARAMETER LoadUserProfile
    Optional switch parameter. When specified with -Credential, loads the user
    profile for the specified user. Default is $false.
    
    .PARAMETER UseShellExecute
    Optional switch parameter. When specified, uses the operating system shell
    to start the process. Allows starting documents with associated applications.
    Cannot be combined with -RedirectStandardOutput or -Credential. Default is $false.
    
    .PARAMETER Verb
    Optional verb to use when starting the process with -UseShellExecute.
    Common verbs: 'runas' (run as administrator), 'open', 'edit', 'print'.
    Only applies when -UseShellExecute is specified.
    
    .PARAMETER RedirectStandardOutput
    Optional file path to redirect standard output to. Cannot be used with
    -UseShellExecute. Output is written to the specified file.
    
    .PARAMETER RedirectStandardError
    Optional file path to redirect standard error to. Cannot be used with
    -UseShellExecute. Error output is written to the specified file.
    
    .EXAMPLE
    RunProcess -FilePath "C:\Windows\System32\notepad.exe"
    Starts Notepad and returns immediately with the process ID.
    
    .EXAMPLE
    $result = RunProcess -FilePath "C:\Tools\app.exe" -ArgumentList @("/silent", "/config:default")
    if ($result.code -eq 0) {
        Write-Host "Process started with PID: $($result.data.ProcessId)"
    }
    
    .EXAMPLE
    RunProcess -FilePath "C:\Setup.exe" -Wait -TimeoutSeconds 300
    Starts setup and waits up to 5 minutes for completion.
    
    .EXAMPLE
    $result = RunProcess -FilePath "cmd.exe" -ArgumentList @("/c", "dir") -RedirectStandardOutput "C:\output.txt"
    Runs command and redirects output to file.
    
    .EXAMPLE
    # Run as administrator
    RunProcess -FilePath "C:\Tools\admin-tool.exe" -UseShellExecute -Verb "runas"
    
    .EXAMPLE
    # Run as different user
    $cred = Get-Credential
    RunProcess -FilePath "C:\App.exe" -Credential $cred -LoadUserProfile
    
    .NOTES
    - Requires execute permissions on the file
    - Returns immediately unless -Wait is specified
    - Process ID is returned in the processId property
    - With -Wait, exit code is returned in the exitCode property
    - Some combinations of parameters are mutually exclusive (documented in parameter help)
    - Administrative privileges may be required for certain operations
    - Returns comprehensive process start details in the data field
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ArgumentList = @(),
        
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Normal', 'Hidden', 'Minimized', 'Maximized')]
        [string]$WindowStyle = 'Normal',
        
        [Parameter(Mandatory = $false)]
        [switch]$Wait,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSeconds,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $false)]
        [switch]$LoadUserProfile,
        
        [Parameter(Mandatory = $false)]
        [switch]$UseShellExecute,
        
        [Parameter(Mandatory = $false)]
        [string]$Verb,
        
        [Parameter(Mandatory = $false)]
        [string]$RedirectStandardOutput,
        
        [Parameter(Mandatory = $false)]
        [string]$RedirectStandardError
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return OPSreturn -Code -1 -Message "Parameter 'FilePath' is required but was not provided or is empty"
    }
    
    try {
        # Normalize file path
        $NormalizedPath = $FilePath.Replace('/', '\\')
        
        # Check if file exists
        if (-not (Test-Path -Path $NormalizedPath -PathType Leaf)) {
            return OPSreturn -Code -1 -Message "Executable file '$NormalizedPath' does not exist or is not a file"
        }
        
        # Get file information
        try {
            $FileItem = Get-Item -Path $NormalizedPath -ErrorAction Stop
            $FullFilePath = $FileItem.FullName
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to access executable file '$NormalizedPath': $($_.Exception.Message)"
        }
        
        # Validate working directory if specified
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $NormalizedWorkingDir = $WorkingDirectory.Replace('/', '\\').TrimEnd('\\')
            
            if (-not (Test-Path -Path $NormalizedWorkingDir -PathType Container)) {
                return OPSreturn -Code -1 -Message "Working directory '$NormalizedWorkingDir' does not exist or is not a directory"
            }
            
            $WorkingDirectory = (Get-Item -Path $NormalizedWorkingDir).FullName
        }
        else {
            $WorkingDirectory = $PWD.Path
        }
        
        # Validate parameter combinations
        if ($UseShellExecute -and ($RedirectStandardOutput -or $RedirectStandardError)) {
            return OPSreturn -Code -1 -Message "Cannot use -UseShellExecute with -RedirectStandardOutput or -RedirectStandardError"
        }
        
        if ($UseShellExecute -and $Credential) {
            return OPSreturn -Code -1 -Message "Cannot use -UseShellExecute with -Credential"
        }
        
        if ($Verb -and -not $UseShellExecute) {
            return OPSreturn -Code -1 -Message "Parameter -Verb requires -UseShellExecute to be specified"
        }
        
        if ($TimeoutSeconds -and -not $Wait) {
            return OPSreturn -Code -1 -Message "Parameter -TimeoutSeconds requires -Wait to be specified"
        }
        
        if ($LoadUserProfile -and -not $Credential) {
            return OPSreturn -Code -1 -Message "Parameter -LoadUserProfile requires -Credential to be specified"
        }
        
        # Validate redirect output paths
        if ($RedirectStandardOutput) {
            $OutputParent = Split-Path -Path $RedirectStandardOutput -Parent
            if ($OutputParent -and -not (Test-Path -Path $OutputParent -PathType Container)) {
                return OPSreturn -Code -1 -Message "Parent directory for RedirectStandardOutput '$OutputParent' does not exist"
            }
        }
        
        if ($RedirectStandardError) {
            $ErrorParent = Split-Path -Path $RedirectStandardError -Parent
            if ($ErrorParent -and -not (Test-Path -Path $ErrorParent -PathType Container)) {
                return OPSreturn -Code -1 -Message "Parent directory for RedirectStandardError '$ErrorParent' does not exist"
            }
        }
        
        # Build argument string
        $ArgumentString = if ($ArgumentList.Count -gt 0) {
            ($ArgumentList | ForEach-Object {
                if ($_ -match '\\s') { "`"$_`"" } else { $_ }
            }) -join ' '
        } else {
            ""
        }
        
        # Prepare confirmation message
        $ProcessDescription = "$($FileItem.Name)"
        if ($ArgumentString) { $ProcessDescription += " $ArgumentString" }
        $ConfirmMessage = "Start process: $ProcessDescription"
        
        # Map window style to ProcessWindowStyle enum
        $WindowStyleMap = @{
            'Normal' = [System.Diagnostics.ProcessWindowStyle]::Normal
            'Hidden' = [System.Diagnostics.ProcessWindowStyle]::Hidden
            'Minimized' = [System.Diagnostics.ProcessWindowStyle]::Minimized
            'Maximized' = [System.Diagnostics.ProcessWindowStyle]::Maximized
        }
        
        # Attempt to start the process
        try {
            Write-Verbose "Starting process: $FullFilePath"
            if ($ArgumentString) { Write-Verbose "Arguments: $ArgumentString" }
            Write-Verbose "Working directory: $WorkingDirectory"
            Write-Verbose "Window style: $WindowStyle"
            
            if ($PSCmdlet.ShouldProcess($ProcessDescription, $ConfirmMessage)) {
                
                # Create ProcessStartInfo
                $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
                $StartInfo.FileName = $FullFilePath
                $StartInfo.Arguments = $ArgumentString
                $StartInfo.WorkingDirectory = $WorkingDirectory
                $StartInfo.WindowStyle = $WindowStyleMap[$WindowStyle]
                $StartInfo.UseShellExecute = $UseShellExecute.IsPresent
                
                # Configure verb if specified
                if ($Verb) {
                    $StartInfo.Verb = $Verb
                    Write-Verbose "Verb: $Verb"
                }
                
                # Configure redirection if specified
                if (-not $UseShellExecute) {
                    if ($RedirectStandardOutput) {
                        $StartInfo.RedirectStandardOutput = $true
                        Write-Verbose "Redirecting stdout to: $RedirectStandardOutput"
                    }
                    
                    if ($RedirectStandardError) {
                        $StartInfo.RedirectStandardError = $true
                        Write-Verbose "Redirecting stderr to: $RedirectStandardError"
                    }
                    
                    if ($RedirectStandardOutput -or $RedirectStandardError) {
                        $StartInfo.CreateNoWindow = $true
                    }
                }
                
                # Configure credentials if specified
                if ($Credential) {
                    $StartInfo.Domain = ""
                    $StartInfo.UserName = $Credential.UserName
                    $StartInfo.Password = $Credential.Password
                    $StartInfo.LoadUserProfile = $LoadUserProfile.IsPresent
                    Write-Verbose "Running as user: $($Credential.UserName)"
                }
                
                # Start the process
                $Process = New-Object System.Diagnostics.Process
                $Process.StartInfo = $StartInfo
                
                $ProcessStarted = $Process.Start()
                
                if (-not $ProcessStarted) {
                    return OPSreturn -Code -1 -Message "Failed to start process. Process.Start() returned false."
                }
                
                $ProcessId = $Process.Id
                $StartTime = $Process.StartTime
                
                Write-Verbose "Process started successfully with PID: $ProcessId"
                
                # Handle output redirection if specified
                if ($RedirectStandardOutput -and -not $UseShellExecute) {
                    try {
                        $StdOutContent = $Process.StandardOutput.ReadToEnd()
                        [System.IO.File]::WriteAllText($RedirectStandardOutput, $StdOutContent)
                        Write-Verbose "Standard output written to: $RedirectStandardOutput"
                    }
                    catch {
                        Write-Verbose "Warning: Failed to redirect standard output: $($_.Exception.Message)"
                    }
                }
                
                if ($RedirectStandardError -and -not $UseShellExecute) {
                    try {
                        $StdErrContent = $Process.StandardError.ReadToEnd()
                        [System.IO.File]::WriteAllText($RedirectStandardError, $StdErrContent)
                        Write-Verbose "Standard error written to: $RedirectStandardError"
                    }
                    catch {
                        Write-Verbose "Warning: Failed to redirect standard error: $($_.Exception.Message)"
                    }
                }
                
                $ExitCode = $null
                $HasExited = $false
                
                # Wait for process if requested
                if ($Wait) {
                    Write-Verbose "Waiting for process to exit..."
                    
                    if ($TimeoutSeconds) {
                        $Exited = $Process.WaitForExit($TimeoutSeconds * 1000)
                        
                        if (-not $Exited) {
                            return OPSreturn -Code -1 -Message "Process did not exit within timeout period of $TimeoutSeconds seconds"
                        }
                    }
                    else {
                        $Process.WaitForExit()
                    }
                    
                    $ExitCode = $Process.ExitCode
                    $HasExited = $true
                    
                    Write-Verbose "Process exited with code: $ExitCode"
                }
                else {
                    # Check if process has already exited
                    $Process.Refresh()
                    $HasExited = $Process.HasExited
                    
                    if ($HasExited) {
                        $ExitCode = $Process.ExitCode
                        Write-Verbose "Process has already exited with code: $ExitCode"
                    }
                }
                
                # Prepare return data object with comprehensive process start details
                $ReturnData = [PSCustomObject]@{
                    FilePath        = $FullFilePath
                    ProcessId       = $ProcessId
                    ProcessHandle   = $Process
                    ExitCode        = $ExitCode
                    StartTime       = $StartTime
                    HasExited       = $HasExited
                }
                
                return OPSreturn -Code 0 -Message "" -Data $ReturnData
            }
            else {
                return OPSreturn -Code -1 -Message "Operation cancelled by user"
            }
        }
        catch [System.ComponentModel.Win32Exception] {
            return OPSreturn -Code -1 -Message "Win32 error starting process: $($_.Exception.Message) (Error code: $($_.Exception.NativeErrorCode))"
        }
        catch [System.UnauthorizedAccessException] {
            return OPSreturn -Code -1 -Message "Access denied starting process. Check permissions or use -Verb 'runas' for elevation."
        }
        catch [System.InvalidOperationException] {
            return OPSreturn -Code -1 -Message "Invalid operation starting process: $($_.Exception.Message)"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to start process '$FullFilePath': $($_.Exception.Message)"
        }
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in RunProcess function: $($_.Exception.Message)"
    }
}
