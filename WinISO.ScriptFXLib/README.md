# PSxFramework

**PowerShell Framework for PSx Composer**

A comprehensive PowerShell module providing core functionality for PSx Composer, a tool for creating PowerShell executables using SFX (Self-Extracting Archive) modules.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Functions](#functions)
  - [Logging](#logging)
  - [Installation Management](#installation-management)
  - [Binary Verification](#binary-verification)
  - [Temporary Data Management](#temporary-data-management)
  - [SFX Preparation](#sfx-preparation)
  - [Data Bundle Management](#data-bundle-management)
  - [Release Creation](#release-creation)
  - [Integrity Verification](#integrity-verification)
- [Complete Build Workflow](#complete-build-workflow)
- [Return Object Structure](#return-object-structure)
- [Architecture](#architecture)
- [Function Suggestions](#function-suggestions)
- [Contributing](#contributing)
- [License](#license)

---

## 🎯 Overview

PSxFramework is designed to support the PSx Composer application by providing modular, reusable functions for:

- Managing PSx Composer installation paths
- Verifying required binary dependencies
- Creating and managing temporary build directories
- Preparing SFX modules and configuration files
- Packaging application data into compressed archives
- Creating final self-extracting executables
- Generating integrity checksums
- Comprehensive logging capabilities

By separating these core functions into a dedicated module, the main PSx Composer application remains lightweight and maintainable.

---

## ✨ Features

- **🔍 Installation Detection**: Automatically locates PSx Composer installation via Windows Registry
- **✅ Binary Verification**: Validates existence of required executables (7-Zip, Resource Hacker, etc.)
- **📁 Temporary Directory Management**: Creates, cleans, and removes hidden temporary build directories
- **📦 SFX Module Support**: Prepares different SFX modules (GUI, Console, Installer, Custom)
- **⚙️ Configuration Management**: Handles SFX configuration template preparation
- **🗜️ Data Bundling**: Copies and packages application files into 7z archives
- **🏗️ Release Building**: Combines SFX, config, and archive into executable (system/dotnet methods)
- **🔐 Integrity Verification**: SHA256/SHA512 checksum generation
- **📝 Advanced Logging**: Timestamps, severity levels, and comprehensive error tracking
- **🛡️ Robust Error Handling**: Standardized return objects for consistent error reporting
- **🌐 Multi-Edition Support**: Compatible with PowerShell 5.1+ and PowerShell Core

---

## 📦 Requirements

- **PowerShell**: Version 5.1 or higher
- **.NET Framework**: 4.7.2 or higher (for Windows PowerShell)
- **Operating System**: Windows (requires registry access)
- **PSx Composer**: Installation required for full functionality
- **7-Zip**: Bundled with PSx Composer or external installation

---

## 💾 Installation

### Manual Installation

1. Clone or download the repository:
   ```powershell
   git clone https://github.com/praetoriani/PowerShell.Mods.git
   ```

2. Copy the `PSxFramework` folder to one of your PowerShell module paths:
   ```powershell
   # View your module paths
   $env:PSModulePath -split ';'
   
   # Example: Copy to user module directory
   Copy-Item -Path "./PSxFramework" -Destination "$HOME\Documents\PowerShell\Modules\" -Recurse
   ```

3. Import the module:
   ```powershell
   Import-Module PSxFramework
   ```

### Verify Installation

```powershell
# Check if module is loaded
Get-Module PSxFramework

# List available functions
Get-Command -Module PSxFramework
```

---

## 📚 Functions

### Logging

#### WriteLogMessage

Writes formatted log messages with timestamps and severity levels.

**Parameters:**
- `Logfile` (string, mandatory): Full path to log file
- `Message` (string, mandatory): Log message text
- `Flag` (string, optional): Severity level - `INFO`, `DEBUG`, `WARN`, `ERROR` (default: `DEBUG`)
- `Override` (int, optional): Overwrite file (1) or append (0) (default: 0)

**Example:**
```powershell
WriteLogMessage -Logfile "C:\Logs\build.log" -Message "Build started" -Flag "INFO"
WriteLogMessage -Logfile "C:\Logs\build.log" -Message "Processing files" -Flag "DEBUG"
WriteLogMessage -Logfile "C:\Logs\build.log" -Message "Error occurred" -Flag "ERROR"
```

---

### Installation Management

#### GetInstallDir

Retrieves the PSx Composer installation directory from Windows Registry.

**Parameters:** None

**Example:**
```powershell
$result = GetInstallDir
if ($result.code -eq 0) {
    Write-Host "Installation found at: $($result.data)"
} else {
    Write-Warning $result.msg
}
```

---

### Binary Verification

#### VerifyBinary

Verifies that an executable file exists at the specified path.

**Parameters:**
- `ExePath` (string, mandatory): Full path to executable file

**Example:**
```powershell
$installDir = (GetInstallDir).data
$sevenZipPath = Join-Path $installDir "include\7zip\7z.exe"

$result = VerifyBinary -ExePath $sevenZipPath
if ($result.code -eq 0) {
    Write-Host "7-Zip verified at: $($result.data)"
}
```

---

### Temporary Data Management

#### CreateHiddenTempData

Creates a hidden temporary directory for build operations.

**Parameters:** None

**Example:**
```powershell
$result = CreateHiddenTempData
if ($result.code -eq 0) {
    Write-Host "Temp directory created: $($result.data)"
}
```

---

#### CleanHiddenTempData

Removes all contents from temporary directory while preserving the directory itself.

**Parameters:** None

**Example:**
```powershell
# Clean up after build process
$result = CleanHiddenTempData
if ($result.code -eq 0) {
    Write-Host "Temp directory cleaned successfully"
}
```

---

#### RemoveHiddenTempData

Completely removes the temporary directory and all its contents.

**Parameters:** None

**Example:**
```powershell
# Complete cleanup during uninstall
$result = RemoveHiddenTempData
if ($result.code -eq 0) {
    Write-Host "Temp directory removed successfully"
}
```

---

### SFX Preparation

#### PrepareSFX

Copies the appropriate SFX module to the temporary directory.

**Parameters:**
- `SFXmod` (string, mandatory): SFX module type
  - `GUI-Mode`: 7z.sfx (graphical interface)
  - `CMD-Mode`: 7zCon.sfx (console mode)
  - `Installer`: 7zS2.sfx (installer mode)
  - `Custom`: 7zSD.sfx (custom dialog mode)

**Example:**
```powershell
# Prepare GUI-mode SFX module
$result = PrepareSFX -SFXmod "GUI-Mode"
if ($result.code -eq 0) {
    Write-Host "SFX module prepared: $($result.data)"
}
```

---

#### PrepareCFG

Copies and prepares the configuration file for the selected SFX module.

**Parameters:**
- `SFXmod` (string, mandatory): SFX module type (same values as PrepareSFX)

**Example:**
```powershell
# Prepare configuration for Installer mode
$result = PrepareCFG -SFXmod "Installer"
if ($result.code -eq 0) {
    Write-Host "Config file prepared: $($result.data)"
}
```

---

### Data Bundle Management

#### PrepareDataBundle

Copies application data from source directory to build directory.

**Parameters:**
- `DataSource` (string, mandatory): Source directory with application files
- `DestFolder` (string, mandatory): Destination directory (typically `{INSTALLDIR}\tmpdata\{APPNAME}`)

**Example:**
```powershell
$installDir = (GetInstallDir).data
$appName = "MyApplication"
$destPath = Join-Path $installDir "tmpdata\$appName"

$result = PrepareDataBundle -DataSource "C:\MyApp\Files" -DestFolder $destPath
if ($result.code -eq 0) {
    Write-Host "Data prepared: $($result.msg)"
}
```

---

#### CreateDataBundle

Creates a 7z archive from prepared application data.

**Parameters:**
- `InputPath` (string, mandatory): Directory to compress
- `7zBinary` (string, optional): Path to 7z.exe (default: bundled version)
- `Filename` (string, mandatory): Archive name (without .7z extension)
- `Output` (string, optional): Output directory (default: `{INSTALLDIR}\tmpdata`)
- `CompLvl` (int, optional): Compression level 0-9 (default: 5)

**Example:**
```powershell
$result = CreateDataBundle -InputPath "C:\PSx\tmpdata\MyApp" -Filename "MyApp" -CompLvl 7
if ($result.code -eq 0) {
    Write-Host "Archive created: $($result.data)"
}
```

---

### Release Creation

#### CreateRelease

Combines SFX module, config, and archive into final executable.

**Parameters:**
- `ReleaseName` (string, mandatory): Application name
- `ReleaseVers` (string, mandatory): Version (e.g., "v1.00.00")
- `Method` (string, optional): "system" or "dotnet" (default: auto-tries both)
- `OutputPath` (string, optional): Output directory
- `SHAchecksum` (bool, optional): Create checksum file (default: $false)
- `SHAmethod` (int, optional): 256 or 512 (default: 256)

**Example:**
```powershell
$result = CreateRelease -ReleaseName "MyApp" -ReleaseVers "v1.00.00" -SHAchecksum $true
if ($result.code -eq 0) {
    Write-Host "Release created: $($result.data)"
}
```

---

### Integrity Verification

#### CreateChecksum

Generates SHA256 or SHA512 checksum file.

**Parameters:**
- `InputFile` (string, mandatory): File to checksum
- `SHA` (int, optional): 256 or 512 (default: 256)
- `OutputPath` (string, optional): Output directory

**Example:**
```powershell
$result = CreateChecksum -InputFile "C:\Release\MyApp.exe" -SHA 512
if ($result.code -eq 0) {
    Write-Host "Checksum created: $($result.data)"
}
```

---

## 🔄 Complete Build Workflow

```powershell
# Import module
Import-Module PSxFramework

# Initialize logging
$logFile = "C:\Logs\build.log"
WriteLogMessage -Logfile $logFile -Message "Starting build" -Flag "INFO" -Override 1

# Verify installation
$installResult = GetInstallDir
if ($installResult.code -ne 0) { exit 1 }
$installDir = $installResult.data

# Create temp workspace
CreateHiddenTempData

# Prepare data
$appName = "MyApplication"
$destPath = Join-Path $installDir "tmpdata\$appName"
PrepareDataBundle -DataSource "C:\MyApp\Source" -DestFolder $destPath

# Create 7z archive
CreateDataBundle -InputPath $destPath -Filename $appName -CompLvl 7

# Prepare SFX and config
PrepareSFX -SFXmod "GUI-Mode"
PrepareCFG -SFXmod "GUI-Mode"

# Create release with checksum
$releaseResult = CreateRelease -ReleaseName $appName -ReleaseVers "v1.00.00" -SHAchecksum $true -SHAmethod 512

if ($releaseResult.code -eq 0) {
    WriteLogMessage -Logfile $logFile -Message "Build completed: $($releaseResult.data)" -Flag "INFO"
}

# Cleanup
CleanHiddenTempData
```

---

## 🔄 Return Object Structure

All functions in this module use a standardized return object structure:

```powershell
[PSCustomObject]@{
    code = 0 | -1          # 0 = Success, -1 = Failure
    msg  = "Message"       # Detailed status or error message
    data = $value          # Optional data payload (paths, objects, etc.)
}
```

**Usage Pattern:**

```powershell
$result = SomeFunction -Parameter "Value"

if ($result.code -eq 0) {
    # Success - use $result.data if needed
    Write-Host "Success: $($result.msg)"
} else {
    # Failure - handle error using $result.msg
    Write-Error "Error: $($result.msg)"
}
```

---

## 🏗️ Architecture

### Module Structure

```
PSxFramework/
├── PSxFramework.psd1           # Module manifest
├── PSxFramework.psm1           # Module loader
├── README.md                   # This file
├── Private/
│   └── OPSreturn.ps1          # Internal helper function
├── Public/
│   ├── WriteLogMessage.ps1     # Logging function
│   ├── GetInstallDir.ps1       # Installation detection
│   ├── VerifyBinary.ps1        # Binary verification
│   ├── CreateHiddenTempData.ps1 # Create temp directory
│   ├── CleanHiddenTempData.ps1  # Clean temp directory
│   ├── RemoveHiddenTempData.ps1 # Remove temp directory
│   ├── PrepareSFX.ps1          # Prepare SFX modules
│   ├── PrepareCFG.ps1          # Prepare config files
│   ├── PrepareDataBundle.ps1   # Prepare application data
│   ├── CreateDataBundle.ps1    # Create 7z archives
│   ├── CreateChecksum.ps1      # Generate checksums
│   └── CreateRelease.ps1       # Create final executable
└── Examples/
    ├── Complete-Build-Example.ps1
    └── Individual-Function-Examples.ps1
```

### Design Principles

1. **Modularity**: Each function has a single, well-defined purpose
2. **Consistency**: All functions use the same return object structure
3. **Robustness**: Comprehensive error handling and validation
4. **Documentation**: Extensive inline comments and help documentation
5. **Reusability**: Functions can be used independently or combined

---

## 💡 Function Suggestions

### Recommended Additional Functions (Public)

1. **SetApplicationIcon**
   - Uses Resource Hacker to apply custom icons to executables
   - Parameters: ExePath, IconPath, ResourceHackerPath (optional)
   - Integrates with CreateRelease workflow

2. **ValidateRelease**
   - Comprehensive validation of created executable
   - Checks file size, PE header, digital signature status
   - Verifies SFX module integrity

3. **CreateVersionInfo**
   - Generates version information resource data
   - Parameters: Product name, version, company, copyright, etc.
   - Can be embedded in executable

4. **CompressWithLZMA**
   - Alternative compression using LZMA2 algorithm
   - Better compression ratio for certain file types
   - Parameters similar to CreateDataBundle

5. **BackupRelease**
   - Creates backup copies of releases with timestamps
   - Organizes backups in dated folders
   - Cleanup of old backups based on retention policy

6. **PublishRelease**
   - Copies release to deployment/distribution locations
   - Supports network shares, FTP, cloud storage
   - Creates deployment manifest

### Recommended Additional Functions (Private/Helper)

1. **ValidateParameter**
   - Centralized parameter validation helper
   - Reduces code duplication across functions
   - Returns standardized validation errors

2. **InvokeProcessSafely**
   - Wrapper for Process.Start with timeout and error handling
   - Captures stdout/stderr consistently
   - Used by CreateDataBundle, CreateRelease, etc.

3. **EnsureDirectory**
   - Creates directory if not exists
   - Handles permission issues gracefully
   - Returns OPSreturn object

4. **GetFileSize**
   - Returns formatted file size (KB, MB, GB)
   - Consistent formatting across all functions

5. **WriteVerboseLog**
   - Enhanced verbose output for debugging
   - Conditional logging based on verbosity level
   - Timestamps and caller information

---

## 🤝 Contributing

Contributions are welcome! Please ensure:

- Code follows existing style and conventions
- All functions include comprehensive comment-based help
- Error handling uses the OPSreturn helper function
- Code is written in English
- Functions are properly tested

---

## 📄 License

Copyright © 2026 Praetoriani (M.Sczepanski). All rights reserved.

---

## 📞 Contact & Support

- **GitHub**: [https://github.com/praetoriani/PowerShell.Mods](https://github.com/praetoriani/PowerShell.Mods)
- **Author**: Praetoriani (a.k.a. M.Sczepanski)

---

## 📝 Version History

### Version 1.00.00 (Initial Release - February 1, 2026)

**Core Functions:**
- ✅ WriteLogMessage: Advanced logging with timestamps and severity flags
- ✅ GetInstallDir: Registry-based installation detection
- ✅ VerifyBinary: Executable file verification
- ✅ CreateHiddenTempData: Hidden temporary directory creation
- ✅ CleanHiddenTempData: Temporary directory content removal
- ✅ RemoveHiddenTempData: Complete temporary directory removal
- ✅ PrepareSFX: SFX module preparation
- ✅ PrepareCFG: Configuration file preparation
- ✅ PrepareDataBundle: Application data preparation and copying
- ✅ CreateDataBundle: 7z archive creation with compression control
- ✅ CreateChecksum: SHA256/SHA512 integrity verification
- ✅ CreateRelease: Final executable creation (system/dotnet methods)

**Features:**
- ✅ Standardized return object structure (OPSreturn)
- ✅ Comprehensive error handling
- ✅ Full English documentation
- ✅ PowerShell 5.1+ and Core compatibility
- ✅ Modular architecture with Public/Private function separation
- ✅ Complete build workflow support

---

*Built with ❤️ for the PowerShell community*
