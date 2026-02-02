<#
.SYNOPSIS
    Examples for Process and Service Management functions in PSAppCoreLib module

.DESCRIPTION
    This script demonstrates the usage of:
    - RunProcess / GetProcessByName / GetProcessByID
    - RestartProcess / StopProcess / KillProcess
    - StartService / RestartService / ForceRestartService
    - StopService / KillService / SetServiceState

.NOTES
    Version: 1.06.00
    Author: Praetoriani (a.k.a. M.Sczepanski)
    Website: https://github.com/praetoriani
#>

Import-Module PSAppCoreLib -Force

Write-Host "`n=== PSAppCoreLib Process & Service Management Examples ===`n" -ForegroundColor Cyan

#region Process Management Examples

Write-Host "[Process] Example 1: RunProcess" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow

# Safe demo: run notepad
$result = RunProcess -FilePath "notepad.exe" -Arguments "" -Wait:$false
if ($result.code -eq 0) {
    $pid = $result.data
    Write-Host "✓ notepad.exe started, PID: $pid" -ForegroundColor Green
} else {
    Write-Host "✗ Error starting notepad: $($result.msg)" -ForegroundColor Red
}
Write-Host ""

if ($pid) {
    Write-Host "[Process] Example 2: GetProcessByID" -ForegroundColor Yellow
    Write-Host "-----------------------------------" -ForegroundColor Yellow

    $result = GetProcessByID -Id $pid
    if ($result.code -eq 0) {
        $proc = $result.data
        Write-Host "✓ Process found: $($proc.ProcessName) (PID=$($proc.Id))" -ForegroundColor Green
    } else {
        Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "[Process] Example 3: RestartProcess" -ForegroundColor Yellow
    Write-Host "------------------------------------" -ForegroundColor Yellow

    $result = RestartProcess -Id $pid
    Write-Host "RestartProcess: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
    Write-Host ""

    Write-Host "[Process] Example 4: StopProcess" -ForegroundColor Yellow
    Write-Host "---------------------------------" -ForegroundColor Yellow

    $result = StopProcess -Id $pid
    Write-Host "StopProcess: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
    Write-Host ""
}

#endregion

#region Service Management Examples

# Pick a commonly available service (Spooler) - adjust if needed
$serviceName = "Spooler"

Write-Host "[Service] Example 5: StartService" -ForegroundColor Yellow
Write-Host "----------------------------------" -ForegroundColor Yellow

$result = StartService -Name $serviceName
Write-Host "StartService: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
Write-Host ""

Write-Host "[Service] Example 6: RestartService" -ForegroundColor Yellow
Write-Host "------------------------------------" -ForegroundColor Yellow

$result = RestartService -Name $serviceName
Write-Host "RestartService: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
Write-Host ""

Write-Host "[Service] Example 7: SetServiceState" -ForegroundColor Yellow
Write-Host "-------------------------------------" -ForegroundColor Yellow

# Demo: ensure start type is Automatic
$result = SetServiceState -Name $serviceName -StartupType "Automatic"
Write-Host "SetServiceState: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
Write-Host ""

Write-Host "`n=== Process & Service Management Examples Completed ===`n" -ForegroundColor Cyan
