<#
.SYNOPSIS
    local.httpserver - A simple HTTP server module for PowerShell with SPA-Support.
.DESCRIPTION
    This module provides a lightweight HTTP server implementation in PowerShell, designed
    to serve static files and support Single Page Applications (SPAs) with client-side routing.
    It is ideal for local development, testing, and quick file sharing without the need
    for complex server setups.
.EXAMPLE
    Import-Module "local.httpserver"
    SetCoreConfig -PathPointer "C:\wwwroot" -UseLogging 1
.REMARKS
    IMPORTANT NOTE: This module follows an Enterprise-Pattern with three simple steps
    -> Import the local.httpserver-Module
    -> Configure the server via SetCoreConfig
    -> Start using the Module
    That means:
.NOTES
    Creation Date : 15.04.2026
    Last Update   : 18.04.2026
    Version       : 1.00.00
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Website       : https://github.com/praetoriani

    REQUIREMENTS:
    - PowerShell 5.1 or higher
    - No external dependencies
#>

# ___________________________________________________________________________
# -> SECTION 1: Module Configuration
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# In this section we're defining the absolute minimum configuration for local.httpserver to work.
# This configuration can be accessed/changed via the SetCoreConfig function and is stored in the
# $script:config variable.

$script:root = $PSScriptRoot    # <- This is the root directory of the module, used for resolving relative paths in the config files

$script:syschecks = $true       # <- Indicates, if all system checks have been passed

$script:config = @{
    # please check below for a short description of the meaning
    PathPointer = $null             # <- Defaults to $httpHost.wwwroot on error
    ServerName  = "local.httpserver"
    UseLogging  = 0
    Mode        = 'console'
    UseIPC      = $false
}

function SetCoreConfig {
[CmdletBinding()]
param(
    # The path to the directory that should be served by the HTTP server.
    [Parameter(Mandatory = $true, HelpMessage = "Set the path to the directory that should be served by the HTTP server.", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "PathPointer")]
    [ValidateNotNullOrEmpty()]
    [string]$PathPointer,

    # Give your HTTP-Server a Name :-)
    [Parameter(Mandatory = $false, HelpMessage = "The name of your own local.httpserver.", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "ServerName")]
    [ValidateNotNullOrEmpty()]
    [string]$ServerName,

    # If set to 1, the module will create a logfile during runtime
    [Parameter(Mandatory = $false, HelpMessage = "Specify whether or not logging should be used.", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "UseLogging")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet(0,1)]
    [int]$UseLogging,

    # Set the operatin mode of the HTP-Server
    [Parameter(Mandatory = $false, HelpMessage = "Set the Mode local.hhtpserver should use", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "Mode")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('hidden','systray','console','desktop')]
    # hidden  -> local.httpserver runs completely (hidden) in the background
    # systray -> local.httpserver can be accessed via an icon in the system tray
    # console -> local.httpserver will show the original console window containing its process
    # desktop -> local.httpserver as a full WPF/XML-Based PowerShell UI
    [string]$Mode,

    # If used, a Pipe-Server will be created for IPC (Inter-Process Communication)
    # to allow external processes to send commands to the HTTP-Server.
    [Parameter(Mandatory = $false, HelpMessage = "Activates IPC to use named pipes for communicaating with local.httpserver", HelpMessageBaseName = "SetCoreConfig", HelpMessageResourceId = "UseIPC")]
    [switch]$UseIPC
)
    # Only handover the params, which were really used by the user
    foreach ($key in $PSBoundParameters.Keys) {
        $script:config[$key] = $PSBoundParameters[$key]
    }

    # ___________________________________________________________________________
    # -> Synchronize $script:httpHost with $script:config (Phase 1.2)
    # ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
    # $httpHost is loaded from module.config (Single Source of Truth).
    # SetCoreConfig writes into $script:config; we now keep $script:httpHost in sync
    # so that all internal functions can rely on $script:httpHost.wwwroot etc.

    if ($null -ne (Get-Variable -Name 'httpHost' -Scope Script -ErrorAction SilentlyContinue)) {

        # PathPointer -> wwwroot
        if ($PSBoundParameters.ContainsKey('PathPointer')) {
            $script:httpHost['wwwroot'] = $PathPointer
            Write-Verbose "[SetCoreConfig] \$httpHost.wwwroot updated to: $PathPointer"
        }

        # ServerName -> logfile
        if ($PSBoundParameters.ContainsKey('ServerName')) {
            $script:httpHost['logfile'] = $ServerName
            Write-Verbose "[SetCoreConfig] \$httpHost.logfile updated to: $ServerName"
        }

    } else {
        Write-Warning "[SetCoreConfig] \$httpHost is not available in script scope. module.config may not have been loaded yet."
    }

    # Ensure PathPointer fallback: if PathPointer was not supplied, default to $httpHost.wwwroot
    if ([string]::IsNullOrEmpty($script:config['PathPointer'])) {
        if ($null -ne (Get-Variable -Name 'httpHost' -Scope Script -ErrorAction SilentlyContinue)) {
            $script:config['PathPointer'] = $script:httpHost['wwwroot']
            Write-Verbose "[SetCoreConfig] PathPointer defaulted to \$httpHost.wwwroot: $($script:config['PathPointer'])"
        }
    }
}


