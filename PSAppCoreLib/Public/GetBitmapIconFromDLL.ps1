function GetBitmapIconFromDLL {
    <#
    .SYNOPSIS
    Extracts an icon from a DLL file and converts it to a bitmap.
    
    .DESCRIPTION
    The GetBitmapIconFromDLL function extracts a specified icon from a DLL file
    by index and converts it to a bitmap format. It validates the DLL file existence,
    checks the icon index availability, and handles proper error reporting through
    a standardized return object.
    
    .PARAMETER DLLfile
    Full path including filename to the DLL file containing the icons.
    
    .PARAMETER IconIndex
    Zero-based index of the icon to extract from the DLL file.
    
    .EXAMPLE
    GetBitmapIconFromDLL -DLLfile "C:\Windows\System32\shell32.dll" -IconIndex 0
    Extracts the first icon (index 0) from shell32.dll and converts it to a bitmap.
    
    .EXAMPLE
    GetBitmapIconFromDLL -DLLfile "C:\Windows\System32\imageres.dll" -IconIndex 15
    Extracts the icon at index 15 from imageres.dll and converts it to a bitmap.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DLLfile,
        
        [Parameter(Mandatory = $true)]
        [int]$IconIndex
    )
    
    # Initialize status object for return value
    $status = [PSCustomObject]@{
        code = -1
        msg = "Detailed error message"
        bitmap = $null
    }
    
    # Validate mandatory parameters
    if ([string]::IsNullOrEmpty($DLLfile)) {
        $status.msg = "Parameter 'DLLfile' is required but was not provided"
        return $status
    }
    
    if ($IconIndex -lt 0) {
        $status.msg = "Parameter 'IconIndex' must be a non-negative integer"
        return $status
    }
    
    try {
        # Check if DLL file exists
        if (-not (Test-Path -Path $DLLfile -PathType Leaf)) {
            $status.msg = "DLL file '$DLLfile' does not exist"
            return $status
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
                $status.msg = "Failed to load Win32 API definitions: $($_.Exception.Message). This may be due to missing assemblies or compilation errors."
                return $status
            }
        }
        
        # Get total icon count in the DLL
        try {
            $IconCount = [PSAppCoreLib.IconExtractor]::GetIconCount($DLLfile)
            if ($IconCount -le 0) {
                $status.msg = "No icons found in DLL file '$DLLfile' or file is not accessible"
                return $status
            }
            Write-Verbose "Found $IconCount icons in DLL file"
        }
        catch {
            $status.msg = "Failed to determine icon count in DLL file '$DLLfile': $($_.Exception.Message)"
            return $status
        }
        
        # Validate icon index against available icons
        if ($IconIndex -ge $IconCount) {
            $status.msg = "Icon index $IconIndex is not available. DLL file '$DLLfile' contains only $IconCount icons (indices 0-$($IconCount-1))"
            return $status
        }
        
        # Extract the icon
        try {
            $ExtractedIcon = [PSAppCoreLib.IconExtractor]::ExtractIcon($DLLfile, $IconIndex, $true) # true for large icon
            if ($null -eq $ExtractedIcon) {
                $status.msg = "Failed to extract icon at index $IconIndex from DLL file '$DLLfile'"
                return $status
            }
            Write-Verbose "Successfully extracted icon at index $IconIndex"
        }
        catch {
            $status.msg = "Error during icon extraction from '$DLLfile' at index $IconIndex`: $($_.Exception.Message)"
            return $status
        }
        
        # Convert icon to bitmap
        try {
            $ConvertedBitmap = $ExtractedIcon.ToBitmap()
            if ($null -eq $ConvertedBitmap) {
                $status.msg = "Failed to convert extracted icon to bitmap"
                return $status
            }
            Write-Verbose "Successfully converted icon to bitmap (Size: $($ConvertedBitmap.Width)x$($ConvertedBitmap.Height))"
        }
        catch {
            $status.msg = "Error during bitmap conversion: $($_.Exception.Message)"
            return $status
        }
        finally {
            # Clean up the icon handle
            if ($ExtractedIcon) {
                $ExtractedIcon.Dispose()
            }
        }
        
        # Success - set return values
        $status.code = 0
        $status.msg = ""
        $status.bitmap = $ConvertedBitmap
        return $status
    }
    catch {
        $status.msg = "Unexpected error in GetBitmapIconFromDLL function: $($_.Exception.Message)"
        return $status
    }
}