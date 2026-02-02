# PSAppCoreLib Developer Guide

## Table of Contents

- [Introduction](#introduction)
- [Return Object Structure](#return-object-structure)
- [Windows Registry Management](#windows-registry-management)
  - [CreateRegKey](#createregkey)
  - [CreateRegVal](#createregval)
  - [DeleteRegKey](#deleteregkey)
  - [DeleteRegVal](#deleteregval)
  - [GetRegEntryValue](#getregentryvalue)
  - [GetRegEntryType](#getregentrytype)
  - [SetNewRegValue](#setnewregvalue)
- [File and Directory Management](#file-and-directory-management)
  - [CreateNewDir](#createnewdir)
  - [CreateNewFile](#createnewfile)
  - [CopyDir](#copydir)
  - [RemoveDir](#removedir)
  - [RemoveDirs](#removedirs)
  - [CopyFile](#copyfile)
  - [CopyFiles](#copyfiles)
  - [RemoveFile](#removefile)
  - [RemoveFiles](#removefiles)
  - [WriteTextToFile](#writetexttofile)
  - [ReadTextFile](#readtextfile)
- [Special System Management](#special-system-management)
  - [RemoveOnReboot](#removeonreboot)
  - [RemoveAllOnReboot](#removeallonreboot)
- [Process Management](#process-management)
  - [RunProcess](#runprocess)
  - [GetProcessByName](#getprocessbyname)
  - [GetProcessByID](#getprocessbyid)
  - [RestartProcess](#restartprocess)
  - [StopProcess](#stopprocess)
  - [KillProcess](#killprocess)
- [Service Management](#service-management)
  - [StartService](#startservice)
  - [RestartService](#restartservice)
  - [ForceRestartService](#forcerestartservice)
  - [StopService](#stopservice)
  - [KillService](#killservice)
  - [SetServiceState](#setservicestate)
- [Logging](#logging)
  - [WriteLogMessage](#writelogmessage)
- [Miscellaneous](#miscellaneous)
  - [GetBitmapIconFromDLL](#getbitmapic onfromdll)

---

## Introduction

PSAppCoreLib is a powerful collection of useful Windows System functions designed for PowerShell application development. This guide provides comprehensive documentation for all public functions available in the module.

### Prerequisites

- PowerShell 5.1 or higher
- .NET Framework 4.7.2 or higher
- Windows Operating System
- Administrator privileges (for some functions)

### Installation

```powershell
# Import the module
Import-Module PSAppCoreLib

# Verify module loaded
Get-Module PSAppCoreLib

# List all available functions
Get-Command -Module PSAppCoreLib
```

---

## Return Object Structure

All functions in PSAppCoreLib use a standardized return object structure provided by the internal `OPSreturn` function:

```powershell
[PSCustomObject]@{
    code = [int]      # 0 = Success, -1 = Error
    msg  = [string]   # Error message (empty on success)
    data = [object]   # Additional return data (varies by function)
}
```

### Usage Example

```powershell
$result = SomeFunction -Parameter "Value"

if ($result.code -eq 0) {
    Write-Host "Success!"
    # Access additional data
    Write-Host "Data: $($result.data)"
} else {
    Write-Host "Error: $($result.msg)"
}
```

---

## Windows Registry Management

### CreateRegKey

**Description:** Creates a new Windows Registry key with comprehensive validation and error handling.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RegistryPath` | string | Yes | Full registry path (e.g., "HKLM:\Software\MyApp") |
| `Force` | switch | No | Create parent keys if they don't exist |

**Return Data:**

- `RegistryPath`: Full path to the created key
- `KeyName`: Name of the created key
- `ParentPath`: Path to parent key

**Example:**

```powershell
# Create a registry key
$result = CreateRegKey -RegistryPath "HKLM:\Software\MyApplication\Settings"

if ($result.code -eq 0) {
    Write-Host "Registry key created: $($result.data.RegistryPath)"
} else {
    Write-Host "Error: $($result.msg)"
}

# Create with Force to create parent keys
$result = CreateRegKey -RegistryPath "HKCU:\Software\MyApp\Config\Advanced" -Force
```

**Notes:**

- Supports both local and remote registry operations
- Validates registry hive names (HKLM, HKCU, HKCR, HKU, HKCC)
- Prevents creation of system-critical registry paths
- Requires appropriate permissions

---

### CreateRegVal

**Description:** Creates a new registry value with support for all registry data types.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RegistryPath` | string | Yes | Full registry key path |
| `ValueName` | string | Yes | Name of the registry value |
| `ValueData` | object | Yes | Data to store in the value |
| `ValueType` | string | Yes | Type: String, ExpandString, Binary, DWord, QWord, MultiString |
| `Force` | switch | No | Overwrite existing value |

**Return Data:**

- `RegistryPath`: Full path to the key
- `ValueName`: Name of created value
- `ValueData`: Data stored
- `ValueType`: Type of the value

**Example:**

```powershell
# Create a string value
$result = CreateRegVal -RegistryPath "HKLM:\Software\MyApp" `
                       -ValueName "ApplicationPath" `
                       -ValueData "C:\Program Files\MyApp" `
                       -ValueType "String"

# Create a DWORD value
$result = CreateRegVal -RegistryPath "HKCU:\Software\MyApp\Settings" `
                       -ValueName "MaxConnections" `
                       -ValueData 100 `
                       -ValueType "DWord"

# Create a binary value
$binaryData = [byte[]](0x01, 0x02, 0x03, 0x04)
$result = CreateRegVal -RegistryPath "HKLM:\Software\MyApp" `
                       -ValueName "BinaryConfig" `
                       -ValueData $binaryData `
                       -ValueType "Binary"

# Create a multi-string value
$paths = @("C:\Path1", "C:\Path2", "C:\Path3")
$result = CreateRegVal -RegistryPath "HKCU:\Software\MyApp" `
                       -ValueName "SearchPaths" `
                       -ValueData $paths `
                       -ValueType "MultiString"
```

**Supported Value Types:**

- `String`: Regular string value (REG_SZ)
- `ExpandString`: Expandable string with environment variables (REG_EXPAND_SZ)
- `Binary`: Binary data (REG_BINARY)
- `DWord`: 32-bit integer (REG_DWORD)
- `QWord`: 64-bit integer (REG_QWORD)
- `MultiString`: Array of strings (REG_MULTI_SZ)

---

### DeleteRegKey

**Description:** Deletes a Windows Registry key with optional recursive deletion.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RegistryPath` | string | Yes | Full registry key path to delete |
| `Recurse` | switch | No | Delete key and all subkeys |

**Return Data:**

- `DeletedKeyPath`: Path to the deleted key
- `RecursiveDelete`: Boolean indicating if recursive delete was used

**Example:**

```powershell
# Delete a single registry key
$result = DeleteRegKey -RegistryPath "HKCU:\Software\MyApp\TempSettings"

if ($result.code -eq 0) {
    Write-Host "Key deleted: $($result.data.DeletedKeyPath)"
}

# Delete key and all subkeys recursively
$result = DeleteRegKey -RegistryPath "HKLM:\Software\OldApplication" -Recurse
```

**Notes:**

- Protected system-critical paths are prevented from deletion
- Requires confirmation for recursive deletions
- Supports `-WhatIf` and `-Confirm` parameters

---

### DeleteRegVal

**Description:** Deletes a specific registry value from a key.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RegistryPath` | string | Yes | Full registry key path |
| `ValueName` | string | Yes | Name of the value to delete |

**Return Data:**

- `RegistryPath`: Path to the key
- `DeletedValueName`: Name of deleted value

**Example:**

```powershell
# Delete a specific registry value
$result = DeleteRegVal -RegistryPath "HKCU:\Software\MyApp\Settings" `
                       -ValueName "ObsoleteOption"

if ($result.code -eq 0) {
    Write-Host "Value deleted: $($result.data.DeletedValueName)"
}
```

---

### GetRegEntryValue

**Description:** Reads a registry value with type-aware handling and conversion.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RegistryPath` | string | Yes | Full registry key path |
| `ValueName` | string | Yes | Name of the value to read |

**Return Data:**

- `RegistryPath`: Path to the key
- `ValueName`: Name of the value
- `ValueData`: The actual data
- `ValueType`: Registry type

**Example:**

```powershell
# Read a registry value
$result = GetRegEntryValue -RegistryPath "HKLM:\Software\Microsoft\Windows\CurrentVersion" `
                           -ValueName "ProgramFilesDir"

if ($result.code -eq 0) {
    Write-Host "Value: $($result.data.ValueData)"
    Write-Host "Type: $($result.data.ValueType)"
}

# Read and use binary data
$result = GetRegEntryValue -RegistryPath "HKCU:\Software\MyApp" `
                           -ValueName "BinaryConfig"
if ($result.code -eq 0) {
    $binaryData = $result.data.ValueData
    # Process binary data...
}
```

---

### GetRegEntryType

**Description:** Determines the data type of a registry value.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RegistryPath` | string | Yes | Full registry key path |
| `ValueName` | string | Yes | Name of the value |

**Return Data:**

- `RegistryPath`: Path to the key
- `ValueName`: Name of the value
- `ValueType`: Registry type (String, DWord, Binary, etc.)

**Example:**

```powershell
# Check registry value type
$result = GetRegEntryType -RegistryPath "HKLM:\Software\MyApp" `
                          -ValueName "Version"

if ($result.code -eq 0) {
    Write-Host "Value type: $($result.data.ValueType)"
    
    switch ($result.data.ValueType) {
        "String" { # Handle string }
        "DWord" { # Handle integer }
        "Binary" { # Handle binary data }
    }
}
```

---

### SetNewRegValue

**Description:** Updates an existing registry value with validation and type conversion.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RegistryPath` | string | Yes | Full registry key path |
| `ValueName` | string | Yes | Name of the value to update |
| `NewValueData` | object | Yes | New data to set |
| `ValueType` | string | No | New type (if changing type) |

**Return Data:**

- `RegistryPath`: Path to the key
- `ValueName`: Name of updated value
- `OldValueData`: Previous data
- `NewValueData`: New data
- `ValueType`: Current type

**Example:**

```powershell
# Update an existing string value
$result = SetNewRegValue -RegistryPath "HKCU:\Software\MyApp" `
                         -ValueName "InstallPath" `
                         -NewValueData "D:\MyApp"

# Update a DWORD value
$result = SetNewRegValue -RegistryPath "HKLM:\Software\MyApp\Settings" `
                         -ValueName "Timeout" `
                         -NewValueData 300

# Change value type while updating
$result = SetNewRegValue -RegistryPath "HKCU:\Software\MyApp" `
                         -ValueName "Port" `
                         -NewValueData 8080 `
                         -ValueType "DWord"

if ($result.code -eq 0) {
    Write-Host "Updated from: $($result.data.OldValueData)"
    Write-Host "Updated to: $($result.data.NewValueData)"
}
```

---

## File and Directory Management

### CreateNewDir

**Description:** Creates a new directory with comprehensive validation and parent directory creation.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DirectoryPath` | string | Yes | Full path for the new directory |
| `Force` | switch | No | Create parent directories if needed |

**Return Data:**

- `DirectoryPath`: Full path to created directory
- `CreationTime`: When the directory was created
- `ParentCreated`: Boolean indicating if parent was created

**Example:**

```powershell
# Create a simple directory
$result = CreateNewDir -DirectoryPath "C:\MyData\Archives"

if ($result.code -eq 0) {
    Write-Host "Directory created: $($result.data.DirectoryPath)"
}

# Create with nested parents
$result = CreateNewDir -DirectoryPath "D:\Projects\WebApp\Assets\Images" -Force

# Create on network share
$result = CreateNewDir -DirectoryPath "\\Server\Share\Backup\2026\January"
```

---

### CreateNewFile

**Description:** Creates a new file with optional content and encoding support.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `FilePath` | string | Yes | Full path for the new file |
| `Content` | string | No | Initial file content |
| `Encoding` | string | No | UTF8, ASCII, or Unicode (default: UTF8) |
| `Force` | switch | No | Overwrite if file exists |

**Return Data:**

- `FilePath`: Full path to created file
- `SizeBytes`: File size in bytes
- `Encoding`: Encoding used
- `CreationTime`: When file was created

**Example:**

```powershell
# Create empty file
$result = CreateNewFile -FilePath "C:\Logs\application.log"

# Create file with content
$content = "Application Log - Started at $(Get-Date)"
$result = CreateNewFile -FilePath "C:\Logs\app.log" -Content $content

# Create with specific encoding
$result = CreateNewFile -FilePath "C:\Data\unicode.txt" `
                        -Content "Üñíçødé téxt" `
                        -Encoding "Unicode"

# Overwrite existing file
$result = CreateNewFile -FilePath "C:\Temp\data.txt" `
                        -Content "New content" `
                        -Force

if ($result.code -eq 0) {
    Write-Host "File created: $($result.data.FilePath)"
    Write-Host "Size: $($result.data.SizeBytes) bytes"
}
```

---

### CopyDir

**Description:** Copies a complete directory with all its contents recursively.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SourcePath` | string | Yes | Source directory path |
| `DestinationPath` | string | Yes | Destination directory path |
| `Force` | switch | No | Overwrite existing files |
| `ExcludeFiles` | string[] | No | File patterns to exclude |
| `ExcludeDirs` | string[] | No | Directory patterns to exclude |

**Return Data:**

- `DestinationPath`: Full destination path
- `FilesCopied`: Number of files copied
- `DirectoriesCopied`: Number of directories copied
- `TotalSizeBytes`: Total size copied

**Example:**

```powershell
# Simple directory copy
$result = CopyDir -SourcePath "C:\Projects\MyApp" `
                  -DestinationPath "D:\Backup\MyApp"

if ($result.code -eq 0) {
    Write-Host "Copied $($result.data.FilesCopied) files"
    Write-Host "Copied $($result.data.DirectoriesCopied) directories"
    Write-Host "Total size: $($result.data.TotalSizeBytes) bytes"
}

# Copy with file exclusions
$result = CopyDir -SourcePath "C:\WebApp" `
                  -DestinationPath "D:\Backup" `
                  -ExcludeFiles @("*.tmp", "*.log", "*.cache")

# Copy with directory exclusions
$result = CopyDir -SourcePath "C:\Source" `
                  -DestinationPath "D:\Destination" `
                  -ExcludeDirs @(".git", ".svn", "node_modules", "bin", "obj") `
                  -Force

# Complex copy scenario
$result = CopyDir -SourcePath "C:\DevProject" `
                  -DestinationPath "\\Server\Backup" `
                  -ExcludeFiles @("*.tmp", "*.log", "debug.txt") `
                  -ExcludeDirs @(".vs", ".vscode", "packages") `
                  -Force
```

---

### RemoveDir

**Description:** Deletes a directory with safety checks and validation.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DirectoryPath` | string | Yes | Directory path to delete |
| `Recurse` | switch | No | Delete directory and all contents |
| `Force` | switch | No | Delete read-only and hidden items |

**Return Data:**

- `DeletedPath`: Path that was deleted
- `DeletedRecursively`: Boolean indicating recursive delete

**Example:**

```powershell
# Delete empty directory
$result = RemoveDir -DirectoryPath "C:\Temp\OldData"

# Delete directory and all contents
$result = RemoveDir -DirectoryPath "C:\Temp\ProjectBackup" -Recurse

if ($result.code -eq 0) {
    Write-Host "Deleted: $($result.data.DeletedPath)"
}

# Force delete including read-only files
$result = RemoveDir -DirectoryPath "C:\OldFiles" -Recurse -Force
```

**Notes:**

- Protected system paths (Windows, Program Files, System32) are prevented from deletion
- Requires confirmation for recursive deletions
- Supports `-WhatIf` and `-Confirm` parameters

---

### RemoveDirs

**Description:** Deletes multiple directories with detailed reporting.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DirectoryPaths` | string[] | Yes | Array of directory paths to delete |
| `Recurse` | switch | No | Delete directories and all contents |
| `Force` | switch | No | Delete read-only and hidden items |
| `StopOnError` | switch | No | Stop if any deletion fails |

**Return Data:**

- `SuccessCount`: Number of successfully deleted directories
- `FailureCount`: Number of failed deletions
- `DeletedDirectories`: Array of deleted paths
- `FailedDirectories`: Array with paths and error messages

**Example:**

```powershell
# Delete multiple directories
$dirs = @(
    "C:\Temp\Dir1",
    "C:\Temp\Dir2",
    "D:\OldBackup"
)
$result = RemoveDirs -DirectoryPaths $dirs -Recurse

Write-Host "Deleted: $($result.data.SuccessCount) directories"
Write-Host "Failed: $($result.data.FailureCount) directories"

# Check failed deletions
if ($result.data.FailedDirectories.Count -gt 0) {
    foreach ($failed in $result.data.FailedDirectories) {
        Write-Host "Failed to delete $($failed.Path): $($failed.Error)"
    }
}

# Stop on first error
$result = RemoveDirs -DirectoryPaths $dirs -Recurse -StopOnError
```

---

### CopyFile

**Description:** Copies a single file to a new location with timestamp preservation.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SourcePath` | string | Yes | Source file path |
| `DestinationPath` | string | Yes | Destination file path or directory |
| `Force` | switch | No | Overwrite existing file |
| `PreserveTimestamps` | bool | No | Preserve file timestamps (default: true) |

**Return Data:**

- `SourcePath`: Full source path
- `DestinationPath`: Full destination path
- `SizeBytes`: File size in bytes

**Example:**

```powershell
# Simple file copy
$result = CopyFile -SourcePath "C:\Data\report.pdf" `
                   -DestinationPath "D:\Backup\report.pdf"

if ($result.code -eq 0) {
    Write-Host "File copied: $($result.data.SourcePath)"
    Write-Host "To: $($result.data.DestinationPath)"
    Write-Host "Size: $($result.data.SizeBytes) bytes"
}

# Copy to directory (filename preserved)
$result = CopyFile -SourcePath "C:\Source\data.xlsx" `
                   -DestinationPath "D:\Archive\"

# Copy with overwrite
$result = CopyFile -SourcePath "C:\Logs\current.log" `
                   -DestinationPath "C:\Logs\archive.log" `
                   -Force

# Copy from network share
$result = CopyFile -SourcePath "\\Server\Share\file.zip" `
                   -DestinationPath "C:\Local\file.zip"
```

---

### CopyFiles

**Description:** Copies multiple files from various locations to a single destination directory.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `SourcePaths` | string[] | Yes | Array of source file paths |
| `DestinationDirectory` | string | Yes | Destination directory |
| `Force` | switch | No | Overwrite existing files |
| `PreserveTimestamps` | bool | No | Preserve timestamps (default: true) |
| `StopOnError` | switch | No | Stop if any copy fails |

**Return Data:**

- `DestinationDirectory`: Destination directory path
- `SuccessCount`: Number of successfully copied files
- `FailureCount`: Number of failed copies
- `TotalSizeBytes`: Total size copied
- `CopiedFiles`: Array of successfully copied files
- `FailedFiles`: Array of failed files with errors

**Example:**

```powershell
# Copy multiple files
$files = @(
    "C:\Data\file1.txt",
    "C:\Reports\file2.pdf",
    "D:\Images\photo.jpg"
)
$result = CopyFiles -SourcePaths $files -DestinationDirectory "E:\Backup"

Write-Host "Successfully copied: $($result.data.SuccessCount) files"
Write-Host "Failed: $($result.data.FailureCount) files"
Write-Host "Total size: $($result.data.TotalSizeBytes) bytes"

# Display copied files
foreach ($file in $result.data.CopiedFiles) {
    Write-Host "$($file.SourcePath) -> $($file.DestinationPath)"
}

# Copy log files with overwrite
$logs = Get-ChildItem "C:\Logs\*.log" | Select-Object -ExpandProperty FullName
$result = CopyFiles -SourcePaths $logs `
                    -DestinationDirectory "D:\LogArchive" `
                    -Force

# Stop on first error
$result = CopyFiles -SourcePaths $files `
                    -DestinationDirectory "E:\Backup" `
                    -StopOnError
```

---

### RemoveFile

**Description:** Deletes a single file with safety checks.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `FilePath` | string | Yes | File path to delete |
| `Force` | switch | No | Delete read-only and hidden files |

**Return Data:**

- `DeletedFilePath`: Path of deleted file
- `FileSizeBytes`: Size of deleted file

**Example:**

```powershell
# Delete a file
$result = RemoveFile -FilePath "C:\Temp\oldfile.txt"

if ($result.code -eq 0) {
    Write-Host "Deleted: $($result.data.DeletedFilePath)"
    Write-Host "Size: $($result.data.FileSizeBytes) bytes"
}

# Force delete read-only file
$result = RemoveFile -FilePath "C:\Data\readonly.dat" -Force
```

---

### RemoveFiles

**Description:** Deletes multiple files with detailed reporting.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `FilePaths` | string[] | Yes | Array of file paths to delete |
| `Force` | switch | No | Delete read-only and hidden files |
| `StopOnError` | switch | No | Stop if any deletion fails |

**Return Data:**

- `SuccessCount`: Number of successfully deleted files
- `FailureCount`: Number of failed deletions
- `TotalSizeBytes`: Total size of deleted files
- `DeletedFiles`: Array of deleted file details
- `FailedFiles`: Array with paths and error messages

**Example:**

```powershell
# Delete multiple files
$files = @(
    "C:\Temp\file1.tmp",
    "C:\Temp\file2.tmp",
    "D:\Cache\data.cache"
)
$result = RemoveFiles -FilePaths $files

Write-Host "Deleted: $($result.data.SuccessCount) files"
Write-Host "Failed: $($result.data.FailureCount) files"
Write-Host "Total size deleted: $($result.data.TotalSizeBytes) bytes"

# Delete all .tmp files
$tempFiles = Get-ChildItem "C:\Windows\Temp\*.tmp" | Select-Object -ExpandProperty FullName
$result = RemoveFiles -FilePaths $tempFiles -Force

# Display failed deletions
if ($result.data.FailedFiles.Count -gt 0) {
    foreach ($failed in $result.data.FailedFiles) {
        Write-Host "Failed: $($failed.FilePath) - $($failed.Error)"
    }
}
```

---

### WriteTextToFile

**Description:** Writes text content to a file with encoding support.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `FilePath` | string | Yes | File path to write to |
| `Content` | string | Yes | Text content to write |
| `Encoding` | string | No | UTF8, ASCII, or Unicode (default: UTF8) |
| `Append` | switch | No | Append to existing file |
| `Force` | switch | No | Overwrite existing file |

**Return Data:**

- `FilePath`: Full file path
- `SizeBytes`: File size after write
- `Encoding`: Encoding used
- `Appended`: Boolean indicating append mode

**Example:**

```powershell
# Write text to new file
$content = "This is my log entry for $(Get-Date)"
$result = WriteTextToFile -FilePath "C:\Logs\app.log" -Content $content

# Append to existing file
$newEntry = "`n[$(Get-Date)] Application event occurred"
$result = WriteTextToFile -FilePath "C:\Logs\app.log" `
                          -Content $newEntry `
                          -Append

# Write with specific encoding
$unicodeText = "Spëçîål çhåråçtërs: ÄÖÜ äöü ßéè"
$result = WriteTextToFile -FilePath "C:\Data\unicode.txt" `
                          -Content $unicodeText `
                          -Encoding "Unicode"

# Overwrite existing file
$result = WriteTextToFile -FilePath "C:\Config\settings.txt" `
                          -Content "New configuration" `
                          -Force

if ($result.code -eq 0) {
    Write-Host "Written to: $($result.data.FilePath)"
    Write-Host "Size: $($result.data.SizeBytes) bytes"
}
```

---

### ReadTextFile

**Description:** Reads the complete content from a text file with encoding support.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `FilePath` | string | Yes | File path to read from |
| `Encoding` | string | No | UTF8, ASCII, or Unicode (default: UTF8) |

**Return Data:**

- `FilePath`: Full file path
- `Content`: File content as string
- `SizeBytes`: File size
- `Encoding`: Encoding used
- `LineCount`: Number of lines

**Example:**

```powershell
# Read text file
$result = ReadTextFile -FilePath "C:\Logs\application.log"

if ($result.code -eq 0) {
    Write-Host "File content:"
    Write-Host $result.data.Content
    Write-Host "`nLines: $($result.data.LineCount)"
    Write-Host "Size: $($result.data.SizeBytes) bytes"
}

# Read with specific encoding
$result = ReadTextFile -FilePath "C:\Data\unicode.txt" -Encoding "Unicode"

# Process file content
$result = ReadTextFile -FilePath "C:\Config\settings.txt"
if ($result.code -eq 0) {
    $lines = $result.data.Content -split "`n"
    foreach ($line in $lines) {
        # Process each line
        Write-Host $line
    }
}

# Read and parse log file
$result = ReadTextFile -FilePath "C:\Logs\errors.log"
if ($result.code -eq 0) {
    $errors = $result.data.Content | Select-String -Pattern "ERROR"
    Write-Host "Found $($errors.Count) error entries"
}
```

---

## Special System Management

### RemoveOnReboot

**Description:** Schedules a file or directory for deletion on the next system reboot using the Windows PendingFileRenameOperations mechanism.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Path` | string | Yes | File or directory path to delete on reboot |

**Return Data:**

- `ScheduledPath`: Path scheduled for deletion
- `IsDirectory`: Boolean indicating if path is directory
- `CurrentPendingOperations`: Number of total pending operations

**Example:**

```powershell
# Schedule file for deletion on reboot
$result = RemoveOnReboot -Path "C:\Windows\Temp\locked-file.dll"

if ($result.code -eq 0) {
    Write-Host "Scheduled for deletion: $($result.data.ScheduledPath)"
    Write-Host "Total pending operations: $($result.data.CurrentPendingOperations)"
    Write-Host "Restart required to complete deletion"
}

# Schedule directory for deletion
$result = RemoveOnReboot -Path "C:\ProgramData\OldApp"

# Schedule locked system file
$result = RemoveOnReboot -Path "C:\Windows\System32\old-driver.sys"
```

**Notes:**

- Requires Administrator privileges
- Changes take effect after system restart
- Useful for removing locked or in-use files
- Uses registry: `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations`

---

### RemoveAllOnReboot

**Description:** Schedules complete removal of a directory and all its contents on the next system reboot.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DirectoryPath` | string | Yes | Directory path to delete on reboot |

**Return Data:**

- `ScheduledPath`: Directory path scheduled for deletion
- `TotalItemsScheduled`: Number of items scheduled
- `FilesScheduled`: Number of files scheduled
- `DirectoriesScheduled`: Number of directories scheduled
- `CurrentPendingOperations`: Total pending operations

**Example:**

```powershell
# Schedule entire directory tree for deletion
$result = RemoveAllOnReboot -DirectoryPath "C:\Program Files\OldApplication"

if ($result.code -eq 0) {
    Write-Host "Scheduled for deletion: $($result.data.ScheduledPath)"
    Write-Host "Files to delete: $($result.data.FilesScheduled)"
    Write-Host "Directories to delete: $($result.data.DirectoriesScheduled)"
    Write-Host "Total items: $($result.data.TotalItemsScheduled)"
    Write-Host "System restart required"
}

# Schedule locked application directory
$result = RemoveAllOnReboot -DirectoryPath "C:\ProgramData\LockedApp"
```

**Notes:**

- Requires Administrator privileges
- Schedules all files and subdirectories recursively
- Changes take effect after system restart
- Use with caution - operation cannot be easily undone

---

## Process Management

### RunProcess

**Description:** Starts a new process with comprehensive options and returns the process ID.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `FilePath` | string | Yes | Path to executable |
| `Arguments` | string | No | Command line arguments |
| `WorkingDirectory` | string | No | Working directory for process |
| `WindowStyle` | string | No | Normal, Hidden, Minimized, Maximized |
| `Wait` | switch | No | Wait for process to complete |
| `PassThru` | switch | No | Return process object |

**Return Data:**

- `ProcessId`: ID of started process
- `ProcessName`: Name of the process
- `FilePath`: Executable path
- `ExitCode`: Exit code (if Wait was used)
- `StartTime`: When process started

**Example:**

```powershell
# Start a simple process
$result = RunProcess -FilePath "C:\Windows\System32\notepad.exe"

if ($result.code -eq 0) {
    Write-Host "Process started with ID: $($result.data.ProcessId)"
}

# Start with arguments
$result = RunProcess -FilePath "C:\Windows\System32\cmd.exe" `
                     -Arguments "/c dir C:\ > C:\output.txt"

# Start and wait for completion
$result = RunProcess -FilePath "C:\Tools\backup.exe" `
                     -Arguments "-full -path D:\Data" `
                     -Wait

if ($result.code -eq 0) {
    Write-Host "Process completed with exit code: $($result.data.ExitCode)"
}

# Start hidden process
$result = RunProcess -FilePath "C:\Scripts\maintenance.exe" `
                     -WindowStyle "Hidden" `
                     -WorkingDirectory "C:\Scripts"

# Start process and get object
$result = RunProcess -FilePath "powershell.exe" `
                     -Arguments "-File C:\Scripts\task.ps1" `
                     -PassThru

if ($result.code -eq 0) {
    $processId = $result.data.ProcessId
    # Monitor or manipulate process...
}
```

---

### GetProcessByName

**Description:** Gets a process by exact name match and returns the process ID.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ProcessName` | string | Yes | Exact name of the process (without .exe) |

**Return Data:**

- `ProcessId`: ID of the process
- `ProcessName`: Name of the process
- `StartTime`: When process started
- `Path`: Executable path
- `WorkingSet`: Memory usage in bytes

**Example:**

```powershell
# Get process by name
$result = GetProcessByName -ProcessName "notepad"

if ($result.code -eq 0) {
    Write-Host "Process ID: $($result.data.ProcessId)"
    Write-Host "Started: $($result.data.StartTime)"
    Write-Host "Memory: $($result.data.WorkingSet / 1MB) MB"
}

# Find and monitor specific process
$result = GetProcessByName -ProcessName "chrome"
if ($result.code -eq 0) {
    $pid = $result.data.ProcessId
    # Monitor or manage this process
}

# Check if application is running
$result = GetProcessByName -ProcessName "myapp"
if ($result.code -eq 0) {
    Write-Host "Application is running with PID: $($result.data.ProcessId)"
} else {
    Write-Host "Application is not running"
}
```

---

### GetProcessByID

**Description:** Gets a process by process ID and returns detailed process information.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ProcessId` | int | Yes | Process ID |

**Return Data:**

- `ProcessId`: ID of the process
- `ProcessName`: Name of the process
- `StartTime`: When process started
- `Path`: Executable path
- `WorkingSet`: Memory usage in bytes
- `Responding`: Boolean indicating if process is responding

**Example:**

```powershell
# Get process by ID
$result = GetProcessByID -ProcessId 1234

if ($result.code -eq 0) {
    Write-Host "Process: $($result.data.ProcessName)"
    Write-Host "Path: $($result.data.Path)"
    Write-Host "Memory: $([math]::Round($result.data.WorkingSet / 1MB, 2)) MB"
    Write-Host "Responding: $($result.data.Responding)"
}

# Check if process is still running
$pid = 5678
$result = GetProcessByID -ProcessId $pid
if ($result.code -eq 0) {
    if ($result.data.Responding) {
        Write-Host "Process is running and responding"
    } else {
        Write-Host "Process is running but not responding"
    }
} else {
    Write-Host "Process not found or terminated"
}
```

---

### RestartProcess

**Description:** Restarts a process by process ID (stops and restarts it).

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ProcessId` | int | Yes | Process ID to restart |
| `Arguments` | string | No | Arguments for restarted process |
| `WorkingDirectory` | string | No | Working directory |

**Return Data:**

- `OldProcessId`: ID of stopped process
- `NewProcessId`: ID of restarted process
- `ProcessName`: Name of the process
- `ExecutablePath`: Path to executable

**Example:**

```powershell
# Restart a process
$result = RestartProcess -ProcessId 1234

if ($result.code -eq 0) {
    Write-Host "Process restarted"
    Write-Host "Old PID: $($result.data.OldProcessId)"
    Write-Host "New PID: $($result.data.NewProcessId)"
}

# Restart with different arguments
$result = RestartProcess -ProcessId 5678 `
                         -Arguments "-config new-config.xml"

# Restart service executable
$result = GetProcessByName -ProcessName "myservice"
if ($result.code -eq 0) {
    $restartResult = RestartProcess -ProcessId $result.data.ProcessId
    Write-Host "Service restarted with new PID: $($restartResult.data.NewProcessId)"
}
```

---

### StopProcess

**Description:** Gracefully stops a process by process ID (sends close message).

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ProcessId` | int | Yes | Process ID to stop |
| `Timeout` | int | No | Timeout in seconds (default: 30) |

**Return Data:**

- `ProcessId`: ID of stopped process
- `ProcessName`: Name of the process
- `StoppedGracefully`: Boolean indicating graceful shutdown
- `TimeoutReached`: Boolean indicating if timeout was reached

**Example:**

```powershell
# Gracefully stop a process
$result = StopProcess -ProcessId 1234

if ($result.code -eq 0) {
    if ($result.data.StoppedGracefully) {
        Write-Host "Process stopped gracefully"
    } else {
        Write-Host "Process was forcefully terminated"
    }
}

# Stop with custom timeout
$result = StopProcess -ProcessId 5678 -Timeout 60

# Stop application process
$result = GetProcessByName -ProcessName "myapp"
if ($result.code -eq 0) {
    $stopResult = StopProcess -ProcessId $result.data.ProcessId
    Write-Host "Application stopped"
}
```

---

### KillProcess

**Description:** Forcefully terminates a process by process ID.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ProcessId` | int | Yes | Process ID to kill |
| `Force` | switch | No | Force termination even if process is critical |

**Return Data:**

- `ProcessId`: ID of killed process
- `ProcessName`: Name of the process
- `ForcefullyTerminated`: Always true

**Example:**

```powershell
# Kill a process
$result = KillProcess -ProcessId 1234

if ($result.code -eq 0) {
    Write-Host "Process terminated: $($result.data.ProcessName)"
}

# Force kill protected process
$result = KillProcess -ProcessId 5678 -Force

# Kill hung process
$result = GetProcessByName -ProcessName "hung-app"
if ($result.code -eq 0) {
    $killResult = KillProcess -ProcessId $result.data.ProcessId
    Write-Host "Hung application terminated"
}

# Try graceful stop first, then kill
$pid = 9876
$result = StopProcess -ProcessId $pid -Timeout 10
if ($result.code -ne 0) {
    Write-Host "Graceful stop failed, force killing..."
    $result = KillProcess -ProcessId $pid -Force
}
```

**Notes:**

- Use StopProcess first for graceful shutdown
- KillProcess should be last resort
- May cause data loss in target application

---

## Service Management

### StartService

**Description:** Starts a Windows service by name.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ServiceName` | string | Yes | Name of the service |
| `Timeout` | int | No | Timeout in seconds (default: 30) |

**Return Data:**

- `ServiceName`: Name of the service
- `DisplayName`: Display name
- `Status`: Current status
- `StartType`: Startup type

**Example:**

```powershell
# Start a service
$result = StartService -ServiceName "Spooler"

if ($result.code -eq 0) {
    Write-Host "Service started: $($result.data.DisplayName)"
    Write-Host "Status: $($result.data.Status)"
}

# Start with custom timeout
$result = StartService -ServiceName "wuauserv" -Timeout 60

# Start custom application service
$result = StartService -ServiceName "MyAppService"
if ($result.code -eq 0) {
    Write-Host "Application service is now running"
}
```

---

### RestartService

**Description:** Restarts a Windows service by name (stop then start).

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ServiceName` | string | Yes | Name of the service |
| `StopTimeout` | int | No | Stop timeout in seconds (default: 30) |
| `StartTimeout` | int | No | Start timeout in seconds (default: 30) |

**Return Data:**

- `ServiceName`: Name of the service
- `DisplayName`: Display name
- `Status`: Current status after restart
- `RestartedSuccessfully`: Boolean

**Example:**

```powershell
# Restart a service
$result = RestartService -ServiceName "wuauserv"

if ($result.code -eq 0) {
    Write-Host "Service restarted: $($result.data.DisplayName)"
    Write-Host "New status: $($result.data.Status)"
}

# Restart with custom timeouts
$result = RestartService -ServiceName "MyService" `
                         -StopTimeout 60 `
                         -StartTimeout 90

# Restart network service
$result = RestartService -ServiceName "LanmanServer"
```

---

### ForceRestartService

**Description:** Forcefully restarts a Windows service by name (kills process if needed).

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ServiceName` | string | Yes | Name of the service |
| `Timeout` | int | No | Timeout in seconds (default: 30) |

**Return Data:**

- `ServiceName`: Name of the service
- `DisplayName`: Display name
- `Status`: Current status
- `ForcefullyRestarted`: Boolean indicating if force was needed

**Example:**

```powershell
# Force restart a service
$result = ForceRestartService -ServiceName "MyService"

if ($result.code -eq 0) {
    Write-Host "Service force restarted: $($result.data.DisplayName)"
    if ($result.data.ForcefullyRestarted) {
        Write-Host "Force was required"
    }
}

# Force restart hung service
$result = ForceRestartService -ServiceName "HungService" -Timeout 10
```

---

### StopService

**Description:** Stops a Windows service by name.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ServiceName` | string | Yes | Name of the service |
| `Timeout` | int | No | Timeout in seconds (default: 30) |
| `Force` | switch | No | Force stop even if service has dependents |

**Return Data:**

- `ServiceName`: Name of the service
- `DisplayName`: Display name
- `Status`: Current status
- `PreviousStatus`: Status before stop

**Example:**

```powershell
# Stop a service
$result = StopService -ServiceName "Spooler"

if ($result.code -eq 0) {
    Write-Host "Service stopped: $($result.data.DisplayName)"
    Write-Host "Previous status: $($result.data.PreviousStatus)"
    Write-Host "Current status: $($result.data.Status)"
}

# Force stop service with dependents
$result = StopService -ServiceName "MyService" -Force

# Stop with custom timeout
$result = StopService -ServiceName "wuauserv" -Timeout 60
```

---

### KillService

**Description:** Forcefully terminates a Windows service by killing its process.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ServiceName` | string | Yes | Name of the service |

**Return Data:**

- `ServiceName`: Name of the service
- `DisplayName`: Display name
- `ProcessId`: ID of killed process
- `Status`: Current status

**Example:**

```powershell
# Kill a service
$result = KillService -ServiceName "HungService"

if ($result.code -eq 0) {
    Write-Host "Service killed: $($result.data.DisplayName)"
    Write-Host "Process ID: $($result.data.ProcessId)"
}

# Try graceful stop first, then kill
$serviceName = "MyService"
$result = StopService -ServiceName $serviceName -Timeout 10
if ($result.code -ne 0) {
    Write-Host "Graceful stop failed, killing service..."
    $result = KillService -ServiceName $serviceName
}
```

**Notes:**

- Use StopService first for graceful shutdown
- KillService should be last resort
- Requires Administrator privileges

---

### SetServiceState

**Description:** Changes the startup type of a Windows service.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ServiceName` | string | Yes | Name of the service |
| `StartType` | string | Yes | Automatic, Manual, Disabled, AutomaticDelayedStart |

**Return Data:**

- `ServiceName`: Name of the service
- `DisplayName`: Display name
- `PreviousStartType`: Startup type before change
- `NewStartType`: New startup type
- `CurrentStatus`: Current running status

**Example:**

```powershell
# Set service to automatic start
$result = SetServiceState -ServiceName "MyService" -StartType "Automatic"

if ($result.code -eq 0) {
    Write-Host "Service: $($result.data.DisplayName)"
    Write-Host "Previous: $($result.data.PreviousStartType)"
    Write-Host "New: $($result.data.NewStartType)"
}

# Disable a service
$result = SetServiceState -ServiceName "DiagTrack" -StartType "Disabled"

# Set to manual start
$result = SetServiceState -ServiceName "wuauserv" -StartType "Manual"

# Set to automatic with delayed start
$result = SetServiceState -ServiceName "MyAppService" `
                          -StartType "AutomaticDelayedStart"

if ($result.code -eq 0) {
    Write-Host "Service will start automatically (delayed)"
}
```

**Startup Types:**

- `Automatic`: Start automatically at boot
- `AutomaticDelayedStart`: Start automatically after boot (delayed)
- `Manual`: Start only when requested
- `Disabled`: Cannot be started

---

## Logging

### WriteLogMessage

**Description:** Writes messages to a log file with timestamps and severity flags.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Logfile` | string | Yes | Full path to log file |
| `Message` | string | Yes | Log message text |
| `Flag` | string | No | INFO, DEBUG, WARN, ERROR (default: DEBUG) |
| `Override` | int | No | 1 to overwrite, 0 to append (default: 0) |

**Return Data:**

- Returns the formatted log entry string

**Example:**

```powershell
# Write a debug message
$result = WriteLogMessage -Logfile "C:\Logs\app.log" `
                          -Message "Application started successfully"

# Write an info message
$result = WriteLogMessage -Logfile "C:\Logs\app.log" `
                          -Message "Configuration loaded" `
                          -Flag "INFO"

# Write a warning
$result = WriteLogMessage -Logfile "C:\Logs\app.log" `
                          -Message "Low disk space detected" `
                          -Flag "WARN"

# Write an error
$result = WriteLogMessage -Logfile "C:\Logs\app.log" `
                          -Message "Failed to connect to database" `
                          -Flag "ERROR"

# Start new log file (overwrite)
$result = WriteLogMessage -Logfile "C:\Logs\daily.log" `
                          -Message "=== Log started at $(Get-Date) ===" `
                          -Flag "INFO" `
                          -Override 1

if ($result.code -eq 0) {
    Write-Host "Log entry: $($result.data)"
}

# Advanced logging example
function Write-AppLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $logPath = "C:\Logs\MyApp_$(Get-Date -Format 'yyyyMMdd').log"
    WriteLogMessage -Logfile $logPath -Message $Message -Flag $Level
}

Write-AppLog "Application initialized" "INFO"
Write-AppLog "Processing data..." "DEBUG"
Write-AppLog "Operation completed" "INFO"
```

**Log Format:**

```
[2026.02.02 ; 16:45:23] [INFO]  Configuration loaded
[2026.02.02 ; 16:45:24] [DEBUG] Processing request
[2026.02.02 ; 16:45:25] [WARN]  High memory usage
[2026.02.02 ; 16:45:26] [ERROR] Connection failed
```

---

## Miscellaneous

### GetBitmapIconFromDLL

**Description:** Extracts a bitmap icon from a DLL or EXE file and returns it as a System.Drawing.Bitmap object.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DllPath` | string | Yes | Path to DLL or EXE file |
| `IconIndex` | int | No | Index of icon to extract (default: 0) |
| `IconSize` | int | No | Size in pixels (16, 32, 48, 256, default: 32) |

**Return Data:**

- Returns a `System.Drawing.Bitmap` object

**Example:**

```powershell
# Extract default icon from system DLL
$result = GetBitmapIconFromDLL -DllPath "C:\Windows\System32\shell32.dll"

if ($result.code -eq 0) {
    $bitmap = $result.data
    # Save to file
    $bitmap.Save("C:\Icons\icon.png", [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Icon extracted and saved"
}

# Extract specific icon with index
$result = GetBitmapIconFromDLL -DllPath "C:\Windows\System32\imageres.dll" `
                               -IconIndex 15 `
                               -IconSize 48

if ($result.code -eq 0) {
    $icon = $result.data
    $icon.Save("C:\Icons\folder.png", [System.Drawing.Imaging.ImageFormat]::Png)
}

# Extract large icon
$result = GetBitmapIconFromDLL -DllPath "C:\Windows\System32\shell32.dll" `
                               -IconIndex 2 `
                               -IconSize 256

# Extract from application
$result = GetBitmapIconFromDLL -DllPath "C:\Program Files\MyApp\MyApp.exe" `
                               -IconIndex 0 `
                               -IconSize 32

if ($result.code -eq 0) {
    $appIcon = $result.data
    # Use bitmap in WPF/WinForms application
    # $pictureBox.Image = $appIcon
}

# Extract multiple icons
for ($i = 0; $i -lt 10; $i++) {
    $result = GetBitmapIconFromDLL -DllPath "C:\Windows\System32\shell32.dll" `
                                   -IconIndex $i `
                                   -IconSize 32
    if ($result.code -eq 0) {
        $result.data.Save("C:\Icons\icon_$i.png", [System.Drawing.Imaging.ImageFormat]::Png)
    }
}
```

**Notes:**

- Requires System.Drawing assembly
- Supports ICO, DLL, and EXE files
- Common icon sources:
  - `shell32.dll`: Windows shell icons
  - `imageres.dll`: Windows image resources
  - `DDORes.dll`: Windows system icons
- Icon index starts at 0
- Returns System.Drawing.Bitmap which can be:
  - Saved as PNG, BMP, JPEG, GIF
  - Used in WinForms PictureBox
  - Converted for WPF ImageSource
  - Manipulated with GDI+ methods

---

## Best Practices

### Error Handling

```powershell
function Invoke-SafeOperation {
    param([string]$Path)
    
    $result = SomeFunction -Parameter $Path
    
    if ($result.code -eq 0) {
        # Success - process data
        Write-Host "Operation successful"
        return $result.data
    } else {
        # Error - log and handle
        WriteLogMessage -Logfile "C:\Logs\errors.log" `
                       -Message $result.msg `
                       -Flag "ERROR"
        throw $result.msg
    }
}
```

### Batch Operations

```powershell
# Process multiple items with reporting
$files = Get-ChildItem "C:\Source\*.txt"
$result = CopyFiles -SourcePaths ($files | Select-Object -ExpandProperty FullName) `
                    -DestinationDirectory "D:\Backup"

if ($result.data.FailureCount -gt 0) {
    # Handle failures
    foreach ($failed in $result.data.FailedFiles) {
        WriteLogMessage -Logfile "C:\Logs\copy-errors.log" `
                       -Message "Failed: $($failed.SourcePath) - $($failed.Error)" `
                       -Flag "ERROR"
    }
}
```

### Registry Safety

```powershell
# Always read before write
$readResult = GetRegEntryValue -RegistryPath "HKLM:\Software\MyApp" `
                               -ValueName "Setting"

if ($readResult.code -eq 0) {
    $oldValue = $readResult.data.ValueData
    
    # Make change
    $writeResult = SetNewRegValue -RegistryPath "HKLM:\Software\MyApp" `
                                  -ValueName "Setting" `
                                  -NewValueData "NewValue"
    
    if ($writeResult.code -eq 0) {
        WriteLogMessage -Logfile "C:\Logs\registry.log" `
                       -Message "Changed Setting from '$oldValue' to 'NewValue'" `
                       -Flag "INFO"
    }
}
```

### Service Management

```powershell
# Graceful service restart with fallback
function Restart-ServiceSafely {
    param([string]$ServiceName)
    
    # Try normal restart
    $result = RestartService -ServiceName $ServiceName -StopTimeout 30 -StartTimeout 30
    
    if ($result.code -ne 0) {
        WriteLogMessage -Logfile "C:\Logs\services.log" `
                       -Message "Normal restart failed, trying force restart" `
                       -Flag "WARN"
        
        # Try force restart
        $result = ForceRestartService -ServiceName $ServiceName
        
        if ($result.code -ne 0) {
            WriteLogMessage -Logfile "C:\Logs\services.log" `
                           -Message "Force restart failed: $($result.msg)" `
                           -Flag "ERROR"
            return $false
        }
    }
    
    return $true
}
```

---

## Troubleshooting

### Common Issues

**Access Denied Errors:**
- Run PowerShell as Administrator
- Check file/registry permissions
- Verify user has required rights

**Path Not Found:**
- Use full paths (avoid relative paths)
- Check for typos in paths
- Verify paths exist before operations

**Service Operations Failing:**
- Ensure service name is correct (use `Get-Service`)
- Check if service exists
- Verify sufficient permissions
- Some services require special privileges

**Registry Operations Failing:**
- Verify registry path format
- Check hive name is correct (HKLM, HKCU, etc.)
- Ensure key exists before value operations
- Some registry keys are protected

### Debug Mode

```powershell
# Enable verbose output
$VerbosePreference = 'Continue'

$result = CopyDir -SourcePath "C:\Source" `
                  -DestinationPath "D:\Backup" `
                  -Verbose

# Check what would happen without making changes
$result = RemoveDir -DirectoryPath "C:\Test" `
                    -Recurse `
                    -WhatIf
```

---

## Version History

**Version 1.06.00** - Windows Service Management
- Added StartService, RestartService, ForceRestartService
- Added StopService, KillService, SetServiceState

**Version 1.05.00** - Process Management
- Added RunProcess, GetProcessByName, GetProcessByID
- Added RestartProcess, StopProcess, KillProcess

**Version 1.04.00** - Extended File Operations & Reboot Scheduling
- Added CopyFile, CopyFiles, RemoveFile, RemoveFiles
- Added WriteTextToFile, ReadTextFile
- Added RemoveOnReboot, RemoveAllOnReboot

**Version 1.03.00** - File System Management
- Added CreateNewDir, CreateNewFile
- Added CopyDir, RemoveDir, RemoveDirs

**Version 1.02.00** - Extended Registry Management
- Added DeleteRegKey, DeleteRegVal
- Added GetRegEntryValue, GetRegEntryType, SetNewRegValue

**Version 1.01.00** - Registry Functions
- Added CreateRegKey, CreateRegVal

**Version 1.00.00** - Initial Release
- WriteLogMessage, GetBitmapIconFromDLL

---

## Support and Contributing

**Repository:** https://github.com/praetoriani/PowerShell.Mods

**Author:** Praetoriani (M.Sczepanski)

**License:** © 2025 Praetoriani. All rights reserved.

---

## Conclusion

PSAppCoreLib provides a comprehensive set of functions for Windows system management, file operations, process control, service management, and more. All functions follow consistent patterns with standardized return objects, making integration into your PowerShell applications straightforward and reliable.

For the latest updates, examples, and community contributions, visit the GitHub repository.
