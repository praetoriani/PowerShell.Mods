# PSAppCoreLib Developer Guide

## Table of Contents

- [Overview](#overview)
- [Common Patterns](#common-patterns)
  - [OPSreturn Pattern](#opsreturn-pattern)
  - [Error Handling](#error-handling)
  - [Data Access](#data-access)
- [File Management](#file-management)
  - [CopyFile](#copyfile)
  - [CopyFiles](#copyfiles)
  - [CreateNewFile](#createnewfile)
  - [RemoveFile](#removefile)
  - [RemoveFiles](#removefiles)
  - [RemoveOnReboot](#removeonreboot)
  - [RemoveAllOnReboot](#removeallonreboot)
- [Directory Management](#directory-management)
  - [CopyDir](#copydir)
  - [CreateNewDir](#createnewdir)
  - [RemoveDir](#removedir)
  - [RemoveDirs](#removedirs)
- [Process Management](#process-management)
  - [GetProcessByName](#getprocessbyname)
  - [GetProcessByID](#getprocessbyid)
  - [RunProcess](#runprocess)
  - [StopProcess](#stopprocess)
  - [KillProcess](#killprocess)
  - [RestartProcess](#restartprocess)
- [Service Management](#service-management)
  - [StartService](#startservice)
  - [StopService](#stopservice)
  - [RestartService](#restartservice)
  - [ForceRestartService](#forcerestartservice)
  - [KillService](#killservice)
  - [SetServiceState](#setservicestate)
- [Registry Operations](#registry-operations)
  - [CreateRegKey](#createregkey)
  - [CreateRegVal](#createregval)
  - [SetNewRegValue](#setnewregvalue)
  - [GetRegEntryType](#getregentrytype)
  - [GetRegEntryValue](#getregentryvalue)
  - [DeleteRegKey](#deleteregkey)
  - [DeleteRegVal](#deleteregval)
- [Text I/O Operations](#text-io-operations)
  - [ReadTextFile](#readtextfile)
  - [WriteTextToFile](#writetexttofile)
- [Utility Functions](#utility-functions)
  - [GetBitmapIconFromDLL](#getbitmapiconfigromdll)
  - [WriteLogMessage](#writelogmessage)

---

## Overview

PSAppCoreLib is a comprehensive PowerShell module providing robust file, directory, process, service, and registry management functions. All functions follow the **OPSreturn pattern** for consistent error handling and data return structures.

### Key Features

- ✅ **Consistent Return Pattern** - All functions use OPSreturn for uniform error handling
- ✅ **Comprehensive Error Handling** - Detailed error messages and validation
- ✅ **Rich Data Properties** - Structured data objects with operation metadata
- ✅ **Production Ready** - Battle-tested in enterprise environments
- ✅ **Well Documented** - Complete parameter and return value documentation

---

## Common Patterns

### OPSreturn Pattern

All PSAppCoreLib functions return a standardized object structure using the `OPSreturn` function:

```powershell
$result = SomePSAppCoreLibFunction -Parameters

# Result structure:
$result.code     # Integer: 0 = success, -1 = error
$result.msg      # String: Error message (empty on success)
$result.data     # PSCustomObject: Function-specific data (varies by function)
```

### Error Handling

**Best Practice Pattern:**

```powershell
$result = SomeFunction -Parameter "Value"

if ($result.code -eq 0) {
    # Success - access data
    Write-Host "Operation successful"
    $data = $result.data
    # Use $data properties
}
else {
    # Error - handle failure
    Write-Error "Operation failed: $($result.msg)"
    # Optionally check if $result.data contains additional error context
}
```

### Data Access

Each function returns specific data properties in `$result.data`. Refer to individual function documentation for available properties.

**Example:**

```powershell
$result = CopyFile -SourcePath "C:\Source\file.txt" -DestinationPath "C:\Dest\file.txt"

if ($result.code -eq 0) {
    Write-Host "Source: $($result.data.SourcePath)"
    Write-Host "Destination: $($result.data.DestinationPath)"
    Write-Host "Size: $($result.data.FileSizeBytes) bytes"
    Write-Host "Duration: $($result.data.CopyDurationMs) ms"
}
```

---

## File Management

### CopyFile

Copies a single file from source to destination with optional overwrite control.

**Synopsis:**
Copies a file with validation, progress tracking, and comprehensive error handling.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `SourcePath` | String | Yes | - | Full path to source file |
| `DestinationPath` | String | Yes | - | Full path to destination file |
| `Force` | Switch | No | `$false` | Overwrite existing file without confirmation |

**Return Data Properties:**

```powershell
$result.data.SourcePath          # String: Absolute source path
$result.data.DestinationPath     # String: Absolute destination path
$result.data.FileSizeBytes       # Long: File size in bytes
$result.data.CopyDurationMs      # Long: Copy operation duration in milliseconds
$result.data.FileHash            # String: SHA256 hash of copied file (if verification performed)
```

**Example:**

```powershell
# Simple file copy
$result = CopyFile -SourcePath "C:\Source\document.pdf" `
                   -DestinationPath "D:\Backup\document.pdf"

if ($result.code -eq 0) {
    Write-Host "File copied successfully"
    Write-Host "Size: $($result.data.FileSizeBytes) bytes"
    Write-Host "Duration: $($result.data.CopyDurationMs) ms"
}
else {
    Write-Error "Copy failed: $($result.msg)"
}

# Force overwrite existing file
$result = CopyFile -SourcePath "C:\App\config.xml" `
                   -DestinationPath "C:\Backup\config.xml" `
                   -Force
```

**Notes:**
- Creates destination directory automatically if it doesn't exist
- Validates source file exists before copying
- Preserves file attributes and timestamps
- Use `-Force` to overwrite readonly files

---

### CopyFiles

Copies multiple files from source directory to destination with pattern matching and progress tracking.

**Synopsis:**
Bulk file copy operation with wildcard support, filtering, and detailed progress reporting.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `SourcePath` | String | Yes | - | Source directory path |
| `DestinationPath` | String | Yes | - | Destination directory path |
| `Filter` | String | No | `"*"` | File pattern filter (e.g., "*.txt") |
| `Recurse` | Switch | No | `$false` | Include subdirectories |
| `Force` | Switch | No | `$false` | Overwrite existing files |

**Return Data Properties:**

```powershell
$result.data.SourcePath          # String: Source directory
$result.data.DestinationPath     # String: Destination directory
$result.data.FilesProcessed      # Int: Total files processed
$result.data.FilesSuccessful     # Int: Successfully copied files
$result.data.FilesFailed         # Int: Failed copy operations
$result.data.TotalBytes          # Long: Total bytes copied
$result.data.TotalDurationMs     # Long: Total operation duration
$result.data.CopiedFiles         # Array: List of successfully copied files
$result.data.FailedFiles         # Array: List of failed file operations with reasons
```

**Example:**

```powershell
# Copy all text files
$result = CopyFiles -SourcePath "C:\Logs" `
                    -DestinationPath "D:\Archive\Logs" `
                    -Filter "*.txt"

if ($result.code -eq 0) {
    Write-Host "Copied $($result.data.FilesSuccessful) of $($result.data.FilesProcessed) files"
    Write-Host "Total size: $([Math]::Round($result.data.TotalBytes/1MB, 2)) MB"
    
    if ($result.data.FilesFailed -gt 0) {
        Write-Warning "$($result.data.FilesFailed) files failed to copy"
        foreach ($failedFile in $result.data.FailedFiles) {
            Write-Warning "  $($failedFile.Path): $($failedFile.Reason)"
        }
    }
}

# Recursive copy with force overwrite
$result = CopyFiles -SourcePath "C:\Data" `
                    -DestinationPath "E:\Backup\Data" `
                    -Recurse -Force
```

**Notes:**
- Supports wildcard patterns (*, ?, [])
- Creates destination directory structure automatically
- Progress tracking for long operations
- Failed files don't stop the overall operation

---

### CreateNewFile

Creates a new empty file or file with optional initial content.

**Synopsis:**
Creates files with validation, directory creation, and optional content initialization.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Full path of file to create |
| `Content` | String | No | `""` | Optional initial file content |
| `Force` | Switch | No | `$false` | Overwrite if file exists |
| `Encoding` | String | No | `"UTF8"` | Text encoding (UTF8, ASCII, Unicode) |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Absolute file path
$result.data.FileSizeBytes       # Long: File size in bytes
$result.data.Created             # DateTime: File creation timestamp
$result.data.Encoding            # String: File encoding used
```

**Example:**

```powershell
# Create empty file
$result = CreateNewFile -Path "C:\Temp\newfile.txt"

if ($result.code -eq 0) {
    Write-Host "File created: $($result.data.Path)"
}

# Create file with content
$content = "Initial content`nLine 2`nLine 3"
$result = CreateNewFile -Path "C:\Config\settings.txt" `
                        -Content $content `
                        -Encoding "UTF8"

if ($result.code -eq 0) {
    Write-Host "Created file with $($result.data.FileSizeBytes) bytes"
}

# Force overwrite existing file
$result = CreateNewFile -Path "C:\Data\output.log" `
                        -Content "New log started" `
                        -Force
```

**Notes:**
- Creates parent directories automatically
- Validates path is not an existing directory
- Supports multiple text encodings
- Use `-Force` to overwrite existing files

---

### RemoveFile

Deletes a single file with optional force deletion of readonly files.

**Synopsis:**
Safe file deletion with validation and confirmation support.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Full path to file to delete |
| `Force` | Switch | No | `$false` | Delete readonly/system files |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Deleted file path
$result.data.FileSizeBytes       # Long: Size of deleted file
$result.data.WasReadonly         # Boolean: Whether file was readonly
$result.data.DeletedAt           # DateTime: Deletion timestamp
```

**Example:**

```powershell
# Simple file deletion
$result = RemoveFile -Path "C:\Temp\oldfile.txt"

if ($result.code -eq 0) {
    Write-Host "Deleted file: $($result.data.Path)"
    Write-Host "Freed: $($result.data.FileSizeBytes) bytes"
}

# Force delete readonly file
$result = RemoveFile -Path "C:\System\readonly.log" -Force

if ($result.code -eq 0) {
    if ($result.data.WasReadonly) {
        Write-Host "Forced deletion of readonly file"
    }
}
```

**Notes:**
- Validates file exists before deletion
- Fails on readonly files unless `-Force` is used
- Supports `ShouldProcess` for `-WhatIf` and `-Confirm`
- Cannot delete files in use by other processes

---

### RemoveFiles

Deletes multiple files matching a pattern with progress tracking.

**Synopsis:**
Bulk file deletion with wildcard support and detailed reporting.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Directory path or file pattern |
| `Filter` | String | No | `"*"` | File pattern filter |
| `Recurse` | Switch | No | `$false` | Include subdirectories |
| `Force` | Switch | No | `$false` | Delete readonly files |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Search path
$result.data.FilesProcessed      # Int: Total files processed
$result.data.FilesDeleted        # Int: Successfully deleted files
$result.data.FilesFailed         # Int: Failed deletions
$result.data.TotalBytesFreed     # Long: Total space freed
$result.data.DeletedFiles        # Array: List of deleted files
$result.data.FailedFiles         # Array: Failed deletions with reasons
```

**Example:**

```powershell
# Delete all log files
$result = RemoveFiles -Path "C:\Logs" -Filter "*.log"

if ($result.code -eq 0) {
    Write-Host "Deleted $($result.data.FilesDeleted) log files"
    Write-Host "Freed: $([Math]::Round($result.data.TotalBytesFreed/1MB, 2)) MB"
    
    if ($result.data.FilesFailed -gt 0) {
        Write-Warning "Failed to delete $($result.data.FilesFailed) files"
    }
}

# Recursive deletion with force
$result = RemoveFiles -Path "C:\Temp" `
                      -Filter "*.tmp" `
                      -Recurse -Force
```

**Notes:**
- Supports wildcard patterns
- Failed deletions don't stop the operation
- Use with caution - deleted files are not recoverable
- Progress tracking for large operations

---

### RemoveOnReboot

Schedules a file or directory for deletion on next system reboot.

**Synopsis:**
Registers file/directory for deletion on reboot using PendingFileRenameOperations registry key.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Full path to file or directory |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Scheduled path
$result.data.IsDirectory         # Boolean: Whether path is directory
$result.data.RegistryKey         # String: Registry key used
$result.data.RequiresReboot      # Boolean: Always true
```

**Example:**

```powershell
# Schedule file for deletion on reboot
$result = RemoveOnReboot -Path "C:\Windows\System32\olddriver.sys"

if ($result.code -eq 0) {
    Write-Host "File scheduled for deletion on reboot"
    Write-Warning "System restart required"
}

# Schedule directory for deletion
$result = RemoveOnReboot -Path "C:\Program Files\OldApp"

if ($result.code -eq 0) {
    Write-Host "Directory will be removed on reboot"
}
```

**Notes:**
- Requires administrative privileges
- Useful for locked files/directories
- Changes take effect only after reboot
- Multiple paths can be scheduled

---

### RemoveAllOnReboot

Clears all pending file operations scheduled for reboot.

**Synopsis:**
Removes all entries from PendingFileRenameOperations registry key.

**Parameters:**

None

**Return Data Properties:**

```powershell
$result.data.ClearedEntries      # Int: Number of entries cleared
$result.data.RegistryKey         # String: Registry key cleared
```

**Example:**

```powershell
$result = RemoveAllOnReboot

if ($result.code -eq 0) {
    Write-Host "Cleared $($result.data.ClearedEntries) pending operations"
}
else {
    Write-Error "Failed to clear pending operations: $($result.msg)"
}
```

**Notes:**
- Requires administrative privileges
- Cancels all scheduled deletions/renames
- Use with caution - may affect system updates

---

## Directory Management

### CopyDir

Copies an entire directory structure with all files and subdirectories.

**Synopsis:**
Recursive directory copy with progress tracking and error reporting.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `SourcePath` | String | Yes | - | Source directory path |
| `DestinationPath` | String | Yes | - | Destination directory path |
| `Force` | Switch | No | `$false` | Overwrite existing files |

**Return Data Properties:**

```powershell
$result.data.SourcePath          # String: Source directory
$result.data.DestinationPath     # String: Destination directory
$result.data.DirectoriesCopied   # Int: Number of directories copied
$result.data.FilesCopied         # Int: Number of files copied
$result.data.TotalBytes          # Long: Total bytes copied
$result.data.CopyDurationMs      # Long: Operation duration
```

**Example:**

```powershell
# Copy directory structure
$result = CopyDir -SourcePath "C:\Projects\MyApp" `
                  -DestinationPath "D:\Backup\MyApp"

if ($result.code -eq 0) {
    Write-Host "Copied $($result.data.DirectoriesCopied) directories"
    Write-Host "Copied $($result.data.FilesCopied) files"
    Write-Host "Total: $([Math]::Round($result.data.TotalBytes/1MB, 2)) MB"
}

# Force overwrite
$result = CopyDir -SourcePath "C:\Data" `
                  -DestinationPath "E:\Archive\Data" `
                  -Force
```

**Notes:**
- Preserves directory structure
- Maintains file attributes
- Creates destination directory if needed
- Reports partial success if some files fail

---

### CreateNewDir

Creates a new directory with optional parent directory creation.

**Synopsis:**
Safe directory creation with validation and recursive parent creation.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Directory path to create |
| `Force` | Switch | No | `$false` | Create parent directories |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Created directory path
$result.data.Created             # DateTime: Creation timestamp
$result.data.ParentsCreated      # Int: Number of parent dirs created
```

**Example:**

```powershell
# Simple directory creation
$result = CreateNewDir -Path "C:\Temp\NewFolder"

if ($result.code -eq 0) {
    Write-Host "Created directory: $($result.data.Path)"
}

# Create with parents
$result = CreateNewDir -Path "C:\Deep\Nested\Folder\Structure" -Force

if ($result.code -eq 0) {
    Write-Host "Created directory with $($result.data.ParentsCreated) parent folders"
}
```

**Notes:**
- Validates path is not an existing file
- Use `-Force` to create parent directories
- Returns success if directory already exists

---

### RemoveDir

Deletes a directory and optionally all its contents.

**Synopsis:**
Safe directory deletion with recursive content removal.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Directory path to delete |
| `Recurse` | Switch | No | `$false` | Delete contents recursively |
| `Force` | Switch | No | `$false` | Delete readonly items |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Deleted directory path
$result.data.FilesDeleted        # Int: Files deleted
$result.data.SubdirsDeleted      # Int: Subdirectories deleted
$result.data.TotalBytesFreed     # Long: Space freed
```

**Example:**

```powershell
# Delete empty directory
$result = RemoveDir -Path "C:\Temp\EmptyFolder"

if ($result.code -eq 0) {
    Write-Host "Directory deleted"
}

# Delete directory with all contents
$result = RemoveDir -Path "C:\Temp\OldData" -Recurse -Force

if ($result.code -eq 0) {
    Write-Host "Deleted directory with:"
    Write-Host "  Files: $($result.data.FilesDeleted)"
    Write-Host "  Subdirs: $($result.data.SubdirsDeleted)"
    Write-Host "  Freed: $([Math]::Round($result.data.TotalBytesFreed/1MB, 2)) MB"
}
```

**Notes:**
- Directory must be empty unless `-Recurse` is used
- Use with caution - no recovery possible
- Supports `ShouldProcess` for safety

---

### RemoveDirs

Deletes multiple directories matching a pattern.

**Synopsis:**
Bulk directory deletion with wildcard support and detailed reporting.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Base path or pattern |
| `Filter` | String | No | `"*"` | Directory name filter |
| `Recurse` | Switch | No | `$false` | Delete contents |
| `Force` | Switch | No | `$false` | Delete readonly items |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Search path
$result.data.DirsProcessed       # Int: Directories processed
$result.data.DirsDeleted         # Int: Successfully deleted
$result.data.DirsFailed          # Int: Failed deletions
$result.data.TotalBytesFreed     # Long: Total space freed
$result.data.DeletedDirs         # Array: List of deleted directories
$result.data.FailedDirs          # Array: Failed deletions with reasons
```

**Example:**

```powershell
# Delete all cache directories
$result = RemoveDirs -Path "C:\Users\*\AppData\Local" `
                     -Filter "Cache" `
                     -Recurse -Force

if ($result.code -eq 0) {
    Write-Host "Deleted $($result.data.DirsDeleted) cache directories"
    Write-Host "Freed: $([Math]::Round($result.data.TotalBytesFreed/1GB, 2)) GB"
}
```

**Notes:**
- Supports wildcard patterns
- Use with extreme caution
- Failed deletions reported in detail

---

## Process Management

### GetProcessByName

Retrieves process information by exact process name.

**Synopsis:**
Searches for processes by name with flexible selection options.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Name` | String | Yes | - | Process name (without .exe) |
| `IncludeExtension` | Switch | No | `$false` | Expect .exe extension |
| `SelectFirst` | Switch | No | `$false` | Return first if multiple found |
| `SelectAll` | Switch | No | `$false` | Return all matching processes |

**Return Data Properties:**

```powershell
$result.data.ProcessName         # String: Process name
$result.data.ProcessId           # Int: Process ID (primary)
$result.data.ProcessHandle       # Process: Process object
$result.data.ProcessCount        # Int: Number of matching processes
$result.data.Processes           # Array: All matching process objects
$result.data.PIDs                # String: Comma-separated PIDs
$result.data.StartTime           # DateTime: Process start time
$result.data.WorkingSetMB        # Double: Memory usage in MB
$result.data.Path                # String: Process executable path
```

**Example:**

```powershell
# Find single process
$result = GetProcessByName -Name "notepad"

if ($result.code -eq 0) {
    Write-Host "Found Notepad with PID: $($result.data.ProcessId)"
    Write-Host "Memory: $($result.data.WorkingSetMB) MB"
    Write-Host "Path: $($result.data.Path)"
}

# Handle multiple instances
$result = GetProcessByName -Name "chrome" -SelectFirst

if ($result.code -eq 0) {
    Write-Host "First Chrome instance: PID $($result.data.ProcessId)"
}

# Get all instances
$result = GetProcessByName -Name "svchost" -SelectAll

if ($result.code -eq 0) {
    Write-Host "Found $($result.data.ProcessCount) svchost processes"
    foreach ($proc in $result.data.Processes) {
        Write-Host "  PID: $($proc.Id), Memory: $([Math]::Round($proc.WorkingSet64/1MB,2)) MB"
    }
}
```

**Notes:**
- Process name is case-insensitive
- Requires exact match (no wildcards)
- Returns error if multiple found without selection flag
- Process handle can be used for further operations

---

### GetProcessByID

Retrieves detailed process information by process ID.

**Synopsis:**
Gets comprehensive process information including memory, threads, and optional module details.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ProcessId` | Int | Yes | - | Process ID (PID) |
| `IncludeModules` | Switch | No | `$false` | Include loaded modules (DLLs) |
| `IncludeThreads` | Switch | No | `$false` | Include thread information |

**Return Data Properties:**

```powershell
$result.data.ProcessId           # Int: Process ID
$result.data.ProcessName         # String: Process name
$result.data.ProcessHandle       # Process: Process object
$result.data.Path                # String: Executable path
$result.data.CommandLine         # String: Command line arguments
$result.data.WorkingSetMB        # Double: Physical memory (MB)
$result.data.PrivateMemoryMB     # Double: Private memory (MB)
$result.data.VirtualMemoryMB     # Double: Virtual memory (MB)
$result.data.ThreadCount         # Int: Number of threads
$result.data.HandleCount         # Int: Number of handles
$result.data.StartTime           # DateTime: Process start time
$result.data.TotalProcessorTime  # TimeSpan: CPU time used
$result.data.HasExited           # Boolean: Process exit status
$result.data.ExitCode            # Int: Exit code (if exited)
$result.data.ModuleCount         # Int: Number of loaded modules
$result.data.Modules             # Array: Loaded modules (if requested)
$result.data.Threads             # Array: Thread info (if requested)
```

**Example:**

```powershell
# Get basic process info
$result = GetProcessByID -ProcessId 1234

if ($result.code -eq 0) {
    Write-Host "Process: $($result.data.ProcessName)"
    Write-Host "Path: $($result.data.Path)"
    Write-Host "Memory: $($result.data.WorkingSetMB) MB"
    Write-Host "Threads: $($result.data.ThreadCount)"
    Write-Host "Started: $($result.data.StartTime)"
}

# Include module information
$result = GetProcessByID -ProcessId $PID -IncludeModules

if ($result.code -eq 0) {
    Write-Host "Loaded $($result.data.ModuleCount) modules:"
    foreach ($module in $result.data.Modules) {
        Write-Host "  $($module.ModuleName)"
    }
}

# Check if process still running
$result = GetProcessByID -ProcessId 9999

if ($result.code -eq 0) {
    if ($result.data.HasExited) {
        Write-Host "Process exited with code: $($result.data.ExitCode)"
    } else {
        Write-Host "Process is running"
    }
}
```

**Notes:**
- Some details may require elevated privileges
- Module enumeration can be slow for processes with many DLLs
- System processes may have limited accessible information

---

### RunProcess

Executes a process with optional arguments, working directory, and output capture.

**Synopsis:**
Comprehensive process execution with output redirection, exit code capture, and timeout control.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `FilePath` | String | Yes | - | Executable path |
| `Arguments` | String | No | `""` | Command line arguments |
| `WorkingDirectory` | String | No | Current | Working directory |
| `Wait` | Switch | No | `$false` | Wait for process to exit |
| `CaptureOutput` | Switch | No | `$false` | Capture stdout/stderr |
| `TimeoutSeconds` | Int | No | 0 | Timeout (0 = infinite) |
| `WindowStyle` | String | No | `"Normal"` | Window style (Normal, Hidden, Minimized, Maximized) |
| `NoNewWindow` | Switch | No | `$false` | Don't create new window |

**Return Data Properties:**

```powershell
$result.data.ProcessId           # Int: Started process ID
$result.data.ProcessName         # String: Process name
$result.data.FilePath            # String: Executable path
$result.data.Arguments           # String: Arguments used
$result.data.WorkingDirectory    # String: Working directory
$result.data.StartTime           # DateTime: Process start time
$result.data.ExitCode            # Int: Exit code (if waited)
$result.data.ExitTime            # DateTime: Exit time (if waited)
$result.data.ExecutionTimeMs     # Long: Execution duration (if waited)
$result.data.StandardOutput      # String: Stdout (if captured)
$result.data.StandardError       # String: Stderr (if captured)
$result.data.TimedOut            # Boolean: Whether timeout occurred
```

**Example:**

```powershell
# Simple process execution
$result = RunProcess -FilePath "notepad.exe"

if ($result.code -eq 0) {
    Write-Host "Started Notepad with PID: $($result.data.ProcessId)"
}

# Execute with arguments and wait
$result = RunProcess -FilePath "ipconfig.exe" `
                     -Arguments "/all" `
                     -Wait `
                     -CaptureOutput

if ($result.code -eq 0) {
    Write-Host "Exit Code: $($result.data.ExitCode)"
    Write-Host "Duration: $($result.data.ExecutionTimeMs) ms"
    Write-Host "Output:`n$($result.data.StandardOutput)"
}

# Execute with timeout
$result = RunProcess -FilePath "long-running.exe" `
                     -Wait `
                     -TimeoutSeconds 30

if ($result.code -eq 0) {
    if ($result.data.TimedOut) {
        Write-Warning "Process timed out and was terminated"
    }
}

# Hidden execution
$result = RunProcess -FilePath "backup.bat" `
                     -WorkingDirectory "C:\Scripts" `
                     -WindowStyle "Hidden" `
                     -Wait
```

**Notes:**
- Use `-Wait` to get exit code and output
- Output capture requires `-Wait`
- Timeout kills process if exceeded
- Administrator rights may be needed for some executables

---

### StopProcess

Gracefully stops a process by process ID.

**Synopsis:**
Attempts graceful process termination allowing cleanup and save operations.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ProcessId` | Int | Yes | - | Process ID to stop |
| `WaitForExit` | Int | No | 5 | Timeout in seconds |

**Return Data Properties:**

```powershell
$result.data.ProcessId           # Int: Process ID
$result.data.ProcessName         # String: Process name
$result.data.StopDurationMs      # Long: Stop operation duration
$result.data.ExitedGracefully    # Boolean: Whether process exited cleanly
```

**Example:**

```powershell
# Gracefully stop process
$result = StopProcess -ProcessId 1234

if ($result.code -eq 0) {
    Write-Host "Process stopped gracefully"
    Write-Host "Duration: $($result.data.StopDurationMs) ms"
}

# Stop with custom timeout
$result = StopProcess -ProcessId 5678 -WaitForExit 10

if ($result.code -eq 0) {
    if ($result.data.ExitedGracefully) {
        Write-Host "Process exited cleanly"
    }
}
else {
    Write-Warning "Graceful stop failed, consider using KillProcess"
}
```

**Notes:**
- Allows process to clean up resources
- May fail if process is unresponsive
- Use `KillProcess` if graceful stop fails

---

### KillProcess

Forcefully terminates a process by process ID.

**Synopsis:**
Immediate process termination without cleanup opportunity.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ProcessId` | Int | Yes | - | Process ID to kill |
| `Force` | Switch | No | `$false` | Kill process tree (children) |
| `WaitForExit` | Int | No | 5 | Verification timeout |

**Return Data Properties:**

```powershell
$result.data.ProcessId           # Int: Process ID
$result.data.ProcessName         # String: Process name
$result.data.KilledProcessCount  # Int: Processes killed (including children)
$result.data.ChildProcessCount   # Int: Child processes killed
$result.data.TerminationDurationMs # Long: Kill operation duration
```

**Example:**

```powershell
# Kill single process
$result = KillProcess -ProcessId 1234

if ($result.code -eq 0) {
    Write-Host "Process killed"
    Write-Host "Termination time: $($result.data.TerminationDurationMs) ms"
}

# Kill process tree
$result = KillProcess -ProcessId 5678 -Force

if ($result.code -eq 0) {
    Write-Host "Killed $($result.data.KilledProcessCount) processes"
    Write-Host "  Main process: 1"
    Write-Host "  Child processes: $($result.data.ChildProcessCount)"
}
```

**Notes:**
- Immediate termination - no cleanup possible
- Unsaved work will be lost
- Use only when `StopProcess` fails
- Supports confirmation prompts

---

### RestartProcess

Restarts a process by stopping and starting it again.

**Synopsis:**
Graceful process restart preserving executable path and arguments.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ProcessId` | Int | Yes | - | Process ID to restart |
| `WaitForExit` | Int | No | 5 | Stop timeout |

**Return Data Properties:**

```powershell
$result.data.OldProcessId        # Int: Original process ID
$result.data.NewProcessId        # Int: New process ID
$result.data.ProcessName         # String: Process name
$result.data.StopDurationMs      # Long: Stop phase duration
$result.data.StartDurationMs     # Long: Start phase duration
$result.data.TotalDurationMs     # Long: Total restart duration
```

**Example:**

```powershell
# Restart application
$result = RestartProcess -ProcessId 1234

if ($result.code -eq 0) {
    Write-Host "Process restarted"
    Write-Host "Old PID: $($result.data.OldProcessId)"
    Write-Host "New PID: $($result.data.NewProcessId)"
    Write-Host "Total time: $($result.data.TotalDurationMs) ms"
}
```

**Notes:**
- Preserves original command line arguments
- May fail if executable path not accessible
- Uses graceful stop - may fail for unresponsive processes

---

## Service Management

### StartService

Starts a Windows service by name.

**Synopsis:**
Starts service with validation, dependency handling, and progress tracking.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ServiceName` | String | Yes | - | Service name |
| `TimeoutSeconds` | Int | No | 30 | Start timeout |
| `PassThru` | Switch | No | `$false` | Include service object in data |

**Return Data Properties:**

```powershell
$result.data.ServiceName         # String: Service name
$result.data.DisplayName         # String: Service display name
$result.data.Status              # String: Current status
$result.data.StartType           # String: Startup type
$result.data.PreviousStatus      # String: Status before start
$result.data.StartDurationSeconds # Double: Time to start
$result.data.ServiceObject       # ServiceController: Service object (if PassThru)
```

**Example:**

```powershell
# Start service
$result = StartService -ServiceName "Spooler"

if ($result.code -eq 0) {
    Write-Host "Service started: $($result.data.DisplayName)"
    Write-Host "Status: $($result.data.Status)"
    Write-Host "Duration: $($result.data.StartDurationSeconds) seconds"
}

# Start with timeout
$result = StartService -ServiceName "wuauserv" -TimeoutSeconds 60

if ($result.code -eq 0) {
    Write-Host "Windows Update service started"
}
```

**Notes:**
- Requires administrative privileges
- Automatically starts dependent services
- Returns success if service already running
- Validates service exists before starting

---

### StopService

Stops a Windows service by name.

**Synopsis:**
Gracefully stops service with dependent service handling.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ServiceName` | String | Yes | - | Service name |
| `TimeoutSeconds` | Int | No | 30 | Stop timeout |
| `Force` | Switch | No | `$false` | Stop dependent services |
| `PassThru` | Switch | No | `$false` | Include service object |

**Return Data Properties:**

```powershell
$result.data.ServiceName         # String: Service name
$result.data.DisplayName         # String: Display name
$result.data.Status              # String: Current status
$result.data.PreviousStatus      # String: Status before stop
$result.data.StopDurationSeconds # Double: Time to stop
$result.data.StoppedDependentServices # Array: Dependent services stopped
$result.data.ServiceObject       # ServiceController: Service object (if PassThru)
```

**Example:**

```powershell
# Stop service
$result = StopService -ServiceName "Spooler"

if ($result.code -eq 0) {
    Write-Host "Service stopped"
    Write-Host "Duration: $($result.data.StopDurationSeconds) seconds"
}

# Stop with dependent services
$result = StopService -ServiceName "LanmanServer" -Force

if ($result.code -eq 0) {
    Write-Host "Stopped service and dependencies:"
    foreach ($dep in $result.data.StoppedDependentServices) {
        Write-Host "  - $dep"
    }
}
```

**Notes:**
- Requires administrative privileges
- Fails if dependent services running (unless `-Force`)
- Returns success if service already stopped

---

### RestartService

Restarts a Windows service.

**Synopsis:**
Graceful service restart with timing tracking for both phases.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ServiceName` | String | Yes | - | Service name |
| `TimeoutSeconds` | Int | No | 30 | Stop timeout |
| `PassThru` | Switch | No | `$false` | Include service object |

**Return Data Properties:**

```powershell
$result.data.ServiceName         # String: Service name
$result.data.DisplayName         # String: Display name
$result.data.Status              # String: Current status
$result.data.StopDurationSeconds # Double: Stop phase duration
$result.data.StartDurationSeconds # Double: Start phase duration
$result.data.TotalDurationSeconds # Double: Total restart duration
$result.data.ServiceObject       # ServiceController: Service object (if PassThru)
```

**Example:**

```powershell
# Restart service
$result = RestartService -ServiceName "Spooler"

if ($result.code -eq 0) {
    Write-Host "Service restarted: $($result.data.DisplayName)"
    Write-Host "Stop phase: $($result.data.StopDurationSeconds)s"
    Write-Host "Start phase: $($result.data.StartDurationSeconds)s"
    Write-Host "Total: $($result.data.TotalDurationSeconds)s"
}
```

**Notes:**
- Requires administrative privileges
- More reliable than manual stop/start sequence
- Handles dependencies automatically

---

### ForceRestartService

Forcefully restarts a service by killing its processes if needed.

**Synopsis:**
Aggressive service restart when graceful restart fails.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ServiceName` | String | Yes | - | Service name |
| `TimeoutSeconds` | Int | No | 30 | Timeout |
| `PassThru` | Switch | No | `$false` | Include service object |

**Return Data Properties:**

```powershell
$result.data.ServiceName         # String: Service name
$result.data.DisplayName         # String: Display name
$result.data.Status              # String: Current status
$result.data.WasForced           # Boolean: Whether force was needed
$result.data.KilledProcessCount  # Int: Processes killed
$result.data.StopDurationSeconds # Double: Stop phase duration
$result.data.StartDurationSeconds # Double: Start phase duration
$result.data.TotalDurationSeconds # Double: Total duration
$result.data.ServiceObject       # ServiceController: Service object (if PassThru)
```

**Example:**

```powershell
# Force restart hung service
$result = ForceRestartService -ServiceName "W3SVC"

if ($result.code -eq 0) {
    if ($result.data.WasForced) {
        Write-Warning "Service was forcefully restarted"
        Write-Host "Killed $($result.data.KilledProcessCount) processes"
    } else {
        Write-Host "Service restarted gracefully"
    }
}
```

**Notes:**
- Use only when `RestartService` fails
- Kills service processes forcefully
- May cause data loss
- Requires administrative privileges

---

### KillService

Terminates all processes associated with a service.

**Synopsis:**
Immediate service termination by killing all related processes.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ServiceName` | String | Yes | - | Service name |
| `Force` | Switch | No | `$false` | Kill dependent services |

**Return Data Properties:**

```powershell
$result.data.ServiceName         # String: Service name
$result.data.DisplayName         # String: Display name
$result.data.Status              # String: Current status
$result.data.KilledProcessCount  # Int: Processes killed
$result.data.TerminationDurationMs # Long: Kill operation duration
$result.data.KilledDependentServices # Array: Dependent services killed
```

**Example:**

```powershell
# Kill service processes
$result = KillService -ServiceName "stuck-service"

if ($result.code -eq 0) {
    Write-Host "Killed $($result.data.KilledProcessCount) processes"
    Write-Host "Duration: $($result.data.TerminationDurationMs) ms"
}

# Kill with dependencies
$result = KillService -ServiceName "main-service" -Force

if ($result.code -eq 0) {
    Write-Host "Killed service and dependencies:"
    foreach ($dep in $result.data.KilledDependentServices) {
        Write-Host "  - $dep"
    }
}
```

**Notes:**
- Last resort when all other methods fail
- Service cleanup won't occur
- May corrupt service state
- Requires administrative privileges

---

### SetServiceState

Configures a service's startup type.

**Synopsis:**
Changes service startup configuration (Automatic, Manual, Disabled).

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ServiceName` | String | Yes | - | Service name |
| `StartupType` | String | Yes | - | Automatic, AutomaticDelayed, Manual, Disabled |

**Return Data Properties:**

```powershell
$result.data.ServiceName         # String: Service name
$result.data.DisplayName         # String: Display name
$result.data.PreviousStartType   # String: Original startup type
$result.data.CurrentStartType    # String: New startup type
$result.data.CurrentStatus       # String: Service status
```

**Example:**

```powershell
# Set service to automatic
$result = SetServiceState -ServiceName "Spooler" `
                          -StartupType "Automatic"

if ($result.code -eq 0) {
    Write-Host "Changed startup type:"
    Write-Host "  From: $($result.data.PreviousStartType)"
    Write-Host "  To: $($result.data.CurrentStartType)"
}

# Disable service
$result = SetServiceState -ServiceName "unnecessary-service" `
                          -StartupType "Disabled"
```

**Notes:**
- Requires administrative privileges
- Does not affect current running state
- AutomaticDelayed starts after boot completes
- Disabled services cannot be started manually

---

## Registry Operations

### CreateRegKey

Creates a new registry key.

**Synopsis:**
Creates registry key with validation and recursive parent creation.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Registry path (e.g., "HKLM:\Software\MyApp") |
| `Force` | Switch | No | `$false` | Create parent keys |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Created key path
$result.data.Exists              # Boolean: Whether key already existed
$result.data.Created             # DateTime: Creation timestamp
```

**Example:**

```powershell
# Create registry key
$result = CreateRegKey -Path "HKLM:\Software\MyCompany\MyApp"

if ($result.code -eq 0) {
    Write-Host "Key created: $($result.data.Path)"
}

# Create with parents
$result = CreateRegKey -Path "HKCU:\Software\Deep\Nested\Key" -Force

if ($result.code -eq 0) {
    if ($result.data.Exists) {
        Write-Host "Key already existed"
    } else {
        Write-Host "Key created with parent structure"
    }
}
```

**Notes:**
- HKLM keys require administrative privileges
- Use `-Force` to create parent keys
- Returns success if key already exists

---

### CreateRegVal

Creates a new registry value.

**Synopsis:**
Creates registry value with type validation and optional key creation.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Registry key path |
| `Name` | String | Yes | - | Value name |
| `Value` | Object | Yes | - | Value data |
| `Type` | String | No | `"String"` | Value type (String, DWord, QWord, Binary, MultiString, ExpandString) |
| `Force` | Switch | No | `$false` | Create key if missing |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Registry key path
$result.data.Name                # String: Value name
$result.data.Value               # Object: Value data
$result.data.Type                # String: Value type
$result.data.KeyCreated          # Boolean: Whether key was created
```

**Example:**

```powershell
# Create string value
$result = CreateRegVal -Path "HKCU:\Software\MyApp" `
                       -Name "InstallPath" `
                       -Value "C:\Program Files\MyApp" `
                       -Type "String"

if ($result.code -eq 0) {
    Write-Host "Value created: $($result.data.Name)"
}

# Create DWORD value
$result = CreateRegVal -Path "HKLM:\Software\MyApp" `
                       -Name "Version" `
                       -Value 10 `
                       -Type "DWord" `
                       -Force

if ($result.code -eq 0) {
    if ($result.data.KeyCreated) {
        Write-Host "Key and value created"
    }
}
```

**Notes:**
- Validates value type matches data
- Creates parent key with `-Force`
- Overwrites existing values

---

### SetNewRegValue

Updates an existing registry value or creates it if missing.

**Synopsis:**
Safe registry value update with validation and backup capability.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Registry key path |
| `Name` | String | Yes | - | Value name |
| `Value` | Object | Yes | - | New value data |
| `Type` | String | No | `"String"` | Value type |
| `Force` | Switch | No | `$false` | Create if missing |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Registry key path
$result.data.Name                # String: Value name
$result.data.OldValue            # Object: Previous value (if existed)
$result.data.NewValue            # Object: New value
$result.data.Type                # String: Value type
$result.data.WasCreated          # Boolean: Whether value was created
```

**Example:**

```powershell
# Update existing value
$result = SetNewRegValue -Path "HKCU:\Software\MyApp" `
                         -Name "Theme" `
                         -Value "Dark"

if ($result.code -eq 0) {
    Write-Host "Updated value:"
    Write-Host "  Old: $($result.data.OldValue)"
    Write-Host "  New: $($result.data.NewValue)"
}

# Create or update
$result = SetNewRegValue -Path "HKLM:\Software\MyApp" `
                         -Name "MaxUsers" `
                         -Value 100 `
                         -Type "DWord" `
                         -Force
```

**Notes:**
- Returns previous value for rollback capability
- Creates value with `-Force` if missing
- Type must match existing value

---

### GetRegEntryType

Retrieves the type of a registry value.

**Synopsis:**
Determines registry value type without reading its data.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Registry key path |
| `Name` | String | Yes | - | Value name |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Registry key path
$result.data.Name                # String: Value name
$result.data.Type                # String: Value type
$result.data.TypeCode            # Int: .NET RegistryValueKind enum
```

**Example:**

```powershell
$result = GetRegEntryType -Path "HKCU:\Software\MyApp" `
                          -Name "InstallDate"

if ($result.code -eq 0) {
    Write-Host "Value type: $($result.data.Type)"
    
    # Use type for conditional processing
    switch ($result.data.Type) {
        "String" { Write-Host "This is a string value" }
        "DWord"  { Write-Host "This is a DWORD value" }
    }
}
```

**Notes:**
- Fast operation - doesn't read value data
- Useful for type validation before operations

---

### GetRegEntryValue

Retrieves the value of a registry entry.

**Synopsis:**
Reads registry value with type information.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Registry key path |
| `Name` | String | Yes | - | Value name |
| `DefaultValue` | Object | No | `$null` | Return this if value doesn't exist |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Registry key path
$result.data.Name                # String: Value name
$result.data.Value               # Object: Value data
$result.data.Type                # String: Value type
$result.data.Exists              # Boolean: Whether value exists
```

**Example:**

```powershell
# Read value
$result = GetRegEntryValue -Path "HKCU:\Software\MyApp" `
                            -Name "InstallPath"

if ($result.code -eq 0) {
    Write-Host "Install Path: $($result.data.Value)"
    Write-Host "Type: $($result.data.Type)"
}

# Read with default
$result = GetRegEntryValue -Path "HKLM:\Software\MyApp" `
                            -Name "MaxConnections" `
                            -DefaultValue 10

if ($result.code -eq 0) {
    $maxConn = $result.data.Value
    Write-Host "Max Connections: $maxConn"
}
```

**Notes:**
- Returns default value if entry doesn't exist
- Handles all registry value types
- Type information included in result

---

### DeleteRegKey

Deletes a registry key and optionally all subkeys.

**Synopsis:**
Safe registry key deletion with recursive option.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Registry key path |
| `Recurse` | Switch | No | `$false` | Delete subkeys |
| `Force` | Switch | No | `$false` | No confirmation |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Deleted key path
$result.data.SubkeysDeleted      # Int: Number of subkeys deleted
$result.data.ValuesDeleted       # Int: Number of values deleted
```

**Example:**

```powershell
# Delete empty key
$result = DeleteRegKey -Path "HKCU:\Software\OldApp"

if ($result.code -eq 0) {
    Write-Host "Key deleted"
}

# Delete with subkeys
$result = DeleteRegKey -Path "HKLM:\Software\OldApp" `
                       -Recurse -Force

if ($result.code -eq 0) {
    Write-Host "Deleted key with:"
    Write-Host "  Subkeys: $($result.data.SubkeysDeleted)"
    Write-Host "  Values: $($result.data.ValuesDeleted)"
}
```

**Notes:**
- Key must be empty unless `-Recurse` used
- HKLM operations require admin rights
- Use with caution - no undo

---

### DeleteRegVal

Deletes a registry value.

**Synopsis:**
Safe registry value deletion with validation.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | Registry key path |
| `Name` | String | Yes | - | Value name to delete |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Registry key path
$result.data.Name                # String: Deleted value name
$result.data.OldValue            # Object: Previous value (for rollback)
$result.data.OldType             # String: Previous value type
```

**Example:**

```powershell
# Delete value
$result = DeleteRegVal -Path "HKCU:\Software\MyApp" `
                       -Name "TempSetting"

if ($result.code -eq 0) {
    Write-Host "Deleted value: $($result.data.Name)"
    Write-Host "Previous value was: $($result.data.OldValue)"
}
```

**Notes:**
- Returns previous value for potential rollback
- Fails gracefully if value doesn't exist
- HKLM operations require admin rights

---

## Text I/O Operations

### ReadTextFile

Reads text content from a file with encoding support.

**Synopsis:**
Comprehensive text file reading with encoding detection and validation.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | File path to read |
| `Encoding` | String | No | `"Auto"` | Text encoding (UTF8, ASCII, Unicode, Auto) |
| `Raw` | Switch | No | `$false` | Return as single string |
| `MaxSizeBytes` | Long | No | 104857600 | Maximum file size (100MB) |
| `ValidateText` | Bool | No | `$true` | Check for binary content |

**Return Data Properties:**

```powershell
$result.data.Path                # String: File path
$result.data.Content             # String/Array: File content
$result.data.LineCount           # Int: Number of lines
$result.data.SizeBytes           # Long: File size
$result.data.Encoding            # String: Used encoding
$result.data.DetectedEncoding    # String: Auto-detected encoding
```

**Example:**

```powershell
# Read text file (returns array of lines)
$result = ReadTextFile -Path "C:\Logs\app.log"

if ($result.code -eq 0) {
    Write-Host "Read $($result.data.LineCount) lines"
    Write-Host "Encoding: $($result.data.DetectedEncoding)"
    
    foreach ($line in $result.data.Content) {
        Write-Host $line
    }
}

# Read as single string
$result = ReadTextFile -Path "C:\Config\settings.ini" -Raw

if ($result.code -eq 0) {
    $fullText = $result.data.Content
    Write-Host "File content:`n$fullText"
}

# Read with specific encoding
$result = ReadTextFile -Path "C:\Data\utf8.txt" `
                       -Encoding "UTF8NoBOM"

# Read large file with size limit
$result = ReadTextFile -Path "C:\Data\large.log" `
                       -MaxSizeBytes 10MB

if ($result.code -ne 0) {
    Write-Warning "File too large: $($result.msg)"
}
```

**Notes:**
- Auto-detects encoding from BOM
- Validates text content (no null bytes)
- Returns lines by default, string with `-Raw`
- Size limit prevents memory issues

---

### WriteTextToFile

Writes text content to a file with encoding support.

**Synopsis:**
Comprehensive text file writing with encoding control and append mode.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Path` | String | Yes | - | File path to write |
| `Content` | String/Array | Yes | - | Text content to write |
| `Encoding` | String | No | `"UTF8"` | Text encoding |
| `Append` | Switch | No | `$false` | Append to existing file |
| `Force` | Switch | No | `$false` | Overwrite readonly files |
| `NoNewline` | Switch | No | `$false` | Don't add final newline |

**Return Data Properties:**

```powershell
$result.data.Path                # String: Written file path
$result.data.BytesWritten        # Long: Bytes written
$result.data.LineCount           # Int: Number of lines
$result.data.Encoding            # String: Encoding used
$result.data.WasAppended         # Boolean: Whether appended
```

**Example:**

```powershell
# Write single line
$result = WriteTextToFile -Path "C:\Logs\app.log" `
                          -Content "Application started"

if ($result.code -eq 0) {
    Write-Host "Wrote $($result.data.BytesWritten) bytes"
}

# Append to file
$result = WriteTextToFile -Path "C:\Logs\events.log" `
                          -Content "Error occurred" `
                          -Append

# Write multiple lines
$lines = @(
    "Line 1",
    "Line 2",
    "Line 3"
)

$result = WriteTextToFile -Path "C:\Data\output.txt" `
                          -Content $lines `
                          -Encoding "UTF8NoBOM"

if ($result.code -eq 0) {
    Write-Host "Wrote $($result.data.LineCount) lines"
}

# Force overwrite readonly file
$result = WriteTextToFile -Path "C:\Config\readonly.cfg" `
                          -Content $config `
                          -Force
```

**Notes:**
- Creates parent directories automatically
- Validates content is text (no binary)
- BOM handling depends on PS version
- Use `-Force` for readonly files

---

## Utility Functions

### GetBitmapIconFromDLL

Extracts an icon from a DLL file as a bitmap.

**Synopsis:**
Extracts Windows icons from DLL/EXE files using Win32 API.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `DLLfile` | String | Yes | - | DLL/EXE file path |
| `IconIndex` | Int | Yes | - | Icon index (zero-based) |

**Return Data Properties:**

```powershell
$result.data.DLLPath             # String: Source DLL path
$result.data.IconIndex           # Int: Extracted icon index
$result.data.TotalIconCount      # Int: Total icons in DLL
$result.data.Bitmap              # Bitmap: Extracted bitmap object
$result.data.Width               # Int: Bitmap width
$result.data.Height              # Int: Bitmap height
$result.data.PixelFormat         # String: Pixel format
```

**Example:**

```powershell
# Extract icon from shell32.dll
$result = GetBitmapIconFromDLL -DLLfile "C:\Windows\System32\shell32.dll" `
                               -IconIndex 0

if ($result.code -eq 0) {
    $bitmap = $result.data.Bitmap
    Write-Host "Extracted $($result.data.Width)x$($result.data.Height) icon"
    Write-Host "DLL contains $($result.data.TotalIconCount) total icons"
    
    # Use bitmap in WPF/WinForms
    $pictureBox.Image = $bitmap
    
    # Save to file
    $bitmap.Save("C:\Temp\icon.png", [System.Drawing.Imaging.ImageFormat]::Png)
}

# Extract from custom application
$result = GetBitmapIconFromDLL -DLLfile "C:\Program Files\MyApp\app.exe" `
                               -IconIndex 1
```

**Notes:**
- Requires System.Drawing assembly
- Returns large version of icon (32x32+)
- Index validation before extraction
- Dispose bitmap when done to free memory

---

### WriteLogMessage

Writes formatted log messages to console and/or file.

**Synopsis:**
Simple logging with severity levels and timestamp formatting.

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Message` | String | Yes | - | Log message |
| `Level` | String | No | `"Info"` | Severity (Info, Warning, Error, Debug) |
| `LogFile` | String | No | `""` | Optional log file path |

**Return Data:** None (this is a utility function)

**Example:**

```powershell
# Console logging
WriteLogMessage -Message "Application started" -Level "Info"
WriteLogMessage -Message "Deprecated function called" -Level "Warning"
WriteLogMessage -Message "Connection failed" -Level "Error"

# File logging
WriteLogMessage -Message "Database connected" `
                -Level "Info" `
                -LogFile "C:\Logs\app.log"

# Usage in script
try {
    # ... code ...
    WriteLogMessage "Operation successful" -Level "Info"
}
catch {
    WriteLogMessage "Operation failed: $_" -Level "Error" -LogFile $logPath
}
```

**Notes:**
- Automatically adds timestamp
- Color-coded console output
- Thread-safe file writing
- Creates log file if missing

---

## Best Practices

### Error Handling

```powershell
# Always check return code
$result = SomeFunction -Parameters

if ($result.code -eq 0) {
    # Success path
    ProcessData -Data $result.data
}
else {
    # Error path
    Write-Error $result.msg
    # Handle error appropriately
}
```

### Data Access

```powershell
# Access data properties directly
$result = GetProcessByName -Name "notepad"

if ($result.code -eq 0) {
    $pid = $result.data.ProcessId
    $memory = $result.data.WorkingSetMB
    # Use data...
}
```

### Resource Cleanup

```powershell
# Dispose resources when done
$result = GetBitmapIconFromDLL -DLLfile $dll -IconIndex 0

if ($result.code -eq 0) {
    $bitmap = $result.data.Bitmap
    # Use bitmap...
    $bitmap.Dispose()  # Free memory
}
```

### Privilege Requirements

```powershell
# Check for admin rights when needed
function RequiresAdmin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
                [Security.Principal.WindowsIdentity]::GetCurrent() `
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Error "This operation requires administrative privileges"
        return
    }
    
    # Perform admin operation
    $result = StartService -ServiceName "W3SVC"
}
```

---

## Version History

- **v2.0** - Complete migration to OPSreturn pattern
- **v1.5** - Added process and service management
- **v1.0** - Initial release

---

## Support

For issues, questions, or contributions:
- GitHub: [PowerShell.Mods Repository](https://github.com/praetoriani/PowerShell.Mods)
- Report bugs via GitHub Issues

---

## License

This module is provided as-is for use in PowerShell automation projects.
