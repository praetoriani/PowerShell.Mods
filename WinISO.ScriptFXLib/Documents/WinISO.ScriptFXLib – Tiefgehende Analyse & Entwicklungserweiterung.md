# WinISO.ScriptFXLib – Tiefgehende Analyse & Entwicklungserweiterung

## Modulübersicht & Architekturanalyse

Das Modul `WinISO.ScriptFXLib` (v1.00.03) ist ein PowerShell-Modul für die vollautomatisierte Erstellung, Anpassung und Neuerstellung von bootfähigen Windows 11 Pro Setup-ISO-Dateien. Die Architektur trennt strikt zwischen **Public**-Funktionen (15 Dateien, alle exportiert) und **Private**-Funktionen (6 Dateien, intern), was dem PowerShell-Best-Practice-Muster für Module entspricht.

Das Herzstück des Moduls bilden vier Schlüsselkomponenten:

- **`$script:appenv`** – Hashtable mit allen Umgebungspfaden (ISOroot, MountPoint, OscdimgExe etc.)
- **`$script:appinfo`** – Metadaten des Moduls (Name, Version, Autor)
- **`$script:appcore`** – Core-Konfiguration inkl. Download-URLs für Abhängigkeiten
- **`WinISOcore`** – Type-sicherer Read/Write-Accessor für alle Script-Scope-Variablen

Das Rückgabemuster aller Funktionen ist vollständig vereinheitlicht: `OPSreturn` liefert immer ein `PSCustomObject { .code, .msg, .data }`, wobei `.code = 0` Erfolg und `.code = -1` Fehler signalisiert. Dieses Muster garantiert, dass aufrufender Code immer `$r.code -eq 0` prüfen kann, unabhängig davon welche Funktion aufgerufen wurde.

***

## Analysebefund: InitializeEnvironment (Ist-Zustand)

Die aktuelle Implementierung von `InitializeEnvironment` weist mehrere konzeptionelle Schwächen auf:

1. **Blindes Force-Create**: Jedes Verzeichnis wird via `New-Item -Force` erstellt, ohne vorher zu prüfen, ob es bereits existiert. Dies ist nicht idempotent und kann bei einer Reparatur einer teilweise bestehenden Umgebung irreführende Logs produzieren.
2. **Sofortiger Abbruch bei erstem Fehler**: Jedes `if ($null -eq $makedir)` ruft direkt `return` auf. Sobald ein Verzeichnis scheitert, bricht die Funktion ab und alle nachfolgenden Verzeichnisse werden nicht mehr geprüft oder angelegt.
3. **Keine Ergebnisaggregation**: Im Gegensatz zu `CheckModuleRequirements` (das `CriticalFails` zählt und erst am Ende returniert) gibt `InitializeEnvironment` keine strukturierten Einzelergebnisse zurück.
4. **Fehlerhafter GitHubDownload-Aufruf**: `$DownloadResult -ne 0` vergleicht ein `PSCustomObject` mit einer Zahl — korrekt wäre `$DownloadResult.code -ne 0`.
5. **Kein Kontext-Check**: Die Funktion ermittelt nicht, ob das aufrufende Skript bereits im ISOroot-Verzeichnis liegt, was eine wertvolle Vorabvalidierung wäre.

***

## Redesign: InitializeEnvironment (Soll-Konzept)

Das überarbeitete Design orientiert sich vollständig am **`CheckModuleRequirements`-Pattern**: Ein `$Results`-`List[PSCustomObject]`-Collector sammelt alle Einzelergebnisse, `$FailureCount` zählt Fehler, und am Ende wird **ein einziges** `OPSreturn` zurückgegeben.

### Ausführungslogik (5 Stufen)

