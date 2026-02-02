# PSAppCoreLib PowerShell Module

> **⚠️ Important Notice:**  
> This module is under active development. While most functions have been thoroughly tested, not all functions have undergone complete testing in all scenarios. You may encounter bugs or unexpected behavior. Please report any issues you find, and always test in a non-production environment first.

## Overview

PSAppCoreLib is a comprehensive PowerShell module that provides a collection of useful functions for PowerShell application development. This module includes advanced functions for logging, registry management, file and directory operations, process control, Windows service management, and icon extraction.

## Module Information

- **Name**: PSAppCoreLib
- **Version**: 1.06.00  
- **Author**: Praetoriani (a.k.a. M.Sczepanski)
- **Website**: [github.com/praetoriani](https://github.com/praetoriani)
- **Root Module**: PSAppCoreLib.psm1
- **Description**: Powerful collection of useful Windows system functions for PowerShell apps

## Requirements

- **PowerShell**: Version 5.1 or higher
- **.NET Framework**: 4.7.2 or higher (for Windows PowerShell)
- **PowerShell Core**: Supported on all platforms
- **Required Assemblies**: System.Drawing, System.Windows.Forms

## Installation

### Manual Installation

1. Clone the repository or download the ZIP file
2. Create a folder named `PSAppCoreLib` in one of your PowerShell module paths:
   - `$env:PSModulePath -split ';'` (Windows)
   - `$env:PSModulePath -split ':'` (Linux/macOS)
3. Copy all files from the `PSAppCoreLib` folder into this directory
4. Import the module: `Import-Module PSAppCoreLib`

## Module Structure

```text
PSAppCoreLib/
├── Private/                    # Internal helper functions (not exported)
│   └── OPSreturn.ps1           # Standardized return object (code/msg/data)
├── Public/                     # Public functions (exported)
│   ├── Registry Management
│   │   ├── CreateRegKey.ps1
│   │   ├── CreateRegVal.ps1
│   │   ├── DeleteRegKey.ps1
│   │   ├── DeleteRegVal.ps1
│   │   ├── GetRegEntryType.ps1
│   │   ├── GetRegEntryValue.ps1
│   │   └── SetNewRegValue.ps1
│   ├── File & Directory Management
│   │   ├── CreateNewDir.ps1
│   │   ├── CreateNewFile.ps1
│   │   ├── CopyDir.ps1
│   │   ├── RemoveDir.ps1
│   │   ├── RemoveDirs.ps1
│   │   ├── CopyFile.ps1
│   │   ├── CopyFiles.ps1
│   │   ├── RemoveFile.ps1
│   │   ├── RemoveFiles.ps1
│   │   ├── WriteTextToFile.ps1
│   │   └── ReadTextFile.ps1
│   ├── Special System Management
│   │   ├── RemoveOnReboot.ps1
│   │   └── RemoveAllOnReboot.ps1
│   ├── Process Management
│   │   ├── RunProcess.ps1
│   │   ├── GetProcessByName.ps1
│   │   ├── GetProcessByID.ps1
│   │   ├── RestartProcess.ps1
│   │   ├── StopProcess.ps1
│   │   └── KillProcess.ps1
│   ├── Service Management
│   │   ├── StartService.ps1
│   │   ├── RestartService.ps1
│   │   ├── ForceRestartService.ps1
│   │   ├── StopService.ps1
│   │   ├── KillService.ps1
│   │   └── SetServiceState.ps1
│   ├── Logging
│   │   └── WriteLogMessage.ps1
│   └── Miscellaneous
│       └── GetBitmapIconFromDLL.ps1
├── Examples/                   # Comprehensive usage examples
│   ├── 01_Registry_Management_Examples.ps1
│   ├── 02_File_Directory_Management_Examples.ps1
│   ├── 03_Process_Service_Management_Examples.ps1
│   ├── WriteLogMessage_Examples.ps1
│   └── GetBitmapIconFromDLL_Examples.ps1
├── PSAppCoreLib.psm1          # Main module file (loads Public/Private functions)
├── PSAppCoreLib.psd1          # Module manifest (Version 1.06.00)
└── README.md                   # This file
```

## Standardized Return Object (OPSreturn)

All functions in this module use a unified return object created by the private helper function `OPSreturn`:

```powershell
$status = OPSreturn -Code 0 -Message "Operation completed" -Data $someData
```

The object always has this structure:

```powershell
[PSCustomObject]@{
    code = 0      # 0 = success, -1 = error
    msg  = ""     # Error description or empty on success
    data = $null  # Optional payload object (file paths, handles, content, etc.)
}
```

This allows consistent error checking in your code:

```powershell
$result = CreateNewDir -Path "C:\Temp\Test"
if ($result.code -eq 0) {
    Write-Host "Success" -ForegroundColor Green
} else {
    Write-Warning $result.msg
}
```

## Function Overview (Version 1.06.00)

### Registry Management

- **CreateRegKey**  
  Creates new registry keys with validation (includes protection for critical paths).

- **CreateRegVal**  
  Creates registry values of all common types (String, ExpandString, DWord, QWord, MultiString, Binary).

- **DeleteRegKey**  
  Deletes registry keys with optional recursive deletion. Supports `-WhatIf`/`-Confirm`.

- **DeleteRegVal**  
  Deletes individual registry values.

- **GetRegEntryValue**  
  Reads registry values in a type-aware manner and returns the actual .NET type in the `data` field.

- **GetRegEntryType**  
  Returns the registry type (e.g., `REG_SZ`, `REG_DWORD`, `REG_MULTI_SZ`).

- **SetNewRegValue**  
  Updates existing registry values with validation and type conversion.

**Typical return value:**
```powershell
$result = GetRegEntryValue -KeyPath "HKCU:\Software\MyApp" -ValueName "Setting1"
$result.code  # 0 or -1
$result.msg   # Error text or empty
$result.data  # The read registry value
```

### File & Directory Management

- **CreateNewDir**  
  Creates new directories (local or UNC), including parent creation, reserved name checks, length validation.

- **CreateNewFile**  
  Creates new files with optional content and definable encoding (UTF8, ASCII, Unicode, etc.).

- **CopyDir**  
  Copies complete directory trees recursively, with exclude patterns and timestamp preservation.

- **CopyFile / CopyFiles**  
  Copies single or multiple files, including detailed reporting and StopOnError logic.

- **RemoveDir / RemoveDirs**  
  Safe directory deletion operations with protection for critical paths, optionally recursive.

- **RemoveFile / RemoveFiles**  
  Removes single or multiple files with detailed status reporting.

- **WriteTextToFile**  
  Writes text with desired encoding to files, optionally in override mode.

- **ReadTextFile**  
  Reads text files completely with defined encoding and returns content in the `data` field.

### Special System Management

- **RemoveOnReboot**  
  Schedules individual files/directories for deletion on next reboot (PendingFileRenameOperations).

- **RemoveAllOnReboot**  
  Marks complete directories including contents for removal on next reboot.

### Process Management

- **RunProcess**  
  Starts a process, optionally with arguments and optional wait for completion.  
  Returns the ProcessId in the `data` field.

- **GetProcessByName**  
  Returns the process (or its ID) by exact name match.

- **GetProcessByID**  
  Returns a process by PID (including handle).

- **RestartProcess**  
  Stops and restarts a process with the same command line.

- **StopProcess**  
  Attempts to stop a process gracefully.

- **KillProcess**  
  Forces immediate termination of a process.

### Service Management

- **StartService**  
  Starts a Windows service by name.

- **RestartService**  
  Restarts a service (Stop + Start).

- **ForceRestartService**  
  Forces a restart including kill on failure.

- **StopService**  
  Stops a service regularly.

- **KillService**  
  Terminates a service's process forcefully.

- **SetServiceState**  
  Sets the startup type of a service (Disabled, Manual, Automatic, AutomaticDelayed).

### Logging

- **WriteLogMessage**  
  Writes formatted log entries with timestamps and flags (INFO/DEBUG/WARN/ERROR).  
  Returns the actual log line written in the `data` field.

### Miscellaneous

- **GetBitmapIconFromDLL**  
  Extracts icons from DLLs and returns a `System.Drawing.Bitmap` object in the `data` field.

## Examples

In addition to the original example scripts, there are thematically grouped example scripts in the `Examples` folder:

- `01_Registry_Management_Examples.ps1` – Complete registry demo scenario
- `02_File_Directory_Management_Examples.ps1` – File and folder workflows
- `03_Process_Service_Management_Examples.ps1` – Process & service control
- `WriteLogMessage_Examples.ps1` – Logging patterns
- `GetBitmapIconFromDLL_Examples.ps1` – Icon extraction & saving

Example: Run Registry Management demo

```powershell
Import-Module PSAppCoreLib -Force
& "$PSScriptRoot\Examples\01_Registry_Management_Examples.ps1"
```

Example: Run File/Directory operations demo

```powershell
Import-Module PSAppCoreLib -Force
& "$PSScriptRoot\Examples\02_File_Directory_Management_Examples.ps1"
```

## Error Handling

Through `OPSreturn`, error handling is identical everywhere:

```powershell
$result = RunProcess -FilePath "notepad.exe"
if ($result.code -ne 0) {
    Write-Error "Failed to start process: $($result.msg)"
    return
}

# Success - continue with payload in data field
$pid = $result.data
```

## Advanced Function Features

All functions are implemented as Advanced Functions and provide:

- **[CmdletBinding()]** with good pipeline and parameter behavior
- **Parameter Validation** (ValidateSet, ValidateNotNullOrEmpty, etc.)
- **Verbose Output** via `Write-Verbose`
- **Clean Error Handling** using Try/Catch and OPSreturn
- **Help Texts** in PowerShell standard format (Get-Help compatible)

## Typical Usage

```powershell
# Load module
Import-Module PSAppCoreLib

# Show available functions
Get-Command -Module PSAppCoreLib

# Get help for a function
Get-Help CreateNewDir -Full

# Example: Create directory
$result = CreateNewDir -Path "C:\Temp\MyApp"
if ($result.code -eq 0) {
    Write-Host "Created: $($result.data)" -ForegroundColor Green
} else {
    Write-Warning $result.msg
}
```

## Version History

### Version 1.06.00 (Windows Service Management)
- StartService / RestartService / ForceRestartService
- StopService / KillService / SetServiceState
- Extended examples for processes & services

### Version 1.05.00 (Process Management)
- RunProcess, GetProcessByName, GetProcessByID
- RestartProcess, StopProcess, KillProcess

### Version 1.04.00 (Extended File Operations & Reboot Scheduling)
- CopyFile, CopyFiles, RemoveFile, RemoveFiles
- WriteTextToFile, ReadTextFile
- RemoveOnReboot, RemoveAllOnReboot

### Version 1.03.00 (File System Management)
- CreateNewDir, CreateNewFile, CopyDir, RemoveDir, RemoveDirs

### Version 1.02.00 (Extended Registry Management)
- DeleteRegKey, DeleteRegVal, GetRegEntryValue, GetRegEntryType, SetNewRegValue

### Version 1.01.00 (Registry Functions Update)
- CreateRegKey, CreateRegVal

### Version 1.00.00 (Initial Release)
- WriteLogMessage
- GetBitmapIconFromDLL

---

*Updated: 02 February 2026*  
*Author: Praetoriani (a.k.a. M.Sczepanski)*  
*Website: [github.com/praetoriani](https://github.com/praetoriani)*