# ___________________________________________________________________________
# -> SECTION 2: Load the core configuration file
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# This is the module configuration file for local.httpserver.
$modConf = Join-Path $script:root "include\module.config"

# Try to load the module.conf into the current scope via dot-sourcing the file
if (Test-Path $modConf) {
    . $modConf  # Dot-Sourcing - alle Variablen sind jetzt im aktuellen Scope verfuegbar
} else {
    # Multiline-Error-Message
    [string] $errorMessage = @(
        "[!!] Fatal Error during init-process of local.httpserver"
        "File: local.httpserver.psm1"
        "Date: $((Get-Date).ToString("dd.MM.yyyy"))"
        "Time: $((Get-Date).ToString("HH:mm:ss"))"
        "Info:"
        "-> File not found: $modConf"
    ) -join "`n"
    # drop the full error message
    Write-Error $errorMessage
    exit 1
}

# ___________________________________________________________________________
# -> SECTION 2a: Verify config variables are in scope (Phase 1.2)
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# After dot-sourcing module.config, ensure that all required config variables
# ($httpCore, $httpHost, $httpRouter, $mimeType) are available in script scope.
# This makes the config the Single Source of Truth and prevents silent failures.

$script:configinscope = $true

foreach ($requiredVar in @('httpCore', 'httpHost', 'httpRouter', 'mimeType')) {
    $varValue = Get-Variable -Name $requiredVar -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $varValue) {
        $script:configinscope = $false
        [string] $errorMessage = @(
            "[!!] Fatal Error during init-process of local.httpserver"
            "File: local.httpserver.psm1"
            "Date: $((Get-Date).ToString('dd.MM.yyyy'))"
            "Time: $((Get-Date).ToString('HH:mm:ss'))"
            "Info:"
            "-> Required config variable '`$$requiredVar' was not found in script scope after loading module.config."
            "   Please check include\module.config for correctness."
        ) -join "`n"
        Write-Error $errorMessage
        exit 1
    }
}

if ($script:configinscope) {
    Write-Verbose "[OK] All required config variables (\$httpCore, \$httpHost, \$httpRouter, \$mimeType) are available in script scope."
}


# ___________________________________________________________________________
# -> SECTION 3: Load required plugins
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# In this section we're going to import other modules (named as plugins)
# At htis point we need to sort some things out. The VPDLX Module should
# only be loaded, if UseLogging si set to 1. If Logging isn't activated,
# there is no need to load the Module

