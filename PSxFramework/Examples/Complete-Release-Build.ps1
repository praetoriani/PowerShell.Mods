<#
.SYNOPSIS
    Complete PSx Composer release build example with all new functions

.DESCRIPTION
    This script demonstrates a complete end-to-end build workflow using all PSxFramework
    functions including the new data bundling, archive creation, and release generation.
    
    Workflow:
    1. Initialize logging and verify installation
    2. Create temporary workspace
    3. Prepare application data
    4. Create 7z archive
    5. Prepare SFX module and configuration
    6. Create final executable with checksum
    7. Clean up temporary files

.NOTES
    Author: Praetoriani (a.k.a. M.Sczepanski)
    Date: 01.02.2026
    Version: 1.0
    
    Requirements:
    - PSxFramework module must be installed and imported
    - PSx Composer must be installed on the system
    - Source application files must exist
#>

#Requires -Modules PSxFramework

# ============================================================================
# Configuration Section
# ============================================================================

$Config = @{
    # Application Information
    AppName = "MyApplication"
    AppVersion = "v1.00.00"
    
    # Source Data
    SourceDataPath = "C:\Development\MyApp\Release"  # Your application files
    
    # Build Settings
    SFXMode = "GUI-Mode"  # Options: GUI-Mode, CMD-Mode, Installer, Custom
    CompressionLevel = 7   # 0-9 (0=none, 9=maximum)
    
    # Release Settings
    BuildMethod = ""       # "" (auto), "system", or "dotnet"
    CreateChecksum = $true
    ChecksumMethod = 512   # 256 or 512
    
    # Logging
    LogFile = "$env:TEMP\psx_release_build.log"
}

# ============================================================================
# Helper Functions
# ============================================================================

function Write-BuildLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "DEBUG", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    
    # Write to log file
    WriteLogMessage -Logfile $Config.LogFile -Message $Message -Flag $Level
    
    # Write to console with color coding
    $color = switch ($Level) {
        "INFO"  { "Green" }
        "DEBUG" { "Gray" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
    }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-BuildStep {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Result,
        
        [Parameter(Mandatory = $true)]
        [string]$SuccessMessage,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )
    
    if ($Result.code -eq 0) {
        Write-BuildLog $SuccessMessage "INFO"
        return $true
    }
    else {
        Write-BuildLog "$ErrorMessage : $($Result.msg)" "ERROR"
        return $false
    }
}

# ============================================================================
# Main Build Process
# ============================================================================

