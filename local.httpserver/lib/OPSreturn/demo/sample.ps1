<#
.SYNOPSIS
    sample.ps1 - Interactive step-by-step walkthrough of OPSreturn v1.00.00

.DESCRIPTION
    This script provides an interactive, guided demonstration of the OPSreturn module.
    It covers all 9 public shorthand functions as well as the direct OPSreturn core
    function, the OPScode enum, and the SetCoreConfig configuration options.

    The demo pauses at the end of each section and waits for the user to press
    ENTER before continuing. This gives you time to read the console output and
    understand what happened in each step.

    Sections covered:
        01 - Module import
        02 - SetCoreConfig (timestamp + verbosed)
        03 - Direct OPSreturn call (core function)
        04 - OPSsuccess
        05 - OPSinfo
        06 - OPSdebug
        07 - OPStimeout
        08 - OPSwarn
        09 - OPSfail
        10 - OPSerror
        11 - OPScritical
        12 - OPSfatal
        13 - Return object inspection (all fields)
        14 - Using OPSreturn inside real functions (caller source tracking)
        15 - Error handling: checking .code in a pipeline
        16 - Overview of all OPScode enum values

.NOTES
    Module  : OPSreturn
    Version : 1.00.00
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Updated : 18.04.2026

    Usage:
        .\OPSreturn\demo\sample.ps1
        & 'C:\full\path\to\OPSreturn\demo\sample.ps1'
#>


# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Show-DemoStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $Step,
        [Parameter(Mandatory = $true)] [string] $Title
    )
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor DarkCyan
    Write-Host "  [ STEP $Step ]  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor DarkCyan
    Write-Host ''
}

function WaitForEnter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string] $Message = 'Press ENTER to continue ...',

        [Parameter(Mandatory = $false)]
        [ConsoleColor] $Color = [ConsoleColor]::DarkGray,

        [Parameter(Mandatory = $false)]
        [switch] $Block
    )
    if ($Block.IsPresent) { Write-Host '' }
    do {
        Write-Host $Message -NoNewline -ForegroundColor $Color
        $key = Read-Host
    } while ($key -ne '')
    if ($Block.IsPresent) { Write-Host '' }
}

function Show-OPSResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]  $Result,
        [Parameter(Mandatory = $false)] [string] $Label = 'Result Object'
    )
    Write-Host "  -- $Label" -ForegroundColor DarkGray
    Write-Host ("  {0,-12} : {1}" -f 'code',      $Result.code)      -ForegroundColor White
    Write-Host ("  {0,-12} : {1}" -f 'state',     $Result.state)     -ForegroundColor White
    Write-Host ("  {0,-12} : {1}" -f 'msg',       $Result.msg)       -ForegroundColor White
    Write-Host ("  {0,-12} : {1}" -f 'data',      $(if ($null -eq $Result.data)      { '[null]' } else { $Result.data })) -ForegroundColor White
    Write-Host ("  {0,-12} : {1}" -f 'exception', $(if ($null -eq $Result.exception) { '[null]' } else { $Result.exception })) -ForegroundColor White
    Write-Host ("  {0,-12} : {1}" -f 'source',    $Result.source)    -ForegroundColor White
    Write-Host ("  {0,-12} : {1}" -f 'timecode',  $Result.timecode)  -ForegroundColor White
    Write-Host ''
}


# ==============================================================================
# DEMO START
# ==============================================================================
Clear-Host