# First we need to make sure that we got plugins to load
if ( $script:httpCore['plugin'] -is [hashtable] -and $script:httpCore.plugin.Count -ne 0) {

    # Before we're going to loop through the Plugin-List, we need to verify
    # that every Plugin has the correct pattern and provides the following
    # 4 keys: src , name , desc , vers
    $validPK = 'src' , 'name' , 'desc' , 'vers'

    $script:httpCore.plugin.GetEnumerator() | ForEach-Object {
        $key = $_.Key
        $val = $_.Value
        # The Plugin has wrong type
        if (-not ($val -is [hashtable])) {
            [string] $errorMessage = @(
                "[!!] Validation Error during init-process of local.httpserver"
                "File: local.httpserver.psm1"
                "Date: $((Get-Date).ToString("dd.MM.yyyy"))"
                "Time: $((Get-Date).ToString("HH:mm:ss"))"
                "Info:"
                "Failed processing Plugins! Type is not a valid [hashtable]!"
            ) -join "`n"
            Write-Error $errorMessage
            exit 1
        }
        # The Plugin does not provide all reqired keys
        $missing = $validPK | Where-Object { -not $val.ContainsKey($_) }
        if ($missing) {
            [string] $errorMessage = @(
                "[!!] Fatal Error during init-process of local.httpserver"
                "File: local.httpserver.psm1"
                "Date: $((Get-Date).ToString("dd.MM.yyyy"))"
                "Time: $((Get-Date).ToString("HH:mm:ss"))"
                "Info:"
                "Unable to process. Plugin $val has missing sub-keys (src/name/desc/vers)"
            ) -join "`n"
            Write-Error $errorMessage
            exit 1

        }
    }

    # let's loop through the list of plugins
    foreach ($key in $script:httpCore.plugin.Keys) {

        # The current Module has not been imported yet
        if (-not (Get-Module -Name $script:httpCore.plugin[$key]['name'])) {
            # Make sure that the related file really exists
            if (Test-Path $script:httpCore.plugin[$key]['src']) {
                # At this point, everything looks good. So we're trying to load the modules (with a small exception for VPDLX)

                try {
                    # Special Case for VPDLX
                    if ($key.ToString().ToUpper() -eq "VPDLX") {
                        # Logging is active - so we need to import VPDLX
                        if ($script:config['UseLogging'] -eq 1) {
                            Import-Module $script:httpCore.plugin[$key]['src'] -Scope Global -ErrorAction Stop
                            Write-Verbose "[local.httpserver] Module 'VPDLX' loaded successfully."
                        }
                        # UseLogging=0 - we don't need to load VPDLX
                        else {
                            Write-Verbose "[local.httpserver] Skipped loading Module 'VPDLX' (UseLogging=0)"
                        }
                    }
                    # All other Modules/Plugins will be loaded in any case (as long as they are not VPDLX)
                    else {
                        Import-Module $script:httpCore.plugin[$key]['src'] -Scope Global -ErrorAction Stop
                        Write-Verbose "[local.httpserver] Module $key loaded successfully"
                    }
                }
                # Something went wrong while importing the module
                catch {
                    # Multiline-Error-Message
                    [string] $errorMessage = @(
                        "[!!] An Error occured while loading internal Modules"
                        "File: local.httpserver.psm1"
                        "Date: $((Get-Date).ToString("dd.MM.yyyy"))"
                        "Time: $((Get-Date).ToString("HH:mm:ss"))"
                        "Info:"
                        "-> File not found: $($script:httpCore.plugin[$key]['src'])"
                    ) -join "`n"
                    # drop the full error message
                    Write-Error $errorMessage
                    # In this case we're going to exit!
                    exit -1
                }

            }
            # The file is not available
            else {
                # Multiline-Error-Message
                [string] $errorMessage = @(
                    "[!!] An Error occured while loading internal Modules"
                    "File: local.httpserver.psm1"
                    "Date: $((Get-Date).ToString("dd.MM.yyyy"))"
                    "Time: $((Get-Date).ToString("HH:mm:ss"))"
                    "Info:"
                    "-> File not found: $($script:httpCore.plugin[$key]['src'])"
                ) -join "`n"
                # drop the full error message
                Write-Error $errorMessage
                # In this case we're going to exit!
                exit -1
            }
        }
        # The currrent Module is already available in our scope
        else {
            # Drop an info message and continue
            [string] $infoMessage = @(
                "[local.httpserver]"
                "File: local.httpserver.psm1"
                "Module $key is already loaded - skipping"
            ) -join "`n"
            Write-Verbose $infoMessage
            continue
        }

    }
    
}
# No plugins to load
elseif ( $script:httpCore['plugin'] -is [hashtable] -and $script:httpCore.plugin.Count -eq 0) {
    # Drop an info message and continue
    [string] $infoMessage = @(
        "[local.httpserver]"
        "File: local.httpserver.psm1"
        "No Plugins to load - skipping"
    ) -join "`n"
    Write-Verbose $infoMessage
}
# Wrong Format
else {
    [string] $errorMessage = @(
        "[!!] Validation Error during init-process of local.httpserver"
        "File: local.httpserver.psm1"
        "Date: $((Get-Date).ToString("dd.MM.yyyy"))"
        "Time: $((Get-Date).ToString("HH:mm:ss"))"
        "Info:"
        "Failed processing Plugins! Type is not a valid [hashtable]!"
    ) -join "`n"
    Write-Error $errorMessage
    exit 1
}


