function Invoke-UUPProcessKill {
    <#
    .SYNOPSIS
        Forcefully terminates a process and its entire child process tree.

    .DESCRIPTION
        Used by CreateUUPDiso when KillOnHardIdle is set. Kills the specified
        process and all child processes (e.g. cmd.exe spawning aria2c.exe,
        PowerShell sub-processes, oscdimg.exe, etc.).

        Uses WMI (Win32_Process) to enumerate the process tree before sending
        kill signals, ensuring no orphaned child processes remain.

    .PARAMETER ProcessId
        PID of the root process to kill (typically cmd.exe).

    .OUTPUTS
        [bool] $true if the kill was attempted (even partially), $false on error.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId
    )

    try {
        # Collect all child PIDs via WMI recursively
        $AllPIDs = [System.Collections.Generic.List[int]]::new()
        $AllPIDs.Add($ProcessId)

        $Collect = {
            param([int]$ParentPID)
            $Children = Get-WmiObject Win32_Process -Filter "ParentProcessId = $ParentPID" -ErrorAction SilentlyContinue
            foreach ($Child in $Children) {
                $AllPIDs.Add([int]$Child.ProcessId)
                & $Collect ([int]$Child.ProcessId)
            }
        }
        & $Collect $ProcessId

        # Kill in reverse order (children first, root last)
        $AllPIDs.Reverse()
        foreach ($ProcID in $AllPIDs) {
            try {
                $Proc = Get-Process -Id $ProcID -ErrorAction SilentlyContinue
                if ($null -ne $Proc -and -not $Proc.HasExited) {
                    $Proc.Kill()
                    Write-Verbose "Invoke-UUPProcessKill: Killed PID $ProcID ($($Proc.ProcessName))"
                }
            } catch {
                Write-Verbose "Invoke-UUPProcessKill: Could not kill PID $ProcID : $($_.Exception.Message)"
            }
        }

        return $true
    }
    catch {
        Write-Warning "Invoke-UUPProcessKill: Unexpected error killing PID $ProcessId : $($_.Exception.Message)"
        return $false
    }
}
