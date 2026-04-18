<#
.SYNOPSIS
    The system.precheck.ps1 is launched via ScriptsToProcess!
    It performs a precheck, to ensure that everything we need is in place
.DESCRIPTION
    The system.precheck.ps1 performs a couple of checks, BEFORE the module is fully loaded.
    With this we're trying to make sure that the module is only loaded, if the target system
    fullfils the requirements.
.NOTES
    Version:        v1.00.00
    Author:         Praetoriani
    Github:         http://github.com/praetoriani
    Date Created:   16.04.2026
    Last Updated:   18.04.2026
#>

# ___________________________________________________________________________
# -> SECTION 1: PowerShell Version Check
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Minimum required version: PowerShell 5.1

$script:__precheck_passed = $true

$psMinMajor = 5
$psMinMinor = 1

if ($PSVersionTable.PSVersion.Major -lt $psMinMajor -or
    ($PSVersionTable.PSVersion.Major -eq $psMinMajor -and $PSVersionTable.PSVersion.Minor -lt $psMinMinor)) {

    $script:__precheck_passed = $false
    [string]$errorMessage = @(
        "[!!] Fatal Error: local.httpserver requires PowerShell $psMinMajor.$psMinMinor or higher.",
        "     Detected version: $($PSVersionTable.PSVersion.ToString())",
        "     Please upgrade PowerShell and try again."
    ) -join "`n"
    Write-Error $errorMessage
    throw $errorMessage
}

# ___________________________________________________________________________
# -> SECTION 2: HttpListener Availability Check
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Ensure System.Net.HttpListener is available on this system

try {
    $httpListenerType = [System.Net.HttpListener]
    if ($null -eq $httpListenerType) {
        throw "Type resolved to null."
    }
} catch {
    $script:__precheck_passed = $false
    [string]$errorMessage = @(
        "[!!] Fatal Error: System.Net.HttpListener is not available on this system.",
        "     local.httpserver requires System.Net.HttpListener to operate.",
        "     Error details: $($_.Exception.Message)"
    ) -join "`n"
    Write-Error $errorMessage
    throw $errorMessage
}

# ___________________________________________________________________________
# -> SECTION 3: wwwroot Directory Check
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Check if the configured wwwroot directory exists.
# If $httpHost is already loaded (dot-sourced from module.config), use its wwwroot.
# Otherwise fall back to a default 'wwwroot' subfolder relative to the module root.

$script:__wwwroot_resolved = $null

if ((Get-Variable -Name 'httpHost' -Scope Script -ErrorAction SilentlyContinue) -ne $null) {
    $script:__wwwroot_resolved = $httpHost.wwwroot
} elseif ((Get-Variable -Name 'httpHost' -Scope Global -ErrorAction SilentlyContinue) -ne $null) {
    $script:__wwwroot_resolved = $global:httpHost.wwwroot
}

# Fallback: resolve relative to the module root (PSScriptRoot of the psm1, one level up from include/)
if ([string]::IsNullOrEmpty($script:__wwwroot_resolved)) {
    $script:__wwwroot_resolved = Join-Path (Split-Path $PSScriptRoot -Parent) "wwwroot"
}

if (-not (Test-Path -Path $script:__wwwroot_resolved -PathType Container)) {
    # Non-critical warning: wwwroot missing at load time is acceptable.
    # The path may be supplied later via SetCoreConfig -PathPointer.
    # We write a warning but do NOT abort the module load.
    Write-Warning @"
[!] Warning (system.precheck.ps1):
    The configured wwwroot directory was not found:
    --> $($script:__wwwroot_resolved)
    The module will still load. Make sure to provide a valid path via SetCoreConfig -PathPointer
    before starting the HTTP server.
"@
} else {
    Write-Verbose "[OK] wwwroot directory found: $($script:__wwwroot_resolved)"
}

# ___________________________________________________________________________
# -> SECTION 4: Precheck Summary
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if ($script:__precheck_passed) {
    Write-Verbose "[OK] system.precheck.ps1 completed successfully. All critical requirements are met."
}
