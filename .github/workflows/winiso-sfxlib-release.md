<!-- ===========================================================================
     RELEASE PAGE TEMPLATE FOR WinISO.ScriptFXLib
     ---------------------------------------------------------------------------
     This file is used by the GitHub Actions workflow winiso-sfxlib-release.yml
     to build the release body dynamically.

     The following placeholders are replaced at runtime by the workflow:
       {{LOGO_URL}}        -> Raw URL to the project logo image
       {{ZIP_FILENAME}}    -> Full ZIP filename (e.g. WinISO-1.00.00-Release.zip)
       {{DOWNLOAD_URL}}    -> Full direct download URL for the ZIP file
       {{REPO_URL}}        -> GitHub repository base URL
       {{VERSION}}         -> Version number (e.g. 1.00.00)
       {{UNOFFICIAL_BANNER}} -> Empty string OR unofficial warning banner
       {{RELEASE_NOTES}}   -> Additional release notes or default placeholder
=========================================================================== -->

{{UNOFFICIAL_BANNER}}
<p align="center">
  <img src="{{LOGO_URL}}" alt="WinISO.ScriptFXLib Logo" width="480" />
</p>

## 🖥️ **File Download:**

**📦 [`{{ZIP_FILENAME}}`]({{DOWNLOAD_URL}})**
<br>

## ℹ️ System Requirements:
- Windows 10 / Windows 11
- PowerShell 5.1 or higher
- No administrator privileges required for standard usage
<br>

## 🪛 Installation / Usage:

### 📂 Option A — Direct Import *(local, no installation required)*:
1. Download the ZIP archive from the link above.
2. Extract the archive to a location of your choice.
3. Open PowerShell and navigate to the extracted folder.
4. Import the module directly for the current session:
   ```powershell
   Import-Module .\WinISO.ScriptFXLib.psm1
   ```
5. Refer to the included `README.md` and the `Examples\` folder for detailed usage instructions.

### 🌍 Option B — Global Module Installation *(persistent, user-wide)*:
1. Download and extract the ZIP archive.
2. Determine your personal PowerShell module directory:
   ```powershell
   # Lists all module paths — look for the user-specific path, e.g.:
   # C:\Users\<YourName>\Documents\PowerShell\Modules
   $env:PSModulePath -split ';'
   ```
3. Inside that `Modules` directory, create a new subfolder named exactly `WinISO.ScriptFXLib`.
4. Copy all extracted files into that new subfolder.
5. The module is now permanently available in every PowerShell session:
   ```powershell
   # Auto-discovery works as long as folder name matches the .psm1 filename
   Import-Module WinISO.ScriptFXLib
   ```
6. To verify the installation:
   ```powershell
   Get-Module -ListAvailable WinISO.ScriptFXLib
   ```
<br>

## 📜 License/Copyright:

**WinISO.ScriptFXLib** is licensed for **private, non-commercial use only**.

- ❌ Commercial use of any kind is strictly prohibited.
- ❌ Editing, modifying, or manipulating this software in any form or manner without the explicit written consent of the developer is not permitted.
- ⚠️ Use of WinISO.ScriptFXLib is entirely at the user's own risk. No liability is assumed for any damage to hardware and/or software that may occur.
- ⚠️ Any consequences arising from the use of WinISO.ScriptFXLib are solely the responsibility of the user.

> **WinISO.ScriptFXLib™** · © 2026 by Praetoriani · All rights reserved.
<br>

## 🛟 Security Advise:

> ⚠️ **Important:** The official and only trusted source for WinISO.ScriptFXLib is:
>
> 🔗 **[https://github.com/praetoriani/PowerShell.Mods/tree/main/WinISO.ScriptFXLib](https://github.com/praetoriani/PowerShell.Mods/tree/main/WinISO.ScriptFXLib)**
>
> It is **strongly recommended** to download WinISO.ScriptFXLib **exclusively** from this official source. Do not use copies from unknown or untrusted third-party sources, as these may have been tampered with or contain malicious code.
<br>

## 📝 Additional Notes:

{{RELEASE_NOTES}}
<br>

---
Made with 💖 in Munich (Bavaria, Germany)
