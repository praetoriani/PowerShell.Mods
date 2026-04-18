<#
.SYNOPSIS
    sample.ps1 - Interactive step-by-step demonstration of the OPSreturn module

.DESCRIPTION
    This script demonstrates the OPSreturn module step by step.
    It covers:
      - Importing the module via a relative path using $PSScriptRoot
      - The structure of a standardized OPSreturn result object
      - All public wrapper functions:
            OPSsuccess, OPSinfo, OPSdebug, OPStimeout, OPSwarn,
            OPSfail, OPSerror, OPScritical, OPSfatal
      - Module configuration via SetCoreConfig
      - Realistic example functions using Try/Catch with OPSreturn objects
      - Evaluating OPSreturn result objects on the caller side

    Every OPSreturn function returns a standardized PSCustomObject with:
        code, state, msg, data, exception, source, timecode

.NOTES
    Module  : OPSreturn
    Version : 1.00.00
    Demo    : sample.ps1
    Style   : inspired by VPDLX/Examples/Demo-001.ps1

    Usage:
        .\OPSreturn\sample.ps1
        & 'C:\full\path\to\OPSreturn\sample.ps1'
#>

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Show-DemoStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Step,

        [Parameter(Mandatory = $true)]
        [string] $Title
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
        [string] $Message = 'Press <Enter> to continue ...',

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

function Show-OPSObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Object,

        [Parameter(Mandatory = $false)]
        [string] $Label = 'Result'
    )

    Write-Host "  $Label" -ForegroundColor Yellow
    Write-Host "  $('-' * $Label.Length)" -ForegroundColor DarkYellow
    $Object | Format-List
    Write-Host ''
}

function Show-OPSShort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Object
    )

    $color = if ($Object.code -eq 0) { 'Green' }
             elseif ($Object.code -gt 0) { 'Yellow' }
             else { 'Red' }

    Write-Host "  code      : $($Object.code)"      -ForegroundColor $color
    Write-Host "  state     : $($Object.state)"     -ForegroundColor $color
    Write-Host "  msg       : $($Object.msg)"       -ForegroundColor Gray
    if ($Object.exception) {
        Write-Host "  exception : $($Object.exception)" -ForegroundColor DarkRed
    }
    if ($Object.data) {
        Write-Host "  data      : $($Object.data | Out-String -Width 60)" -ForegroundColor DarkGray
    }
    Write-Host "  source    : $($Object.source)"   -ForegroundColor DarkGray
    Write-Host "  timecode  : $($Object.timecode)" -ForegroundColor DarkGray
    Write-Host ''
}

# ==============================================================================
# EXAMPLE BUSINESS FUNCTIONS
# ==============================================================================

function Get-DemoConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch] $SimulateFailure
    )

    try {
        if ($SimulateFailure) {
            throw [System.IO.FileNotFoundException]::new('Configuration file demo-config.json was not found.')
        }

        $config = [PSCustomObject]@{
            AppName     = 'OPSreturn Demo'
            Environment = 'Development'
            RetryCount  = 3
            Features    = @('Logging', 'Validation', 'ReturnObjects')
        }

        return OPSsuccess 'Configuration loaded successfully.' -Data $config
    }
    catch {
        return OPSerror 'Failed to load configuration.' -Exception $_.Exception.Message
    }
}

function Test-DemoConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ComputerName
    )

    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        return OPSfail 'ComputerName must not be empty.'
    }

    if ($ComputerName -eq 'offline-server') {
        return OPStimeout "Connection to '$ComputerName' timed out." -Exception 'No response within 5000 ms.'
    }

    return OPSsuccess "Connection to '$ComputerName' successful." -Data @{
        ComputerName = $ComputerName
        Reachable    = $true
        LatencyMs    = 12
    }
}

