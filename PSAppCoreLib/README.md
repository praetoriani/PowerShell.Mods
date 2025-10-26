# PSAppCoreLib PowerShell Module

## Overview

PSAppCoreLib is a comprehensive PowerShell module that provides a collection of useful functions for PowerShell application development. This module includes advanced functions for logging, icon extraction, and other common tasks needed in professional PowerShell applications.

## Module Information

- **Name**: PSAppCoreLib
- **Version**: 1.00.00  
- **Author**: Praetoriani (a.k.a. M.Sczepanski)
- **Website**: [github.com/praetoriani](https://github.com/praetoriani)
- **Root Module**: PSAppCoreLib.psm1
- **Description**: Collection of useful functions for PowerShell apps

## Requirements

- **PowerShell**: Version 5.1 or higher
- **.NET Framework**: 4.7.2 or higher (for Windows PowerShell)
- **PowerShell Core**: Supported on all platforms
- **Required Assemblies**: System.Drawing, System.Windows.Forms

## Installation

### Manual Installation

1. Download or clone the module files
2. Create a folder named `PSAppCoreLib` in one of your PowerShell module paths:
   - `$env:PSModulePath -split ';'` (Windows)
   - `$env:PSModulePath -split ':'` (Linux/macOS)
3. Copy all module files to the `PSAppCoreLib` folder
4. Import the module: `Import-Module PSAppCoreLib`

### PowerShell Gallery Installation (Future)

```powershell
# When published to PowerShell Gallery
Install-Module -Name PSAppCoreLib -Scope CurrentUser
```

## Module Structure

```
PSAppCoreLib/
├── Private/                    # Internal helper functions
├── Public/                     # Public functions exported by the module  
│   ├── WriteLogMessage.ps1
│   └── GetBitmapIconFromDLL.ps1
├── Examples/                   # Usage examples for each function
│   ├── WriteLogMessage_Examples.ps1
│   └── GetBitmapIconFromDLL_Examples.ps1
├── PSAppCoreLib.psm1          # Main module file
├── PSAppCoreLib.psd1          # Module manifest
└── README.md                   # This file
```

## Functions

### WriteLogMessage

Creates formatted log entries with timestamps and severity flags.

#### Syntax
```powershell
WriteLogMessage [-Logfile] <String> [-Message] <String> [[-Flag] <String>] [[-Override] <Int32>]
```

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Logfile` | String | Yes | - | Full path including filename to the log file |
| `Message` | String | Yes | - | The text message to write to the log file |
| `Flag` | String | No | "DEBUG" | Severity flag: INFO, DEBUG, WARN, or ERROR |
| `Override` | Int32 | No | 0 | Whether to overwrite the log file (1) or append (0) |

#### Return Value

Returns a status object with the following properties:
- `code`: Integer (0 = success, -1 = error)
- `msg`: String (empty on success, error message on failure)

#### Log Format

```
[2025.10.26 ; 14:30:15] [INFO ] Application started successfully
[2025.10.26 ; 14:30:16] [DEBUG] Configuration loaded
[2025.10.26 ; 14:30:17] [WARN ] Deprecated function used
[2025.10.26 ; 14:30:18] [ERROR] Critical system failure
```

#### Examples

```powershell
# Basic logging with default DEBUG flag
$result = WriteLogMessage -Logfile "C:\Logs\app.log" -Message "Application started"

# Info message logging
$result = WriteLogMessage -Logfile "C:\Logs\app.log" -Message "User logged in" -Flag "INFO"

# Error logging with file override
$result = WriteLogMessage -Logfile "C:\Logs\error.log" -Message "Critical error" -Flag "ERROR" -Override 1

# Check result
if ($result.code -eq 0) {
    Write-Host "Log entry created successfully"
} else {
    Write-Host "Error: $($result.msg)"
}
```

### GetBitmapIconFromDLL

Extracts icons from DLL files and converts them to bitmap format.

#### Syntax
```powershell
GetBitmapIconFromDLL [-DLLfile] <String> [-IconIndex] <Int32>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `DLLfile` | String | Yes | Full path including filename to the DLL file |
| `IconIndex` | Int32 | Yes | Zero-based index of the icon to extract |

#### Return Value

Returns a status object with the following properties:
- `code`: Integer (0 = success, -1 = error)
- `msg`: String (empty on success, error message on failure)
- `bitmap`: System.Drawing.Bitmap object (on success)

#### Examples

```powershell
# Extract icon from shell32.dll
$result = GetBitmapIconFromDLL -DLLfile "$env:SystemRoot\System32\shell32.dll" -IconIndex 0

if ($result.code -eq 0) {
    Write-Host "Icon extracted successfully!"
    Write-Host "Size: $($result.bitmap.Width)x$($result.bitmap.Height)"
    
    # Save bitmap to file
    $result.bitmap.Save("C:\Temp\icon.png", [System.Drawing.Imaging.ImageFormat]::Png)
    
    # Always dispose of the bitmap when done
    $result.bitmap.Dispose()
} else {
    Write-Host "Error: $($result.msg)"
}

# Extract from imageres.dll
$result = GetBitmapIconFromDLL -DLLfile "$env:SystemRoot\System32\imageres.dll" -IconIndex 15
```

## Error Handling

All functions in this module use a standardized error handling approach with a consistent return object:

```powershell
$status = [PSCustomObject]@{
    code = 0        # 0 = success, -1 = error
    msg = ""        # Empty on success, error message on failure
}
```

This allows for reliable error checking and debugging in your applications.

## Advanced Function Features

All functions in this module are implemented as PowerShell Advanced Functions, providing:

- **Parameter Validation**: Built-in parameter validation and type checking
- **Pipeline Support**: Full pipeline support where applicable  
- **Verbose Output**: Detailed verbose output for troubleshooting
- **Error Handling**: Comprehensive error handling with detailed messages
- **Help Documentation**: Complete help documentation accessible via `Get-Help`

## Usage Examples

### Basic Module Usage

```powershell
# Import the module
Import-Module PSAppCoreLib

# Get available functions
Get-Command -Module PSAppCoreLib

# Get help for a specific function
Get-Help WriteLogMessage -Full
Get-Help GetBitmapIconFromDLL -Examples
```

### Logging Workflow

```powershell
# Application startup logging
$logFile = "C:\Logs\MyApp.log"

$result = WriteLogMessage -Logfile $logFile -Message "Application startup initiated" -Flag "INFO"
if ($result.code -ne 0) { 
    throw "Failed to initialize logging: $($result.msg)" 
}

# Process logging
WriteLogMessage -Logfile $logFile -Message "Processing user data" -Flag "DEBUG"
WriteLogMessage -Logfile $logFile -Message "Performance warning: slow response" -Flag "WARN"

# Error logging
try {
    # Your application code here
} catch {
    WriteLogMessage -Logfile $logFile -Message "Exception: $($_.Exception.Message)" -Flag "ERROR"
}
```

### Icon Extraction Workflow

```powershell
# Extract multiple icons from system DLLs
$iconDLLs = @(
    @{ File = "$env:SystemRoot\System32\shell32.dll"; Indices = @(0, 1, 2, 3) }
    @{ File = "$env:SystemRoot\System32\imageres.dll"; Indices = @(5, 10, 15) }
)

foreach ($dll in $iconDLLs) {
    foreach ($index in $dll.Indices) {
        $result = GetBitmapIconFromDLL -DLLfile $dll.File -IconIndex $index
        
        if ($result.code -eq 0) {
            $fileName = "icon_$(Split-Path $dll.File -Leaf)_$index.png"
            $result.bitmap.Save("C:\Icons\$fileName", [System.Drawing.Imaging.ImageFormat]::Png)
            $result.bitmap.Dispose()
            Write-Host "✓ Saved: $fileName"
        } else {
            Write-Warning "Failed to extract icon $index from $(Split-Path $dll.File -Leaf): $($result.msg)"
        }
    }
}
```

## Best Practices

### Memory Management

When using `GetBitmapIconFromDLL`, always dispose of bitmap objects:

```powershell
$result = GetBitmapIconFromDLL -DLLfile $dllPath -IconIndex $index
try {
    # Use the bitmap
    $result.bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    # Always dispose to prevent memory leaks
    if ($result.bitmap) { $result.bitmap.Dispose() }
}
```

### Error Handling

Always check the return code from functions:

```powershell
$result = WriteLogMessage -Logfile $logFile -Message $message
if ($result.code -ne 0) {
    # Handle the error appropriately
    throw "Logging failed: $($result.msg)"
}
```

### Logging Strategy

- Use appropriate log levels (DEBUG for development, INFO for important events, WARN for issues, ERROR for failures)
- Consider log file rotation for long-running applications
- Use meaningful, descriptive log messages

## Troubleshooting

### Common Issues

1. **Assembly Loading Errors**: Ensure .NET Framework 4.7.2+ is installed
2. **Permission Errors**: Verify write permissions to log file directories
3. **DLL Access Errors**: Ensure DLL files exist and are accessible
4. **Memory Issues**: Always dispose of bitmap objects after use

### Verbose Output

Enable verbose output for detailed troubleshooting:

```powershell
Import-Module PSAppCoreLib -Verbose
$VerbosePreference = "Continue"
WriteLogMessage -Logfile $logFile -Message $message -Verbose
```

## Contributing

Contributions are welcome! Please follow these guidelines:

1. All code must be in English with English comments
2. Follow PowerShell best practices and coding standards
3. Implement functions as Advanced Functions with proper parameter validation
4. Include comprehensive help documentation
5. Add examples for new functions
6. Test thoroughly on both Windows PowerShell and PowerShell Core

## License

This module is provided as-is under the MIT License. See the LICENSE file for details.

## Support

For support, issues, and feature requests, please visit:
- **GitHub**: [github.com/praetoriani](https://github.com/praetoriani)
- **Issues**: Create an issue on the GitHub repository

## Version History

### Version 1.00.00 (Initial Release)
- `WriteLogMessage`: Advanced logging function with timestamp and severity flags
- `GetBitmapIconFromDLL`: Extract and convert icons from DLL files to bitmaps  
- Comprehensive error handling with standardized return objects
- Full English documentation and code comments
- Compatible with PowerShell 5.1+ and PowerShell Core
- Complete examples and usage documentation

---

*Generated on: 26 October 2025*  
*Author: Praetoriani (a.k.a. M.Sczepanski)*  
*Website: [github.com/praetoriani](https://github.com/praetoriani)*