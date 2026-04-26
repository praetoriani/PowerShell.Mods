<#
.SYNOPSIS
    Returns the current runtime configuration of local.httpserver.

.DESCRIPTION
    Get-ServerConfig provides a safe, read-only window into the module's
    internal $script:config and $script:httpHost state.

    The module stores its configuration in $script:config and $script:httpHost,
    which are private to the module scope. Launcher scripts, external tools,
    and future IPC handlers (Phase 4) cannot access these variables directly
    with $script: because the $script: prefix is relative to the file in which
    the code runs - not to the module.

    Get-ServerConfig solves this by acting as a controlled gateway: it reads
    the private state inside the module scope and returns a structured
    PSCustomObject that callers can safely read and inspect.

    The returned object is a SNAPSHOT - it reflects the state at the moment
    of the call. It is not a live reference. Modifying its properties has no
    effect on the module's internal configuration; use SetCoreConfig for that.

.PARAMETER Section
    Optional. Narrows the output to a specific section of the configuration.

    'all'      - (default) Returns the full configuration snapshot.
    'config'   - Returns only the $script:config hashtable entries
                 (Mode, Port, PathPointer, UseLogging, ServerName, UseIPC).
    'httphost' - Returns only the $script:httpHost hashtable entries
                 (domain, port, wwwroot, logfile, etc.).
    'mode'     - Returns only the current Mode string (e.g. 'console').
    'port'     - Returns only the current port number as [int].

.OUTPUTS
    PSCustomObject  - when Section is 'all', 'config', or 'httphost'.
    [string]        - when Section is 'mode'.
    [int]           - when Section is 'port'.

.EXAMPLE
    # Get the full configuration snapshot
    $cfg = Get-ServerConfig
    Write-Host "Mode : $($cfg.Mode)"
    Write-Host "Port : $($cfg.Port)"

.EXAMPLE
    # Use in a conditional - replaces the broken $script:config['Mode'] pattern
    if ((Get-ServerConfig -Section 'mode') -eq 'console') {
        Write-Host "Console mode active."
    }

.EXAMPLE
    # Get only the port number
    $port = Get-ServerConfig -Section 'port'
    Write-Host "Server is listening on port $port"

.EXAMPLE
    # Inspect the full httpHost block
    $host = Get-ServerConfig -Section 'httphost'
    Write-Host "wwwRoot : $($host.wwwroot)"
    Write-Host "Domain  : $($host.domain)"

    # In the launcher: Check the mode (the actual fix)
    if ((Get-ServerConfig -Section 'mode') -eq 'console') { ... }

    # Query the current port
    $port = Get-ServerConfig -Section 'port'
    Start-Process "http://localhost:$port"

    # Get the complete configuration as an object
    $cfg = Get-ServerConfig
    Write-Host "Server: $($cfg.ServerName) auf Port $($cfg.Port) im Modus $($cfg.Mode)"

    # Only the httpHost block (for phase 4: IPC server needs wwwroot)
    $hostCfg = Get-ServerConfig -Section 'httphost'
    Write-Host "Serving files from: $($hostCfg.wwwroot)"

    # Output the full config (helpful for debugging)
    Get-ServerConfig | Format-List

.NOTES
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Creation Date : 26.04.2026
    Last Update   : 26.04.2026
    Phase         : Phase 3 - Background mode & Runspaces
    Compatibility : PowerShell 5.1 and PowerShell 7.x
    File          : Public/Get-ServerConfig.ps1

    IMPORTANT - This function returns a READ-ONLY snapshot.
    To change configuration values, use SetCoreConfig.
    To check server runtime status, use Get-LocalHttpServerStatus.
#>
function Get-ServerConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('all', 'config', 'httphost', 'mode', 'port')]
        [string]$Section = 'all'
    )

    # ------------------------------------------------------------------
    # Guard: ensure the module has been initialised
    # ------------------------------------------------------------------
    # $script:config is set during PSM1 startup (Section 1). If it is
    # $null here, the module was not loaded correctly.
    if ($null -eq $script:config) {
        Write-Warning "[Get-ServerConfig] Module configuration is not initialised. Has SetCoreConfig been called?"
        return $null
    }

    # ------------------------------------------------------------------
    # Return the requested section
    # ------------------------------------------------------------------
    switch ($Section) {

        'mode' {
            # Direct string return - ideal for if-conditions in the launcher
            return [string]$script:config['Mode']
        }

        'port' {
            # Direct int return - useful for URL construction
            return [int]$script:config['Port']
        }

        'config' {
            # Snapshot of $script:config only
            return [PSCustomObject]@{
                Mode        = $script:config['Mode']
                Port        = $script:config['Port']
                PathPointer = $script:config['PathPointer']
                ServerName  = $script:config['ServerName']
                UseLogging  = $script:config['UseLogging']
                UseIPC      = $script:config['UseIPC']
            }
        }

        'httphost' {
            # Snapshot of $script:httpHost - returns $null if not loaded
            if ($null -eq $script:httpHost) {
                Write-Warning "[Get-ServerConfig] `$script:httpHost is not available."
                return $null
            }
            return [PSCustomObject]@{
                domain  = $script:httpHost['domain']
                port    = $script:httpHost['port']
                wwwroot = $script:httpHost['wwwroot']
                logfile = $script:httpHost['logfile']
            }
        }

        'all'  {
            # Full snapshot combining both config sources
            $httpHostData = if ($null -ne $script:httpHost) {
                [PSCustomObject]@{
                    domain  = $script:httpHost['domain']
                    port    = $script:httpHost['port']
                    wwwroot = $script:httpHost['wwwroot']
                    logfile = $script:httpHost['logfile']
                }
            } else { $null }

            return [PSCustomObject]@{
                # From $script:config
                Mode        = $script:config['Mode']
                Port        = $script:config['Port']
                PathPointer = $script:config['PathPointer']
                ServerName  = $script:config['ServerName']
                UseLogging  = $script:config['UseLogging']
                UseIPC      = $script:config['UseIPC']
                # From $script:httpHost
                HttpHost    = $httpHostData
            }
        }
    }
}
