# PSAppCoreLib PowerShell Module

## Overview

PSAppCoreLib is a comprehensive PowerShell module that provides a collection of useful functions for PowerShell application development. This module includes advanced functions for logging, registry management, file and directory operations, process control, Windows service management and icon extraction.

## Module Information

- **Name**: PSAppCoreLib
- **Version**: 1.06.00  
- **Author**: Praetoriani (a.k.a. M.Sczepanski)
- **Website**: [github.com/praetoriani](https://github.com/praetoriani)
- **Root Module**: PSAppCoreLib.psm1
- **Description**: Powerful collection of useful Windows system functions for PowerShell apps

## Requirements

- **PowerShell**: Version 5.1 oder höher
- **.NET Framework**: 4.7.2 oder höher (für Windows PowerShell)
- **PowerShell Core**: Unterstützt auf allen Plattformen
- **Required Assemblies**: System.Drawing, System.Windows.Forms

## Installation

### Manuelle Installation

1. Repository klonen oder ZIP herunterladen
2. Einen Ordner `PSAppCoreLib` in einem der PowerShell Modulpfade anlegen:
   - `$env:PSModulePath -split ';'` (Windows)
   - `$env:PSModulePath -split ':'` (Linux/macOS)
3. Alle Dateien aus `PSAppCoreLib` in diesen Ordner kopieren
4. Modul importieren: `Import-Module PSAppCoreLib`

### (Zukünftig) PowerShell Gallery Installation

```powershell
# Sobald das Modul in der Gallery veröffentlicht ist
Install-Module -Name PSAppCoreLib -Scope CurrentUser
```

## Module Structure

```text
PSAppCoreLib/
├── Private/                    # Interne Helper-Funktionen (nicht exportiert)
│   └── OPSreturn.ps1           # Standardisiertes Return-Objekt (code/msg/data)
├── Public/                     # Öffentliche Funktionen (werden exportiert)
│   ├── Registry Management
│   │   ├── CreateRegKey.ps1
│   │   ├── CreateRegVal.ps1
│   │   ├── DeleteRegKey.ps1
│   │   ├── DeleteRegVal.ps1
│   │   ├── GetRegEntryType.ps1
│   │   ├── GetRegEntryValue.ps1
│   │   └── SetNewRegValue.ps1
│   ├── File & Directory Management
│   │   ├── CreateNewDir.ps1
│   │   ├── CreateNewFile.ps1
│   │   ├── CopyDir.ps1
│   │   ├── RemoveDir.ps1
│   │   ├── RemoveDirs.ps1
│   │   ├── CopyFile.ps1
│   │   ├── CopyFiles.ps1
│   │   ├── RemoveFile.ps1
│   │   ├── RemoveFiles.ps1
│   │   ├── WriteTextToFile.ps1
│   │   └── ReadTextFile.ps1
│   ├── Special System Management
│   │   ├── RemoveOnReboot.ps1
│   │   └── RemoveAllOnReboot.ps1
│   ├── Process Management
│   │   ├── RunProcess.ps1
│   │   ├── GetProcessByName.ps1
│   │   ├── GetProcessByID.ps1
│   │   ├── RestartProcess.ps1
│   │   ├── StopProcess.ps1
│   │   └── KillProcess.ps1
│   ├── Service Management
│   │   ├── StartService.ps1
│   │   ├── RestartService.ps1
│   │   ├── ForceRestartService.ps1
│   │   ├── StopService.ps1
│   │   ├── KillService.ps1
│   │   └── SetServiceState.ps1
│   ├── Logging
│   │   └── WriteLogMessage.ps1
│   └── Misc
│       └── GetBitmapIconFromDLL.ps1
├── Examples/                   # Ausführliche Anwendungsbeispiele
│   ├── 01_Registry_Management_Examples.ps1
│   ├── 02_File_Directory_Management_Examples.ps1
│   ├── 03_Process_Service_Management_Examples.ps1
│   ├── WriteLogMessage_Examples.ps1
│   └── GetBitmapIconFromDLL_Examples.ps1
├── PSAppCoreLib.psm1          # Hauptmodul (lädt Public/Private Funktionen)
├── PSAppCoreLib.psd1          # Modul-Manifest (Version 1.06.00)
└── README.md                   # Diese Datei
```

## Standardisiertes Return-Objekt (OPSreturn)

Alle Funktionen im Modul verwenden ein einheitliches Rückgabeobjekt, das von der privaten Helper-Funktion `OPSreturn` erzeugt wird:

```powershell
$status = OPSreturn -Code 0 -Message "Operation completed" -Data $someData
```

Das Objekt hat immer die Form:

```powershell
[PSCustomObject]@{
    code = 0      # 0 = Erfolg, -1 = Fehler
    msg  = ""     # Fehlerbeschreibung oder leer bei Erfolg
    data = $null  # Optionales Payload-Objekt (Dateipfade, Handles, Inhalte,...)
}
```

Dadurch kannst Du in Deinem Code konsistent prüfen:

```powershell
$result = CreateNewDir -Path "C:\Temp\Test"
if ($result.code -eq 0) {
    Write-Host "OK" -ForegroundColor Green
} else {
    Write-Warning $result.msg
}
```

## Function Overview (Version 1.06.00)

### Registry Management

- **CreateRegKey**  
  Erstellt neue Registry-Schlüssel mit Validierung (inkl. Schutz kritischer Pfade).

- **CreateRegVal**  
  Erstellt Registry-Werte aller gängigen Typen (String, ExpandString, DWord, QWord, MultiString, Binary).

- **DeleteRegKey**  
  Löscht Registry-Schlüssel optional rekursiv. Unterstützt `-WhatIf`/`-Confirm`.

- **DeleteRegVal**  
  Löscht einzelne Registry-Werte.

- **GetRegEntryValue**  
  Liest Registry-Werte typ-sensitiv aus und gibt den tatsächlichen .NET-Typ im `data`-Feld zurück.

- **GetRegEntryType**  
  Liefert den Registry-Typ (z.B. `REG_SZ`, `REG_DWORD`, `REG_MULTI_SZ`).

- **SetNewRegValue**  
  Aktualisiert existierende Registry-Werte mit Validierung und Typkonvertierung.

**Typische Rückgabe:**
```powershell
$result = GetRegEntryValue -KeyPath "HKCU:\Software\MyApp" -ValueName "Setting1"
$result.code  # 0 oder -1
$result.msg   # Fehlertext oder leer
$result.data  # Der gelesene Registry-Wert
```

### File & Directory Management

- **CreateNewDir**  
  Erstellt neue Verzeichnisse (lokal oder UNC), inkl. Parent-Creation, Reserved-Name-Checks, Längenprüfung.

- **CreateNewFile**  
  Erstellt neue Dateien mit optionalem Inhalt und definierbarer Kodierung (UTF8, ASCII, Unicode...).

- **CopyDir**  
  Kopiert komplette Verzeichnisbäume rekursiv, mit Exclude-Patterns und Zeitstempel-Übernahme.

- **CopyFile / CopyFiles**  
  Kopieren einzelne bzw. mehrere Dateien, inkl. detailliertem Reporting und StopOnError-Logik.

- **RemoveDir / RemoveDirs**  
  Löschen sichere Verzeichnis-Operationen mit Schutzsystem für kritische Pfade und wahlweise rekursiv.

- **RemoveFile / RemoveFiles**  
  Entfernen einzelne oder mehrere Dateien mit detailliertem Status.

- **WriteTextToFile**  
  Schreibt Text mit gewünschter Kodierung in Dateien, optional im Override-Modus.

- **ReadTextFile**  
  Liest Textdateien vollständig mit definierter Kodierung und liefert den Inhalt im `data`-Feld.

### Special System Management

- **RemoveOnReboot**  
  Plant einzelne Dateien/Verzeichnisse zur Löschung beim nächsten Neustart (PendingFileRenameOperations).

- **RemoveAllOnReboot**  
  Markiert komplette Verzeichnisse inklusive Inhalt zur Entfernung beim nächsten Reboot.

### Process Management

- **RunProcess**  
  Startet einen Prozess, optional mit Argumenten und optionalem Warten auf Beendigung.  
  Liefert z.B. die ProcessId im `data`-Feld.

- **GetProcessByName**  
  Liefert den Prozess (oder seine ID) anhand des exakten Namens.

- **GetProcessByID**  
  Liefert einen Prozess anhand der PID (inkl. Handle).

- **RestartProcess**  
  Stoppt und startet einen Prozess mit gleicher CommandLine neu.

- **StopProcess**  
  Versucht einen Prozess „graceful“ zu stoppen.

- **KillProcess**  
  Erzwingt die sofortige Beendigung eines Prozesses.

### Service Management

- **StartService**  
  Startet einen Windows Dienst per Name.

- **RestartService**  
  Startet einen Dienst neu (Stop + Start).

- **ForceRestartService**  
  Erzwingt einen Neustart inkl. Kill im Fehlerfall.

- **StopService**  
  Stoppt einen Dienst regulär.

- **KillService**  
  Beendet den Prozess eines Dienstes hart.

- **SetServiceState**  
  Setzt den Starttyp eines Dienstes (Disabled, Manual, Automatic, AutomaticDelayed).

### Logging

- **WriteLogMessage**  
  Schreibt formatierte Log-Zeilen mit Zeitstempel und Flag (INFO/DEBUG/WARN/ERROR).
  Rückgabe enthält im `data`-Feld die tatsächlich geschriebene Log-Zeile.

### Miscellaneous

- **GetBitmapIconFromDLL**  
  Extrahiert Icons aus DLLs und liefert ein `System.Drawing.Bitmap`-Objekt im `data`-Feld.

## Examples

Neben den ursprünglichen Beispielskripten gibt es zusätzliche, thematisch gruppierte Example-Skripte im Ordner `Examples`:

- `01_Registry_Management_Examples.ps1` – Komplettes Registry-Demo-Szenario
- `02_File_Directory_Management_Examples.ps1` – Datei- und Ordner-Workflows
- `03_Process_Service_Management_Examples.ps1` – Prozesse & Dienste steuern
- `WriteLogMessage_Examples.ps1` – Logging Pattern
- `GetBitmapIconFromDLL_Examples.ps1` – Icon Extraktion & Speicherung

Beispiel: Registry Management Demo starten

```powershell
Import-Module PSAppCoreLib -Force
& "$PSScriptRoot\Examples\01_Registry_Management_Examples.ps1"
```

Beispiel: Datei-/Verzeichnis-Operations-Demo

```powershell
Import-Module PSAppCoreLib -Force
& "$PSScriptRoot\Examples\02_File_Directory_Management_Examples.ps1"
```

## Error Handling

Durch `OPSreturn` ist das Fehlerhandling überall identisch:

```powershell
$result = RunProcess -FilePath "notepad.exe"
if ($result.code -ne 0) {
    Write-Error "Failed to start process: $($result.msg)"
    return
}

# Erfolg – weiter mit Payload im data-Feld
$pid = $result.data
```

## Advanced Function Features

Alle Funktionen sind als Advanced Functions implementiert und bieten:

- **[CmdletBinding()]** mit gutem Pipeline- und Parameterverhalten
- **Parameter Validation** (ValidateSet, ValidateNotNullOrEmpty, etc.)
- **Verbose Output** via `Write-Verbose`
- **Sauberes Fehlerhandling** mittels Try/Catch und OPSreturn
- **Hilfetexte** im PowerShell-Standardformat (Get-Help kompatibel)

## Typical Usage

```powershell
# Modul laden
Import-Module PSAppCoreLib

# Verfügbare Funktionen anzeigen
Get-Command -Module PSAppCoreLib

# Hilfe für eine Funktion
Get-Help CreateNewDir -Full

# Beispiel: Verzeichnis anlegen
$result = CreateNewDir -Path "C:\Temp\MyApp"
if ($result.code -eq 0) {
    Write-Host "Created: $($result.data)" -ForegroundColor Green
} else {
    Write-Warning $result.msg
}
```

## Version History

### Version 1.06.00 (Windows Service Management)
- StartService / RestartService / ForceRestartService
- StopService / KillService / SetServiceState
- Erweiterte Beispiele für Prozesse & Dienste

### Version 1.05.00 (Process Management)
- RunProcess, GetProcessByName, GetProcessByID
- RestartProcess, StopProcess, KillProcess

### Version 1.04.00 (Extended File Operations & Reboot Scheduling)
- CopyFile, CopyFiles, RemoveFile, RemoveFiles
- WriteTextToFile, ReadTextFile
- RemoveOnReboot, RemoveAllOnReboot

### Version 1.03.00 (File System Management)
- CreateNewDir, CreateNewFile, CopyDir, RemoveDir, RemoveDirs

### Version 1.02.00 (Extended Registry Management)
- DeleteRegKey, DeleteRegVal, GetRegEntryValue, GetRegEntryType, SetNewRegValue

### Version 1.01.00 (Registry Functions Update)
- CreateRegKey, CreateRegVal

### Version 1.00.00 (Initial Release)
- WriteLogMessage
- GetBitmapIconFromDLL

---

*Updated: 02 February 2026*  
*Author: Praetoriani (a.k.a. M.Sczepanski)*  
*Website: [github.com/praetoriani](https://github.com/praetoriani)
