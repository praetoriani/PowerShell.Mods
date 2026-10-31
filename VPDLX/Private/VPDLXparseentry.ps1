<#
.SYNOPSIS
    VPDLXparseentry - Private helper: splits one formatted log line into its parts.

.DESCRIPTION
    Central parser for the VPDLX log line format
        [dd.MM.yyyy | HH:mm:ss]  [LEVEL]      ->  Message text
    It replaces the parsing code that was previously duplicated five times in
    VPDLXexportlogfile and is shared by the export and the attach logic.

    Parsing rules (identical to the previous export behaviour):
      1. Split on '  ->  ' (max. 2 parts) so arrows inside the message survive.
      2. Left part: strip the leading '[' and split on ']  [' into timestamp and level.
      3. Unparseable line  -> Timestamp '', Level 'RAW',     Message = whole line.
         Level not found   -> Timestamp = left part, Level 'UNKNOWN'.

.PARAMETER Line
    One formatted log line.

.OUTPUTS
    [PSCustomObject] with the string properties Timestamp, Level and Message.

.NOTES
    Module  : VPDLX - Virtual PowerShell Data-Logger eXtension
    Version : 1.02.07
    Author  : Praetoriani (a.k.a. M.Sczepanski)
    Created : 30.10.2026
    Scope   : Private - dot-sourced by VPDLX.psm1, not exported
#>

function VPDLXparseentry {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string] $Line
    )

    [string] $ts  = ''
    [string] $lvl = ''
    [string] $msg = ''

    $arrowParts = $Line -split '  ->  ', 2
    if ($arrowParts.Count -eq 2) {
        $msg = $arrowParts[1].Trim()

        [string] $leftPart = $arrowParts[0].Trim().TrimStart('[')
        $bracketParts = $leftPart -split '\]\s+\[', 2
        if ($bracketParts.Count -eq 2) {
            $ts  = $bracketParts[0].Trim()
            $lvl = $bracketParts[1].TrimEnd(']').Trim()
        }
        else {
            $ts  = $leftPart.Trim()
            $lvl = 'UNKNOWN'
        }
    }
    else {
        # Unparseable line - preserve it as a raw message.
        $msg = $Line
        $lvl = 'RAW'
    }

    return [PSCustomObject]@{
        Timestamp = $ts
        Level     = $lvl
        Message   = $msg
    }
}