function Invoke-DemoDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Info','Debug','Warn','Fail','Critical','Fatal')]
        [string] $Mode
    )

    switch ($Mode) {
        'Info' {
            return OPSinfo 'Deployment finished with additional informational notes.' -Data @{
                Stage = 'PostChecks'
                Hint  = 'A reboot may improve service startup times.'
            }
        }
        'Debug' {
            return OPSdebug 'Debug details collected for deployment analysis.' -Data @{
                TraceId = [guid]::NewGuid().Guid
                Step    = 'InstallFeatureX'
            }
        }
        'Warn' {
            return OPSwarn 'Deployment succeeded, but a non-critical issue occurred.' -Exception 'Service restart took longer than expected.' -Data @{
                RestartDurationSec = 18
            }
        }
        'Fail' {
            return OPSfail 'Deployment could not be completed.' -Exception 'Validation step failed.' -Data @{
                FailedStep = 'Validate-Package'
            }
        }
        'Critical' {
            return OPScritical 'Critical deployment issue detected.' -Exception 'Primary dependency missing.' -Data @{
                Dependency = 'VC++ Runtime'
            }
        }
        'Fatal' {
            return OPSfatal 'Fatal deployment error. Manual intervention required.' -Exception 'Rollback was not possible.' -Data @{
                Server = $env:COMPUTERNAME
            }
        }
    }
}

function Read-DemoFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return OPSfail 'Path parameter must not be empty.'
    }

    if (-not (Test-Path $Path)) {
        return OPSfail 'The specified file path does not exist.' -Data @{ Path = $Path }
    }

    try {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        return OPSsuccess 'File read successfully.' -Data $content
    }
    catch {
        return OPSerror 'Unable to read file.' -Exception $_.Exception.Message -Data @{ Path = $Path }
    }
}

# ==============================================================================
# DEMO START - Welcome screen
# ==============================================================================
Clear-Host

$welcomeText = @"
========================================================================
  OPSreturn - Standardized Operation Return Objects
  Interactive Demo
========================================================================

  Welcome! This script walks you through the key features of the
  OPSreturn module step by step.

  OPSreturn provides a consistent PSCustomObject for returning
  operation status information across all module functions.

  Every return object contains:
    code        numeric status code
    state       name of the status
    msg         short descriptive message
    data        optional payload object
    exception   optional exception details
    source      name of the calling function
    timecode    timestamp (if enabled via SetCoreConfig)

  At the end of each section you will be prompted to press <Enter>
  before the next section begins.

========================================================================
"@

Write-Host $welcomeText -ForegroundColor DarkGray
WaitForEnter -Message 'Press <Enter> to start the demonstration ...' -Color DarkGray -Block


# ==============================================================================
# STEP 01 - Import the module
# ==============================================================================
Show-DemoStep -Step '01' -Title 'Import the OPSreturn module'

Write-Host '  The module is imported using Import-Module and the path resolved via' -ForegroundColor Gray
Write-Host '  $PSScriptRoot, so this demo works from any working directory.' -ForegroundColor Gray
Write-Host ''
Write-Host '  Script location : OPSreturn\sample.ps1' -ForegroundColor DarkGray
Write-Host '  Module manifest : OPSreturn\OPSreturn.psd1 (same folder)' -ForegroundColor DarkGray
Write-Host ''

$modulePath = Join-Path $PSScriptRoot '..\OPSreturn.psd1'

if (-not (Test-Path $modulePath)) {
    Write-Host "  [ERROR] Module manifest not found at: $modulePath" -ForegroundColor Red
    Write-Host '  Please make sure sample.ps1 is located inside the OPSreturn folder.' -ForegroundColor Red
    exit -1
}

Import-Module $modulePath -Force -Verbose:$false

Write-Host '  [OK] Module imported successfully.' -ForegroundColor Green
Write-Host '  [OK] Public wrapper functions are now available in the current session.' -ForegroundColor Green
Write-Host ''
Write-Host '  Available public functions:' -ForegroundColor Cyan
Write-Host '  OPSsuccess, OPSinfo, OPSdebug, OPStimeout, OPSwarn,' -ForegroundColor White
Write-Host '  OPSfail, OPSerror, OPScritical, OPSfatal, SetCoreConfig' -ForegroundColor White

WaitForEnter -Block


# ==============================================================================
# STEP 02 - Basic result object structure
# ==============================================================================
Show-DemoStep -Step '02' -Title 'Basic structure of an OPSreturn result object'

