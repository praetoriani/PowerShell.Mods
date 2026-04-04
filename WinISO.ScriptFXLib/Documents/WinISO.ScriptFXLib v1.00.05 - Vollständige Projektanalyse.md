# WinISO.ScriptFXLib — Vollständige Projektanalyse

> **Repository:** [praetoriani/PowerShell.Mods · WinISO.ScriptFXLib](https://github.com/praetoriani/PowerShell.Mods/tree/main/WinISO.ScriptFXLib)
> **Stand der Analyse:** 04.04.2026 — Version 1.00.05

***

## 1. Zusammenfassung des aktuellen Projektstandes

### Projektidentität und Zweck

**WinISO.ScriptFXLib** ist ein PowerShell-Modul (`.psm1` + `.psd1`) das eine vollständig automatisierbare Pipeline zum Herunterladen, Anpassen und Neuerstellen von bootfähigen Windows-11-Setup-ISO-Dateien bereitstellt. Das Modul nutzt [UUP Dump](https://uupdump.net), DISM und `oscdimg.exe` als technische Grundlage und richtet sich sowohl an PowerShell 5.1 (Desktop Edition) als auch an PowerShell 7.x (Core Edition).

Die Entwicklung begann am **28.03.2026** mit dem initialen Projekt-Bootstrap (v1.00.00) und erreichte am **04.04.2026** — also in nur sieben Tagen — bereits Version **1.00.05** mit 26 exportierten Public-Funktionen und 7 Private-Helpern. Die Commit-Historie zeigt eine intensive, täglich aktive Entwicklung mit klar strukturierten Conventional-Commit-Nachrichten wie `feat(v1.00.05):` und `docs(v1.00.05):`.

### Versionsverlauf auf einen Blick

| Version | Datum | Inhalt |
|---------|-------|--------|
| 1.00.00 | 28.03.2026 | Projekt-Bootstrap: Modulstruktur, Scope-Variablen, README-Stub |
| 1.00.01 | 28.03.2026 | `InitializeEnvironment`, `VerifyEnvironment`, `GitHubDownload`, `WriteLogMessage`, `OPSreturn` |
| 1.00.02 | 28.03.2026 | `DownloadUUPDump`, `ExtractUUPDump`, `CleanupUUPDump`, `RenameUUPDiso`, `ExtractUUPDiso` |
| 1.00.03 | 29.03.2026 | `GetLatestPowerShellSetup`, `CreateUUPDiso` (7-Layer-Monitoring), `WinISOcore`, `ImageIndexLookup`, `MountWIMimage`, `UnMountWIMimage`, `CheckModuleRequirements` |
| 1.00.04 | 30.03.2026 | Komplette Registry-Hive-Operationen (7 Funktionen), Private Helper `ValidateRegFile` |
| 1.00.05 | 04.04.2026 | Appx/MSIX-Paket-Operationen (4 Funktionen), Multi-Edition-Download, Bug-Fixes, DEVGUIDE.md, CHANGELOG.md |

### Modularchitektur

Das Modul ist sauber in **Public/** (exportierte Funktionen) und **Private/** (interne Helper) getrennt. Das Root-Modul `WinISO.ScriptFXLib.psm1` dot-sourced alle `.ps1`-Dateien automatisch — neue Funktionen werden lediglich in das entsprechende Unterverzeichnis gelegt und im Manifest `FunctionsToExport` eingetragen, ohne dass `.psm1` bearbeitet werden muss.

```
WinISO.ScriptFXLib\
├── WinISO.ScriptFXLib.psm1   ← Scope-Init + Auto-Loader
├── WinISO.ScriptFXLib.psd1   ← Manifest (Version, Exports)
├── CHANGELOG.md / DEVGUIDE.md / README.md
├── Public\  (26 exportierte Funktionen)
├── Private\ (7 interne Helper)
├── Examples\
├── Requirements\ (oscdimg.exe, ADK-Setup, .NET 4.8-Installer)
└── Ressources\  (Logo-Assets)
```

### Modul-Scope-Variablen

Das Modul verwaltet sieben `$script:`-Scope-Variablen, auf die ausschließlich über die typsichere `WinISOcore`-Funktion geschrieben werden soll:

| Variable | Zweck |
|----------|-------|
| `$script:appinfo` | Modulmetadaten (Name, Version, Autor, Website) |
| `$script:appenv` | 14 Arbeitspfade (ISOroot, MountPoint, LogfileDir, AppxBundle, OEMDrivers …) |
| `$script:appcore` | Core-Pfade, Log-Dateinamen, Tool-Download-URLs |
| `$script:appverify` | Ergebnisse des Requirement-Checks (PASS/FAIL/INFO/WARN + Zähler) |
| `$script:LoadedHives` | Geladene offline Registry-Hives (HiveName → HKLM-Mountkey) |
| `$script:uupdump` | UUPDump-Download-Metadaten (OS-Typ, Version, Arch, Build-Nr., ZIP-Name) |
| `$script:appx` | Appx-Package-Arbeitslisten (listed / remove / inject) |

### Standardisiertes Return-Objekt

Jede Public-Funktion gibt ein einheitliches `PSCustomObject` zurück — dieses Muster wird vom privaten Helper `OPSreturn` erzeugt:

```powershell
[PSCustomObject]@{
    code = 0    # 0 = Erfolg, -1 = Fehler
    msg  = ""   # Human-readable Statusmeldung oder Fehlerbeschreibung
    data = $null # Optionaler Rückgabewert (Array, Objekt, String, …)
}
```

Dieses Muster ermöglicht saubere Pipeline-Verkettung: `if ($r.code -eq 0) { ... }`.

### Aktuelle Funktions-Übersicht (vollständig)

#### Core & Infrastructure (6 Funktionen)

| Funktion | Beschreibung |
|----------|-------------|
| `AppScope` | Read-only Accessor für die wichtigsten Module-Scope-Hashtables (`appinfo`, `appenv`, `reghive`, `appverify`, `appx`) |
| `InitializeEnvironment` | Erstellt die gesamte WinISO-Verzeichnisstruktur und lädt `oscdimg.exe` automatisch herunter |
| `VerifyEnvironment` | Prüft, ob alle erforderlichen Verzeichnisse und Dateien vorhanden sind |
| `CheckModuleRequirements` | Führt einen 11-Punkte-System-Dependency-Audit durch (OS, PS-Version, .NET, Admin-Rechte, DISM, robocopy, cmd.exe, oscdimg, Env-Dirs, Internet); nutzt ein 4-Status-Schema: PASS/FAIL/INFO/WARN |
| `WinISOcore` | Typsicherer Read/Write-Accessor für alle `$script:`-Variablen; verhindert ungewollte Direktzugriffe auf die Hashtabellen-Referenzen |
| `WriteLogMessage` | Strukturierter Log-Writer mit Zeitstempel und Severity-Level (INFO/DEBUG/WARN/ERROR); erstellt Verzeichnis automatisch |

#### Download Helpers (2 Funktionen)

| Funktion | Beschreibung |
|----------|-------------|
| `GitHubDownload` | Generischer GitHub-Asset-Downloader für beliebige öffentliche Repositories |
| `GetLatestPowerShellSetup` | Fragt die GitHub-Releases-API nach dem neuesten stabilen PowerShell-Release ab und lädt den `.msi`-Installer herunter; optionale Silent-Installation via `-Install`-Switch |

#### UUP Dump Workflow (7 Funktionen)

| Funktion | Beschreibung |
|----------|-------------|
| `DownloadUUPDump` | Lädt ein UUP-Dump-ZIP für eine einzelne Edition (Pro/Home) herunter; unterstützt `-IncludeNetFX`/`-ExcludeNetFX` und `-UseESD`-Switch |
| `GetUUPDumpPackage` | Multi-Edition-Download für virtuelle Editionen (ProWorkstations, ProEducation, Education, Enterprise, IoTEnterprise) via autodl=3 |
| `ExtractUUPDump` | Entpackt das UUP-Dump-ZIP ins Zielverzeichnis mit optionaler Integritätsprüfung und ZIP-Cleanup |
| `CreateUUPDiso` | Orchestriert die ISO-Erstellung via `uup_download_windows.cmd` mit 7-schichtigem Prozess-Monitoring (SoftIdle, HardIdle, GlobalTimeout, PollSeconds, KillOnHardIdle) |
| `CleanupUUPDump` | Bereinigt das UUPDump-Verzeichnis und behält ausschließlich die erzeugte ISO-Datei |
| `RenameUUPDiso` | Benennt die ISO-Datei im UUPDump-Verzeichnis um; schlägt kontrolliert fehl bei mehrdeutigem Ergebnis |
| `ExtractUUPDiso` | Mounted die ISO via `Mount-DiskImage`, kopiert den Inhalt mit `robocopy` und dismountet immer in einem `finally`-Block |

#### WIM Image Operations (3 Funktionen)

| Funktion | Beschreibung |
|----------|-------------|
| `ImageIndexLookup` | Durchsucht eine WIM-Datei nach einer Edition per Name und gibt eindeutigen `ImageIndex` zurück |
| `MountWIMimage` | Mounted ein WIM-Image mit Post-Mount-Verifikation und defensivem Auto-Dismount bei Fehler |
| `UnMountWIMimage` | Dismountet ein aktives WIM-Mount mit `commit` oder `discard`; führt Pre- und Post-Dismount-Verifikation durch |

#### Registry Hive Operations (7 Funktionen)

| Funktion | Beschreibung |
|----------|-------------|
| `LoadRegistryHive` | Mountet offline Hive(s) aus dem gemounteten WIM (`SYSTEM`, `SOFTWARE`, `DEFAULT`, `SAM`, `SECURITY`) via `reg.exe load`; Konvention: `HKLM\WinISO_<HiveName>` |
| `UnloadRegistryHive` | Entlädt Hive(s); flusht die Live-Registry vor dem Entladen zur Datenverlust-Prävention |
| `RegistryHiveAdd` | Fügt Registry-Key und/oder -Value hinzu; unterstützt alle gängigen Value-Types (REG_SZ, REG_EXPAND_SZ, REG_DWORD, REG_QWORD, REG_BINARY, REG_MULTI_SZ) |
| `RegistryHiveRem` | Entfernt Key/Value; `-RemoveKey`-Switch löscht den gesamten Key-Baum |
| `RegistryHiveImport` | Importiert eine validierte `.reg`-Datei; ruft intern `ValidateRegFile` auf, bevor der Import erfolgt |
| `RegistryHiveExport` | Exportiert einen Registry-Key-Branch in eine `.reg`-Datei via `reg.exe export` |
| `RegistryHiveQuery` | Fragt Keys und Values ab; gibt strukturierte `PSCustomObject`-Einträge zurück |

#### Appx / MSIX Package Operations (4 Funktionen — neu in v1.00.05)

| Funktion | Beschreibung |
|----------|-------------|
| `GetAppxPackages` | Listet alle provisioned Appx-Pakete aus dem gemounteten WIM via `Get-AppxProvisionedPackage`; schreibt Ergebnis in `$script:appx['listed']`; optionaler Export als TXT/CSV/JSON |
| `RemAppxPackages` | Entfernt alle Pakete aus `$script:appx['remove']` via `DISM.exe /Remove-ProvisionedAppxPackage`; self-cleaning (erfolgreich entfernte Einträge werden aus dem Scope gelöscht); `-ContinueOnError`-Switch |
| `AddAppxPackages` | Injiziert alle Pakete aus `$script:appx['inject']` via `DISM.exe /Add-ProvisionedAppxPackage`; unterstützt `.appx`, `.appxbundle`, `.msix`, `.msixbundle`; optionale `LicenseFile`-Property, Fallback auf `/SkipLicense` |
| `AppxPackageLookUp` | Dual-Mode-Verifikation: **IMAGE-Mode** (Substring-Suche in mounted WIM mit Cache-Support und `-ForceRefresh`) + **FILE-Mode** (physische Dateiprüfung im AppxBundle-Verzeichnis) |

#### Private Helpers (7 Funktionen)

| Funktion | Beschreibung |
|----------|-------------|
| `OPSreturn` | Erzeugt das standardisierte `{ code, msg, data }`-Return-Objekt |
| `Invoke-UUPRuntimeLog` | Erstellt und rotiert das UUP-Runtime-Log |
| `Get-UUPLogTail` | Liest effizient die letzten N Zeilen eines großen Log-Files |
| `Test-UUPConversionPhase` | Erkennt den Phasenübergang Download→Conversion in der UUP-Logausgabe |
| `Invoke-UUPProcessKill` | Beendet einen Prozess und seinen gesamten Child-Prozessbaum via WMI |
| `Get-UUPNewestISO` | Findet die neueste `.iso`-Datei in einem UUPDump-Verzeichnis |
| `ValidateRegFile` | Prüft die Syntax einer `.reg`-Datei (gültiger Header, Inhalt, Key/Value-Format) |

### Qualitätsbewertung des aktuellen Codes

Das Modul zeichnet sich durch eine sehr hohe Konsistenz und durchdachte Architektur aus. Jede Public-Funktion enthält vollständige Comment-Based-Help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`). Der `WinISOcore`-Accessor implementiert Type-Safety mit impliziter Konvertierung vor der Ablehnung. Das 4-Status-Schema (`PASS/FAIL/INFO/WARN`) in `CheckModuleRequirements` ist besonders elegant, da es zwischen automatisch behebbare Probleme (`INFO`), manuell behebbare (`WARN`) und nicht behebbare (`FAIL`) unterscheidet. Das self-cleaning Monitoring in `Rem/AddAppxPackages` ist ein ungewöhnlich durchdachtes Pattern, das nach der Operation sofort Klarheit darüber schafft, welche Pakete fehlgeschlagen sind.

***

## 2. Fehlende Funktionen — Empfehlungen

Die folgenden Funktionen fehlen noch im Projekt, würden es aber erheblich aufwerten. Die Reihenfolge folgt dem logischen Workflow-Ablauf.

### 2.1 Driver-Integration (OEM-Treiber in WIM injizieren)

Der `$script:appenv`-Scope enthält bereits die Keys `OEMDrivers` und `OEMfolder`, und auch das README erwähnt Treiber im Kontext der WIM-Anpassung — es gibt aber **keine einzige Funktion** für Treiber-Operationen. Das ist die offensichtlichste Lücke im aktuellen Funktionsumfang.

| Funktion | Beschreibung |
|----------|-------------|
| `AddDriverToWIM` | Injiziert einen einzelnen OEM-Treiber (`.inf`-Datei oder Treiber-Ordner) in das gemountete WIM-Image via `DISM.exe /Add-Driver`. Unterstützt `-Recurse`-Switch für Unterverzeichnisse und einen `-ForceUnsigned`-Switch für unsignierte Treiber. Schreibt Ergebnisse in einen neuen `$script:drivers`-Scope. |
| `GetDriversFromWIM` | Listet alle aktuell im gemounteten WIM enthaltenen Treiber via `Get-WindowsDriver`-Cmdlet. Optionaler Export als TXT/CSV/JSON (analog zu `GetAppxPackages`). |
| `RemDriverFromWIM` | Entfernt einen spezifischen Treiber aus dem gemounteten WIM anhand von Published-Name oder OEM-Inf-Name via `DISM.exe /Remove-Driver`. |

### 2.2 Unattend.xml / autounattend.xml — Antwortdatei-Generator

Das Manifest listet `UnattendedInstallation`, `UnattendedSetup` und `autounattend` in den Tags — aber keine einzige Funktion erzeugt oder bearbeitet eine Windows-Antwortdatei. Eine solche Datei ist der wichtigste Schritt zwischen ISO-Erstellung und vollautomatischer Windows-Installation.

| Funktion | Beschreibung |
|----------|-------------|
| `NewUnattendXml` | Erzeugt eine neue `unattend.xml`/`autounattend.xml`-Datei aus einem Template mit den häufigsten Einstellungen (Sprache, Zeitzone, SkipOOBE, Administrator-Passwort, AutoLogon, Lizenzkey). Gibt den Pfad zur erstellten Datei zurück. |
| `SetUnattendProperty` | Setzt oder ändert einen spezifischen Wert in einer bestehenden Antwortdatei anhand eines XPath-ähnlichen Schlüssels (z.B. `-Section "oobeSystem"` und `-Property "SkipMachineOOBE"` mit `-Value "true"`). |
| `InjectUnattendXml` | Kopiert eine fertige `unattend.xml`/`autounattend.xml` in das korrekte Verzeichnis des extrahierten ISO-Inhalts (`$script:appenv['ISOdata']`), sodass sie beim Brennen oder beim Erstellen der finalen ISO automatisch enthalten ist. |

### 2.3 Feature-on-Demand (FOD) und Language Packs

In Windows-Image-Customization-Workflows ist das Hinzufügen oder Entfernen von optionalen Features und Sprachpaketen ein Standard-Anwendungsfall — der Modul-Scope erwähnt ihn jedoch nicht.

| Funktion | Beschreibung |
|----------|-------------|
| `GetFeaturesFromWIM` | Listet alle Windows-Features (optional und eingebaut) im gemounteten WIM via `Get-WindowsOptionalFeature`. Optionaler Export. |
| `EnableFeatureInWIM` | Aktiviert ein optionales Windows-Feature im gemounteten WIM via `Enable-WindowsOptionalFeature`. |
| `DisableFeatureInWIM` | Deaktiviert ein optionales Windows-Feature im gemounteten WIM via `Disable-WindowsOptionalFeature`. Wichtig für Minimalisierungs-Szenarien (z.B. Hyper-V, Internet Explorer, .NET-Features). |
| `AddLanguagePackToWIM` | Injiziert ein Language Pack (`.cab`) in das gemountete WIM via `DISM.exe /Add-Package`. |

### 2.4 WIM-Verwaltung — Capture, Split, Export

Das Modul kann WIM-Images nur konsumieren (mounten, anpassen), aber nicht selbst erstellen oder für spezielle Zieldatenträger aufbereiten.

| Funktion | Beschreibung |
|----------|-------------|
| `CaptureWIMimage` | Erstellt ein neues WIM-Image aus einem Quellverzeichnis via `DISM.exe /Capture-Image`. Nützlich z.B. um eine vorkonfigurierte Windows-Installation in ein neues WIM zu "einzufrieren". |
| `SplitWIMimage` | Teilt eine große WIM-Datei in mehrere `.swm`-Teildateien auf (via `DISM.exe /Split-Image`). Notwendig, wenn das finale ISO auf FAT32-formatierten USB-Sticks deployed werden soll (4-GB-Limit). |
| `ExportWIMimage` | Exportiert einen einzelnen Image-Index aus einer WIM-Datei in eine neue, kleinere WIM-Datei via `DISM.exe /Export-Image`. Ermöglicht die Extraktion einer einzelnen Edition (z.B. nur Pro) aus einem Multi-Edition-WIM. |

### 2.5 ISO-Erstellung — Rebuild ohne UUP

Das Modul baut einen vollständigen Workflow um UUP Dump herum auf. Es fehlt aber eine Funktion, die aus einem bereits vorhandenen, angepassten Windows-ISO-Inhalt direkt ein neues bootfähiges ISO erzeugt — ohne den UUP-Download-Workflow zu durchlaufen.

| Funktion | Beschreibung |
|----------|-------------|
| `RebuildISO` | Erzeugt eine neue, bootfähige ISO-Datei aus einem vorhandenen Windows-Setup-Verzeichnis (z.B. `$script:appenv['ISOdata']`) via `oscdimg.exe` mit den richtigen Bootsektor-Parametern (`-b`, `-u2`, `-udfver102`, `-m`). Diese Funktion ist der "fehlende letzte Schritt" in einem vollständigen Custom-ISO-Workflow, der nicht auf UUP Dump basiert. |

### 2.6 Erweiterte Registry-Funktionen

Die bestehenden Registry-Hive-Funktionen decken Add/Remove/Import/Export/Query ab — aber einige nützliche Operationen fehlen noch.

| Funktion | Beschreibung |
|----------|-------------|
| `RegistryHiveCompare` | Vergleicht zwei Registry-Key-Bereiche (z.B. denselben Key aus zwei verschiedenen Hives oder vor/nach einer Änderung). Gibt eine Diff-Ausgabe zurück, die geänderte, hinzugefügte und entfernte Values auflistet. |
| `RegistryHiveCopy` | Kopiert einen Registry-Key-Baum von einem Pfad zu einem anderen innerhalb desselben oder eines anderen geladenen Offline-Hive. |

### 2.7 Globales Session-Logging und Audit-Trail

Das Modul hat eine `WriteLogMessage`-Funktion, aber es fehlt ein globaler Logging-Kontext, der den gesamten Workflow-Verlauf protokolliert.

| Funktion | Beschreibung |
|----------|-------------|
| `StartSessionLog` | Initialisiert ein globales Session-Logfile mit Zeitstempel, Modulversion und System-Info. Setzt eine neue `$script:sessionlog`-Scope-Variable mit dem Logfile-Pfad. Alle nachfolgenden Public-Funktionen können diesen Pfad automatisch nutzen, ohne dass der Aufrufer jedes Mal `-Logfile` angeben muss. |
| `StopSessionLog` | Schließt das aktive Session-Logfile mit einem finalen Eintrag (Endzeitstand, Laufzeit in Sekunden, Zusammenfassung der Erfolge/Fehler). |

### 2.8 Hash-Verifikation für Downloads

Aktuell gibt es keine Integritätsprüfung für heruntergeladene Dateien per Hash.

| Funktion | Beschreibung |
|----------|-------------|
| `VerifyFileHash` | Berechnet den Hash einer Datei (SHA256/SHA512/MD5) und vergleicht ihn optional mit einem erwarteten Hashwert. Gibt `$true`/`$false` als `.data` zurück. Kann als Pre-Check vor `ExtractUUPDump` oder `RebuildISO` eingesetzt werden. |

### 2.9 Konfigurationsmanagement

Aktuell sind alle Pfade (besonders `ISOroot = 'C:\WinISO'`) hardcoded in `psm1`. Es gibt keine Funktion, die eine externe Konfigurationsdatei liest oder schreibt.

| Funktion | Beschreibung |
|----------|-------------|
| `LoadConfiguration` | Liest eine JSON- oder PSD1-Konfigurationsdatei und setzt die relevanten `$script:appenv`-Keys entsprechend über `WinISOcore` — z.B. um `ISOroot` auf einen anderen Pfad zu legen. |
| `SaveConfiguration` | Exportiert den aktuellen `$script:appenv`-Zustand als JSON-Datei, sodass er in zukünftigen Sessions wiederverwendet werden kann. |

### 2.10 WIM-Image-Informationen abrufen

Das Modul kann WIM-Images mounten und modifizieren, aber es gibt keine Funktion, die detaillierte Metadaten eines WIM ausliest ohne es zu mounten.

| Funktion | Beschreibung |
|----------|-------------|
| `GetWIMinfo` | Liest Metadaten einer WIM-Datei (alle enthaltenen Editionen mit Name, Index, Sprache, Architektur, Größe, Erstelldatum) via `Get-WindowsImage -ImagePath`. Gibt ein Array von `PSCustomObject`-Einträgen zurück. Sinnvoll als Vorschau-Schritt vor `MountWIMimage`. |

***

## 3. Verbesserungs- und Optimierungsvorschläge

Die folgenden Vorschläge bauen direkt auf dem analysierten Code auf und adressieren konkrete Schwachstellen oder Ausbaumöglichkeiten.

### 3.1 Globales Logging-System (Zentrales Session-Log)

Das größte Usability-Problem im aktuellen Modul ist, dass `WriteLogMessage` immer einen expliziten `-Logfile`-Parameter erwartet. In einem typischen Workflow mit 15–20 Funktionsaufrufen führt das dazu, dass entweder jede Funktion den Logfile-Pfad separat übergeben bekommt, oder — häufiger — gar kein Logging stattfindet.

**Empfehlung:** Einen neuen `$script:sessionlog`-Scope einführen, der den aktiven Logfile-Pfad speichert. `WriteLogMessage` prüft dann, ob `$script:sessionlog` gesetzt ist, und schreibt automatisch dorthin, wenn kein expliziter `-Logfile`-Parameter übergeben wird. Kombiniert mit einer `StartSessionLog`-Funktion (siehe Abschnitt 2.7) entsteht so ein opt-in Global-Logging ohne Breaking Changes.

```powershell
# Einmalig am Script-Anfang:
StartSessionLog -LogPath "C:\WinISO\Logfiles\session-$(Get-Date -f yyyyMMdd-HHmmss).log"

# Alle nachfolgenden WriteLogMessage-Aufrufe ohne -Logfile nutzen das Session-Log:
WriteLogMessage -Message "Download gestartet" -Flag INFO
```

### 3.2 Konfigurierbarer Basis-Pfad (ISOroot)

Der `ISOroot`-Pfad `C:\WinISO` ist in `WinISO.ScriptFXLib.psm1` hardcoded. Auf Systemen mit knappem C-Laufwerk, in CI/CD-Pipelines oder wenn mehrere parallele WinISO-Umgebungen verwaltet werden sollen, ist das ein erhebliches Hindernis.

**Empfehlung:** `InitializeEnvironment` um einen optionalen `-BasePath`-Parameter erweitern. Wenn angegeben, überschreibt er `ISOroot` über `WinISOcore` und alle daraus abgeleiteten Pfade werden neu berechnet. Da die Pfade in `.psm1` via `Join-Path $script:appenv['ISOroot'] '...'` aufgebaut sind, ist der Änderungsaufwand minimal.

```powershell
$r = InitializeEnvironment -BasePath "D:\CustomISO"
# Setzt $script:appenv['ISOroot'] = 'D:\CustomISO' und leitet alle Subpfade neu ab
```

### 3.3 Dry-Run-Modus für destruktive Operationen

Funktionen wie `RemAppxPackages`, `RegistryHiveRem`, `CleanupUUPDump` und `UnMountWIMimage -Action discard` sind destruktiv und können bei Fehlanwendung schwer rückgängig zu machende Änderungen verursachen.

**Empfehlung:** Einen `-WhatIf`-kompatiblen `-DryRun`-Switch (alternativ `[SupportsShouldProcess()]` nutzen, was PowerShell-nativ ist) zu allen destruktiven Funktionen hinzufügen. Im Dry-Run-Modus führt die Funktion alle Validierungen durch und gibt eine Liste der geplanten Aktionen zurück, ohne sie auszuführen. Das gibt dem Anwender Sicherheit vor dem eigentlichen Lauf.

```powershell
$preview = RemAppxPackages -WhatIf
# Gibt zurück: "Würde entfernen: Microsoft.BingWeather, Microsoft.GetHelp, ..."
```

### 3.4 Fortschrittsanzeige bei langen Operationen

`CreateUUPDiso`, `AddAppxPackages`, `ExtractUUPDiso` und `MountWIMimage` können sehr lange laufen (Minuten bis Stunden bei großen WIM-Dateien). Aktuell gibt es keine Rückmeldung über den Fortschritt an den aufrufenden Code.

**Empfehlung:** `Write-Progress` mit einem definierten `-Activity`-Identifier in die langen Operationen einbauen. Besonders in `AddAppxPackages` und `RemAppxPackages`, wo über ein Array iteriert wird, ist eine Fortschrittsanzeige trivial zu implementieren und sofort sichtbar nützlich.

```powershell
$i = 0
foreach ($Package in $PackageList) {
    $i++
    Write-Progress -Activity "Appx-Pakete injizieren" `
                   -Status "Paket $i von $($PackageList.Count): $($Package.DisplayName)" `
                   -PercentComplete (($i / $PackageList.Count) * 100)
    # ... DISM-Aufruf ...
}
Write-Progress -Activity "Appx-Pakete injizieren" -Completed
```

### 3.5 Rollback / Snapshot-Mechanismus für WIM-Änderungen

Aktuell gibt es keinen Mechanismus, um den Zustand eines gemounteten WIM-Images vor einer Reihe von Änderungen zu speichern und bei Fehlern darauf zurückzuspringen. `UnMountWIMimage -Action discard` verwirft **alle** Änderungen seit dem Mounten — aber es fehlt ein Checkpoint-Konzept zwischen Mount und Dismount.

**Empfehlung:** Eine `SaveWIMcheckpoint`-Funktion, die den aktuellen Zustand des gemounteten WIM committet und intern als `.wim`-Backup sichert. Im Fehlerfall kann dann auf diesen Checkpoint zurückgegriffen werden, ohne das gesamte WIM neu zu mounten. Dies ist besonders wertvoll bei aufwendigen Customization-Pipelines mit vielen Schritten.

### 3.6 `AppScope` um `uupdump` erweitern

In `AppScope` ist der `switch`-Block auf die Keys `appinfo`, `appenv`, `reghive`, `appverify` und `appx` beschränkt. Der `uupdump`-Scope ist nicht enthalten, obwohl er über `WinISOcore` zugänglich ist. Dies ist eine kleine Inkonsistenz, die Verwirrung stiften kann.

**Empfehlung:** Den `switch` in `AppScope` um den Case `'uupdump'` erweitern: `'uupdump' { return $script:uupdump }`. Ebenso sollten `appcore` und die internen `loadedhives`/`exit`-Scopes evaluiert werden.

### 3.7 Pipelining-Support für Appx-Paket-Operationen

Das aktuelle Design, bei dem die zu bearbeitenden Pakete vorab in `$script:appx['remove']` bzw. `$script:appx['inject']` eingetragen werden müssen, ist zwar konsequent und auditierbar — aber für einfache Anwendungsfälle umständlich. Wer nur ein einzelnes Paket entfernen möchte, muss dafür den vollen Scope-Write-Vorgang durchlaufen.

**Empfehlung:** Einen optionalen `-PackageName`-Parameter (für `RemAppxPackages`) und `-PackageFile`-Parameter (für `AddAppxPackages`) hinzufügen, die als schnelle One-Shot-Alternative zum Scope-basierten Workflow fungieren. Das bestehende Scope-basierte Verhalten bleibt der Standard.

```powershell
# Neu: direkt, ohne Scope-Write
$r = RemAppxPackages -PackageName "Microsoft.BingWeather"
```

### 3.8 Hash/Checksum-Verifikation für alle Downloads

`DownloadUUPDump`, `GitHubDownload` und `GetLatestPowerShellSetup` laden Dateien herunter, ohne deren Integrität zu prüfen. In Enterprise-Umgebungen oder bei instabilen Netzwerkverbindungen kann eine unvollständige oder korrumpierte Datei später zu schwer debuggbaren Fehlern führen.

**Empfehlung:** Alle Download-Funktionen um einen optionalen `-ExpectedHash`- und `-HashAlgorithm`-Parameter (Default: SHA256) erweitern. Nach dem Download wird der Hash automatisch berechnet und verglichen. Bei Abweichung schlägt die Funktion mit `.code -1` und einer klaren Fehlermeldung fehl.

### 3.9 Verbesserte `AppScope` Rückgabe als Fehlertyp

Die aktuelle `AppScope`-Funktion gibt bei ungültigem `KeyID` einen `$script:exit`-Hashtable zurück — das ist inkonsistent mit dem Rest des Moduls, der ein standardisiertes `OPSreturn`-Objekt zurückgibt. Ein Aufrufer, der nicht aufpasst, erhält bei Fehler ein Hashtable statt eines `PSCustomObject`.

**Empfehlung:** `AppScope` auf das standardisierte `OPSreturn`-Muster umstellen. Rückgabe bei Fehler: `OPSreturn -Code -1 -Message "..."`. Rückgabe bei Erfolg: `OPSreturn -Code 0 -Data $targetHashtable`. Das macht `AppScope` konsistent mit allen anderen Public-Funktionen.

### 3.10 Verweigerung der Ausführung ohne Admin-Rechte

Die meisten Funktionen (DISM, Registry-Hive-Load, ISO-Mount) **erfordern** Administrator-Rechte. Aktuell wird dieser Check nur in `CheckModuleRequirements` durchgeführt — die einzelnen Funktionen prüfen die Elevation nicht selbst und liefern erst tief im Prozess kryptische DISM-Fehler.

**Empfehlung:** Eine private Helper-Funktion `Test-IsAdminPrivilege` erstellen, die alle Funktionen, die Elevation benötigen, am Anfang aufrufen. Bei fehlender Elevation sofortige Rückgabe mit `OPSreturn -Code -1 -Message "Diese Funktion erfordert Administrator-Rechte. Bitte PowerShell als Administrator starten."`. Alternativ `#Requires -RunAsAdministrator` im Modul-Root setzen.

### 3.11 Konsistente Parameter-Namenskonventionen

Im Modul werden Parameter teils als Single-Wort-Strings (z.B. `-Export`, `-Override`) und teils als Switches (z.B. `-ContinueOnError`, `-ForceRefresh`, `-Unwrap`) implementiert. Der `-Export`-Parameter in `CheckModuleRequirements` ist z.B. als `[int] $Export = 0` mit `ValidateSet(0, 1)` deklariert, anstatt ein `-Switch` zu sein. Das ist funktional korrekt, aber unkonventionell.

**Empfehlung:** Boolesche Parameter systematisch als `[switch]`-Parameter umstellen. Das entspricht den PowerShell-Best-Practices und macht die Aufruf-Syntax intuitiver: `CheckModuleRequirements -Export` statt `CheckModuleRequirements -Export 1`.

### 3.12 Pester-Tests hinzufügen

Das Projekt enthält aktuell keinerlei automatisierte Tests. Bei einer so schnell wachsenden Codebasis (6 Versionen in 7 Tagen) ist das Risiko von Regressionen durch Änderungen an zentralen Funktionen wie `WinISOcore` oder `OPSreturn` erheblich.

**Empfehlung:** Ein `Tests/`-Verzeichnis anlegen und [Pester](https://pester.dev/) als Test-Framework einsetzen. Prioritäten:
- Unit-Tests für `OPSreturn` (prüft Return-Objekt-Struktur)
- Unit-Tests für `WinISOcore` (Type-Safety, Read-Only-Enforcement, alle Scope-Zugriffe)
- Unit-Tests für `AppScope` (alle gültigen und ungültigen Keys)
- Mock-basierte Integration-Tests für `CheckModuleRequirements` (simuliert fehlende Tools)

### 3.13 Binärdateien aus dem Repository entfernen

Das `Requirements/`-Verzeichnis enthält große Binärdateien: `NDP481-x86-x64-AllOS-ENU.exe` (~74 MB), `adksetup.exe` (~2,1 MB), `adkwinpesetup.exe` (~1,9 MB) und `oscdimg.exe` (~150 KB). Binärdateien in Git-Repositories sind problematisch: sie vergrößern den Clone-Umfang, lassen sich nicht diffbar versionieren, und stellen bei ausführbaren Dateien ein Sicherheitsrisiko dar.

**Empfehlung:** Die Binärdateien aus dem Repository entfernen und stattdessen ausschließlich Download-URLs in `$script:appcore['requirement']` hinterlegen (was bereits teilweise so gemacht ist). `InitializeEnvironment` und `GetLatestPowerShellSetup` können diese URLs dann zur Laufzeit auflösen. Eine `.gitignore`-Regel für `Requirements/*.exe` verhindert zukünftige versehentliche Commits.

### 3.14 Commit-Message-Konsistenz verbessern

Die neuesten Commits verwenden Conventional Commits (`feat(v1.00.05):`, `docs(v1.00.05):`) — ältere Commits lauten lediglich `"WinISO.ScriptFXLib Update"` ohne jeglichen Informationsgehalt. Das erschwert das automatische Erstellen von Release-Notes und die Nachvollziehbarkeit der Entwicklung.

**Empfehlung:** Ein `.github/COMMIT_CONVENTION.md` oder eine `CONTRIBUTING.md`-Datei anlegen, die den Conventional-Commit-Standard als Pflicht dokumentiert. Alternativ kann ein GitHub-Action-Workflow Commit-Messages per Regex validieren.

### 3.15 Erweiterte Internet-Konnektivitätsprüfung

`CheckModuleRequirements` testet aktuell per `Invoke-WebRequest -Method Head` ob `uupdump.net` und `github.com` erreichbar sind. In Unternehmensumgebungen können aber HTTP-Verbindungen verfügbar sein, während HTTPS-Downloads durch SSL-Inspection-Proxies scheitern. Außerdem prüft der Test nur Erreichbarkeit, nicht API-Zugänglichkeit.

**Empfehlung:** Den Konnektivitätstest um einen Download-Test erweitern: eine kleine Test-Datei von einem bekannten URL abrufen und deren Hash prüfen. Außerdem sollte der Test bei Proxy-Umgebungen den System-Proxy automatisch berücksichtigen (`-Proxy ([System.Net.WebRequest]::DefaultWebProxy)`).