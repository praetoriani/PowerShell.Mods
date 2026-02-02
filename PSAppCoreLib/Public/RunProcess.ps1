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
        Write-Host "Process started with PID: $($result.processId)"
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
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        filePath = $null
        processId = 0
        processHandle = $null
        exitCode = $null
        startTime = $null
        hasExited = $false
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        $status.msg = "Parameter 'FilePath' is required but was not provided or is empty"
        return $status
    }
    
    try {
        # Normalize file path
        $NormalizedPath = $FilePath.Replace('/', '\')
        
        # Check if file exists
        if (-not (Test-Path -Path $NormalizedPath -PathType Leaf)) {
            $status.msg = "Executable file '$NormalizedPath' does not exist or is not a file"
            return $status
        }
        
        # Get file information
        try {
            $FileItem = Get-Item -Path $NormalizedPath -ErrorAction Stop
            $status.filePath = $FileItem.FullName
        }
        catch {
            $status.msg = "Failed to access executable file '$NormalizedPath': $($_.Exception.Message)"
            return $status
        }
        
        # Validate working directory if specified
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $NormalizedWorkingDir = $WorkingDirectory.Replace('/', '\').TrimEnd('\')
            
            if (-not (Test-Path -Path $NormalizedWorkingDir -PathType Container)) {
                $status.msg = "Working directory '$NormalizedWorkingDir' does not exist or is not a directory"
                return $status
            }
            
            $WorkingDirectory = (Get-Item -Path $NormalizedWorkingDir).FullName
        }
        else {
            $WorkingDirectory = $PWD.Path
        }
        
        # Validate parameter combinations
        if ($UseShellExecute -and ($RedirectStandardOutput -or $RedirectStandardError)) {
            $status.msg = "Cannot use -UseShellExecute with -RedirectStandardOutput or -RedirectStandardError"
            return $status
        }
        
        if ($UseShellExecute -and $Credential) {
            $status.msg = "Cannot use -UseShellExecute with -Credential"
            return $status
        }
        
        if ($Verb -and -not $UseShellExecute) {
            $status.msg = "Parameter -Verb requires -UseShellExecute to be specified"
            return $status
        }
        
        if ($TimeoutSeconds -and -not $Wait) {
            $status.msg = "Parameter -TimeoutSeconds requires -Wait to be specified"
            return $status
        }
        
        if ($LoadUserProfile -and -not $Credential) {
            $status.msg = "Parameter -LoadUserProfile requires -Credential to be specified"
            return $status
        }
        
        # Validate redirect output paths
        if ($RedirectStandardOutput) {
            $OutputParent = Split-Path -Path $RedirectStandardOutput -Parent
            if ($OutputParent -and -not (Test-Path -Path $OutputParent -PathType Container)) {
                $status.msg = "Parent directory for RedirectStandardOutput '$OutputParent' does not exist"
                return $status
            }
        }
        
        if ($RedirectStandardError) {
            $ErrorParent = Split-Path -Path $RedirectStandardError -Parent
            if ($ErrorParent -and -not (Test-Path -Path $ErrorParent -PathType Container)) {
                $status.msg = "Parent directory for RedirectStandardError '$ErrorParent' does not exist"
                return $status
            }
        }
        
        # Build argument string
        $ArgumentString = if ($ArgumentList.Count -gt 0) {
            ($ArgumentList | ForEach-Object {
                if ($_ -match '\s') { "`"$_`"" } else { $_ }
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
            Write-Verbose "Starting process: $($status.filePath)"
            if ($ArgumentString) { Write-Verbose "Arguments: $ArgumentString" }
            Write-Verbose "Working directory: $WorkingDirectory"
            Write-Verbose "Window style: $WindowStyle"
            
            if ($PSCmdlet.ShouldProcess($ProcessDescription, $ConfirmMessage)) {
                
                # Create ProcessStartInfo
                $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
                $StartInfo.FileName = $status.filePath
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
                    $status.msg = "Failed to start process. Process.Start() returned false."
                    return $status
                }
                
                $status.processId = $Process.Id
                $status.processHandle = $Process
                $status.startTime = $Process.StartTime
                
                Write-Verbose "Process started successfully with PID: $($status.processId)"
                
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
                
                # Wait for process if requested
                if ($Wait) {
                    Write-Verbose "Waiting for process to exit..."
                    
                    if ($TimeoutSeconds) {
                        $Exited = $Process.WaitForExit($TimeoutSeconds * 1000)
                        
                        if (-not $Exited) {
                            $status.msg = "Process did not exit within timeout period of $TimeoutSeconds seconds"
                            $status.hasExited = $false
                            return $status
                        }
                    }
                    else {
                        $Process.WaitForExit()
                    }
                    
                    $status.exitCode = $Process.ExitCode
                    $status.hasExited = $true
                    
                    Write-Verbose "Process exited with code: $($status.exitCode)"
                }
                else {
                    # Check if process has already exited
                    $Process.Refresh()
                    $status.hasExited = $Process.HasExited
                    
                    if ($status.hasExited) {
                        $status.exitCode = $Process.ExitCode
                        Write-Verbose "Process has already exited with code: $($status.exitCode)"
                    }
                }
            }
            else {
                $status.msg = "Operation cancelled by user"
                return $status
            }
        }
        catch [System.ComponentModel.Win32Exception] {
            $status.msg = "Win32 error starting process: $($_.Exception.Message) (Error code: $($_.Exception.NativeErrorCode))"
            return $status
        }
        catch [System.UnauthorizedAccessException] {
            $status.msg = "Access denied starting process. Check permissions or use -Verb 'runas' for elevation."
            return $status
        }
        catch [System.InvalidOperationException] {
            $status.msg = "Invalid operation starting process: $($_.Exception.Message)"
            return $status
        }
        catch {
            $status.msg = "Failed to start process '$($status.filePath)': $($_.Exception.Message)"
            return $status
        }
        
        # Success
        $status.code = 0
        $status.msg = ""
        return $status
    }
    catch {
        $status.msg = "Unexpected error in RunProcess function: $($_.Exception.Message)"
        return $status
    }
}
