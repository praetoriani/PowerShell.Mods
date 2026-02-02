<#
.SYNOPSIS
    Individual function usage examples for PSxFramework

.DESCRIPTION
    This script provides isolated examples for each function in the PSxFramework module.
    Each example can be run independently to understand how individual functions work.

.NOTES
    Author: Praetoriani (a.k.a. M.Sczepanski)
    Date: 01.02.2026
    Version: 1.0
    
    Requirements:
    - PSxFramework module must be installed and imported
#>

#Requires -Modules PSxFramework

Write-Host "PSxFramework - Individual Function Examples" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# ============================================================================
# Example 1: WriteLogMessage
# ============================================================================
Write-Host "[Example 1] WriteLogMessage Function" -ForegroundColor Yellow
Write-Host "-------------------------------------`n" -ForegroundColor Yellow

$logPath = "$env:TEMP\psxframework_example.log"

# Create a new log file (Override = 1)
$result = WriteLogMessage -Logfile $logPath -Message "Starting new session" -Flag "INFO" -Override 1
if ($result.code -eq 0) {
    Write-Host "✓ Log initialized successfully" -ForegroundColor Green
}

# Append various log levels
WriteLogMessage -Logfile $logPath -Message "Debug information" -Flag "DEBUG"
WriteLogMessage -Logfile $logPath -Message "Informational message" -Flag "INFO"
WriteLogMessage -Logfile $logPath -Message "Warning message" -Flag "WARN"
WriteLogMessage -Logfile $logPath -Message "Error message" -Flag "ERROR"

Write-Host "✓ Various log levels written" -ForegroundColor Green
Write-Host "Log file: $logPath`n" -ForegroundColor Gray

# ============================================================================
# Example 2: GetInstallDir
# ============================================================================
Write-Host "[Example 2] GetInstallDir Function" -ForegroundColor Yellow
Write-Host "-----------------------------------`n" -ForegroundColor Yellow

$installResult = GetInstallDir

if ($installResult.code -eq 0) {
    Write-Host "✓ PSx Composer installation found" -ForegroundColor Green
    Write-Host "  Installation path: $($installResult.data)" -ForegroundColor Gray
} else {
    Write-Host "✗ PSx Composer not installed" -ForegroundColor Red
    Write-Host "  Message: $($installResult.msg)" -ForegroundColor Gray
}
Write-Host ""

# ============================================================================
# Example 3: VerifyBinary
# ============================================================================
Write-Host "[Example 3] VerifyBinary Function" -ForegroundColor Yellow
Write-Host "----------------------------------`n" -ForegroundColor Yellow