Write-Host '  Every public wrapper function returns a standardized PSCustomObject.' -ForegroundColor Gray
Write-Host '  Here we call OPSsuccess and inspect the full result object.' -ForegroundColor Gray
Write-Host ''

$result = OPSsuccess 'Everything is fine.' -Data @{
    DemoValue = 123
    Active    = $true
}

Show-OPSObject -Object $result -Label 'OPSsuccess result object'

Write-Host '  Property overview:' -ForegroundColor Cyan
Write-Host '  code      → numeric status code (0 = success, negative = error)' -ForegroundColor White
Write-Host '  state     → human-readable name of the status enum value' -ForegroundColor White
Write-Host '  msg       → short message passed by the caller' -ForegroundColor White
Write-Host '  data      → optional payload (any type: hashtable, object, string, ...)' -ForegroundColor White
Write-Host '  exception → optional exception details for error states' -ForegroundColor White
Write-Host '  source    → auto-resolved name of the calling function' -ForegroundColor White
Write-Host '  timecode  → timestamp (controlled by SetCoreConfig -timestamp)' -ForegroundColor White

WaitForEnter -Block


# ==============================================================================
# STEP 03 - OPScode enum and status codes
# ==============================================================================
Show-DemoStep -Step '03' -Title 'Status codes: the OPScode enum'

Write-Host '  OPSreturn uses the internal enum OPScode to define all valid status codes.' -ForegroundColor Gray
Write-Host '  Positive/zero values indicate success or informational states.' -ForegroundColor Gray
Write-Host '  Negative values indicate error states.' -ForegroundColor Gray
Write-Host ''

$statusTable = @(
    [PSCustomObject]@{ Code =  0; State = 'success';  Description = 'Operation completed successfully' }
    [PSCustomObject]@{ Code =  1; State = 'info';     Description = 'Informational message' }
    [PSCustomObject]@{ Code =  2; State = 'debug';    Description = 'Debug / diagnostic information' }
    [PSCustomObject]@{ Code =  3; State = 'timeout';  Description = 'Operation timed out' }
    [PSCustomObject]@{ Code =  4; State = 'warn';     Description = 'Warning - not necessarily an error' }
    [PSCustomObject]@{ Code = -1; State = 'fail';     Description = 'Operation failed' }
    [PSCustomObject]@{ Code = -2; State = 'error';    Description = 'An error occurred' }
    [PSCustomObject]@{ Code = -3; State = 'critical'; Description = 'Critical error' }
    [PSCustomObject]@{ Code = -4; State = 'fatal';    Description = 'Fatal error - unrecoverable' }
)

$statusTable | Format-Table -AutoSize

WaitForEnter -Block


# ==============================================================================
# STEP 04 - All public wrapper functions
# ==============================================================================
Show-DemoStep -Step '04' -Title 'All public wrapper functions at a glance'

Write-Host '  Each public wrapper is a thin convenience layer over the internal OPSreturn function.' -ForegroundColor Gray
Write-Host '  The status code is fixed per wrapper; the caller only provides msg, data, and/or exception.' -ForegroundColor Gray
Write-Host ''

$allWrapperResults = @(
    OPSsuccess  'Task completed without issues.'            -Data @{ Id = 1001 }
    OPSinfo     'Service restarted; note the new port.'     -Data @{ Port = 8443 }
    OPSdebug    'Trace checkpoint reached at line 42.'      -Data @{ TraceId = 'A1-B2-C3' }
    OPStimeout  'The remote call did not respond in time.'  -Exception 'Exceeded 30 s threshold.'
    OPSwarn     'Retry limit almost reached (2 of 3).'      -Exception 'Slow response from upstream.'
    OPSfail     'Could not locate the requested resource.'  -Exception 'Item not found in storage.'
    OPSerror    'Unhandled exception in worker thread.'     -Exception 'NullReferenceException.'
    OPScritical 'Required subsystem is unavailable.'        -Exception 'Dependency check failed.'
    OPSfatal    'Application state is unrecoverable.'       -Exception 'Rollback also failed.'
)

foreach ($item in $allWrapperResults) {
    Show-OPSShort -Object $item
}

WaitForEnter -Block


