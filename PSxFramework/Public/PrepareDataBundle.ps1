function PrepareDataBundle {
    <#
    .SYNOPSIS
    Prepares data for packaging into a 7z archive by copying source files to the build directory.
    
    .DESCRIPTION
    The PrepareDataBundle function copies application data from a source directory to the temporary
    build directory. This prepares the data structure for subsequent packaging into a 7z archive.
    The source directory must exist and contain files, and the destination will be created if needed.
    
    .PARAMETER DataSource
    Full path to the source directory containing the application data to be packaged.
    The directory must exist and must not be empty.
    This parameter is mandatory.
    
    .PARAMETER DestFolder
    Full path to the destination directory where data will be copied.
    Typically this is {INSTALLDIR}\tmpdata\{APPNAME}.
    The directory will be created if it doesn't exist.
    This parameter is mandatory.
    
    .EXAMPLE
    $result = PrepareDataBundle -DataSource "C:\MyApp\Files" -DestFolder "C:\PSx\tmpdata\MyApp"
    if ($result.code -eq 0) {
        Write-Host "Data bundle prepared: $($result.msg)"
    }
    Copies all files from C:\MyApp\Files to the build directory.
    
    .EXAMPLE
    $installDir = (GetInstallDir).data
    $appName = "MyApplication"
    $destPath = Join-Path $installDir "tmpdata\$appName"
    PrepareDataBundle -DataSource "D:\Projects\MyApp" -DestFolder $destPath
    Prepares application data using PSx Composer installation directory.
    
    .NOTES
    This function is typically called after CreateHiddenTempData and before CreateDataBundle.
    All files and subdirectories from the source are copied recursively to the destination.
    #>
    
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DataSource,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestFolder
    )
    
    try {
        # Validate DataSource parameter
        if ([string]::IsNullOrWhiteSpace($DataSource)) {
            return (OPSreturn -Code -1 -Message "Parameter 'DataSource' is required but was not provided or is empty")
        }
        
        # Validate DestFolder parameter
        if ([string]::IsNullOrWhiteSpace($DestFolder)) {
            return (OPSreturn -Code -1 -Message "Parameter 'DestFolder' is required but was not provided or is empty")
        }
        
        # Check if source directory exists
        if (-not (Test-Path -Path $DataSource -PathType Container)) {
            return (OPSreturn -Code -1 -Message "Source directory does not exist: $DataSource")
        }
        
        # Check if source directory is empty
        try {
            $sourceItems = Get-ChildItem -Path $DataSource -Force -ErrorAction Stop
            if ($sourceItems.Count -eq 0) {
                return (OPSreturn -Code -1 -Message "Source directory is empty: $DataSource")
            }
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to enumerate source directory contents: $($_.Exception.Message)")
        }
        
        # Create destination directory if it doesn't exist
        if (-not (Test-Path -Path $DestFolder -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $DestFolder -Force -ErrorAction Stop | Out-Null
            }
            catch {
                return (OPSreturn -Code -1 -Message "Failed to create destination directory '$DestFolder': $($_.Exception.Message)")
            }
        }
        
        # Copy all contents from source to destination recursively
        try {
            # Get all items from source
            $itemsToCopy = Get-ChildItem -Path $DataSource -Recurse -Force
            $totalItems = $itemsToCopy.Count
            $copiedItems = 0
            
            # Copy directory structure and files
            Copy-Item -Path "$DataSource\*" -Destination $DestFolder -Recurse -Force -ErrorAction Stop
            
            # Verify that destination is not empty after copy
            $destItems = Get-ChildItem -Path $DestFolder -Force -ErrorAction SilentlyContinue
            if ($destItems.Count -eq 0) {
                return (OPSreturn -Code -1 -Message "Copy operation completed but destination directory is empty")
            }
            
            # Count copied items for verification
            $copiedItems = (Get-ChildItem -Path $DestFolder -Recurse -Force).Count
            
            return (OPSreturn -Code 0 -Message "Data bundle prepared successfully: $copiedItems items copied from source" -Data $DestFolder)
        }
        catch {
            return (OPSreturn -Code -1 -Message "Failed to copy data from '$DataSource' to '$DestFolder': $($_.Exception.Message)")
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Unexpected error in PrepareDataBundle function: $($_.Exception.Message)")
    }
}