if ($installResult.code -eq 0) {
    $installDir = $installResult.data
    
    # Test various binaries
    $binariesToTest = @(
        @{Name = "7-Zip"; Path = Join-Path $installDir "include\7zip\7z.exe"},
        @{Name = "Resource Hacker"; Path = Join-Path $installDir "include\ResourceHacker\ResourceHacker.exe"},
        @{Name = "Non-existent Binary"; Path = "C:\DoesNotExist\fake.exe"}
    )
    
    foreach ($binary in $binariesToTest) {
        $verifyResult = VerifyBinary -ExePath $binary.Path
        
        if ($verifyResult.code -eq 0) {
            Write-Host "✓ $($binary.Name): Found" -ForegroundColor Green
            Write-Host "  Path: $($verifyResult.data)" -ForegroundColor Gray
        } else {
            Write-Host "✗ $($binary.Name): Not Found" -ForegroundColor Red
            Write-Host "  Error: $($verifyResult.msg)" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "Skipping binary verification (PSx Composer not installed)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Example 4: CreateHiddenTempData
# ============================================================================
Write-Host "[Example 4] CreateHiddenTempData Function" -ForegroundColor Yellow
Write-Host "------------------------------------------`n" -ForegroundColor Yellow

if ($installResult.code -eq 0) {
    $createResult = CreateHiddenTempData
    
    if ($createResult.code -eq 0) {
        Write-Host "✓ Temporary data directory created/verified" -ForegroundColor Green
        Write-Host "  Path: $($createResult.data)" -ForegroundColor Gray
        Write-Host "  Attributes: Hidden + System" -ForegroundColor Gray
        
        # Verify directory exists and has correct attributes
        if (Test-Path $createResult.data) {
            $dirInfo = Get-Item $createResult.data -Force
            $isHidden = $dirInfo.Attributes -band [System.IO.FileAttributes]::Hidden
            $isSystem = $dirInfo.Attributes -band [System.IO.FileAttributes]::System
            
            Write-Host "  Hidden: $([bool]$isHidden)" -ForegroundColor Gray
            Write-Host "  System: $([bool]$isSystem)" -ForegroundColor Gray
        }
    } else {
        Write-Host "✗ Failed to create temporary directory" -ForegroundColor Red
        Write-Host "  Error: $($createResult.msg)" -ForegroundColor Gray
    }
} else {
    Write-Host "Skipping temp directory creation (PSx Composer not installed)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Example 5: PrepareSFX
# ============================================================================
Write-Host "[Example 5] PrepareSFX Function" -ForegroundColor Yellow
Write-Host "--------------------------------`n" -ForegroundColor Yellow

if ($installResult.code -eq 0) {
    # Test all SFX modes
    $sfxModes = @("GUI-Mode", "CMD-Mode", "Installer", "Custom")
    
    foreach ($mode in $sfxModes) {
        $sfxResult = PrepareSFX -SFXmod $mode
        
        if ($sfxResult.code -eq 0) {
            Write-Host "✓ $mode SFX prepared" -ForegroundColor Green
            Write-Host "  $($sfxResult.msg)" -ForegroundColor Gray
        } else {
            Write-Host "✗ $mode SFX failed" -ForegroundColor Red
            Write-Host "  Error: $($sfxResult.msg)" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "Skipping SFX preparation (PSx Composer not installed)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Example 6: PrepareCFG
# ============================================================================
Write-Host "[Example 6] PrepareCFG Function" -ForegroundColor Yellow
Write-Host "--------------------------------`n" -ForegroundColor Yellow

if ($installResult.code -eq 0) {
    # Prepare configuration for Installer mode
    $cfgResult = PrepareCFG -SFXmod "Installer"
    
    if ($cfgResult.code -eq 0) {
        Write-Host "✓ Configuration file prepared" -ForegroundColor Green
        Write-Host "  $($cfgResult.msg)" -ForegroundColor Gray
        Write-Host "  Path: $($cfgResult.data)" -ForegroundColor Gray
        
        # Show first few lines of config file
        if (Test-Path $cfgResult.data) {
            Write-Host "`n  Configuration preview (first 5 lines):" -ForegroundColor Gray
            Get-Content $cfgResult.data -TotalCount 5 | ForEach-Object {
                Write-Host "    $_" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "✗ Failed to prepare configuration" -ForegroundColor Red
        Write-Host "  Error: $($cfgResult.msg)" -ForegroundColor Gray
    }
} else {
    Write-Host "Skipping configuration preparation (PSx Composer not installed)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Example 7: CleanHiddenTempData
# ============================================================================
Write-Host "[Example 7] CleanHiddenTempData Function" -ForegroundColor Yellow
Write-Host "-----------------------------------------`n" -ForegroundColor Yellow

if ($installResult.code -eq 0) {
    $cleanResult = CleanHiddenTempData
    
    if ($cleanResult.code -eq 0) {
        Write-Host "✓ Temporary directory cleaned" -ForegroundColor Green
        Write-Host "  $($cleanResult.msg)" -ForegroundColor Gray
        
        # Verify directory is empty
        if ($cleanResult.data -and (Test-Path $cleanResult.data)) {
            $itemCount = (Get-ChildItem $cleanResult.data -Force).Count
            Write-Host "  Items remaining: $itemCount" -ForegroundColor Gray
        }
    } else {
        Write-Host "✗ Failed to clean directory" -ForegroundColor Red
        Write-Host "  Error: $($cleanResult.msg)" -ForegroundColor Gray
    }
} else {
    Write-Host "Skipping temp directory cleaning (PSx Composer not installed)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Example 8: RemoveHiddenTempData (Optional - commented out by default)
# ============================================================================
Write-Host "[Example 8] RemoveHiddenTempData Function" -ForegroundColor Yellow
Write-Host "------------------------------------------`n" -ForegroundColor Yellow
Write-Host "This function completely removes the tmpdata directory." -ForegroundColor Gray
Write-Host "Uncomment the code below to test this function.`n" -ForegroundColor Gray

<#
if ($installResult.code -eq 0) {
    $removeResult = RemoveHiddenTempData
    
    if ($removeResult.code -eq 0) {
        Write-Host "✓ Temporary directory removed completely" -ForegroundColor Green
        Write-Host "  $($removeResult.msg)" -ForegroundColor Gray
    } else {
        Write-Host "✗ Failed to remove directory" -ForegroundColor Red
        Write-Host "  Error: $($removeResult.msg)" -ForegroundColor Gray
    }
} else {
    Write-Host "Skipping temp directory removal (PSx Composer not installed)" -ForegroundColor Yellow
}
#>

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "All examples completed!" -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Cyan

Write-Host "Check the log file at: $logPath" -ForegroundColor Gray
