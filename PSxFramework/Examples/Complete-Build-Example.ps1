<#
.SYNOPSIS
    Complete PSx Composer build process example

.DESCRIPTION
    This script demonstrates a complete build workflow using the PSxFramework module.
    It shows how to:
    - Initialize logging
    - Verify PSx Composer installation
    - Verify required binaries
    - Create temporary workspace
    - Prepare SFX modules and configuration
    - Clean up after build

.NOTES
    Author: Praetoriani (a.k.a. M.Sczepanski)
    Date: 01.02.2026
    Version: 1.0
    
    Requirements:
    - PSxFramework module must be installed and imported
    - PSx Composer must be installed on the system
#>

#Requires -Modules PSxFramework

# Configuration
$LogFile = "$env:TEMP\psx_build_example.log"
$SFXMode = "GUI-Mode"  # Options: GUI-Mode, CMD-Mode, Installer, Custom

# Function to write both to log and console
function Write-BuildLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "DEBUG", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    
    # Write to log file
    WriteLogMessage -Logfile $LogFile -Message $Message -Flag $Level
    
    # Write to console with color coding
    $color = switch ($Level) {
        "INFO"  { "Green" }
        "DEBUG" { "Gray" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
    }
    
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

# Main build process
try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "PSx Composer Build Process Example" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Step 1: Initialize logging
    Write-BuildLog "Starting PSx Composer build process" "INFO"
    Write-BuildLog "Log file: $LogFile" "DEBUG"
    Write-BuildLog "SFX Mode: $SFXMode" "DEBUG"
    
    # Step 2: Verify PSx Composer installation
    Write-Host "`n[Step 1/6] Verifying PSx Composer installation..." -ForegroundColor Yellow
    $installResult = GetInstallDir
    
    if ($installResult.code -ne 0) {
        Write-BuildLog $installResult.msg "ERROR"
        throw "PSx Composer installation not found. Please install PSx Composer first."
    }
    
    $installDir = $installResult.data
    Write-BuildLog "Installation found: $installDir" "INFO"
    
    # Step 3: Verify required binaries
    Write-Host "`n[Step 2/6] Verifying required binaries..." -ForegroundColor Yellow
    
    $requiredBinaries = @(
        @{Name = "7-Zip"; Path = "include\7zip\7z.exe"},
        @{Name = "Resource Hacker"; Path = "include\ResourceHacker\ResourceHacker.exe"}
    )
    
    foreach ($binary in $requiredBinaries) {
        $fullPath = Join-Path $installDir $binary.Path
        $verifyResult = VerifyBinary -ExePath $fullPath
        
        if ($verifyResult.code -eq 0) {
            Write-BuildLog "$($binary.Name) verified: $fullPath" "INFO"
            Write-Host "  ✓ $($binary.Name) found" -ForegroundColor Green
        } else {
            Write-BuildLog "$($binary.Name) verification failed: $($verifyResult.msg)" "ERROR"
            Write-Host "  ✗ $($binary.Name) not found" -ForegroundColor Red
            throw "Required binary not found: $($binary.Name)"
        }
    }
    
    # Step 4: Create temporary workspace
    Write-Host "`n[Step 3/6] Creating temporary workspace..." -ForegroundColor Yellow
    $tempResult = CreateHiddenTempData
    
    if ($tempResult.code -ne 0) {
        Write-BuildLog $tempResult.msg "ERROR"
        throw "Failed to create temporary workspace"
    }
    
    Write-BuildLog "Temporary workspace created: $($tempResult.data)" "INFO"
    Write-Host "  ✓ Workspace created at: $($tempResult.data)" -ForegroundColor Green
    
    # Step 5: Prepare SFX module
    Write-Host "`n[Step 4/6] Preparing SFX module ($SFXMode)..." -ForegroundColor Yellow
    $sfxResult = PrepareSFX -SFXmod $SFXMode
    
    if ($sfxResult.code -ne 0) {
        Write-BuildLog $sfxResult.msg "ERROR"
        # Clean up before throwing error
        CleanHiddenTempData | Out-Null
        throw "Failed to prepare SFX module"
    }
    
    Write-BuildLog "SFX module prepared: $($sfxResult.data)" "INFO"
    Write-Host "  ✓ SFX module ready: $($sfxResult.msg)" -ForegroundColor Green
    
    # Step 6: Prepare configuration file
    Write-Host "`n[Step 5/6] Preparing configuration file..." -ForegroundColor Yellow
    $cfgResult = PrepareCFG -SFXmod $SFXMode
    
    if ($cfgResult.code -ne 0) {
        Write-BuildLog $cfgResult.msg "ERROR"
        # Clean up before throwing error
        CleanHiddenTempData | Out-Null
        throw "Failed to prepare configuration file"
    }
    
    Write-BuildLog "Configuration file prepared: $($cfgResult.data)" "INFO"
    Write-Host "  ✓ Configuration ready: $($cfgResult.msg)" -ForegroundColor Green
    
    # Step 7: Simulate additional build steps
    Write-Host "`n[Step 6/6] Build process simulation..." -ForegroundColor Yellow
    Write-BuildLog "At this point, the actual build process would execute" "DEBUG"
    Write-BuildLog "- Copy PowerShell scripts to tmpdata" "DEBUG"
    Write-BuildLog "- Create runapp.json configuration" "DEBUG"
    Write-BuildLog "- Package files into 7z archive" "DEBUG"
    Write-BuildLog "- Combine SFX module + config + archive = executable" "DEBUG"
    Write-BuildLog "- Apply icon using Resource Hacker" "DEBUG"
    Write-Host "  ✓ Build steps would execute here" -ForegroundColor Green
    
    # Step 8: Clean up temporary workspace
    Write-Host "`n[Cleanup] Cleaning temporary workspace..." -ForegroundColor Yellow
    $cleanResult = CleanHiddenTempData
    
    if ($cleanResult.code -eq 0) {
        Write-BuildLog "Temporary workspace cleaned successfully" "INFO"
        Write-Host "  ✓ Workspace cleaned" -ForegroundColor Green
    } else {
        Write-BuildLog "Warning: Failed to clean temporary workspace: $($cleanResult.msg)" "WARN"
        Write-Host "  ⚠ Cleanup warning: $($cleanResult.msg)" -ForegroundColor Yellow
    }
    
    # Success message
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Build process completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-BuildLog "Build process completed successfully" "INFO"
    
    # Display log file location
    Write-Host "`nLog file saved to: $LogFile" -ForegroundColor Gray
    
    # Ask if user wants to view the log
    $viewLog = Read-Host "`nWould you like to view the log file? (Y/N)"
    if ($viewLog -eq 'Y' -or $viewLog -eq 'y') {
        Get-Content -Path $LogFile | Write-Host
    }
}
catch {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Build process failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    Write-BuildLog "Build process failed: $($_.Exception.Message)" "ERROR"
    
    # Display log file location
    Write-Host "`nCheck log file for details: $LogFile" -ForegroundColor Yellow
    
    exit 1
}
