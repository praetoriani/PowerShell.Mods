<#
.SYNOPSIS
    Examples for GetBitmapIconFromDLL function from PSAppCoreLib module

.DESCRIPTION
    This file contains various examples demonstrating how to use the GetBitmapIconFromDLL
    function to extract icons from DLL files and convert them to bitmaps.

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

# Example 1: Extract icon from shell32.dll (common Windows DLL with many icons)
$result1 = GetBitmapIconFromDLL -DLLfile "$env:SystemRoot\System32\shell32.dll" -IconIndex 0
if ($result1.code -eq 0) {
    Write-Host "Successfully extracted icon from shell32.dll" -ForegroundColor Green
    Write-Host "  Bitmap size: $($result1.bitmap.Width)x$($result1.bitmap.Height)" -ForegroundColor Cyan
    
    # Save the bitmap to file (optional)
    try {
        $result1.bitmap.Save("C:\Temp\shell32_icon_0.png", [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "  Bitmap saved to C:\Temp\shell32_icon_0.png" -ForegroundColor Green
    }
    catch {
        Write-Host "  Failed to save bitmap: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        # Always dispose of the bitmap to free memory
        $result1.bitmap.Dispose()
    }
} else {
    Write-Host "Error: $($result1.msg)" -ForegroundColor Red
}

# Example 2: Extract different icon from shell32.dll
$result2 = GetBitmapIconFromDLL -DLLfile "$env:SystemRoot\System32\shell32.dll" -IconIndex 3
if ($result2.code -eq 0) {
    Write-Host "Successfully extracted icon index 3 from shell32.dll" -ForegroundColor Green
    Write-Host "  Bitmap size: $($result2.bitmap.Width)x$($result2.bitmap.Height)" -ForegroundColor Cyan
    
    # Dispose of the bitmap
    $result2.bitmap.Dispose()
} else {
    Write-Host "Error: $($result2.msg)" -ForegroundColor Red
}

# Example 3: Extract icon from imageres.dll (another common Windows icon library)
$imageresDLL = "$env:SystemRoot\System32\imageres.dll"
if (Test-Path $imageresDLL) {
    $result3 = GetBitmapIconFromDLL -DLLfile $imageresDLL -IconIndex 15
    if ($result3.code -eq 0) {
        Write-Host "Successfully extracted icon from imageres.dll" -ForegroundColor Green
        Write-Host "  Bitmap size: $($result3.bitmap.Width)x$($result3.bitmap.Height)" -ForegroundColor Cyan
        $result3.bitmap.Dispose()
    } else {
        Write-Host "Error: $($result3.msg)" -ForegroundColor Red
    }
} else {
    Write-Host "imageres.dll not found, skipping example 3" -ForegroundColor Yellow
}

# Example 4: Error handling - invalid icon index
$result4 = GetBitmapIconFromDLL -DLLfile "$env:SystemRoot\System32\shell32.dll" -IconIndex 999999
Write-Host "Expected error for invalid icon index: $($result4.msg)" -ForegroundColor Yellow

# Example 5: Error handling - non-existent file
$result5 = GetBitmapIconFromDLL -DLLfile "C:\NonExistent\file.dll" -IconIndex 0
Write-Host "Expected error for non-existent file: $($result5.msg)" -ForegroundColor Yellow

# Example 6: Error handling - negative icon index
$result6 = GetBitmapIconFromDLL -DLLfile "$env:SystemRoot\System32\shell32.dll" -IconIndex -1
Write-Host "Expected error for negative icon index: $($result6.msg)" -ForegroundColor Yellow

# Example 7: Extract multiple icons from the same DLL
Write-Host ""
Write-Host "Extracting multiple icons from shell32.dll:" -ForegroundColor Cyan
$iconIndices = @(0, 1, 2, 4, 5)

foreach ($index in $iconIndices) {
    $result = GetBitmapIconFromDLL -DLLfile "$env:SystemRoot\System32\shell32.dll" -IconIndex $index
    if ($result.code -eq 0) {
        Write-Host "  Icon $index extracted successfully (Size: $($result.bitmap.Width)x$($result.bitmap.Height))" -ForegroundColor Green
        
        # Save each icon with a unique filename
        try {
            $result.bitmap.Save("C:\Temp\shell32_icon_$index.png", [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Host "    Saved as: C:\Temp\shell32_icon_$index.png" -ForegroundColor Gray
        }
        catch {
            Write-Host "    Failed to save icon $index" -ForegroundColor Red
        }
        finally {
            $result.bitmap.Dispose()
        }
    } else {
        Write-Host "  Failed to extract icon $index - $($result.msg)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "All extracted icons have been saved to C:\Temp\" -ForegroundColor Cyan
Write-Host "Note: Always dispose of bitmap objects to prevent memory leaks!" -ForegroundColor Yellow