<#
.SYNOPSIS
    Examples for Registry Management functions in PSAppCoreLib module

.DESCRIPTION
    This script demonstrates the usage of all Registry Management functions:
    - CreateRegKey: Create new registry keys
    - CreateRegVal: Create registry values with all type support
    - DeleteRegKey: Delete registry keys with optional recursive deletion
    - DeleteRegVal: Delete individual registry values
    - GetRegEntryValue: Read registry value with type-aware handling
    - GetRegEntryType: Determine registry value type
    - SetNewRegValue: Update existing registry values with validation

.NOTES
    Version: 1.06.00
    Author: Praetoriani (a.k.a. M.Sczepanski)
    Website: https://github.com/praetoriani
#>

# Import the module
Import-Module PSAppCoreLib -Force

# Define test registry path (use HKCU for safe testing)
$TestRegPath = "HKCU:\Software\PSAppCoreLibTest"

Write-Host "`n=== PSAppCoreLib Registry Management Examples ===`n" -ForegroundColor Cyan

#region Example 1: Create Registry Key
Write-Host "Example 1: Creating Registry Key" -ForegroundColor Yellow
Write-Host "--------------------------------------" -ForegroundColor Yellow

$result = CreateRegKey -KeyPath $TestRegPath
if ($result.code -eq 0) {
    Write-Host "✓ Registry key created successfully!" -ForegroundColor Green
} else {
    Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

#region Example 2: Create String Registry Value
Write-Host "Example 2: Creating String Registry Value" -ForegroundColor Yellow
Write-Host "------------------------------------------" -ForegroundColor Yellow

$result = CreateRegVal -KeyPath $TestRegPath -ValueName "ApplicationName" -ValueData "PSAppCoreLib Test" -ValueType "String"
if ($result.code -eq 0) {
    Write-Host "✓ String value created successfully!" -ForegroundColor Green
} else {
    Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

#region Example 3: Create DWORD Registry Value
Write-Host "Example 3: Creating DWORD Registry Value" -ForegroundColor Yellow
Write-Host "-----------------------------------------" -ForegroundColor Yellow

$result = CreateRegVal -KeyPath $TestRegPath -ValueName "Version" -ValueData 106 -ValueType "DWord"
if ($result.code -eq 0) {
    Write-Host "✓ DWORD value created successfully!" -ForegroundColor Green
} else {
    Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

#region Example 4: Create MultiString Registry Value
Write-Host "Example 4: Creating MultiString Registry Value" -ForegroundColor Yellow
Write-Host "-----------------------------------------------" -ForegroundColor Yellow

$modules = @("PSAppCoreLib", "PSxFramework")
$result = CreateRegVal -KeyPath $TestRegPath -ValueName "InstalledModules" -ValueData $modules -ValueType "MultiString"
if ($result.code -eq 0) {
    Write-Host "✓ MultiString value created successfully!" -ForegroundColor Green
} else {
    Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

#region Example 5: Read Registry Value
Write-Host "Example 5: Reading Registry Value" -ForegroundColor Yellow
Write-Host "----------------------------------" -ForegroundColor Yellow

$result = GetRegEntryValue -KeyPath $TestRegPath -ValueName "ApplicationName"
if ($result.code -eq 0) {
    Write-Host "✓ Value read successfully!" -ForegroundColor Green
    Write-Host "  Value: $($result.data)" -ForegroundColor Gray
} else {
    Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

#region Example 6: Get Registry Value Type
Write-Host "Example 6: Getting Registry Value Type" -ForegroundColor Yellow
Write-Host "---------------------------------------" -ForegroundColor Yellow

$result = GetRegEntryType -KeyPath $TestRegPath -ValueName "Version"
if ($result.code -eq 0) {
    Write-Host "✓ Value type retrieved successfully!" -ForegroundColor Green
    Write-Host "  Type: $($result.data)" -ForegroundColor Gray
} else {
    Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

#region Example 7: Update Registry Value
Write-Host "Example 7: Updating Registry Value" -ForegroundColor Yellow
Write-Host "-----------------------------------" -ForegroundColor Yellow

$result = SetNewRegValue -KeyPath $TestRegPath -ValueName "Version" -ValueData 107 -ValueType "DWord"
if ($result.code -eq 0) {
    Write-Host "✓ Value updated successfully!" -ForegroundColor Green
    # Verify the update
    $verification = GetRegEntryValue -KeyPath $TestRegPath -ValueName "Version"
    Write-Host "  New Value: $($verification.data)" -ForegroundColor Gray
} else {
    Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

#region Example 8: Delete Registry Value
Write-Host "Example 8: Deleting Registry Value" -ForegroundColor Yellow
Write-Host "-----------------------------------" -ForegroundColor Yellow

$result = DeleteRegVal -KeyPath $TestRegPath -ValueName "InstalledModules"
if ($result.code -eq 0) {
    Write-Host "✓ Value deleted successfully!" -ForegroundColor Green
} else {
    Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

#region Example 9: Delete Registry Key
Write-Host "Example 9: Deleting Registry Key" -ForegroundColor Yellow
Write-Host "---------------------------------" -ForegroundColor Yellow

$result = DeleteRegKey -KeyPath $TestRegPath -Recurse
if ($result.code -eq 0) {
    Write-Host "✓ Registry key deleted successfully!" -ForegroundColor Green
} else {
    Write-Host "✗ Error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

Write-Host "`n=== Registry Management Examples Completed ===`n" -ForegroundColor Cyan
