function VerifyEnvironment {
    <#
    .SYNOPSIS
    VerifyEnvironment - Core function that can verify several things regarding our environment
    
    .DESCRIPTION
    This function gives you the ability to verify multiple configs/settings regarding the WinISO environment.
    
    .EXAMPLE
    InitializeEnvironment
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Defines the type of source you want to verify. Can be 'file', 'dir' or 'conf'.")]
        [AllowEmptyString()]
        [string]$type,
        
        [Parameter(Mandatory = $false, HelpMessage = "The full path to the file/dir you want to verify")]
        [AllowEmptyString()]
        [string]$path,
        
        [Parameter(Mandatory = $false, HelpMessage = "Defines the config you want to check/verify. Can only be used with type=conf")]
        [AllowEmptyString()]
        [ValidateSet("appinfo", "appenv", IgnoreCase = $true)]
        [string]$conf
    )
    # normalize the given params
    if ( $type -ne [string]::Empty) { $type = $type.ToLower() }
    if ( $conf -ne [string]::Empty) { $conf = $conf.ToLower() }

    # Import global vars using getter-functionallity
    $AppInfo = AppScope -KeyID 'appinfo'
    $EnvData = AppScope -KeyID 'appenv'
    # Sample Usage: $EnvData['ISOroot'] will be 'C:\WinISO' (as defined and exported via psm1 file)

    try {
        switch ($type) {
            "file" {
                if ( $path -ne [string]::Empty) {
                    if (Test-Path -Path $path -PathType Leaf) {
                        return (OPSreturn -Code 1 -Message "Function VerifyEnvironment successfully finished! $path exists.")
                    }
                    else {
                        return (OPSreturn -Code 0 -Message "Function VerifyEnvironment successfully finished! $path does not exist!")
                    }
                }
                else {
                    return (OPSreturn -Code -1 -Message "Error in $AppInfo['AppName']! Function VerifyEnvironment failed while using type=$type but no path provided!")
                }
            }
            "dir" {
                if ( $path -ne [string]::Empty) {
                    if (Test-Path -Path $path -PathType Container) {
                        return (OPSreturn -Code 1 -Message "Function VerifyEnvironment successfully finished! $path exists.")
                    }
                    else {
                        return (OPSreturn -Code 0 -Message "Function VerifyEnvironment successfully finished! $path does not exist!")
                    }
                }
                else {
                    return (OPSreturn -Code -1 -Message "Error in $AppInfo['AppName']! Function VerifyEnvironment failed while using type=$type but no path provided!")
                }
            }
            "conf" {
                if ( $conf -ne [string]::Empty) {
                    # ...
                    return (OPSreturn -Code -1 -Message "Error in $AppInfo['AppName']! Function VerifyEnvironment failed! Unable to handle switch-statement 'conf'!")
                }
                else {
                    return (OPSreturn -Code -1 -Message "Error in $AppInfo['AppName']! Function VerifyEnvironment failed while using type=$type but no conf provided!")
                }
            }
            Default {
                return (OPSreturn -Code -1 -Message "Error in $AppInfo['AppName']! Function VerifyEnvironment failed! $type is not a known value for type!")
            }
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Error in $AppInfo['AppName']! Function VerifyEnvironment failed with the following error: $($_.Exception.Message)")
        # optional: $_.Exception.GetType().FullName für Typprüfung
    }
    
}
