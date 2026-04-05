<#
.SYNOPSIS
    VPDLX - Virtual PowerShell Data-Logger eXtension
    This PowerShell module provides a type of virtual logging system that makes it possible
    to create, manage, and export multiple virtual log files simultaneously.

.DESCRIPTION
    Virtual PowerShell Data-Logger eXtension is designed to provide a professional, stable, fast, and secure solution
    for easily creating and managing multiple virtual log files. After successful import into an existing PowerShell
    script, the system is available immediately at runtime. From then on, you can create, read, filter, and analyze
    your own virtual log files, as well as export them in various file formats (e.g., *.txt, *.csv, *.json, *.xlsx).
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

# define vars on module-level (script scope = module scope)
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$script:appinfo = @{
    appname     = 'VPDLX'
    appvers     = '1.00.05'
    appdevname  = 'Praetoriani'
    appdevmail  = 'mr.praetoriani{at}gmail.com'
    appwebsite  = 'https://github.com/praetoriani/PowerShell.Mods'
    datecreate  = '05.05.2026'
    lastupdate  = '05.05.2026'
}

# This is an example of how the structure of a virtual logfile looks like.
# The data-key is an array, to make the handling a bit easier. You can
# simply push new entries to the data array. Every element in this array
# has the same structure:
# [dd.MM.yyyy | HH:mm:ss]   [LOGLEVEL]  →  [LOGMESSAGE]
# Possible log-levels are: INFO, DEBUG, WARNING, ERROR, CRITICAL
# ⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆⋆
$script:logfile = @{
    name        = ""        # Name of the virtual log file
    data        = @()       # This array will hold the entire log data
    info        = @{
        created = Get-Date -Format "[dd.MM.yyyy | HH:mm:ss]"    # Stores the Timestamp when vitual logfile is created
        updated = ""        # Stores the Timestamp when vitual logfile is updated (e.g., new log entry added)
    }
}

# Get public and private function definition files
$PublicFunctions = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)

# Import all functions
foreach ($ImportFile in @($PublicFunctions + $PrivateFunctions)) {
    try {
        Write-Verbose "Importing function from file: $($ImportFile.FullName)"
        . $ImportFile.FullName
    }
    catch {
        Write-Error "Failed to import function $($ImportFile.FullName): $($_.Exception.Message)"
    }
}

# Export public functions only
if ($PublicFunctions) {
    #Export-ModuleMember -Function ($PublicFunctions.BaseName + @('AppScope'))
    Export-ModuleMember -Function ($PublicFunctions.BaseName)
}

# Module initialization message
Write-Verbose "WinISOScriptFXLib module loaded successfully. Available functions: $(($PublicFunctions.BaseName) -join ', ')"