# ==============================================================================
# STEP 05 - SetCoreConfig
# ==============================================================================
Show-DemoStep -Step '05' -Title 'Module configuration via SetCoreConfig'

Write-Host '  SetCoreConfig allows you to change module-level behaviour at runtime.' -ForegroundColor Gray
Write-Host '  Currently supported settings:' -ForegroundColor Gray
Write-Host '    -timestamp  [bool]  controls whether timecode is populated' -ForegroundColor White
Write-Host '    -verbosed   [bool]  controls verbose output within the module' -ForegroundColor White
Write-Host ''

Write-Host '  [1] Timestamp enabled (default):' -ForegroundColor Cyan
SetCoreConfig -timestamp $true
$r1 = OPSinfo 'Timestamp is currently enabled.'
Write-Host "  timecode → $($r1.timecode)" -ForegroundColor White
Write-Host ''

Write-Host '  [2] Timestamp disabled:' -ForegroundColor Cyan
SetCoreConfig -timestamp $false
$r2 = OPSinfo 'Timestamp has been disabled.'
Write-Host "  timecode → $($r2.timecode)" -ForegroundColor White
Write-Host ''

Write-Host '  [3] Timestamp re-enabled:' -ForegroundColor Cyan
SetCoreConfig -timestamp $true
$r3 = OPSinfo 'Timestamp is active again.'
Write-Host "  timecode → $($r3.timecode)" -ForegroundColor White

WaitForEnter -Block


# ==============================================================================
# STEP 06 - Realistic success scenario
# ==============================================================================
Show-DemoStep -Step '06' -Title 'Realistic example: successful configuration load'

Write-Host '  Get-DemoConfiguration returns OPSsuccess on success, OPSerror on failure.' -ForegroundColor Gray
Write-Host '  The result object is then evaluated on the caller side by checking .code.' -ForegroundColor Gray
Write-Host ''

$configResult = Get-DemoConfiguration

if ($configResult.code -eq 0) {
    Write-Host '  [OK] Configuration loaded successfully.' -ForegroundColor Green
    Write-Host "  AppName      : $($configResult.data.AppName)"            -ForegroundColor White
    Write-Host "  Environment  : $($configResult.data.Environment)"        -ForegroundColor White
    Write-Host "  RetryCount   : $($configResult.data.RetryCount)"         -ForegroundColor White
    Write-Host "  Features     : $($configResult.data.Features -join ', ')" -ForegroundColor White
} else {
    Write-Host "  [FAILED] $($configResult.msg)" -ForegroundColor Red
}

Write-Host ''
Show-OPSShort -Object $configResult

WaitForEnter -Block


# ==============================================================================
# STEP 07 - Realistic error scenario
# ==============================================================================
Show-DemoStep -Step '07' -Title 'Realistic example: error path with Try/Catch'

Write-Host '  The same function is now called with -SimulateFailure.' -ForegroundColor Gray
Write-Host '  The exception is caught internally; a standardized OPSerror object is returned.' -ForegroundColor Gray
Write-Host '  The caller never deals with raw exceptions - only with structured result objects.' -ForegroundColor Gray
Write-Host ''

$configErrorResult = Get-DemoConfiguration -SimulateFailure
Show-OPSObject -Object $configErrorResult -Label 'Get-DemoConfiguration -SimulateFailure'

WaitForEnter -Block


# ==============================================================================
# STEP 08 - Timeout scenario
# ==============================================================================
Show-DemoStep -Step '08' -Title 'Realistic example: connection with timeout'

Write-Host '  Not every negative outcome is a classic exception.' -ForegroundColor Gray
Write-Host '  Timeouts are a good example for a well-defined non-success state.' -ForegroundColor Gray
Write-Host ''

$conn1 = Test-DemoConnection -ComputerName 'srv-app-01'
Write-Host '  Test-DemoConnection -ComputerName srv-app-01' -ForegroundColor Cyan
Show-OPSShort -Object $conn1

$conn2 = Test-DemoConnection -ComputerName 'offline-server'
Write-Host '  Test-DemoConnection -ComputerName offline-server' -ForegroundColor Cyan
Show-OPSShort -Object $conn2

