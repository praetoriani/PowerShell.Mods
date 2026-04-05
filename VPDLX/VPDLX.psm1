<#
.SYNOPSIS
    VPDLX - Virtual PowerShell Data-Logger eXtension
    This PowerShell module provides a virtual logging system that makes it possible
    to create, manage, and export multiple virtual log files simultaneously.

.DESCRIPTION
    Virtual PowerShell Data-Logger eXtension is designed to provide a professional,
    stable, fast, and secure solution for easily creating and managing multiple virtual
    log files. After successful import into an existing PowerShell script, the system
    is available immediately at runtime. From then on, you can create, read, filter,
    and analyze your own virtual log files, as well as export them in various file
    formats (e.g., *.txt, *.csv, *.json).
    Only minimal configuration is required before VPDLX can be used.

.NOTES
    Creation Date: 05.04.2026
    Last Update:   05.04.2026
    Version:       1.00.00
    Author:        Praetoriani (a.k.a. M.Sczepanski)
    Website:       https://github.com/praetoriani/PowerShell.Mods

    REQUIREMENTS & DEPENDENCIES:
    - PowerShell 5.1 or higher
#>

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# Module-level meta information
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$script:appinfo = @{
    appname     = 'VPDLX'
    appvers     = '1.00.00'
    appdevname  = 'Praetoriani'
    appdevmail  = 'mr.praetoriani{at}gmail.com'
    appwebsite  = 'https://github.com/praetoriani/PowerShell.Mods'
    datecreate  = '05.04.2026'
    lastupdate  = '05.04.2026'
}

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# Defines the supported log levels and their formatted output prefix.
# Each key is the normalized (lowercase) log level identifier used when calling
# WriteLogfileEntry. The value is the formatted prefix that appears in the log line.
# This hash table is also used to validate the 'loglevel' parameter at runtime.
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$script:loglevel = @{
    info        = '  [INFO]      ->  '
    debug       = '  [DEBUG]     ->  '
    warning     = '  [WARNING]   ->  '
    error       = '  [ERROR]     ->  '
    critical    = '  [CRITICAL]  ->  '
    default     = '  [INFO]      ->  '
}

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# Global file storage registry.
# Stores the names of all currently active virtual log files.
# Written by : CreateNewLogfile (on successful creation)
# Modified by: DeleteLogfile    (on successful deletion)
# Read by    : WriteLogfileEntry, ReadLogfileEntry, ResetLogfile, DeleteLogfile
#
# Each element in this array is the plain filename string (without extension)
# that was passed to CreateNewLogfile. This array provides a simple overview
# of all virtual log files managed by the current VPDLX instance.
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$script:filestorage = @()

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# Runtime storage for all virtual log file instances.
# Key   : normalized filename (lowercase) used as the unique identifier.
# Value : hashtable with the same structure as the logfile template below.
#
# Structure of each instance:
#   name  -> [string]  original filename as provided by the caller
#   data  -> [array]   all log lines in order; each element is one formatted line
#   info  -> [hashtable]
#       created -> [string]  timestamp of creation  ([dd.MM.yyyy | HH:mm:ss])
#       updated -> [string]  timestamp of last write ([dd.MM.yyyy | HH:mm:ss])
#       entries -> [int]     total number of data lines currently in the log
#
# Log line format:
#   [dd.MM.yyyy | HH:mm:ss]   [LOGLEVEL]  ->  MESSAGE
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$script:loginstances = @{}

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# Shared exit/status carrier used by the VPDLXcore accessor.
# code : -1 on failure, 0 on success
# text : human-readable error or status message
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$script:exit = @{
    code = -1
    text = [string]::Empty
}

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# VPDLXcore - Accessor for script-scoped module variables.
# Dot-sourced scripts cannot directly access $script:* variables from the root
# module scope. This getter function bridges that gap by returning the requested
# variable by its key identifier.
#
# Accessible keys:
#   'appinfo'      -> $script:appinfo
#   'loglevel'     -> $script:loglevel
#   'filestorage'  -> $script:filestorage
#   'loginstances' -> $script:loginstances
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
function VPDLXcore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $KeyID
    )

    $script:exit['code'] = -1
    $script:exit['text'] = [string]::Empty

    try {
        if ([string]::IsNullOrWhiteSpace($KeyID)) {
            $script:exit['code'] = -1
            $script:exit['text'] = "Parameter 'KeyID' is required and must not be null, empty, or whitespace-only."
            return $script:exit
        }

        switch ($KeyID.ToLower()) {
            'appinfo'      { return $script:appinfo }
            'loglevel'     { return $script:loglevel }
            'filestorage'  { return $script:filestorage }
            'loginstances' { return $script:loginstances }
            default {
                $script:exit['code'] = -1
                $script:exit['text'] = "Unknown KeyID '$KeyID'. Valid keys: 'appinfo', 'loglevel', 'filestorage', 'loginstances'."
                return $script:exit
            }
        }
    }
    catch {
        $script:exit['code'] = -1
        $script:exit['text'] = "Unexpected error in VPDLXcore: $($_.Exception.Message)"
        return $script:exit
    }
}

# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
# Auto-import all Public and Private function files
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$PublicFunctions  = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1  -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)

foreach ($ImportFile in @($PublicFunctions + $PrivateFunctions)) {
    try {
        Write-Verbose "Importing function from file: $($ImportFile.FullName)"
        . $ImportFile.FullName
    }
    catch {
        Write-Error "Failed to import function $($ImportFile.FullName): $($_.Exception.Message)"
    }
}

if ($PublicFunctions) {
    Export-ModuleMember -Function ($PublicFunctions.BaseName + @('VPDLXcore'))
}

Write-Verbose "VPDLX module loaded successfully. Available functions: $(($PublicFunctions.BaseName) -join ', ')"