Write-Host ('=' * 70) -ForegroundColor DarkGray
Write-Host '  OPSreturn - Standardized Operation Status Reporting'    -ForegroundColor DarkGray
Write-Host '  Interactive Demo  //  Version 1.00.00'                  -ForegroundColor DarkGray
Write-Host ('=' * 70) -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Welcome! This demo walks you through every feature of OPSreturn'  -ForegroundColor Gray
Write-Host '  step by step. Press ENTER at the end of each section to continue.' -ForegroundColor Gray
Write-Host ''
Write-Host '  Every result object contains these 7 fields:'           -ForegroundColor Gray
Write-Host '    code       integer status code  (0+ = ok, negative = problem)' -ForegroundColor DarkGray
Write-Host '    state      string name of the OPScode enum value'     -ForegroundColor DarkGray
Write-Host '    msg        your short message'                        -ForegroundColor DarkGray
Write-Host '    data       optional payload (any type)'               -ForegroundColor DarkGray
Write-Host '    exception  optional exception object'                 -ForegroundColor DarkGray
Write-Host '    source     auto-detected calling function name'       -ForegroundColor DarkGray
Write-Host '    timecode   timestamp (configurable via SetCoreConfig)' -ForegroundColor DarkGray
Write-Host ''
Write-Host ('=' * 70) -ForegroundColor DarkGray
Write-Host ''

WaitForEnter -Message 'Press ENTER to start the demonstration ...' -Color DarkGray -Block


# ==============================================================================
# STEP 01 - Import the OPSreturn module
# ==============================================================================
Show-DemoStep -Step '01' -Title 'Import the OPSreturn module'

Write-Host '  The module is imported using Import-Module. The path is resolved'  -ForegroundColor Gray
Write-Host '  via $PSScriptRoot so this demo works from any working directory.'  -ForegroundColor Gray
Write-Host ''
Write-Host '  Expected layout:'                                                   -ForegroundColor Gray
Write-Host '    OPSreturn\'                                                       -ForegroundColor DarkGray
Write-Host '    OPSreturn\OPSreturn.psd1'                                         -ForegroundColor DarkGray
Write-Host '    OPSreturn\demo\sample.ps1   <-- this file'                        -ForegroundColor DarkGray
Write-Host ''

$modulePath = Join-Path $PSScriptRoot '..\OPSreturn.psd1'

if (-not (Test-Path $modulePath)) {
    Write-Host "  [ERROR] Module manifest not found at: $modulePath" -ForegroundColor Red
    Write-Host '  Please ensure this script lives inside OPSreturn\demo\' -ForegroundColor Red
    exit -1
}

Import-Module $modulePath -Force

Write-Host '  [OK] Module imported successfully.' -ForegroundColor Green
Write-Host '  [OK] OPScode enum registered:' -ForegroundColor Green
Write-Host '       success(0)  info(1)  debug(2)  timeout(3)  warn(4)' -ForegroundColor Green
Write-Host '       fail(-1)  error(-2)  critical(-3)  fatal(-4)' -ForegroundColor Green
Write-Host '  [OK] Public functions: OPSsuccess, OPSinfo, OPSdebug, OPStimeout,' -ForegroundColor Green
Write-Host '       OPSwarn, OPSfail, OPSerror, OPScritical, OPSfatal' -ForegroundColor Green
Write-Host '  [OK] Config function:  SetCoreConfig' -ForegroundColor Green

WaitForEnter -Block


# ==============================================================================
# STEP 02 - SetCoreConfig
# ==============================================================================
Show-DemoStep -Step '02' -Title 'Module configuration: SetCoreConfig'

Write-Host '  SetCoreConfig adjusts module-level behaviour at runtime.' -ForegroundColor Gray
Write-Host '  Two settings are available:'                              -ForegroundColor Gray
Write-Host ''
Write-Host '    -timestamp [bool]  Populate timecode field. Default: $true'  -ForegroundColor DarkGray
Write-Host '    -verbosed  [bool]  Verbose output on module load. Default: $false' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Only parameters you explicitly pass are changed.'        -ForegroundColor Gray
Write-Host ''

Write-Host '  [Default] timestamp = $true (factory default)' -ForegroundColor Yellow
$r = OPSsuccess 'Default config active'
Write-Host ("  timecode : {0}" -f $r.timecode) -ForegroundColor White
Write-Host ''

SetCoreConfig -timestamp $false
Write-Host '  [Config] SetCoreConfig -timestamp $false' -ForegroundColor Yellow
$r = OPSsuccess 'Timestamp disabled'
Write-Host ("  timecode : {0}" -f $r.timecode) -ForegroundColor White
Write-Host ''