WaitForEnter -Block


# ==============================================================================
# STEP 09 - Evaluating results on the caller side
# ==============================================================================
Show-DemoStep -Step '09' -Title 'Evaluating result objects on the caller side'

Write-Host '  The key benefit of OPSreturn is consistent evaluation.' -ForegroundColor Gray
Write-Host '  A single switch/if on .code or .state handles all cases uniformly.' -ForegroundColor Gray
Write-Host ''

$evaluationSamples = @(
    OPSsuccess  'Pipeline stage completed.'
    OPSinfo     'Non-critical note attached.'
    OPSwarn     'Threshold almost reached.'
    OPSfail     'Stage could not be executed.'
    OPScritical 'Unrecoverable condition detected.'
)

foreach ($item in $evaluationSamples) {
    switch ($item.code) {
        0           { Write-Host "  [SUCCESS]  ($($item.state.PadRight(8)))  $($item.msg)" -ForegroundColor Green }
        { $_ -gt 0 }{ Write-Host "  [NOTICE ]  ($($item.state.PadRight(8)))  $($item.msg)" -ForegroundColor Yellow }
        default     { Write-Host "  [ERROR  ]  ($($item.state.PadRight(8)))  $($item.msg)" -ForegroundColor Red }
    }
}

WaitForEnter -Block


# ==============================================================================
# STEP 10 - All error/status states from one business function
# ==============================================================================
Show-DemoStep -Step '10' -Title 'All states produced by a single business function'

Write-Host '  Invoke-DemoDeployment returns a different OPSreturn state for each scenario.' -ForegroundColor Gray
Write-Host '  This shows how one function can cover all relevant status paths cleanly.' -ForegroundColor Gray
Write-Host ''

foreach ($mode in @('Info','Debug','Warn','Fail','Critical','Fatal')) {
    Write-Host "  Mode: $mode" -ForegroundColor Cyan
    $r = Invoke-DemoDeployment -Mode $mode
    Show-OPSShort -Object $r
}

WaitForEnter -Block


# ==============================================================================
# STEP 11 - Automatic caller resolution (source field)
# ==============================================================================
Show-DemoStep -Step '11' -Title 'Automatic caller resolution via source field'

Write-Host '  OPSreturn resolves the calling function automatically via Get-PSCallStack.' -ForegroundColor Gray
Write-Host '  The source field tells you exactly where the status was generated.' -ForegroundColor Gray
Write-Host ''

$rDirect = OPSsuccess 'Called directly from sample.ps1'
Write-Host '  Direct call from script scope:' -ForegroundColor Cyan
Write-Host "  source → $($rDirect.source)" -ForegroundColor White
Write-Host ''

$rFromFunc = Get-DemoConfiguration
Write-Host '  Called from inside Get-DemoConfiguration:' -ForegroundColor Cyan
Write-Host "  source → $($rFromFunc.source)" -ForegroundColor White
Write-Host ''

$rFromConn = Test-DemoConnection -ComputerName 'srv-web-02'
Write-Host '  Called from inside Test-DemoConnection:' -ForegroundColor Cyan
Write-Host "  source → $($rFromConn.source)" -ForegroundColor White

WaitForEnter -Block


# ==============================================================================
# STEP 12 - Passing data payloads
# ==============================================================================
Show-DemoStep -Step '12' -Title 'Passing structured data via the data field'

Write-Host '  The -Data parameter accepts any type: hashtable, PSCustomObject, array, string.' -ForegroundColor Gray
Write-Host '  This allows rich, structured results to flow back to the caller.' -ForegroundColor Gray
Write-Host ''

# Hashtable payload
$r1 = OPSsuccess 'Hashtable payload example.' -Data @{
    Server   = 'SRV-DB-01'
    Database = 'Production'
    Records  = 4823
}
Write-Host '  Hashtable payload:' -ForegroundColor Cyan
$r1.data | Format-List
Write-Host ''

# Array payload
$r2 = OPSsuccess 'Array payload example.' -Data @(
    'Feature A enabled'
    'Feature B enabled'
    'Feature C disabled'
)
Write-Host '  Array payload:' -ForegroundColor Cyan
$r2.data | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
Write-Host ''