| Stufe | Aktion | Besonderheit |
|-------|--------|--------------|
| 1 | Caller-Verzeichnis ermitteln | `$MyInvocation.PSScriptRoot` → `$PSScriptRoot` → `GetCurrentDirectory()` |
| 2 | ISOroot verifizieren/erstellen | Sonderfall: Caller liegt *in* ISOroot → Verzeichnis ist bewiesen vorhanden |
| 3 | Alle Env-Verzeichnisse prüfen/erstellen | `installwim` wird **explizit ausgelassen** (WIM erst beim Mount nötig) |
| 4 | OEM-Unterverzeichnisse (`root`, `windir`) | Nur erstellen, wenn `OEMfolder` erfolgreich erstellt/vorhanden |
| 5 | `oscdimg.exe` verifizieren/downloaden | Bei Fehlen: `GitHubDownload` mit `$appcore['requirement']['oscdimg']` |

**Gesamterfolg** = `$FailureCount -eq 0` → alle Verzeichnisse vorhanden UND `oscdimg.exe` vorhanden/erfolgreich heruntergeladen.

### Warum `installwim` ausgelassen wird

`$script:appenv['installwim']` zeigt auf `C:\WinISO\DATA\sources\install.wim`. Diese Datei entsteht erst, wenn ein UUP-Dump-ISO gemountet und kopiert wurde. `InitializeEnvironment` richtet lediglich die *Verzeichnisstruktur* ein — das Vorhandensein des WIM-Images ist ausschließlich für `MountWIMimage` relevant.

***

## Neue Funktionsgruppe: Registry Hive Management