SetCoreConfig -timestamp $true
Write-Host '  [Config] SetCoreConfig -timestamp $true  (re-enabled for rest of demo)' -ForegroundColor Yellow
$r = OPSsuccess 'Timestamp re-enabled'
Write-Host ("  timecode : {0}" -f $r.timecode) -ForegroundColor White

WaitForEnter -Block


# ==============================================================================
# STEP 03 - Direct OPSreturn call
# ==============================================================================
Show-DemoStep -Step '03' -Title 'Direct core call: OPSreturn'

Write-Host '  OPSreturn is the private core used by all shorthand wrappers.' -ForegroundColor Gray
Write-Host '  Call it directly when you need any OPScode value explicitly.' -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:' -ForegroundColor Gray
Write-Host '    OPSreturn -Code [OPScode] -Message [string] -Data [object] -Exception [object]' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  OPScode enum values:' -ForegroundColor Gray
Write-Host '    success=0  info=1  debug=2  timeout=3  warn=4' -ForegroundColor DarkGray
Write-Host '    fail=-1  error=-2  critical=-3  fatal=-4'       -ForegroundColor DarkGray
Write-Host ''

$r = OPSreturn -Code ([OPScode]::success) -Message 'Direct core call - success' -Data @{ key = 'value'; count = 42 }
Show-OPSResult -Result $r -Label 'OPSreturn -Code success'

$r = OPSreturn -Code ([OPScode]::warn) -Message 'Direct core call - warn'
Show-OPSResult -Result $r -Label 'OPSreturn -Code warn'

WaitForEnter -Block


# ==============================================================================
# STEP 04 - OPSsuccess
# ==============================================================================
Show-DemoStep -Step '04' -Title 'OPSsuccess  (code 0)'

Write-Host '  Signals that an operation completed without any issues.' -ForegroundColor Gray
Write-Host '  Note: OPSsuccess has no -Exception parameter.'           -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:  OPSsuccess  -Message [string]  -Data [object]' -ForegroundColor DarkGray
Write-Host ''

$r = OPSsuccess 'Configuration file loaded successfully.'
Show-OPSResult -Result $r -Label 'OPSsuccess - message only'

$configData = [PSCustomObject]@{ path = 'C:\app\config.json'; entries = 12 }
$r = OPSsuccess 'Configuration parsed.' -Data $configData
Show-OPSResult -Result $r -Label 'OPSsuccess - with -Data payload'

WaitForEnter -Block


# ==============================================================================
# STEP 05 - OPSinfo
# ==============================================================================
Show-DemoStep -Step '05' -Title 'OPSinfo  (code 1)'

Write-Host '  Signals an informational result - no problem, just noteworthy.' -ForegroundColor Gray
Write-Host '  Like OPSsuccess, it has no -Exception parameter.'               -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:  OPSinfo  -Message [string]  -Data [object]' -ForegroundColor DarkGray
Write-Host ''

$r = OPSinfo 'Service is running in maintenance mode. No action required.'
Show-OPSResult -Result $r -Label 'OPSinfo - status message'

$r = OPSinfo 'Found 3 pending update(s).' -Data @('KB001', 'KB002', 'KB003')
Show-OPSResult -Result $r -Label 'OPSinfo - with array data'

WaitForEnter -Block


# ==============================================================================
# STEP 06 - OPSdebug
# ==============================================================================
Show-DemoStep -Step '06' -Title 'OPSdebug  (code 2)'

Write-Host '  Intended for diagnostic return values during development.' -ForegroundColor Gray
Write-Host '  Supports -Exception to carry detailed debug context.'      -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:  OPSdebug  -Message [string]  -Data [object]  -Exception [object]' -ForegroundColor DarkGray
Write-Host ''

$r = OPSdebug 'Entering function Invoke-DataSync. Parameter count: 3.'
Show-OPSResult -Result $r -Label 'OPSdebug - trace message'

