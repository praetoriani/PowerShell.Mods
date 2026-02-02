function WriteLogMessage {
    <#
    .SYNOPSIS
    Writes messages to a log file with timestamps and severity flags.
    
    .DESCRIPTION
    The WriteLogMessage function creates or appends to a log file with formatted messages
    including timestamps and severity levels. It handles file creation, validation, and
    proper error handling through a standardized return object.
    
    .PARAMETER Logfile
    Full path including filename to the log file. If the file doesn't exist, it will be created.
    
    .PARAMETER Message
    The text message to write to the log file.
    
    .PARAMETER Flag
    Optional severity flag for the message. Valid values are INFO, DEBUG, WARN, or ERROR.
    Default is DEBUG if not specified.
    
    .PARAMETER Override
    Optional parameter to specify whether to overwrite the existing log file (1) or append to it (0).
    Default is 0 (append) if not specified.
    
    .EXAMPLE
    WriteLogMessage -Logfile "C:\Logs\application.log" -Message "Application started successfully"
    Creates a log entry with DEBUG flag (default) and current timestamp.
    
    .EXAMPLE
    WriteLogMessage -Logfile "C:\Logs\application.log" -Message "Configuration loaded" -Flag "INFO"
    Creates a log entry with INFO flag and current timestamp.
    
    .EXAMPLE
    WriteLogMessage -Logfile "C:\Logs\application.log" -Message "Critical error occurred" -Flag "ERROR" -Override 1
    Overwrites the existing log file and creates a new entry with ERROR flag.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Logfile,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "DEBUG", "WARN", "ERROR", IgnoreCase = $true)]
        [string]$Flag = "DEBUG",
        
        [Parameter(Mandatory = $false)]
        [int]$Override = 0
    )
    
    # Validate mandatory parameters (now handles empty strings properly)
    if ([string]::IsNullOrEmpty($Logfile)) {
        return OPSreturn -Code -1 -Message "Parameter 'Logfile' is required but was not provided or is empty"
    }
    
    if ([string]::IsNullOrEmpty($Message)) {
        return OPSreturn -Code -1 -Message "Parameter 'Message' is required but was not provided or is empty"
    }
    
    try {
        # Normalize the flag to uppercase for consistency
        $Flag = $Flag.ToUpper()
        
        # Validate flag parameter (case insensitive check already done by ValidateSet)
        # Adjust flag formatting for consistent spacing
        switch ($Flag) {
            "INFO"  { $FormattedFlag = "[INFO] " }
            "DEBUG" { $FormattedFlag = "[DEBUG]" }
            "WARN"  { $FormattedFlag = "[WARN] " }
            "ERROR" { $FormattedFlag = "[ERROR]" }
            default { $FormattedFlag = "[DEBUG]" }
        }
        
        # Generate timestamp in specified format [2025.06.22 ; 08:16:24]
        $Timestamp = Get-Date -Format "[yyyy.MM.dd ; HH:mm:ss]"
        
        # Create formatted log entry
        $LogEntry = "$Timestamp $FormattedFlag $Message"
        
        # Check if log file exists
        $FileExists = Test-Path -Path $Logfile
        
        # Determine write operation based on Override parameter and file existence
        if ($Override -eq 1 -or -not $FileExists) {
            # Create new file or overwrite existing file
            try {
                # Ensure directory exists
                $LogDirectory = Split-Path -Path $Logfile -Parent
                if ($LogDirectory -and -not (Test-Path -Path $LogDirectory)) {
                    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
                }
                
                # Write to file (overwrite mode)
                $LogEntry | Out-File -FilePath $Logfile -Encoding UTF8 -Force
            }
            catch {
                return OPSreturn -Code -1 -Message "Failed to create or overwrite log file '$Logfile': $($_.Exception.Message)"
            }
        }
        else {
            # Append to existing file
            try {
                $LogEntry | Out-File -FilePath $Logfile -Encoding UTF8 -Append
            }
            catch {
                return OPSreturn -Code -1 -Message "Failed to append to log file '$Logfile': $($_.Exception.Message)"
            }
        }
        
        # Success
        return OPSreturn -Code 0 -Message "" -Data $LogEntry
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in WriteLogMessage function: $($_.Exception.Message)"
    }
}
