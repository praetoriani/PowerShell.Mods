function GetUUPDumpPackage {
    <#
    .SYNOPSIS
        Downloads a multi-edition UUPDump package ZIP file from uupdump.net.

    .DESCRIPTION
        GetUUPDumpPackage queries the UUP Dump API to find the correct build based on the
        provided OS type, version, architecture and optional build number. It then
        downloads the corresponding ZIP archive configured to build a multi-edition ISO
        using the UUPDump Virtual Editions feature
        (autodl=3 / "Download, add additional editions and convert to ISO").

        This function is designed for scenarios where you need editions beyond the standard
        Windows Pro or Home editions covered by DownloadUUPDump. Available editions:
        - ProWorkstations  : Windows Pro for Workstations
        - ProEducation     : Windows Pro Education
        - Education        : Windows Education
        - Enterprise       : Windows Enterprise
        - IoTEnterprise    : Windows IoT Enterprise

        At least one edition must be specified. Multiple editions can be combined.

        The function ensures:
        - The target directory structure is created automatically if it does not exist
        - Any pre-existing ZIP file at the target path is deleted before downloading
        - The downloaded ZIP file is verified for completeness via HTTP Content-Length comparison
        - All relevant download metadata is written to the module-scope $script:uupdump
          variable via WinISOcore upon successful completion

    .PARAMETER OStype
        Specifies the operating system name. Currently only 'Windows11' is supported.

    .PARAMETER OSvers
        Specifies the OS version. Valid values: '24H2' (default) or '25H2'.

    .PARAMETER OSarch
        Specifies the target architecture. Valid values: 'amd64' or 'arm64'.

    .PARAMETER Editions
        Array of Windows editions to include in the multi-edition ISO.
        At least one edition must be specified. Valid values:
        - 'ProWorkstations'  : Windows Pro for Workstations
        - 'ProEducation'     : Windows Pro Education
        - 'Education'        : Windows Education
        - 'Enterprise'       : Windows Enterprise
        - 'IoTEnterprise'    : Windows IoT Enterprise

    .PARAMETER BuildNo
        Optional. A specific build number in the format '00000.0000' (digits and exactly one dot).
        If omitted, the latest available retail build is selected automatically.

    .PARAMETER Target
        Full path to the target ZIP file including filename.
        The directory structure is created automatically if it does not exist.

    .PARAMETER ExcludeNetFX
        Switch parameter. When specified, .NET Framework 3.5 integration is explicitly
        excluded from the UUP conversion package (NetFx3=0 in ConvertConfig.ini).
        Default behavior: .NET Framework 3.5 is included (matching standard UUPDump behavior).

    .PARAMETER UseESD
        Switch parameter. When specified, the ISO is created with an install.esd file
        instead of install.wim (wim2esd=1 in ConvertConfig.ini).
        Default behavior: install.wim is used (UseESD not set).

    .OUTPUTS
        PSCustomObject with fields:
        .code  >>  0 = Success | -1 = Error
        .msg   >>  Description of the result or error
        .data  >>  Full path to the downloaded ZIP file on success, $null on failure

    .EXAMPLE
        # Download Windows 11 Enterprise 24H2 amd64
        $result = GetUUPDumpPackage -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' `
                                    -Editions @('Enterprise') `
                                    -Target 'C:\WinISO\uupdump\Win11_Enterprise_24H2.zip'
        if ($result.code -eq 0) { Write-Host "Downloaded: $($result.data)" }

    .EXAMPLE
        # Download multi-edition ISO: Enterprise + Education + Pro for Workstations
        $result = GetUUPDumpPackage -OStype 'Windows11' -OSvers '24H2' -OSarch 'amd64' `
                                    -Editions @('Enterprise', 'Education', 'ProWorkstations') `
                                    -Target 'C:\WinISO\uupdump\Win11_Multi_24H2.zip'

    .EXAMPLE
        # Download Windows 11 Enterprise 25H2, no .NET FX 3.5, with ESD format
        $result = GetUUPDumpPackage -OStype 'Windows11' -OSvers '25H2' -OSarch 'amd64' `
                                    -Editions @('Enterprise', 'IoTEnterprise') `
                                    -ExcludeNetFX -UseESD `
                                    -Target 'C:\WinISO\uupdump\Win11_Enterprise_IoT_25H2_ESD.zip'

    .NOTES
        Version:      1.00.05
        Dependencies:
        - Private function OPSreturn must be available (loaded via module)
        - WinISOcore must be available for $script:uupdump write-back
        - Requires internet access to api.uupdump.net and uupdump.net
        - Requires PowerShell 5.1 or higher
        - Requires .NET 4.7.2+ (System.Web.HttpUtility)
        - See also: DownloadUUPDump for Windows Pro / Home single-edition downloads
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "OS type. Currently only 'Windows11' is supported.")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Windows11')]
        [string]$OStype,

        [Parameter(Mandatory = $true, HelpMessage = "OS version. Valid values: '24H2' or '25H2'.")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('24H2', '25H2')]
        [string]$OSvers,

        [Parameter(Mandatory = $true, HelpMessage = "Target architecture. Valid values: 'amd64' or 'arm64'.")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('amd64', 'arm64')]
        [string]$OSarch,

        [Parameter(Mandatory = $true, HelpMessage = "One or more Windows editions. Valid: 'ProWorkstations', 'ProEducation', 'Education', 'Enterprise', 'IoTEnterprise'.")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('ProWorkstations', 'ProEducation', 'Education', 'Enterprise', 'IoTEnterprise')]
        [string[]]$Editions,

        [Parameter(Mandatory = $false, HelpMessage = "Optional build number in format '00000.0000'.")]
        [AllowEmptyString()]
        [string]$BuildNo = '',

        [Parameter(Mandatory = $true, HelpMessage = "Full path to the target ZIP file including filename.")]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

        [Parameter(Mandatory = $false, HelpMessage = "Explicitly exclude .NET Framework 3.5 from the conversion package.")]
        [switch]$ExcludeNetFX,

        [Parameter(Mandatory = $false, HelpMessage = "Create ISO with install.esd instead of install.wim.")]
        [switch]$UseESD
    )

    # Retrieve module-scope variables via WinISOcore
    $appinfo = WinISOcore -Scope 'env' -GlobalVar 'appinfo' -Permission 'read' -Unwrap
    $appenv  = WinISOcore -Scope 'env' -GlobalVar 'appenv'  -Permission 'read' -Unwrap
    $appcore = WinISOcore -Scope 'env' -GlobalVar 'appcore' -Permission 'read' -Unwrap
    $uupdump = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'read' -Unwrap

    # Internal API and base URL constants for UUP Dump
    $UUP_API_URL  = 'https://api.uupdump.net'
    $UUP_BASE_URL = 'https://uupdump.net'

    # ----------------------------------------------------------------
    # STEP 1 >> Map edition names to UUPDump internal edition identifiers
    # ----------------------------------------------------------------
    # UUPDump edition IDs used in GET URL (semicolon-separated for multi-edition)
    # Display names used in $script:uupdump['multiedition'] (semicolon-separated)
    $EditionIDMap = @{
        'ProWorkstations' = @{ UUPID = 'professional_workstations'; Display = 'Pro for Workstations' }
        'ProEducation'    = @{ UUPID = 'professional_education';    Display = 'Pro Education'        }
        'Education'       = @{ UUPID = 'education';                 Display = 'Education'            }
        'Enterprise'      = @{ UUPID = 'enterprise';                Display = 'Enterprise'           }
        'IoTEnterprise'   = @{ UUPID = 'iotenterprise';             Display = 'IoT Enterprise'       }
    }

    # Deduplicate editions array (preserve order)
    $UniqueEditions = $Editions | Select-Object -Unique

    # Build semicolon-separated UUP edition string for GET URL
    $UUPEditionIDs   = ($UniqueEditions | ForEach-Object { $EditionIDMap[$_].UUPID }) -join ';'
    # Human-readable display string for log messages
    $DisplayEditions = ($UniqueEditions | ForEach-Object { $EditionIDMap[$_].Display }) -join ', '
    # Semicolon-joined display names stored in $script:uupdump['multiedition']
    $MultiEditionStr = ($UniqueEditions | ForEach-Object { $EditionIDMap[$_].Display }) -join ';'

    # Resolve NetFX and ESD settings
    $NetFXValue = if ($ExcludeNetFX.IsPresent) { '0' } else { '1' }
    $ESDValue   = if ($UseESD.IsPresent) { '1' } else { '0' }

    # ----------------------------------------------------------------
    # STEP 2 >> Validate optional BuildNo parameter format (if provided)
    # ----------------------------------------------------------------
    if (-not [string]::IsNullOrWhiteSpace($BuildNo)) {
        if ($BuildNo -notmatch '^\d{5}\.\d{4}$') {
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Parameter 'BuildNo' must be in format '00000.0000' (e.g. '26100.3476'). Provided value: '$BuildNo'")
        }
    }

    # ----------------------------------------------------------------
    # STEP 3 >> Validate and prepare the target path / directory
    # ----------------------------------------------------------------
    try {
        if ([System.IO.Path]::GetExtension($Target).ToLower() -ne '.zip') {
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Parameter 'Target' must point to a .zip file. Provided: '$Target'")
        }

        $TargetDir = [System.IO.Path]::GetDirectoryName($Target)

        if ([string]::IsNullOrWhiteSpace($TargetDir)) {
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Could not determine target directory from path: '$Target'")
        }

        if (-not (Test-Path -Path $TargetDir -PathType Container)) {
            $null = New-Item -Path $TargetDir -ItemType Directory -Force -ErrorAction Stop
        }

        if (Test-Path -Path $Target -PathType Leaf) {
            Remove-Item -Path $Target -Force -ErrorAction Stop
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Error preparing target path '$Target': $($_.Exception.Message)")
    }

    # ----------------------------------------------------------------
    # STEP 4 >> Build the UUP Dump API search query
    # ----------------------------------------------------------------
    $BuildUUID   = $null
    $BuildNumber = $null

    try {
        $SearchTerm   = "Windows 11 $OSvers $OSarch"
        $ApiSearchUrl = "$UUP_API_URL/listid.php"
        $SearchBody   = @{ search = $SearchTerm }

        $ApiResponse = Invoke-RestMethod -Uri $ApiSearchUrl -Method Get -Body $SearchBody -ErrorAction Stop

        if ($ApiResponse.response.error) {
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! UUP Dump API returned error: $($ApiResponse.response.error)")
        }

        if (-not $ApiResponse.response.builds) {
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! UUP Dump API returned no builds for search term: '$SearchTerm'")
        }

        # Filter builds: retail only (exclude Preview / Insider builds)
        $Builds = $ApiResponse.response.builds.PSObject.Properties | Where-Object {
            $_.Value.title   -like "*Windows 11*"    -and
            $_.Value.title   -like "*$OSvers*"       -and
            $_.Value.arch    -eq $OSarch             -and
            $_.Value.title   -notlike "*preview*"    -and
            $_.Value.title   -notlike "*Insider*"
        } | Sort-Object { $_.Value.created } -Descending

        if ($Builds.Count -eq 0) {
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! No matching retail builds found for: OS='$OStype' Version='$OSvers' Arch='$OSarch'")
        }

        if (-not [string]::IsNullOrWhiteSpace($BuildNo)) {
            $MatchingBuild = $Builds | Where-Object { $_.Value.build -eq $BuildNo } | Select-Object -First 1

            if (-not $MatchingBuild) {
                return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Build number '$BuildNo' was not found for: OS='$OStype' Version='$OSvers' Arch='$OSarch'")
            }

            $BuildUUID   = $MatchingBuild.Value.uuid
            $BuildTitle  = $MatchingBuild.Value.title
            $BuildNumber = $MatchingBuild.Value.build
        }
        else {
            $BuildUUID   = $Builds[0].Value.uuid
            $BuildTitle  = $Builds[0].Value.title
            $BuildNumber = $Builds[0].Value.build
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Error querying UUP Dump API: $($_.Exception.Message)")
    }

    # ----------------------------------------------------------------
    # STEP 5 >> Build the UUP Dump download URL and POST body
    # ----------------------------------------------------------------
    try {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

        # For multi-edition VE mode, the GET edition parameter contains the semicolon-separated
        # list of UUP internal edition IDs. This tells UUPDump which editions to prepare.
        $DownloadParams = @{
            id      = $BuildUUID
            pack    = 'de-de'
            edition = $UUPEditionIDs
        }

        $QueryString = ($DownloadParams.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))"
        }) -join '&'

        $DownloadUrl = "$UUP_BASE_URL/get.php?$QueryString"

        # POST body for Virtual Editions mode:
        # autodl=3: Download, add additional editions and convert to ISO (StartVirtual=1 in ConvertConfig.ini)
        $PostBody = @{
            autodl  = '3'           # Virtual Editions conversion mode
            updates = '0'           # Do not integrate cumulative updates
            cleanup = '0'           # Do not run cleanup after conversion
            netfx   = $NetFXValue   # .NET Framework 3.5 integration (parameterized)
            esd     = $ESDValue     # ESD vs WIM format (parameterized)
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Error building download URL for build '$BuildTitle' (UUID: $BuildUUID): $($_.Exception.Message)")
    }

    # ----------------------------------------------------------------
    # STEP 6 >> Perform the HTTP POST download with completeness verification
    # ----------------------------------------------------------------
    try {
        $WebResponse = Invoke-WebRequest -Uri $DownloadUrl -Method Post -Body $PostBody `
                                         -OutFile $Target -UseBasicParsing -PassThru -ErrorAction Stop

        if (-not (Test-Path -Path $Target -PathType Leaf)) {
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Download completed but ZIP file was not found at: '$Target'")
        }

        $WrittenSize = (Get-Item -Path $Target).Length

        $ContentLength = 0
        if ($WebResponse.Headers['Content-Length']) {
            [long]::TryParse($WebResponse.Headers['Content-Length'], [ref]$ContentLength) | Out-Null
        }

        if ($ContentLength -gt 0 -and $WrittenSize -ne $ContentLength) {
            Remove-Item -Path $Target -Force -ErrorAction SilentlyContinue
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! ZIP file appears incomplete. Expected=$ContentLength bytes / Written=$WrittenSize bytes. Incomplete file was removed.")
        }

        if ($WrittenSize -eq 0) {
            Remove-Item -Path $Target -Force -ErrorAction SilentlyContinue
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Downloaded ZIP file has 0 bytes. Incomplete file was removed.")
        }
    }
    catch {
        if (Test-Path -Path $Target -PathType Leaf) {
            Remove-Item -Path $Target -Force -ErrorAction SilentlyContinue
        }
        return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Error during download of build '$BuildTitle' (UUID: $BuildUUID): $($_.Exception.Message)")
    }

    # -------------------------------------------------------------------------
    # SUCCESS >> ZIP file downloaded and verified
    # -------------------------------------------------------------------------
    $FinalSizeKB = [math]::Round($WrittenSize / 1KB, 2)
    $ZipFileName = [System.IO.Path]::GetFileName($Target)

    # ----------------------------------------------------------------
    # STEP 7 >> Write all relevant download metadata to module-scope $script:uupdump
    #           All keys MUST be written successfully for the function to report success.
    # ----------------------------------------------------------------
    $WriteOps = @(
        @{ VarKeyID = 'ostype';        SetNewVal = $OStype         },
        @{ VarKeyID = 'osvers';        SetNewVal = $OSvers         },
        @{ VarKeyID = 'osarch';        SetNewVal = $OSarch         },
        @{ VarKeyID = 'edition';       SetNewVal = ''              },
        @{ VarKeyID = 'multiedition';  SetNewVal = $MultiEditionStr },
        @{ VarKeyID = 'buildno';       SetNewVal = $BuildNumber    },
        @{ VarKeyID = 'kbsize';        SetNewVal = $FinalSizeKB    },
        @{ VarKeyID = 'zipname';       SetNewVal = $ZipFileName    }
    )

    foreach ($Op in $WriteOps) {
        $WriteResult = WinISOcore -Scope 'env' -GlobalVar 'uupdump' -Permission 'write' `
                                  -VarKeyID $Op.VarKeyID -SetNewVal $Op.SetNewVal
        if ($WriteResult.code -ne 0) {
            return (OPSreturn -Code -1 -Message "Function GetUUPDumpPackage failed! Download succeeded but could not write '$($Op.VarKeyID)' to `$script:uupdump. Reason: $($WriteResult.msg)")
        }
    }

    return (OPSreturn -Code 0 -Message "GetUUPDumpPackage successfully finished! Editions: '$DisplayEditions' | Build: '$BuildTitle' | BuildNo: $BuildNumber | UUID: $BuildUUID | NetFX: $NetFXValue | ESD: $ESDValue | File: '$Target' ($FinalSizeKB KB)" -Data $Target)
}