$debugSnapshot = [PSCustomObject]@{ iteration = 7; variable = '$buffer'; value = 1024 }
$r = OPSdebug 'Loop checkpoint reached.' -Data $debugSnapshot
Show-OPSResult -Result $r -Label 'OPSdebug - with snapshot data'

WaitForEnter -Block


# ==============================================================================
# STEP 07 - OPStimeout
# ==============================================================================
Show-DemoStep -Step '07' -Title 'OPStimeout  (code 3)'

Write-Host '  Signals that an operation did not complete within the allowed time.' -ForegroundColor Gray
Write-Host '  Use -Exception to carry the original exception if one was thrown.'   -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:  OPStimeout  -Message [string]  -Data [object]  -Exception [object]' -ForegroundColor DarkGray
Write-Host ''

$r = OPStimeout 'Connection to remote host timed out after 30 seconds.'
Show-OPSResult -Result $r -Label 'OPStimeout - no exception'

try {
    throw [System.TimeoutException]::new('Simulated: socket read deadline exceeded.')
} catch {
    $r = OPStimeout 'Remote API did not respond in time.' -Exception $_.Exception
    Show-OPSResult -Result $r -Label 'OPStimeout - with TimeoutException'
}

WaitForEnter -Block


# ==============================================================================
# STEP 08 - OPSwarn
# ==============================================================================
Show-DemoStep -Step '08' -Title 'OPSwarn  (code 4)'

Write-Host '  Signals a warning: operation succeeded but something unexpected' -ForegroundColor Gray
Write-Host '  was encountered that the caller should know about.'               -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:  OPSwarn  -Message [string]  -Data [object]  -Exception [object]' -ForegroundColor DarkGray
Write-Host ''

$r = OPSwarn 'Disk usage has exceeded 85 percent. Consider cleanup.'
Show-OPSResult -Result $r -Label 'OPSwarn - threshold exceeded'

$r = OPSwarn 'Fallback config applied. Two keys were missing.' -Data @{ missing = @('timeout','retryCount') }
Show-OPSResult -Result $r -Label 'OPSwarn - fallback with data'

WaitForEnter -Block


# ==============================================================================
# STEP 09 - OPSfail
# ==============================================================================
Show-DemoStep -Step '09' -Title 'OPSfail  (code -1)'

Write-Host '  Signals a soft failure - the operation could not complete, but the' -ForegroundColor Gray
Write-Host '  cause is known and non-critical (e.g. missing input, validation).'  -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:  OPSfail  -Message [string]  -Data [object]  -Exception [object]' -ForegroundColor DarkGray
Write-Host ''

$r = OPSfail 'Required parameter -TargetPath was not provided.'
Show-OPSResult -Result $r -Label 'OPSfail - validation failure'

try {
    $null.ToString()
} catch {
    $r = OPSfail 'Operation failed due to a null reference.' -Exception $_.Exception
    Show-OPSResult -Result $r -Label 'OPSfail - with caught exception'
}

WaitForEnter -Block


# ==============================================================================
# STEP 10 - OPSerror
# ==============================================================================
Show-DemoStep -Step '10' -Title 'OPSerror  (code -2)'

Write-Host '  Signals a recoverable error that requires attention but does not' -ForegroundColor Gray
Write-Host '  necessarily stop the overall process.'                             -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:  OPSerror  -Message [string]  -Data [object]  -Exception [object]' -ForegroundColor DarkGray
Write-Host ''

$r = OPSerror 'HTTP request to api.example.com returned status 503.'
Show-OPSResult -Result $r -Label 'OPSerror - HTTP failure'

try {
    [System.IO.File]::ReadAllText('C:\this\path\does\not\exist.txt')
} catch {
    $r = OPSerror 'Failed to read configuration file from disk.' -Exception $_.Exception
    Show-OPSResult -Result $r -Label 'OPSerror - file read with exception'
}

WaitForEnter -Block


# ==============================================================================
# STEP 11 - OPScritical
# ==============================================================================
Show-DemoStep -Step '11' -Title 'OPScritical  (code -3)'

