function GetBitmapIconFromDLL {
    <#
    .SYNOPSIS
    Extracts an icon from a DLL file and converts it to a bitmap.
    
    .DESCRIPTION
    The GetBitmapIconFromDLL function extracts a specified icon from a DLL file
    by index and converts it to a bitmap format. It validates the DLL file existence,
    checks the icon index availability, and handles proper error reporting through
    OPSreturn standardized return pattern.
    
    .PARAMETER DLLfile
    Full path including filename to the DLL file containing the icons.
    
    .PARAMETER IconIndex
    Zero-based index of the icon to extract from the DLL file.
    
    .EXAMPLE
    $result = GetBitmapIconFromDLL -DLLfile "C:\Windows\System32\shell32.dll" -IconIndex 0
    if ($result.code -eq 0) {
        $bitmap = $result.data.Bitmap
        Write-Host "Extracted icon: $($result.data.Width)x$($result.data.Height) pixels"
    }
    
    .EXAMPLE
    $result = GetBitmapIconFromDLL -DLLfile "C:\Windows\System32\imageres.dll" -IconIndex 15
    if ($result.code -eq 0) {
        # Use the bitmap from $result.data.Bitmap
        $pictureBox.Image = $result.data.Bitmap
    }
    
    .EXAMPLE
    # Check available icon count first
    $result = GetBitmapIconFromDLL -DLLfile "C:\Windows\System32\shell32.dll" -IconIndex 0
    Write-Host "DLL contains $($result.data.TotalIconCount) icons"
    
    .NOTES
    - Requires System.Drawing and System.Windows.Forms assemblies
    - Icon extraction uses Win32 API (ExtractIconEx)
    - Returns large version of icon (32x32 or larger)
    - Bitmap object should be disposed when no longer needed
    - Returns comprehensive icon metadata in the data field
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DLLfile,
        
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$IconIndex
    )
    
    # Validate mandatory parameters
    if ([string]::IsNullOrEmpty($DLLfile)) {
        return OPSreturn -Code -1 -Message "Parameter 'DLLfile' is required but was not provided"
    }
    
    if ($IconIndex -lt 0) {
        return OPSreturn -Code -1 -Message "Parameter 'IconIndex' must be a non-negative integer"
    }
    
    try {
        # Check if DLL file exists
        if (-not (Test-Path -Path $DLLfile -PathType Leaf)) {
            return OPSreturn -Code -1 -Message "DLL file '$DLLfile' does not exist"
        }
        
        # Add required .NET assemblies for icon extraction
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore if assemblies are already loaded
        }
        
        # Check if IconExtractor type already exists
        $typeExists = $false
        try {
            $null = [PSAppCoreLib.IconExtractor]
            $typeExists = $true
            Write-Verbose "IconExtractor type already loaded"
        }
        catch {
            Write-Verbose "IconExtractor type not loaded, creating new type"
        }
        
        # Define Win32API for icon extraction only if not already loaded
        if (-not $typeExists) {
            $Win32API = @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace PSAppCoreLib
{
    public class IconExtractor
    {
        [DllImport("Shell32.dll", EntryPoint = "ExtractIconExW", CharSet = CharSet.Unicode, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
        private static extern int ExtractIconEx(string sFile, int iIndex, out IntPtr piLargeVersion, out IntPtr piSmallVersion, int amountIcons);
        
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool DestroyIcon(IntPtr hIcon);
        
        public static int GetIconCount(string file)
        {
            try
            {
                IntPtr large;
                IntPtr small;
                return ExtractIconEx(file, -1, out large, out small, 0);
            }
            catch
            {
                return 0;
            }
        }
        
        public static Icon ExtractIcon(string file, int index, bool large)
        {
            IntPtr hLarge = IntPtr.Zero;
            IntPtr hSmall = IntPtr.Zero;
            
            try
            {
                int result = ExtractIconEx(file, index, out hLarge, out hSmall, 1);
                
                if (result > 0)
                {
                    IntPtr hIcon = large ? hLarge : hSmall;
                    if (hIcon != IntPtr.Zero)
                    {
                        Icon icon = (Icon)Icon.FromHandle(hIcon).Clone();
                        
                        // Clean up the unused handle
                        if (large && hSmall != IntPtr.Zero)
                            DestroyIcon(hSmall);
                        else if (!large && hLarge != IntPtr.Zero)
                            DestroyIcon(hLarge);
                            
                        return icon;
                    }
                }
                return null;
            }
            catch
            {
                // Clean up handles on error
                if (hLarge != IntPtr.Zero) DestroyIcon(hLarge);
                if (hSmall != IntPtr.Zero) DestroyIcon(hSmall);
                throw;
            }
        }
    }
}
"@
            
            # Compile the Win32API code with proper error handling
            try {
                Add-Type -TypeDefinition $Win32API -ReferencedAssemblies @('System.Drawing', 'System.Windows.Forms') -ErrorAction Stop
                Write-Verbose "Successfully compiled IconExtractor type"
            }
            catch {
                return OPSreturn -Code -1 -Message "Failed to load Win32 API definitions: $($_.Exception.Message). This may be due to missing assemblies or compilation errors."
            }
        }
        
        # Get total icon count in the DLL
        $IconCount = 0
        try {
            $IconCount = [PSAppCoreLib.IconExtractor]::GetIconCount($DLLfile)
            if ($IconCount -le 0) {
                return OPSreturn -Code -1 -Message "No icons found in DLL file '$DLLfile' or file is not accessible"
            }
            Write-Verbose "Found $IconCount icons in DLL file"
        }
        catch {
            return OPSreturn -Code -1 -Message "Failed to determine icon count in DLL file '$DLLfile': $($_.Exception.Message)"
        }
        
        # Validate icon index against available icons
        if ($IconIndex -ge $IconCount) {
            return OPSreturn -Code -1 -Message "Icon index $IconIndex is not available. DLL file '$DLLfile' contains only $IconCount icons (indices 0-$($IconCount-1))"
        }
        
        # Extract the icon
        $ExtractedIcon = $null
        try {
            $ExtractedIcon = [PSAppCoreLib.IconExtractor]::ExtractIcon($DLLfile, $IconIndex, $true) # true for large icon
            if ($null -eq $ExtractedIcon) {
                return OPSreturn -Code -1 -Message "Failed to extract icon at index $IconIndex from DLL file '$DLLfile'"
            }
            Write-Verbose "Successfully extracted icon at index $IconIndex"
        }
        catch {
            return OPSreturn -Code -1 -Message "Error during icon extraction from '$DLLfile' at index $IconIndex`: $($_.Exception.Message)"
        }
        
        # Convert icon to bitmap
        $ConvertedBitmap = $null
        try {
            $ConvertedBitmap = $ExtractedIcon.ToBitmap()
            if ($null -eq $ConvertedBitmap) {
                return OPSreturn -Code -1 -Message "Failed to convert extracted icon to bitmap"
            }
            Write-Verbose "Successfully converted icon to bitmap (Size: $($ConvertedBitmap.Width)x$($ConvertedBitmap.Height))"
        }
        catch {
            return OPSreturn -Code -1 -Message "Error during bitmap conversion: $($_.Exception.Message)"
        }
        finally {
            # Clean up the icon handle
            if ($ExtractedIcon) {
                $ExtractedIcon.Dispose()
            }
        }
        
        # Prepare return data with comprehensive bitmap metadata
        $ReturnData = [PSCustomObject]@{
            DLLPath        = $DLLfile
            IconIndex      = $IconIndex
            TotalIconCount = $IconCount
            Bitmap         = $ConvertedBitmap
            Width          = $ConvertedBitmap.Width
            Height         = $ConvertedBitmap.Height
            PixelFormat    = $ConvertedBitmap.PixelFormat.ToString()
        }
        
        Write-Verbose "Icon extraction completed successfully"
        Write-Verbose "  DLL: $DLLfile"
        Write-Verbose "  Index: $IconIndex of $IconCount"
        Write-Verbose "  Size: $($ConvertedBitmap.Width)x$($ConvertedBitmap.Height)"
        
        return OPSreturn -Code 0 -Message "" -Data $ReturnData
    }
    catch {
        return OPSreturn -Code -1 -Message "Unexpected error in GetBitmapIconFromDLL function: $($_.Exception.Message)"
    }
}
