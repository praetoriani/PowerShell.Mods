<#
.SYNOPSIS
    Examples for File & Directory Management functions in PSAppCoreLib module

.DESCRIPTION
    This script demonstrates the usage of File & Directory Management functions:
    - CreateNewDir
    - CreateNewFile
    - CopyDir
    - CopyFile / CopyFiles
    - RemoveDir / RemoveDirs
    - RemoveFile / RemoveFiles
    - WriteTextToFile
    - ReadTextFile

.NOTES
    Version: 1.06.00
    Author: Praetoriani (a.k.a. M.Sczepanski)
    Website: https://github.com/praetoriani
#>

Import-Module PSAppCoreLib -Force

$BasePath    = Join-Path -Path $env:TEMP -ChildPath "PSAppCoreLib_FileDemo"
$SourceDir   = Join-Path -Path $BasePath -ChildPath "Source"
$TargetDir   = Join-Path -Path $BasePath -ChildPath "Target"
$LogFile     = Join-Path -Path $BasePath -ChildPath "demo.log"

Write-Host "`n=== PSAppCoreLib File & Directory Management Examples ===`n" -ForegroundColor Cyan

#region Prep: Clean up previous demo
if (Test-Path $BasePath) {
    Remove-Item -Path $BasePath -Recurse -Force -ErrorAction SilentlyContinue
}
#endregion

#region Example 1: Create directories
Write-Host "Example 1: Creating directories" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow

$result = CreateNewDir -Path $SourceDir -Force
Write-Host "SourceDir:  code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray

$result = CreateNewDir -Path $TargetDir -Force
Write-Host "TargetDir:  code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
Write-Host ""
#endregion

#region Example 2: Create files with content
Write-Host "Example 2: Creating files" -ForegroundColor Yellow
Write-Host "----------------------------" -ForegroundColor Yellow

$file1 = Join-Path $SourceDir "file1.txt"
$file2 = Join-Path $SourceDir "file2.txt"

$result = CreateNewFile -Path $file1 -Content "Hello from PSAppCoreLib!" -Encoding "UTF8"
Write-Host "file1: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray

$result = CreateNewFile -Path $file2 -Content "Another test file" -Encoding "UTF8"
Write-Host "file2: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
Write-Host ""
#endregion

#region Example 3: Copy single file
Write-Host "Example 3: Copy single file" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow

$targetFile1 = Join-Path $TargetDir "file1_copy.txt"
$result = CopyFile -Source $file1 -Destination $targetFile1 -OverwriteExisting
Write-Host "CopyFile: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
Write-Host ""
#endregion

#region Example 4: Copy directory recursively
Write-Host "Example 4: Copy directory recursively" -ForegroundColor Yellow
Write-Host "--------------------------------------" -ForegroundColor Yellow

$DeepSource = Join-Path $SourceDir "Deep"
$DeepFile   = Join-Path $DeepSource "deep.txt"

# Create nested structure
CreateNewDir -Path $DeepSource -Force | Out-Null
CreateNewFile -Path $DeepFile -Content "Deep file" -Encoding "UTF8" | Out-Null

$CopyTarget = Join-Path $TargetDir "SourceCopy"
$result = CopyDir -Source $SourceDir -Destination $CopyTarget -Recurse -PreserveTime
Write-Host "CopyDir: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
Write-Host ""
#endregion

#region Example 5: Read and write text file
Write-Host "Example 5: Read & write text file" -ForegroundColor Yellow
Write-Host "-----------------------------------" -ForegroundColor Yellow

$result = WriteTextToFile -Path $LogFile -Content "First log line" -Encoding "UTF8" -Override
Write-Host "WriteTextToFile: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray

$result = ReadTextFile -Path $LogFile -Encoding "UTF8"
if ($result.code -eq 0) {
    Write-Host "ReadTextFile content:" -ForegroundColor Green
    Write-Host $result.data -ForegroundColor Gray
} else {
    Write-Host "ReadTextFile error: $($result.msg)" -ForegroundColor Red
}
Write-Host ""
#endregion

#region Example 6: Remove files and directories
Write-Host "Example 6: Remove files and directories" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

$result = RemoveFile -Path $targetFile1
Write-Host "RemoveFile: code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray

$result = RemoveDir -Path $BasePath -Recurse
Write-Host "RemoveDir:  code=$($result.code); msg='$($result.msg)'" -ForegroundColor Gray
Write-Host ""
#endregion

Write-Host "`n=== File & Directory Management Examples Completed ===`n" -ForegroundColor Cyan