Write-Host '  Signals a critical error that severely impacts the operation.' -ForegroundColor Gray
Write-Host '  The system may still be running, but a key subsystem has failed.' -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:  OPScritical  -Message [string]  -Data [object]  -Exception [object]' -ForegroundColor DarkGray
Write-Host ''

$r = OPScritical 'Primary database cluster is unreachable. Failover initiated.'
Show-OPSResult -Result $r -Label 'OPScritical - cluster failure'

try {
    throw [System.UnauthorizedAccessException]::new('Simulated: access to system registry denied.')
} catch {
    $r = OPScritical 'Cannot access Windows registry hive. Run as administrator.' -Exception $_.Exception
    Show-OPSResult -Result $r -Label 'OPScritical - with UnauthorizedAccessException'
}

WaitForEnter -Block


# ==============================================================================
# STEP 12 - OPSfatal
# ==============================================================================
Show-DemoStep -Step '12' -Title 'OPSfatal  (code -4)'

Write-Host '  Signals an unrecoverable error. The operation must be aborted.'    -ForegroundColor Gray
Write-Host '  Reserve this for situations where continuing would cause data'      -ForegroundColor Gray
Write-Host '  corruption or system instability.'                                  -ForegroundColor Gray
Write-Host ''
Write-Host '  Signature:  OPSfatal  -Message [string]  -Data [object]  -Exception [object]' -ForegroundColor DarkGray
Write-Host ''

$r = OPSfatal 'Unrecoverable exception in core scheduler. Process will terminate.'
Show-OPSResult -Result $r -Label 'OPSfatal - process termination'

try {
    throw [System.OutOfMemoryException]::new('Simulated: heap allocation failed.')
} catch {
    $r = OPSfatal 'Memory allocation failed. Cannot continue execution.' -Exception $_.Exception
    Show-OPSResult -Result $r -Label 'OPSfatal - with OutOfMemoryException'
}

WaitForEnter -Block


# ==============================================================================
# STEP 13 - Return object field reference
# ==============================================================================
Show-DemoStep -Step '13' -Title 'Return object field reference'

Write-Host '  Every OPSreturn result always contains exactly these 7 fields.' -ForegroundColor Gray
Write-Host '  Here is a fully populated example for reference.' -ForegroundColor Gray
Write-Host ''

try {
    throw [System.IO.IOException]::new('Simulated I/O error for demonstration purposes.')
} catch {
    $demoException = $_.Exception
}

$demoData = [PSCustomObject]@{ server = 'srv-prod-01'; port = 8443; attempts = 3 }

$r = OPSerror 'Connection to remote server failed after 3 attempts.' `
              -Data      $demoData `
              -Exception $demoException

Write-Host '  Field        Type             Description' -ForegroundColor Cyan
Write-Host '  ------------ ---------------- -----------------------------------------------' -ForegroundColor DarkGray
Write-Host ("  {0,-12} {1,-16} -> {2}" -f 'code',      '[int]',         "$($r.code)  (negative=problem, 0+=ok)")        -ForegroundColor White
Write-Host ("  {0,-12} {1,-16} -> {2}" -f 'state',     '[string]',      "'$($r.state)'  (enum name as string)")          -ForegroundColor White
Write-Host ("  {0,-12} {1,-16} -> {2}" -f 'msg',       '[string]',      "'$($r.msg)'")                                   -ForegroundColor White
Write-Host ("  {0,-12} {1,-16} -> {2}" -f 'data',      '[object/null]', 'PSCustomObject { server, port, attempts }')     -ForegroundColor White
Write-Host ("  {0,-12} {1,-16} -> {2}" -f 'exception', '[object/null]', $r.exception.GetType().Name)                    -ForegroundColor White
Write-Host ("  {0,-12} {1,-16} -> {2}" -f 'source',    '[string]',      "'$($r.source)'  (auto via call stack)")         -ForegroundColor White
Write-Host ("  {0,-12} {1,-16} -> {2}" -f 'timecode',  '[string]',      "'$($r.timecode)'")                              -ForegroundColor White
Write-Host ''

