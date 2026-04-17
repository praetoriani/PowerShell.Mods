
# ____________________________________________________________________________________________________
#  → ENUMERATION CLASS
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
enum OPScode {
    success     = 0
    info        = 1
    debug       = 2
    timeout     = 3
    warn        = 4
    fail        = -1
    error       = -2
    critical    = -3
    fatal       = -4
}

function OPSreturn {

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # PARAM: Code → Must be one of the OPScode-Enums. Defaults to -1 (fail)
        [Parameter(Mandatory = $false)]
        [ValidateScript({
            $validCodes = [System.Enum]::GetValues([OPScode]) | ForEach-Object { [int]$_ }
            if ($_ -in $validCodes) { return $true }
            throw "OPSreturn: Invalid status code '$_'. Valid values: $($validCodes -join ', ')"
        })]
        [OPScode]$Code = [OPScode]::fail,
        
        # PARAM: Message → A short Message you want to pass to the caller
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",

        # PARAM: Data → Can be used to pass data to the caller
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Data = $null,

        # PARAM: Exception → Use it to pass a more detailed message to the caller
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Exception = $null
    )

    # Auto-resolve the name of the calling function via the PowerShell call stack.
    # Index [0] = OPSreturn itself, Index [1] = direct caller.
    # Falls back to '<unknown>' if the call stack is unexpectedly shallow.
    [string]$callerSrc = try {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 2) { $callStack[2].Command }
        elseif ($callStack.Count -gt 1) { $callStack[1].Command }
        else { '<unknown>' }
    }
    catch {
        '<unknown>'
    }

    # Create and return standardized status object
    return [PSCustomObject]@{
        code        = [int]$Code
        state       = $Code.ToString()
        msg         = $Message
        data        = $Data
        exception   = $Exception
        source      = $callerSrc
        timecode    = if ( $script:conf['timestamp'] -eq $true ) { (Get-Date).ToString('dd.MM.yyyy ; HH:mm:ss.fff') } else { '<notused>' }
        #timecode    = if ( $script:conf['timestamp'] -eq $true ) { (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff') + ' UTC' }
    }
}





[string]$callerSrc = try {
    $callStack = Get-PSCallStack
    if ($callStack.Count -gt 2)      { $callStack[2].Command }
    elseif ($callStack.Count -gt 1)  { $callStack[1].Command }
    else                              { '<unknown>' }
} catch { '<unknown>' }