try {
    Write-Host "`n" -NoNewline
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host "PSx Composer - Complete Release Build" -ForegroundColor Cyan
    Write-Host "="*80 -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Application: $($Config.AppName) $($Config.AppVersion)" -ForegroundColor White
    Write-Host "SFX Mode: $($Config.SFXMode)" -ForegroundColor White
    Write-Host "Compression: Level $($Config.CompressionLevel)" -ForegroundColor White
    Write-Host "Checksum: $(if($Config.CreateChecksum){"SHA$($Config.ChecksumMethod)"}else{"No"})" -ForegroundColor White
    Write-Host ""
    
    # Initialize logging
    Write-BuildLog "=== Starting Release Build Process ===" "INFO"
    Write-BuildLog "Application: $($Config.AppName) $($Config.AppVersion)" "DEBUG"
    Write-BuildLog "Log file: $($Config.LogFile)" "DEBUG"
    
    # ========================================================================
    # Step 1: Verify PSx Composer Installation
    # ========================================================================
    Write-Host "[Step 1/8] Verifying PSx Composer installation..." -ForegroundColor Yellow
    
    $installResult = GetInstallDir
    if (-not (Test-BuildStep $installResult "PSx Composer installation verified" "PSx Composer not found")) {
        throw "PSx Composer installation verification failed"
    }
    
    $installDir = $installResult.data
    Write-Host "  Installation: $installDir" -ForegroundColor Gray
    
    # ========================================================================
    # Step 2: Verify Source Data Exists
    # ========================================================================
    Write-Host "`n[Step 2/8] Verifying source data..." -ForegroundColor Yellow
    
    if (-not (Test-Path -Path $Config.SourceDataPath -PathType Container)) {
        Write-BuildLog "Source data path does not exist: $($Config.SourceDataPath)" "ERROR"
        throw "Source data verification failed"
    }
    
    $sourceItems = Get-ChildItem -Path $Config.SourceDataPath -Force
    if ($sourceItems.Count -eq 0) {
        Write-BuildLog "Source data directory is empty: $($Config.SourceDataPath)" "ERROR"
        throw "Source data verification failed"
    }
    
    Write-BuildLog "Source data verified: $($sourceItems.Count) items found" "INFO"
    Write-Host "  Source: $($Config.SourceDataPath)" -ForegroundColor Gray
    Write-Host "  Items: $($sourceItems.Count)" -ForegroundColor Gray
    
    # ========================================================================
    # Step 3: Create Temporary Workspace
    # ========================================================================
    Write-Host "`n[Step 3/8] Creating temporary workspace..." -ForegroundColor Yellow
    
    $tempResult = CreateHiddenTempData
    if (-not (Test-BuildStep $tempResult "Temporary workspace created" "Failed to create workspace")) {
        throw "Workspace creation failed"
    }
    
    Write-Host "  Workspace: $($tempResult.data)" -ForegroundColor Gray
    
    # ========================================================================
    # Step 4: Prepare Application Data Bundle
    # ========================================================================
    Write-Host "`n[Step 4/8] Preparing application data bundle..." -ForegroundColor Yellow
    
    $destPath = Join-Path $installDir "tmpdata\$($Config.AppName)"
    $bundleResult = PrepareDataBundle -DataSource $Config.SourceDataPath -DestFolder $destPath
    
    if (-not (Test-BuildStep $bundleResult "Application data bundle prepared" "Failed to prepare data bundle")) {
        CleanHiddenTempData | Out-Null
        throw "Data bundle preparation failed"
    }
    
    Write-Host "  Destination: $destPath" -ForegroundColor Gray
    Write-Host "  Status: $($bundleResult.msg)" -ForegroundColor Gray
    
    # ========================================================================
    # Step 5: Create 7z Archive
    # ========================================================================
    Write-Host "`n[Step 5/8] Creating 7z archive..." -ForegroundColor Yellow
    
    $archiveResult = CreateDataBundle -InputPath $destPath -Filename $Config.AppName -CompLvl $Config.CompressionLevel
    
    if (-not (Test-BuildStep $archiveResult "7z archive created successfully" "Failed to create archive")) {
        CleanHiddenTempData | Out-Null
        throw "Archive creation failed"
    }
    
    Write-Host "  Archive: $($archiveResult.data)" -ForegroundColor Gray
    Write-Host "  Details: $($archiveResult.msg)" -ForegroundColor Gray
    
    # ========================================================================
    # Step 6: Prepare SFX Module and Configuration
    # ========================================================================
    Write-Host "`n[Step 6/8] Preparing SFX module and configuration..." -ForegroundColor Yellow
    
    # Prepare SFX module
    $sfxResult = PrepareSFX -SFXmod $Config.SFXMode
    if (-not (Test-BuildStep $sfxResult "SFX module prepared" "Failed to prepare SFX module")) {
        CleanHiddenTempData | Out-Null
        throw "SFX preparation failed"
    }
    
    Write-Host "  SFX: $($sfxResult.msg)" -ForegroundColor Gray
    
    # Prepare configuration
    $cfgResult = PrepareCFG -SFXmod $Config.SFXMode
    if (-not (Test-BuildStep $cfgResult "Configuration prepared" "Failed to prepare configuration")) {
        CleanHiddenTempData | Out-Null
        throw "Configuration preparation failed"
    }
    
    Write-Host "  Config: $($cfgResult.msg)" -ForegroundColor Gray
    
    # ========================================================================
    # Step 7: Create Final Release
    # ========================================================================
    Write-Host "`n[Step 7/8] Creating final release executable..." -ForegroundColor Yellow
    
    $releaseParams = @{
        ReleaseName = $Config.AppName
        ReleaseVers = $Config.AppVersion
        SHAchecksum = $Config.CreateChecksum
        SHAmethod = $Config.ChecksumMethod
    }
    
    if (-not [string]::IsNullOrEmpty($Config.BuildMethod)) {
        $releaseParams.Method = $Config.BuildMethod
    }
    
    $releaseResult = CreateRelease @releaseParams
    
    if (-not (Test-BuildStep $releaseResult "Release executable created" "Failed to create release")) {
        CleanHiddenTempData | Out-Null
        throw "Release creation failed"
    }
    
    Write-Host "  Executable: $($releaseResult.data)" -ForegroundColor Gray
    Write-Host "  Details: $($releaseResult.msg)" -ForegroundColor Gray
    
    # ========================================================================
    # Step 8: Cleanup Temporary Files
    # ========================================================================
    Write-Host "`n[Step 8/8] Cleaning up temporary files..." -ForegroundColor Yellow
    
    $cleanResult = CleanHiddenTempData
    if ($cleanResult.code -eq 0) {
        Write-BuildLog "Temporary workspace cleaned" "INFO"
        Write-Host "  ✓ Cleanup completed" -ForegroundColor Green
    }
    else {
        Write-BuildLog "Cleanup warning: $($cleanResult.msg)" "WARN"
        Write-Host "  ⚠ Cleanup warning (non-critical)" -ForegroundColor Yellow
    }
    
    # ========================================================================
    # Build Complete - Summary
    # ========================================================================
    Write-Host ""
    Write-Host "="*80 -ForegroundColor Green
    Write-Host "BUILD COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "="*80 -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Release Information:" -ForegroundColor White
    Write-Host "  Name: $($Config.AppName)" -ForegroundColor Gray
    Write-Host "  Version: $($Config.AppVersion)" -ForegroundColor Gray
    Write-Host "  Executable: $($releaseResult.data)" -ForegroundColor Gray
    
    if ($Config.CreateChecksum) {
        $checksumFile = [System.IO.Path]::ChangeExtension($releaseResult.data, "checksum.txt")
        if (Test-Path $checksumFile) {
            Write-Host "  Checksum: $checksumFile" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "Log file: $($Config.LogFile)" -ForegroundColor Gray
    Write-Host ""
    
    Write-BuildLog "=== Build Process Completed Successfully ===" "INFO"
    
    # Open release folder in Explorer
    $releaseFolder = Split-Path -Path $releaseResult.data -Parent
    Start-Process explorer.exe -ArgumentList $releaseFolder
    
}
catch {
    Write-Host ""
    Write-Host "="*80 -ForegroundColor Red
    Write-Host "BUILD FAILED" -ForegroundColor Red
    Write-Host "="*80 -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    
    Write-BuildLog "Build process failed: $($_.Exception.Message)" "ERROR"
    Write-BuildLog "Stack trace: $($_.ScriptStackTrace)" "DEBUG"
    
    Write-Host "Check log file for details: $($Config.LogFile)" -ForegroundColor Yellow
    Write-Host ""
    
    exit 1
}