WaitForEnter -Block


# ==============================================================================
# STEP 14 - Caller source tracking inside real functions
# ==============================================================================
Show-DemoStep -Step '14' -Title 'Caller source tracking inside real functions'

Write-Host '  OPSreturn automatically resolves the calling function name via' -ForegroundColor Gray
Write-Host '  Get-PSCallStack. The .source field is always populated without' -ForegroundColor Gray
Write-Host '  any manual input from you.' -ForegroundColor Gray
Write-Host ''

function Read-AppConfig {
    [CmdletBinding()]
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return OPSfail "Config file not found: $Path"
    }
    return OPSsuccess 'Config loaded.' -Data (Get-Content $Path -Raw)
}

function Connect-RemoteEndpoint {
    [CmdletBinding()]
    param([string]$Hostname, [int]$Port)
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $tcp.Connect($Hostname, $Port)
        $tcp.Close()
        return OPSsuccess "Connected to ${Hostname}:${Port} successfully."
    } catch {
        return OPSerror "Cannot reach ${Hostname}:${Port}" -Exception $_.Exception
    }
}

function Assert-PositiveValue {
    [CmdletBinding()]
    param([int]$Value)
    if ($Value -lt 0) { return OPSwarn "Value $Value is negative. Expected 0 or higher." }
    return OPSsuccess "Value $Value is valid."
}

Write-Host '  Calling Read-AppConfig with a non-existent path:' -ForegroundColor Cyan
$r = Read-AppConfig -Path 'C:\does\not\exist\app.config'
Write-Host ("  .source = '{0}'   .state = '{1}'   .msg = '{2}'" -f $r.source, $r.state, $r.msg) -ForegroundColor White
Write-Host ''

Write-Host '  Calling Connect-RemoteEndpoint with an unreachable host:' -ForegroundColor Cyan
$r = Connect-RemoteEndpoint -Hostname '192.0.2.1' -Port 9999
Write-Host ("  .source = '{0}'   .state = '{1}'" -f $r.source, $r.state) -ForegroundColor White
Write-Host ''

Write-Host '  Calling Assert-PositiveValue with -5:' -ForegroundColor Cyan
$r = Assert-PositiveValue -Value -5
Write-Host ("  .source = '{0}'   .state = '{1}'   .msg = '{2}'" -f $r.source, $r.state, $r.msg) -ForegroundColor White
Write-Host ''

Write-Host '  Calling Assert-PositiveValue with 100:' -ForegroundColor Cyan
$r = Assert-PositiveValue -Value 100
Write-Host ("  .source = '{0}'   .state = '{1}'   .msg = '{2}'" -f $r.source, $r.state, $r.msg) -ForegroundColor White

WaitForEnter -Block


# ==============================================================================
# STEP 15 - Checking .code in control flow
# ==============================================================================
Show-DemoStep -Step '15' -Title 'Checking .code in control flow'

Write-Host '  The .code field is the primary way to branch on a result.' -ForegroundColor Gray
Write-Host '  Positive values (>= 0) indicate ok/info states.' -ForegroundColor Gray
Write-Host '  Negative values (< 0) indicate failure states.' -ForegroundColor Gray
Write-Host ''
Write-Host '  Recommended generic pattern:' -ForegroundColor Gray
Write-Host '    if ($r.code -ge 0) { ... ok path ...   }' -ForegroundColor DarkGray
Write-Host '    else               { ... fail path ... }' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Strict equality pattern:' -ForegroundColor Gray
Write-Host '    if ($r.code -eq [int][OPScode]::success) { ... }' -ForegroundColor DarkGray
Write-Host ''

Write-Host '  Pattern 1: generic ok / fail split across 5 operations' -ForegroundColor Cyan
Write-Host ''