Der konzeptionelle Kontext: Mit DISM wird ein Windows-Image in `$script:appenv['MountPoint']` gemountet. Die dort liegende Registry (offline Hive-Dateien unter `MountPoint\Windows\System32\config\`) kann über `reg.exe LOAD` in die laufende Registry eingehängt werden, um Schlüssel und Werte direkt zu modifizieren, ohne das Image zu booten.

### Hive-Dateipfade im gemounteten Image

| Hive-Name | Quelle innerhalb von MountPoint |
|-----------|----------------------------------|
| `SOFTWARE` | `Windows\System32\config\SOFTWARE` |
| `SYSTEM` | `Windows\System32\config\SYSTEM` |
| `DEFAULT` | `Windows\System32\config\DEFAULT` |
| `NTUSER` | `Users\Default\NTUSER.DAT` |

Nach dem `LOAD`-Befehl sind diese Hives unter `HKLM:\WinISO_<Name>` erreichbar, was Konflikte mit Systemhives ausschließt.

***

## LoadRegistryHive — Design & Implementierung

### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|--------------|
| `HiveID` | `string` | ✅ Mandatory | Hive-Name (`SOFTWARE`, `SYSTEM`, `DEFAULT`, `NTUSER`) oder `ALL` |

### Kernlogik

1. **MountPoint-Validierung**: `$appenv['MountPoint']` muss existieren und ein `Windows`-Unterverzeichnis enthalten — andernfalls ist kein Image gemountet.
2. **Hive-Map**: Statische Hashtable mit den vier bekannten Hive-Namen → Dateipfaden.
3. **`ALL`-Expansion**: Wenn `HiveID = 'ALL'`, wird die gesamte `$HiveMap` iteriert.
4. **Unbekannte Namen**: Sofort `OPSreturn -Code -1` mit Liste der gültigen Namen.
5. **Idempotenz**: Ist ein Hive bereits in `$script:LoadedHives` eingetragen, wird er übersprungen (`SKIP`-Status) — kein Fehler, keine doppelte Registrierung.
6. **Tracker**: `$script:LoadedHives` (Script-Scope Hashtable) speichert `HiveName → RegMountKey` für spätere Verwendung durch `UnloadRegistryHive`.
7. **reg.exe LOAD**: Ausführung mit splatting `@RegArgs`, Exit-Code-Auswertung via `$LASTEXITCODE`.

### Fehlerbehandlung

Die Funktion gilt als **FAIL**, wenn auch nur ein einzelner Hive-Load scheitert. Dies entspricht dem Konzept: Eine unvollständig geladene Hive-Gruppe ist für Registry-Operationen nicht zuverlässig nutzbar.

***

## UnloadRegistryHive — Design & Implementierung

### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|--------------|
| `HiveID` | `string` | ❌ Optional | Hive-Name zum Entladen. Ohne Angabe: alle geladenen Hives |

### Auto-Discovery-Modus

Der wichtigste Anwendungsfall ist der parameterlose Aufruf **direkt vor `UnMountWIMimage`**. Die Funktion durchsucht `$script:LoadedHives` und unlädt alle dort eingetragenen Hives automatisch. Dies verhindert, dass beim WIM-Dismount noch offene Registry-Handles einen Fehler verursachen.

### GC-Trick für Registry-Handles

```powershell
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
```

Dieser Block wird **vor jedem `reg.exe UNLOAD`** ausgeführt. PowerShell 5.1 (und gelegentlich auch PS 7.x) hält bei Registry-Zugriffen über den PS-Provider oder .NET manchmal Handles auf geöffnete Schlüssel. Der GC-Pass zwingt das .NET-Runtime, diese Finalizer auszuführen und die Handles freizugeben, bevor `reg.exe` versucht, den Hive zu entladen.

***

## ValidateRegFile (Private) — Prüfstrategie

Diese private Hilfsfunktion wird ausschließlich von `RegistryHiveImport` aufgerufen und führt bis zu **6 Prüfungen** durch:

| Prüfung | Kriterium | Relevanz |
|---------|-----------|----------|
| 1 | Datei existiert + `.reg`-Extension | Grundvoraussetzung |
| 2 | Datei nicht leer (≥1 Non-Blank-Line) | Korrupte/leere Exporte erkennen |
| 3 | Header = `Windows Registry Editor Version 5.00` | REG4-Format ausschließen |
| 4 | Mindestens ein Key-Header (`
Der **Encoding-Fallback** ist wichtig: `.reg`-Dateien die von `reg.exe EXPORT` erzeugt werden, sind standardmäßig UTF-16 LE. Die Funktion versucht zunächst Unicode-Lesen und fällt bei unbrauchbarem Ergebnis auf UTF-8 zurück.

***

## RegistryHiveAdd — Design

### Verhalten je nach Parameterkombination

| Übergabe | Ergebnis |
|----------|----------|
| Nur `KeyPath` | Nur den Key erstellen (idempotent) |
| `KeyPath` + `ValueName` + `ValueData` + `ValueType` | Key erstellen (falls nötig) + Value setzen |
| `KeyPath` + `ValueName` ohne `ValueData` | Fehler: `ValueData` darf nicht `$null` sein |

### `-Force` Semantik

Ohne `-Force` schlägt die Funktion fehl, wenn ein Value mit demselben Namen bereits existiert. Mit `-Force` wird überschrieben. Dies entspricht dem PowerShell-Standard (`New-ItemProperty -Force`).

### Pfad-Normalisierung

```powershell
$PSHivePath  = $HiveMountPath -replace 'HKLM\\', 'HKLM:\'
$FullKeyPath = Join-Path $PSHivePath $KeyPath.TrimStart('\/')
```

`reg.exe` arbeitet mit `HKLM\WinISO_SOFTWARE`, der PS-Provider braucht `HKLM:\WinISO_SOFTWARE`. Diese Konversion ist in allen Registry-Funktionen einheitlich implementiert.

***

## RegistryHiveRem — Design

Zwei Modi:

- **Value-Modus** (`ValueName` angegeben): Nur den benannten Wert entfernen, Key bleibt intakt.
- **Key-Modus** (`ValueName` leer): Gesamten Key-Baum inkl. aller Subkeys und Values löschen (`Remove-Item -Recurse -Force`).

Der `-IgnoreMissing`-Switch ermöglicht idempotente Cleanup-Skripte: wenn ein Key/Value bereits gelöscht ist, wird trotzdem `code = 0` zurückgegeben.

***

## RegistryHiveImport — Zwei-Phasen-Design

```
Phase 1: ValidateRegFile  ──(FAIL)──► OPSreturn -Code -1, kein Import
              │
           (PASS)
              │
Phase 2: reg.exe IMPORT ──(FAIL)──► OPSreturn -Code -1
              │
           (PASS)
              │
         OPSreturn -Code 0
```

Das Ergebnis aus `ValidateRegFile` (`$ValidationResult.data`) wird immer mit in `.data` zurückgegeben, auch im Fehlerfall — so kann der Aufrufer die genauen Validierungsfehler inspizieren.

### `-ValidateHiveTarget` Switch

Dieser Switch aktiviert Prüfung #6 in `ValidateRegFile`. Der übergebene `HivePrefix` lautet `"WinISO_$HiveIDNorm"`. Wenn ein `.reg`-File Keys für `HKLM\SOFTWARE\...` statt `HKLM\WinISO_SOFTWARE\...` enthält, schlägt der Import **vor** der Ausführung fehl — verhindert ungewollte Schreiboperationen in den falschen Hive.

***

## RegistryHiveExport — Implementierungsdetails

Der Export via `reg.exe EXPORT` schreibt UTF-16 LE kodierte `.reg`-Dateien. Das `/y`-Flag (nur bei `-Force`) verhindert den interaktiven Überschreib-Dialog. Der exportierte Pfad hat das Format `HKLM\WinISO_SOFTWARE\<KeyPath>` — genau das Format, das `ValidateRegFile` bei einem späteren Re-Import mit `-ValidateHiveTarget` erwartet.

***

## RegistryHiveQuery — Dual-Mode

### KEY-Modus (kein `ValueName`)

Öffnet den Schlüssel via `.NET` (`[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey()`), um exakte Typinformationen zu erhalten. `GetValueKind()` liefert den echten `RegistryValueKind`-Enum (`DWord`, `ExpandString` etc.), den `Get-ItemProperty` allein nicht immer korrekt zurückgibt.

`.data.Values` ist eine Hashtable: `ValueName → { Data, Type }`. `.data.SubKeys` ist ein `string[]` mit den Namen aller direkten Unterkeys.

### VALUE-Modus (`ValueName` angegeben)

Verwendet ebenfalls `OpenSubKey()` mit `GetValueKind()` und `GetValue(..., DoNotExpandEnvironmentNames)` — letzteres ist wichtig, um den Rohwert von `ExpandString`-Werten zu erhalten, anstatt expandierter Umgebungsvariablen.

***

## Änderungen am Modul-Manifest (psd1)

Um alle neuen Funktionen korrekt zu exportieren, muss `WinISO.ScriptFXLib.psd1` aktualisiert werden:

### FunctionsToExport — Ergänzungen

```powershell
FunctionsToExport = @(
    # Core / Infrastructure
    'AppScope',
    'InitializeEnvironment',
    'VerifyEnvironment',
    'CheckModuleRequirements',
    'WinISOcore',

    # Logging
    'WriteLogMessage',

    # Download helpers
    'GitHubDownload',
    'GetLatestPowerShellSetup',

    # UUP Dump workflow
    'DownloadUUPDump',
    'ExtractUUPDump',
    'CreateUUPDiso',
    'CleanupUUPDump',
    'RenameUUPDiso',
    'ExtractUUPDiso',

    # WIM image operations
    'ImageIndexLookup',
    'MountWIMimage',
    'UnMountWIMimage',

    # Registry Hive Operations   ← NEU
    'LoadRegistryHive',
    'UnloadRegistryHive',
    'RegistryHiveAdd',
    'RegistryHiveRem',
    'RegistryHiveImport',
    'RegistryHiveExport',
    'RegistryHiveQuery'
)
```

### FileList — Ergänzungen

```powershell
# Private (NEU)
'Private\ValidateRegFile.ps1',

# Public (NEU)
'Public\LoadRegistryHive.ps1',
'Public\UnloadRegistryHive.ps1',
'Public\RegistryHiveAdd.ps1',
'Public\RegistryHiveRem.ps1',
'Public\RegistryHiveImport.ps1',
'Public\RegistryHiveExport.ps1',
'Public\RegistryHiveQuery.ps1'
```

### ModuleVersion

```powershell
ModuleVersion = '1.00.04'
```

***

## Empfohlener Workflow: Registry-Hives bearbeiten

```powershell
# 1. Umgebung sicherstellen
$env = InitializeEnvironment
if ($env.code -ne 0) { throw $env.msg }

# 2. WIM mounten
$mount = MountWIMimage -ImageIndex 1
if ($mount.code -ne 0) { throw $mount.msg }

# 3. Hives laden
$load = LoadRegistryHive -HiveID 'ALL'
if ($load.code -ne 0) { throw $load.msg }

# 4. Registry-Operationen durchführen
RegistryHiveAdd -HiveID 'SOFTWARE' `
    -KeyPath 'MyCompany\MyApp' `
    -ValueName 'SilentInstall' -ValueData 1 -ValueType 'DWord'

RegistryHiveImport -HiveID 'SOFTWARE' `
    -RegFilePath 'C:\WinISO\Configs\tweaks.reg' `
    -ValidateHiveTarget

$q = RegistryHiveQuery -HiveID 'SOFTWARE' `
    -KeyPath 'Microsoft\Windows NT\CurrentVersion' `
    -ValueName 'CurrentBuild'
Write-Host "Build: $($q.data.ValueData)"

# 5. IMMER VOR DISMOUNT: Hives entladen
$unload = UnloadRegistryHive   # alle, kein Parameter
if ($unload.code -ne 0) { throw $unload.msg }

# 6. WIM dismounten (mit Commit)
UnMountWIMimage -Commit
```

***

## Wichtige Hinweise & Einschränkungen

### Administrator-Rechte

Alle Registry-Hive-Operationen (LOAD, UNLOAD, Schreibzugriff auf HKLM) erfordern eine **erhöhte PowerShell-Sitzung** (Run as Administrator). `CheckModuleRequirements` prüft dies explizit.

### $script:LoadedHives Lifetime

Der `$script:LoadedHives`-Tracker existiert nur während der Modulsitzung. Bei einem `Remove-Module WinISO.ScriptFXLib` oder Neustart der PowerShell-Sitzung gehen die Tracking-Informationen verloren. Hives die über ein `reg.exe LOAD` manuell geladen wurden, bleiben jedoch in der Registry **bis zum nächsten Neustart** oder expliziten UNLOAD erhalten. Es empfiehlt sich, `UnloadRegistryHive` immer im `finally`-Block oder als letzten Schritt vor dem WIM-Dismount aufzurufen.

### reg.exe vs. PS-Provider

Die Funktionen verwenden **beide** Mechanismen gezielt:
- `reg.exe LOAD/UNLOAD/IMPORT/EXPORT` → Aktionen die keine PS-Provider-Entsprechung haben
- `New-Item / New-ItemProperty / Remove-Item / Remove-ItemProperty / Get-ItemProperty` → PS-Provider für Key/Value-CRUD (besser in Skripte integrierbar, Exception-sicher)
- `[Microsoft.Win32.Registry]` .NET-API → für exakte Typinformationen (Query)

### OEM-Verzeichnisse

`InitializeEnvironment` erstellt `OEM\root` und `OEM\windir` nur dann, wenn `OEMfolder` selbst erfolgreich vorhanden ist. Falls `OEMfolder` fehlschlägt und `$FailureCount` erhöht wird, werden die Unterverzeichnisse trotzdem versucht (kein früher Abbruch) — da `OEMfolder` als Basispfad für `Join-Path` dient, schlägt `New-Item` dann mit einem klaren Fehler fehl, der protokolliert wird.