# PSCustomObject payload
$r3 = OPSsuccess 'PSCustomObject payload example.' -Data ([PSCustomObject]@{
    Version   = '2.1.4'
    BuildDate = '2026-04-17'
    Stable    = $true
})
Write-Host '  PSCustomObject payload:' -ForegroundColor Cyan
$r3.data | Format-List

WaitForEnter -Block


# ==============================================================================
# STEP 13 - Recommended usage pattern
# ==============================================================================
Show-DemoStep -Step '13' -Title 'Recommended usage pattern for your own functions'

Write-Host '  A clean pattern for any module or script function:' -ForegroundColor Gray
Write-Host ''
Write-Host '  1. Validate inputs  → return OPSfail for invalid arguments' -ForegroundColor White
Write-Host '  2. Try/Catch block  → catch real exceptions and return OPSerror / OPScritical' -ForegroundColor White
Write-Host '  3. Return success   → return OPSsuccess with optional data payload' -ForegroundColor White
Write-Host '  4. Caller evaluates → check .code or .state for branching logic' -ForegroundColor White
Write-Host ''

$patternDemo = @"
  function Invoke-MyOperation {
      [CmdletBinding()]
      param(
          [Parameter(Mandatory = `$true)]
          [string] `$Path
      )

      # Step 1: input validation
      if (-not (Test-Path `$Path)) {
          return OPSfail 'The specified path does not exist.' -Data @{ Path = `$Path }
      }

      # Step 2: operational logic with exception handling
      try {
          `$content = Get-Content -Path `$Path -Raw -ErrorAction Stop
          return OPSsuccess 'File read successfully.' -Data `$content
      }
      catch {
          return OPSerror 'Unable to read file.' -Exception `$_.Exception.Message
      }
  }

  # Step 4: evaluate on caller side
  `$result = Invoke-MyOperation -Path 'C:\config\app.json'

  if (`$result.code -eq 0) {
      Write-Host `$result.data
  }
  else {
      Write-Warning `$result.msg
  }
"@

Write-Host $patternDemo -ForegroundColor DarkGray

WaitForEnter -Block


# ==============================================================================
# STEP 14 - Read-DemoFile: a complete example end-to-end
# ==============================================================================
Show-DemoStep -Step '14' -Title 'End-to-end example: Read-DemoFile'

Write-Host '  Read-DemoFile demonstrates the full pattern: validation, try/catch, and return.' -ForegroundColor Gray
Write-Host ''

# Case 1: empty path
Write-Host '  [14a] Empty path → OPSfail' -ForegroundColor Cyan
$r = Read-DemoFile -Path ''
Show-OPSShort -Object $r

# Case 2: non-existent file
Write-Host '  [14b] File does not exist → OPSfail' -ForegroundColor Cyan
$r = Read-DemoFile -Path 'C:\does\not\exist\file.txt'
Show-OPSShort -Object $r

# Case 3: read the module manifest as a valid existing file
Write-Host '  [14c] Valid existing file (OPSreturn.psd1) → OPSsuccess' -ForegroundColor Cyan
$r = Read-DemoFile -Path (Join-Path $PSScriptRoot 'OPSreturn.psd1')
if ($r.code -eq 0) {
    Write-Host "  [OK] File read successfully. Content length: $($r.data.Length) characters." -ForegroundColor Green
    Write-Host "  source   : $($r.source)"   -ForegroundColor DarkGray
    Write-Host "  timecode : $($r.timecode)" -ForegroundColor DarkGray
} else {
    Write-Host "  [FAILED] $($r.msg)" -ForegroundColor Red
}

WaitForEnter -Block


# ==============================================================================
# DONE
# ==============================================================================
Write-Host ''
Write-Host ('=' * 70) -ForegroundColor DarkGreen
Write-Host '  OPSreturn sample.ps1 completed successfully.' -ForegroundColor Green
Write-Host '  All demonstration steps have been executed.' -ForegroundColor Green
Write-Host '  Thank you for exploring OPSreturn!' -ForegroundColor Green
Write-Host ('=' * 70) -ForegroundColor DarkGreen
Write-Host ''