$operations = @(
    @{ label = 'Load config';      result = (OPSsuccess 'Config loaded.')                         },
    @{ label = 'Check free space'; result = (OPSwarn    'Low disk space on C:\')                  },
    @{ label = 'Read remote data'; result = (OPSfail    'Remote host refused connection.')         },
    @{ label = 'Write audit log';  result = (OPSsuccess 'Audit entry written.')                    },
    @{ label = 'Flush cache';      result = (OPSerror   'Cache flush failed. Buffer locked.')      }
)

foreach ($op in $operations) {
    $r = $op.result
    if ($r.code -ge 0) {
        Write-Host ("  [OK  ] {0,-20} state={1,-8}  {2}" -f $op.label, $r.state, $r.msg) -ForegroundColor Green
    } else {
        Write-Host ("  [FAIL] {0,-20} state={1,-8}  {2}" -f $op.label, $r.state, $r.msg) -ForegroundColor Red
    }
}
Write-Host ''

Write-Host '  Pattern 2: strict equality on .code' -ForegroundColor Cyan
Write-Host ''

$r = OPSsuccess 'All prerequisites met.'
if ($r.code -eq [int][OPScode]::success) {
    Write-Host '  Strict check passed: .code is exactly 0 (success).' -ForegroundColor Green
}

$r = OPScritical 'Subsystem X is offline.'
if ($r.code -eq [int][OPScode]::critical) {
    Write-Host '  Strict check passed: .code is exactly -3 (critical).' -ForegroundColor Red
}

WaitForEnter -Block


# ==============================================================================
# STEP 16 - OPScode enum complete reference
# ==============================================================================
Show-DemoStep -Step '16' -Title 'OPScode enum - complete reference'

Write-Host '  All valid OPScode values, their codes, category, and intended use.' -ForegroundColor Gray
Write-Host ''
Write-Host '  --------------------------------------------------------------------------' -ForegroundColor DarkGray
Write-Host ('  {0,-10} {1,6}   {2,-12} {3}' -f 'Name', 'Code', 'Category', 'Intended use') -ForegroundColor Cyan
Write-Host '  --------------------------------------------------------------------------' -ForegroundColor DarkGray

$enumTable = @(
    @{ name='success';  code= 0; cat='Positive'; use='Operation completed successfully.'          },
    @{ name='info';     code= 1; cat='Positive'; use='Informational result, no issues.'           },
    @{ name='debug';    code= 2; cat='Positive'; use='Diagnostic data for development.'           },
    @{ name='timeout';  code= 3; cat='Positive'; use='Operation did not finish in time.'          },
    @{ name='warn';     code= 4; cat='Positive'; use='Success with noteworthy condition.'         },
    @{ name='fail';     code=-1; cat='Negative'; use='Soft failure, known/expected cause.'        },
    @{ name='error';    code=-2; cat='Negative'; use='Recoverable error, needs attention.'        },
    @{ name='critical'; code=-3; cat='Negative'; use='Severe failure, key subsystem impacted.'   },
    @{ name='fatal';    code=-4; cat='Negative'; use='Unrecoverable, must abort.'                 }
)

foreach ($entry in $enumTable) {
    $color = if ($entry.code -ge 0) { 'Green' } else { 'Red' }
    Write-Host ('  {0,-10} {1,6}   {2,-12} {3}' -f $entry.name, $entry.code, $entry.cat, $entry.use) -ForegroundColor $color
}

Write-Host '  --------------------------------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Note: timeout(3) and warn(4) have positive codes but signal degraded'  -ForegroundColor DarkGray
Write-Host '  conditions. Use .state for precise level checks when needed.'           -ForegroundColor DarkGray

WaitForEnter -Block


# ==============================================================================
# DONE
# ==============================================================================
Write-Host ''
Write-Host ('=' * 70) -ForegroundColor DarkGreen
Write-Host '  OPSreturn sample.ps1 completed successfully.' -ForegroundColor Green
Write-Host '  All 16 steps walked through. Enjoy using OPSreturn!' -ForegroundColor Green
Write-Host ('=' * 70) -ForegroundColor DarkGreen
Write-Host ''