<#
.SYNOPSIS
    Examples for WriteLogMessage function from PSAppCoreLib module

.DESCRIPTION
    This file contains various examples demonstrating how to use the WriteLogMessage
    function for different logging scenarios.

.NOTES
    Author: Praetoriani (a.k.a. M.Sczepanski)
    Website: https://github.com/praetoriani
#>

# Import the PSAppCoreLib module
# Automatically detect module location (works from Examples directory)
$moduleRoot = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $moduleRoot "PSAppCoreLib.psm1"

if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
    Write-Host "Module loaded from: $modulePath" -ForegroundColor Green
} else {
    Write-Error "Cannot find PSAppCoreLib.psm1 at: $modulePath"
    Write-Host "Current script location: $PSScriptRoot" -ForegroundColor Yellow
    Write-Host "Looking for module at: $modulePath" -ForegroundColor Yellow
    exit 1
}

# Example 1: Basic logging with default DEBUG flag
$result1 = WriteLogMessage -Logfile "C:\Temp\application.log" -Message "Application started successfully"
if ($result1.code -eq 0) {
    Write-Host "Log entry created successfully" -ForegroundColor Green
} else {
    Write-Host "Error: $($result1.msg)" -ForegroundColor Red
}

# Example 2: Info message logging
$result2 = WriteLogMessage -Logfile "C:\Temp\application.log" -Message "Configuration loaded from config.xml" -Flag "INFO"
if ($result2.code -eq 0) {
    Write-Host "INFO log entry created successfully" -ForegroundColor Green
} else {
    Write-Host "Error: $($result2.msg)" -ForegroundColor Red
}

# Example 3: Warning message logging
$result3 = WriteLogMessage -Logfile "C:\Temp\application.log" -Message "Deprecated function used, please update" -Flag "WARN"
if ($result3.code -eq 0) {
    Write-Host "WARNING log entry created successfully" -ForegroundColor Yellow
} else {
    Write-Host "Error: $($result3.msg)" -ForegroundColor Red
}

# Example 4: Error message logging with override (new file)
$result4 = WriteLogMessage -Logfile "C:\Temp\error.log" -Message "Critical system failure detected" -Flag "ERROR" -Override 1
if ($result4.code -eq 0) {
    Write-Host "ERROR log entry created in new file" -ForegroundColor Red
} else {
    Write-Host "Error: $($result4.msg)" -ForegroundColor Red
}

# Example 5: Case insensitive flag handling
$result5 = WriteLogMessage -Logfile "C:\Temp\application.log" -Message "Testing case insensitive flags" -Flag "info"
if ($result5.code -eq 0) {
    Write-Host "Case insensitive flag handling works" -ForegroundColor Green
} else {
    Write-Host "Error: $($result5.msg)" -ForegroundColor Red
}

# Example 6: Error handling - empty logfile parameter (now works correctly)
$result6 = WriteLogMessage -Logfile "" -Message "This should fail"
Write-Host "Expected error result: $($result6.msg)" -ForegroundColor Yellow

# Example 7: Error handling - empty message parameter  
$result7 = WriteLogMessage -Logfile "C:\Temp\test.log" -Message ""
Write-Host "Expected error result: $($result7.msg)" -ForegroundColor Yellow

# Example 8: Multiple log entries in sequence
$messages = @(
    @{ Message = "Starting data processing"; Flag = "INFO" }
    @{ Message = "Processing 1000 records"; Flag = "DEBUG" }
    @{ Message = "Performance warning: slow database response"; Flag = "WARN" }
    @{ Message = "Processing completed successfully"; Flag = "INFO" }
)

foreach ($msg in $messages) {
    $result = WriteLogMessage -Logfile "C:\Temp\processing.log" -Message $msg.Message -Flag $msg.Flag
    if ($result.code -eq 0) {
        Write-Host "Logged: $($msg.Message)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Check the log files in C:\Temp\ to see the formatted output!" -ForegroundColor Cyan