# ___________________________________________________________________________
# -> SECTION 4: Logfile initialisation
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# The initialization of the virtual logging will only be performed, when
# UseLogging is 1. If logging is deactivated, the entire section will be skipped

if ($script:config['UseLogging'] -eq 1) {

    # Create new log file
    $newLogfile = VPDLXnewlogfile -Logfile $script:httpHost.logfile
    if ($newLogfile.code -ne 0) {
        # Multiline-Error-Message
        [string] $errorMessage = @(
            "[!!] Fatal Error during init-process of local.httpserver"
            "File: local.httpserver.psm1"
            "Date: $((Get-Date).ToString("dd.MM.yyyy"))"
            "Time: $((Get-Date).ToString("HH:mm:ss"))"
            "Info:"
            "-> $($newLogfile.msg)"
        ) -join "`n"
        # drop the full error message
        Write-Error $errorMessage
        exit 1
    }
    # verify existence of the virtual logfile
    if (VPDLXislogfile -Logfile $script:httpHost.logfile) {
        # virtual logfile is ready. Let's write a first entry
        $result = VPDLXwritelogfile -Logfile $script:httpHost.logfile -Level 'info' -Message 'local.httpserver successfully initialized'
    }
    else {
        # looks like the logfile doesn't exist :/
        [string] $errorMessage = @(
            "[!!] Error while creating virtual logfile"
            "File: local.httpserver.psm1"
            "Date: $((Get-Date).ToString("dd.MM.yyyy"))"
            "Time: $((Get-Date).ToString("HH:mm:ss"))"
            "Info:"
            "-> Module VPDLX caused a runtime error. Function VPDLXnewlogfile did not create a logfile."
        ) -join "`n"
        # drop the full error message
        Write-Error $errorMessage
        exit 1
    }

}
else {
    # Drop an info message and continue
    [string] $infoMessage = @(
        "[local.httpserver]"
        "File: local.httpserver.psm1"
        "Logging is disabled (UseLogging=0) - skipping logfile initialization."
    ) -join "`n"
    Write-Verbose $infoMessage
}


# ___________________________________________________________________________
# -> SECTION 5: Bootstrapping
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# The Reason, why we do the dot-sourcing at the beginnging of the module is, that we have access to
# all public and private functions of this module during the runtime of local.httpserver.psm1.
# Get public and private function definition files
$PublicFunctions  = @(Get-ChildItem -Path $script:root\Public\*.ps1  -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path $script:root\Private\*.ps1 -ErrorAction SilentlyContinue)

# Import all functions
foreach ($ImportFile in @($PublicFunctions + $PrivateFunctions)) {
    try {
        Write-Verbose "Importing function from file: $($ImportFile.FullName)"
        . $ImportFile.FullName
    } catch {
        Write-Error "Failed to import function $($ImportFile.FullName): $($_.Exception.Message)"
    }
}

# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# NOTE: AS A PERSONAL DECISION, EXPORT-MODULEMEMBER ISN'T USED ANYMORE.
# EXPORT OF THE FUNCTIONS WILL FULLY BE HANDLED IN local.httpserver.psd1
# ___________________________________________________________________________

# Export public functions only
#if ($PublicFunctions) {
#    Export-ModuleMember -Function ($PublicFunctions.BaseName)
#}

# Bootstraping finished.
# The code below this line has now access to the public and private functions of this module.

# ___________________________________________________________________________
# Module initialization message
[string] $finalMessage = @(
    "‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"
    "local.httpserver module loaded successfully. Available functions:"
    "$(($PublicFunctions.BaseName) -join ', ')"
    "___________________________________________________________________________"
    "Enjoy using local.httpserver :-)"
    ""
) -join "`n"
Write-Verbose $finalMessage
