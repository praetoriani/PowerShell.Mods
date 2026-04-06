# VPDLX v1.01.00 — Entwickler-Dokumentation

> **Projekt:** Virtual PowerShell Data-Logger eXtension  
> **Version:** 1.01.00  
> **Stand:** 06. April 2026  
> **Autor:** Praetoriani (M. Sczepanski)  
> **Repository:** [github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX](https://github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX)

***

## 1. Executive Summary

VPDLX ist ein PowerShell-Modul, das ein vollständig klassenbasiertes virtuelles Logging-System bereitstellt. Anstatt Log-Einträge sofort auf die Festplatte zu schreiben, hält VPDLX beliebig viele benannte Log-Instanzen vollständig im Arbeitsspeicher und erlaubt gleichzeitiges Schreiben, Lesen, Filtern und Verwalten dieser Instanzen innerhalb einer PowerShell-Session. Version **1.01.00** stellt einen vollständigen Architektur-Neuschrieb gegenüber v1.00.00 dar: Die ursprüngliche funktionsbasierte Implementierung wurde durch eine saubere OOP-Architektur mit drei exportierbaren Klassen ersetzt.

Die aktuelle Version ist **funktional korrekt**, weist jedoch erhebliche Inkonsistenzen zwischen dem implementierten Code und den begleitenden Dokumentations- und Beispieldateien auf. Die Demo-Skripte, die QUICKSTART.md und die README.md referenzieren noch die veraltete v1.00.00 API. Für eine produktionsreife Version müssen diese Lücken geschlossen und mehrere noch fehlende Basis-Funktionalitäten implementiert werden.

***

## 2. Modul-Übersicht und Versionshistorie

### 2.1 Versionsverlauf

| Version | Datum | Typ | Kernänderung |
|---|---|---|---|
| 1.00.00 | 05.04.2026 | Initial Release | Funktionsbasierte Architektur (`CreateNewLogfile`, `WriteLogfileEntry`, etc.) |
| 1.01.00 | 06.04.2026 | Breaking Rewrite | Vollständiger Wechsel auf klassenbasierte OOP-Architektur |

Das CHANGELOG.md enthält **ausschließlich die Dokumentation von v1.00.00** — der Breaking-Change-Rewrite zu v1.01.00 ist dort nicht aufgeführt, obwohl das Manifest und das psm1 bereits `1.01.00` ausweisen. Dies ist ein kritisches Dokumentationsproblem.

### 2.2 Technische Voraussetzungen

| Anforderung | Wert |
|---|---|
| PowerShell | 5.1 (Desktop) oder 7.x+ (Core) |
| Kompatible PSEditions | `Desktop`, `Core` |
| Externe Abhängigkeiten | Keine |
| Erforderliche Privilegien | Standard-Benutzer (keine Elevation nötig) |
| Plattform | Windows 10 / Windows 11 |

***

## 3. Repository-Struktur (IST-Zustand)

```
VPDLX/
├── VPDLX.psm1                 ← Root-Modul: Initialisierung, Klassen-Loading, TypeAccelerators
├── VPDLX.psd1                 ← Modul-Manifest (Version, Exports, Metadaten)
├── CHANGELOG.md               ← Versionshistorie (⚠ veraltet — nur v1.00 dokumentiert)
├── QUICKSTART.md              ← Quick-Start Guide (⚠ veraltet — v1.00 API)
├── README.md                  ← Vollständige Referenz (⚠ veraltet — v1.00 API)
│
├── Classes/
│   ├── FileDetails.ps1        ← Metadata-Begleiter für jede Logfile-Instanz
│   ├── FileStorage.ps1        ← Zentrales Registry für alle aktiven Logfile-Instanzen
│   └── Logfile.ps1            ← Kern-Klasse (user-facing, alle CRUD-Operationen)
│
├── Private/
│   └── VPDLXreturn.ps1        ← Factory-Funktion für standardisierte Return-Objekte
│
├── Examples/
│   └── Demo-001.ps1           ← Demo-Skript (⚠ veraltet — verwendet v1.00 API)
│
└── .backup/
    ├── VPDLX.psm1             ← Backup der v1.00 Root-Modul
    └── VPDLX.psd1             ← Backup des v1.00 Manifests
```

> **Hinweis:** Das `Public/`-Verzeichnis ist im Repository **nicht angelegt**, obwohl das psm1 aktiv nach `$PSScriptRoot\Public\*.ps1`-Dateien sucht. Dies ist funktional korrekt (die Suche schlägt still fehl), erzeugt aber Verwirrung.

***

## 4. Architektur — Tiefgehende Analyse

### 4.1 Modul-Root (VPDLX.psm1)

Die Root-Modul-Datei implementiert eine sorgfältig aufgebaute, achtstufige Initialisierungssequenz:

1. **Section 1 — Modul-Metadaten:** `$script:appinfo` (read-only Hashtable mit Name, Version, Autor, Datum) und `$script:export` (Format-Definitionen für künftige Export-Funktionen: `.txt`, `.csv`, `.json`, `.log`)
2. **Section 2 — Klassen-Loading:** Geordnetes Dot-Sourcing der drei Klassen-Dateien in strikter Reihenfolge (FileDetails → FileStorage → Logfile), da Forward-References in PS 5.1 nicht aufgelöst werden
3. **Section 3 — FileStorage-Singleton:** Einmalige Instantiierung des `[FileStorage]`-Objekts in `$script:storage`
4. **Section 4 — Private/Public Function Loading:** Auto-Discovery via `Get-ChildItem *.ps1`
5. **Section 5 — VPDLXcore Accessor:** Definiert die öffentliche Zugriffs-Funktion auf `$script:*`-Variablen
6. **Section 6 — TypeAccelerator-Registrierung:** Macht `[FileDetails]`, `[FileStorage]`, `[Logfile]` global über normale `Import-Module`-Aufrufe nutzbar
7. **Section 7 — Export-Deklarationen:** Exportiert `VPDLXcore` + alle Auto-discovered Public-Funktionen
8. **Section 8 — OnRemove Handler:** Räumt TypeAccelerators beim `Remove-Module` sauber auf

Der Load-Order-Guard (Existenzprüfung via `Test-Path` für jede Klassen-Datei mit explizitem `Write-Error` + `return`) ist ein besonders sorgfältig implementiertes Detail, das einen partiell geladenen Modul-Zustand verhindert.

### 4.2 Klasse: `FileDetails`

`FileDetails` ist der Metadaten-Begleiter jeder `Logfile`-Instanz und implementiert das **Information Expert Principle** — alle Metadaten-Pflege liegt bei der Klasse selbst.

**Interne Felder (alle `hidden`):**

| Feld | Typ | Beschreibung |
|---|---|---|
| `_created` | `[string]` | Erstellungszeitpunkt (einmalig bei Konstruktor gesetzt) |
| `_updated` | `[string]` | Zeitpunkt des letzten Write/Print/Reset-Aufrufs |
| `_lastAccessed` | `[string]` | Zeitpunkt des letzten Read/SoakUp/Filter-Aufrufs |
| `_totalInteractions` | `[int]` | Gesamtzähler aller Interaktionen seit Erstellung |
| `_totalEntries` | `[int]` | Aktueller Zähler der Log-Einträge (absolut gesetzt, nicht inkrementiert) |

**Interne Methoden (alle `hidden`, nur für `Logfile`-Methoden):**

| Methode | Aufruf durch | Wirkung |
|---|---|---|
| `RecordWrite()` | `Write()`, `Print()` | `_updated` = jetzt; `_totalInteractions++` |
| `RecordRead()` | `Read()`, `SoakUp()`, `Filter()` | `_lastAccessed` = jetzt; `_totalInteractions++` |
| `SetEntryCount([int])` | `Write()`, `Print()`, nach `Reset()` | Setzt `_totalEntries` absolut (kein Increment!) |
| `ApplyReset()` | `Reset()` | `_updated` + `_lastAccessed` = jetzt; `_totalInteractions++`; `_totalEntries = 0`; `_created` bleibt! |

**Öffentliche Getter-Methoden:**

```powershell
[string] GetCreated()
[string] GetUpdated()
[string] GetLastAccessed()
[int]    GetTotalInteractions()
[int]    GetTotalEntries()
[string] ToString()
[System.Collections.Specialized.OrderedDictionary] ToHashtable()
```

Das Timestamp-Format ist `[dd.MM.yyyy | HH:mm:ss]` — ein bewusst gewähltes, lesbares Format mit Trennzeichen. Da Timestamps als `[string]` statt `[datetime]` gespeichert werden, sind keine direkten Zeitberechnungen (z.B. Log-Alter ermitteln) möglich.

### 4.3 Klasse: `FileStorage`

`FileStorage` implementiert das **Singleton Registry Pattern** — es gibt genau eine Instanz im `$script:storage`-Scope der Root-Modul.

**Interne Datenstrukturen:**

- `_registry`: `Dictionary[string, object]` mit `StringComparer.OrdinalIgnoreCase` — ermöglicht O(1)-Lookups case-insensitiv. Der Typ ist `object` statt `[Logfile]`, um PS 5.1-Forward-Reference-Probleme zu vermeiden.
- `_names`: `List[string]` — speichert die originalen (case-preserved) Namen in Einfügereihenfolge für `GetNames()`

**Öffentliche API:**

| Methode | Rückgabetyp | Beschreibung |
|---|---|---|
| `Contains([string])` | `[bool]` | O(1)-Prüfung ob Name registriert |
| `Get([string])` | `[object]` | Gibt Instanz zurück oder `$null` |
| `Count()` | `[int]` | Anzahl registrierter Instanzen |
| `GetNames()` | `[string[]]` | Alle Namen in Einfügereihenfolge; niemals `$null` |
| `ToString()` | `[string]` | Lesbare Zusammenfassung |

**Interne (hidden) API — nur für `Logfile`-Klasse:**

| Methode | Aufruf durch | Fehlerverhalten |
|---|---|---|
| `Add([string], [object])` | `Logfile`-Konstruktor | `throw` bei Duplikat |
| `Remove([string])` | `Logfile.Destroy()` | `throw` wenn nicht gefunden |

### 4.4 Klasse: `Logfile`

`Logfile` ist die zentrale, nach außen sichtbare Benutzer-Klasse.

**Öffentliche Eigenschaften:**

| Eigenschaft | Typ | Beschreibung |
|---|---|---|
| `Name` | `[string]` | Originaler Name (case-preserved, unveränderlich nach Konstruktor) |

**Statische Felder:**

```powershell
static [hashtable] $LogLevels = @{
    info     = '  [INFO]      ->  '
    debug    = '  [DEBUG]     ->  '
    warning  = '  [WARNING]   ->  '
    error    = '  [ERROR]     ->  '
    critical = '  [CRITICAL]  ->  '
}
```

**Konstruktor-Validierung:**
- Name darf nicht null/leer/whitespace-only sein
- Name muss 3–64 Zeichen lang sein
- Name muss dem Regex `^[a-zA-Z0-9_\-\.]+$` entsprechen
- Name darf nicht doppelt vorkommen (case-insensitive Prüfung via `$script:storage.Contains()`)

**Log-Entry-Format:**
```
[dd.MM.yyyy | HH:mm:ss]  [LEVEL]     ->  MESSAGE
```

**Vollständige öffentliche Methoden:**

| Methode | Signatur | Beschreibung |
|---|---|---|
| `Write` | `Write([string] $level, [string] $message) → void` | Einzelnen Eintrag anhängen |
| `Print` | `Print([string] $level, [string[]] $messages) → void` | Batch-Einträge (Pre-Validation!) |
| `Read` | `Read([int] $line) → string` | 1-basierter Zugriff, auto-geclampt |
| `SoakUp` | `SoakUp() → string[]` | Gesamten Inhalt als Array |
| `Filter` | `Filter([string] $level) → string[]` | Nur Einträge eines Levels |
| `Reset` | `Reset() → void` | Alle Daten löschen (irreversibel) |
| `Destroy` | `Destroy() → void` | Aus Storage entfernen + Daten freigeben |
| `Info` | `Info([string] $msg) → void` | Shortcut für `Write('info', ...)` |
| `Debug` | `Debug([string] $msg) → void` | Shortcut für `Write('debug', ...)` |
| `Warning` | `Warning([string] $msg) → void` | Shortcut für `Write('warning', ...)` |
| `Error` | `Error([string] $msg) → void` | Shortcut für `Write('error', ...)` |
| `Critical` | `Critical([string] $msg) → void` | Shortcut für `Write('critical', ...)` |
| `GetDetails` | `GetDetails() → FileDetails` | Metadaten-Objekt abrufen |
| `ToString` | `ToString() → string` | Einzeilige Zusammenfassung |

**Private Hilfsmethoden:**

| Methode | Zweck |
|---|---|
| `hidden BuildEntry([string] $level, [string] $message) → string` | Formatiert einen Log-Eintrag |
| `hidden ValidateLevel([string] $level) → string` | Normalisiert und validiert den Level-String |
| `hidden ValidateMessage([string] $message) → void` | Prüft auf Nicht-Leer + min. 3 Nicht-Whitespace-Zeichen |

**Print()-Besonderheit:** Alle Nachrichten werden **vor** dem Schreiben validiert. Erst wenn alle `ValidateMessage()`-Prüfungen bestanden sind, werden die Einträge zur Liste hinzugefügt. Dies garantiert, dass das Log bei einem Fehler in der Mitte eines Batches konsistent bleibt. `RecordWrite()` wird nur **einmal** pro `Print()`-Aufruf aufgerufen — der gesamte Batch zählt als eine Interaktion.

### 4.5 Funktion: `VPDLXreturn` (Private)

Standardisierte PSCustomObject-Factory mit drei Feldern:

```powershell
[PSCustomObject] @{
    code = [int]     # 0 = Erfolg, -1 = Fehler
    msg  = [string]  # Menschenlesbare Beschreibung
    data = [object]  # Payload oder $null
}
```

Der `[ordered]`-Modifier garantiert vorhersagbare Eigenschaftsreihenfolge in `Format-List` und `Format-Table`. Derzeit wird `VPDLXreturn` ausschließlich von `VPDLXcore` verwendet — die Klassen selbst werfen bei Fehlern `.NET`-Exceptions anstatt `VPDLXreturn`-Objekte zurückzugeben.

### 4.6 Funktion: `VPDLXcore` (Public)

Kontrollierter, read-only Accessor für `$script:*`-Variablen der Root-Modul.

| KeyID | Gibt zurück | Typ |
|---|---|---|
| `'appinfo'` | Modul-Metadaten | `[hashtable]` |
| `'storage'` | FileStorage-Singleton | `[FileStorage]` |
| `'export'` | Export-Format-Definitionen | `[hashtable]` |

Bei ungültigem `KeyID` gibt `VPDLXcore` ein `VPDLXreturn`-Objekt mit `code = -1` zurück.

### 4.7 TypeAccelerator-Mechanismus

Der gewählte Ansatz über `[psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')` entspricht der offiziell empfohlenen Methode für die Nutzung von PowerShell-Klassen nach `Import-Module` ohne `using module`:

```powershell
# On Load
$TypeAcceleratorsClass::Add($Type.FullName, $Type)

# On Remove (OnRemove Handler mit .GetNewClosure())
$TypeAcceleratorsClass::Remove($Type.FullName) | Out-Null
```

Der Duplicate-Guard (`ContainsKey`-Prüfung vor `Add`) verhindert Exceptions bei `Import-Module -Force` oder re-Import in derselben Session.

***

## 5. Bekannte Diskrepanzen und kritische Probleme

### 5.1 Kritische Versionsinkongruenz (API-Bruch undokumentiert)

Der vollständige Rewrite von v1.00.00 auf v1.01.00 hat die gesamte öffentliche API ersetzt, ist aber in der Dokumentation nicht nachgeführt worden. Das betrifft drei zentrale Dateien:

**README.md:** Zeigt noch die Architektur mit `Public/*.ps1`-Funktionsdateien (`CreateNewLogfile.ps1`, `WriteLogfileEntry.ps1`, etc.) und die v1.00-API in allen Code-Beispielen. Das Architektur-Diagramm enthält `VPDLXcore.ps1` als separate Datei in `Public/` — diese existiert in v1.01.00 nicht.

**QUICKSTART.md:** Alle 6 Schritte des Walkthrough basieren auf `CreateNewLogfile`, `WriteLogfileEntry`, `ReadLogfileEntry`, `ResetLogfile`, `DeleteLogfile`. Diese Funktionen sind in v1.01.00 nicht mehr vorhanden. Ebenso listet der QUICKSTART 8 Log-Levels auf (DEBUG, INFO, VERBOSE, TRACE, WARNING, ERROR, CRITICAL, FATAL), während v1.01.00 nur 5 unterstützt (info, debug, warning, error, critical).

**Demo-001.ps1 (Examples/):** Das komplette Demo-Skript verwendet ausschließlich die v1.00-API und würde nach `Import-Module VPDLX` v1.01.00 mit Fehlern wie `"The term 'CreateNewLogfile' is not recognized"` abbrechen.

**CHANGELOG.md:** Enthält ausschließlich die v1.00.00-Einträge. Der vollständige Rewrite zu v1.01.00, der eine Breaking Change ist, fehlt vollständig.

### 5.2 Fehlendes `Public/`-Verzeichnis

Das Modul-Root sucht aktiv nach `Public/*.ps1`-Dateien:
```powershell
$PublicFunctions = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)
```
Das `Public/`-Verzeichnis ist im Repository nicht angelegt. Das `FunctionsToExport`-Array im Manifest listet ausschließlich `'VPDLXcore'`, was dem tatsächlichen Verhalten entspricht — aber das Fehlen des Ordners und der Code-Kommentar ("reserved for future wrapper functions") erzeugen unnötige Verwirrung.

### 5.3 Log-Level Reduktion (Breaking Change)

v1.00.00 unterstützte 8 Log-Level: `DEBUG`, `INFO`, `VERBOSE`, `TRACE`, `WARNING`, `ERROR`, `CRITICAL`, `FATAL`  
v1.01.00 unterstützt nur noch 5: `info`, `debug`, `warning`, `error`, `critical`

`VERBOSE`, `TRACE` und `FATAL` sind weggefallen. Dies ist ein Breaking Change, der nirgends dokumentiert ist.

### 5.4 Fehlendes Speicherformat-Inkonsistenz

Im Manifest (`VPDLX.psd1`) wird der Pfad zu Klassen-Dateien mit Backslash angegeben (`Classes\FileDetails.ps1`), während im psm1 ebenfalls Backslash verwendet wird. Dies funktioniert auf Windows korrekt, würde aber auf Linux/macOS (PS Core) fehlschlagen — obwohl `CompatiblePSEditions = @('Desktop', 'Core')` deklariert ist.

***

## 6. TODO-Liste: Fehlende Basis-Funktionalitäten

Die folgenden Punkte müssen umgesetzt werden, damit v1.01.00 alle Basis-Funktionalitäten für die virtuelle Logfile-Arbeit vollständig abdeckt (Export-Funktionalität ausgeschlossen).

### 6.1 KRITISCH — Muss vor Freigabe erledigt sein

| # | Aufgabe | Datei(en) | Begründung |
|---|---|---|---|
| K-01 | **CHANGELOG.md aktualisieren** — vollständigen v1.01.00-Eintrag mit Breaking-Change-Hinweis, neuer Klassenarchitektur, entfernten Funktionen und neuen Leveln hinzufügen | `CHANGELOG.md` | Versionsverlauf komplett fehlerhaft |
| K-02 | **README.md vollständig neu schreiben** — v1.01.00-Architektur, Klassen-API statt Funktionen, korrektes Architektur-Diagramm | `README.md` | Zeigt inexistente v1.00-API |
| K-03 | **QUICKSTART.md vollständig neu schreiben** — alle Beispiele auf `[Logfile]::new()` und Methoden-Aufrufe umstellen, Log-Levels korrigieren | `QUICKSTART.md` | Zeigt inexistente v1.00-API |
| K-04 | **Demo-001.ps1 für v1.01.00 neu schreiben** (oder neues Demo-002.ps1 erstellen) — komplettes Demo mit neuer Klassen-API | `Examples/Demo-002.ps1` | Demo bricht bei Ausführung komplett |
| K-05 | **`Public/`-Verzeichnis anlegen** (leere `.gitkeep`-Datei) — oder Suche in psm1 entfernen und Kommentar anpassen | `VPDLX.psm1` / Repository | Klarheit über Struktur |

### 6.2 WICHTIG — Basis-Funktionalität runden

| # | Aufgabe | Datei(en) | Begründung |
|---|---|---|---|
| W-01 | **`Get-VPDLXLogfile` Public Wrapper** — Funktion zum Abrufen einer Logfile-Instanz by Name ohne `VPDLXcore` umständlich aufrufen zu müssen | `Public/Get-VPDLXLogfile.ps1` | Ergonomie: `$log = Get-VPDLXLogfile -Name 'AppLog'` statt `(VPDLXcore -KeyID storage).Get('AppLog')` |
| W-02 | **`Get-VPDLXLogfileList` Public Wrapper** — Funktion zum Auflisten aller registrierten Logfiles | `Public/Get-VPDLXLogfileList.ps1` | Standardaufgabe sollte einfach erreichbar sein |
| W-03 | **`IsEmpty()` / `HasEntries()` Methode in `Logfile`** — schnelle Prüfung vor `Read()`-Aufruf | `Classes/Logfile.ps1` | Verhindert `InvalidOperationException` ohne try/catch |
| W-04 | **`Count` Property oder `EntryCount()` Methode in `Logfile`** — direkter Zugriff auf Eintragsanzahl ohne `GetDetails().GetTotalEntries()` Umweg | `Classes/Logfile.ps1` | `GetDetails().GetTotalEntries()` ist ein unnötig tiefer Accessor-Chain |
| W-05 | **Log-Level-Ergänzung: VERBOSE, TRACE** (FATAL optional) — Entscheidung ob v1.01.00 mit 5 oder 8 Levels arbeitet, dann konsequent dokumentieren | `Classes/Logfile.ps1`, `QUICKSTART.md`, `Demo` | Breaking Change aus v1.00 muss bewusst entschieden und dokumentiert werden |
| W-06 | **`Print()` Overload mit Single-Message** — `Print([string] $level, [string] $message)` als bequeme Alternative zu `Write()` | `Classes/Logfile.ps1` | Methodenname "Print" suggeriert auch Einzel-Nutzung |
| W-07 | **Pfad-Trennzeichen in `.psd1` FileList** auf Forward-Slash umstellen (`Classes/FileDetails.ps1` statt `Classes\FileDetails.ps1`) | `VPDLX.psd1` | PS Core Kompatibilität (Linux/macOS) |

### 6.3 NICE TO HAVE — Komfort und Vollständigkeit

| # | Aufgabe | Datei(en) | Begründung |
|---|---|---|---|
| N-01 | **`GetAll()` Methode in `FileStorage`** — direkte Rückgabe aller Logfile-Instanzen als Array | `Classes/FileStorage.ps1` | Iteration ohne GetNames() + Get() Kombi |
| N-02 | **`Logfile.Contains([string] $searchText)` Methode** — sucht Text in allen Einträgen (ähnlich `Filter()` aber für freien Text) | `Classes/Logfile.ps1` | Nützliche Basis-Suchfunktion |
| N-03 | **`Logfile.GetRange([int] $from, [int] $to)` Methode** — Seitenweise Ausgabe eines Bereichs | `Classes/Logfile.ps1` | Ergänzt `Read()` für Bulk-Lesezugriff |
| N-04 | **Badge-Version in README.md** korrigieren (zeigt `1.00.00`) | `README.md` | Kosmetisch, aber sichtbar falsch |
| N-05 | **Beispiel-Demo für Multi-Logfile-Szenario** — zeigt gleichzeitiges Arbeiten mit mehreren benannten Logs | `Examples/Demo-003.ps1` | Hebt den Hauptvorteil von VPDLX hervor |
| N-06 | **`New-VPDLXLogfile` Public Wrapper** — PowerShell-Verb-Noun-konformer Wrapper um `[Logfile]::new()` | `Public/New-VPDLXLogfile.ps1` | Konventionell für PS-Skripter ohne OOP-Hintergrund |

***

## 7. Analyse: Fehlende Funktionalitäten im Detail

### 7.1 Fehlende `IsEmpty()` / `HasEntries()` Sicherheitsabfrage

Die `Read()`-Methode wirft eine `System.InvalidOperationException`, wenn der Log leer ist:

```powershell
if ($this._data.Count -eq 0) {
    throw [System.InvalidOperationException]::new(
        "Logfile '$($this.Name)' contains no entries."
    )
}
```

Ohne eine `IsEmpty()`- oder `HasEntries()`-Methode muss der Caller entweder `try/catch` verwenden oder den Umweg `$log.GetDetails().GetTotalEntries() -gt 0` nehmen. Eine einfache Methode würde den Code deutlich lesbarer machen:

```powershell
# Empfehlung für Logfile.ps1
[bool] IsEmpty()     { return $this._data.Count -eq 0 }
[bool] HasEntries()  { return $this._data.Count -gt 0 }
```

### 7.2 Fehlende direkte Eintragsanzahl

`GetDetails().GetTotalEntries()` ist ein Accessor-Chain über zwei Objekte für eine der am häufigsten benötigten Informationen. Da `_data.Count` und `_details._totalEntries` semantisch identisch sind, bietet sich eine Convenience-Property an:

```powershell
# Empfehlung für Logfile.ps1
[int] EntryCount() { return $this._data.Count }
```

### 7.3 Fehlende öffentliche Wrapper-Funktionen

Der Einstiegspunkt für Caller, die eine vorhandene Logfile-Instanz nach Name abrufen wollen, ist derzeit:

```powershell
$store = VPDLXcore -KeyID 'storage'
$log   = $store.Get('AppLog')
```

Das entspricht nicht der PS-Konvention für Modulnutzung. Eine Public-Funktion wäre:

```powershell
# Get-VPDLXLogfile.ps1
function Get-VPDLXLogfile {
    param([string] $Name)
    $store = VPDLXcore -KeyID 'storage'
    $instance = $store.Get($Name)
    if ($null -eq $instance) {
        return VPDLXreturn -Code -1 -Message "No logfile named '$Name' found."
    }
    return VPDLXreturn -Code 0 -Message "Logfile '$Name' retrieved." -Data $instance
}
```

***

## 8. Performance-Analyse

### 8.1 `List<string>` vs. Array für `_data`

Die Wahl von `System.Collections.Generic.List[string]` für `_data` statt eines PowerShell-Arrays (`[string[]]`) ist architektonisch korrekt und wichtig. Das Array-Append-Operator `+=` erzeugt bei jedem Aufruf eine vollständige Kopie — bei `n` Einträgen hat das eine O(n²)-Gesamtkomplexität. `List.Add()` ist O(1) amortisiert.

### 8.2 `Get-Date` bei jedem Eintrag

`BuildEntry()` ruft `Get-Date` für jeden einzelnen Eintrag auf:

```powershell
hidden [string] BuildEntry([string] $level, [string] $message) {
    [string] $ts = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
    ...
}
```

Bei `Print()`-Aufrufen mit großen Batches (z.B. 1000 Nachrichten) werden 1000 `Get-Date`-Aufrufe ausgeführt. Das ist zwar für typische Logging-Szenarien akzeptabel, aber bei sehr großen Batches messbar. 

**Optimierungsvorschlag:** Timestamp einmalig am Anfang von `Print()` capturieren und für alle Nachrichten desselben Batches verwenden:

```powershell
[void] Print([string] $level, [string[]] $messages) {
    [string] $normalizedLevel = $this.ValidateLevel($level)
    # ... Pre-Validation ...
    [string] $batchTs = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
    [string] $prefix  = [Logfile]::LogLevels[$normalizedLevel]
    foreach ($msg in $messages) {
        $this._data.Add("$batchTs$prefix$msg")
    }
    # ...
}
```

### 8.3 `Filter()` mit `Where-Object`

```powershell
$results = $this._data | Where-Object { $_ -match [regex]::Escape($marker) }
```

Die `Where-Object`-Pipeline hat in PowerShell Overhead gegenüber einer direkten .NET-Schleife. Bei Logs mit vielen Einträgen ist ein `.LINQ`-basierter Ansatz oder eine direkte `foreach`-Schleife mit `.Contains()` effizienter:

```powershell
# Optimierter Ansatz
[string[]] Filter([string] $level) {
    [string] $normalizedLevel = $this.ValidateLevel($level)
    [string] $marker          = "[$($normalizedLevel.ToUpper())]"
    $this._details.RecordRead()
    
    $results = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $this._data) {
        if ($line.Contains($marker)) {
            $results.Add($line)
        }
    }
    return $results.ToArray()
}
```

`.Contains()` ist bei einfachen String-Suchen ca. 2-5x schneller als `Where-Object { $_ -match ... }` bei großen Datensätzen, da kein Regex-Overhead entsteht und die Pipeline-Abstraktion vermieden wird.

### 8.4 `SoakUp()` — Memory Overhead

`SoakUp()` gibt via `$this._data.ToArray()` eine vollständige Kopie aller Log-Einträge zurück. Bei sehr großen Logs (>100.000 Einträge) verdoppelt sich damit der Arbeitsspeicherbedarf vorübergehend. Für Export-Zwecke, die das eigentliche Ziel von `SoakUp()` sind, wäre ein `IEnumerable`-basierter Ansatz speichereffizienter — für die typischen In-Memory-Logging-Szenarien ist die aktuelle Implementierung jedoch ausreichend.

### 8.5 `FileStorage._registry` Typ `[object]` statt `[Logfile]`

Das `_registry` Dictionary ist als `Dictionary[string, object]` deklariert, nicht als `Dictionary[string, Logfile]`. Der Grund ist PS 5.1-Kompatibilität (Forward-Reference). Dies bedeutet, dass alle `Get()`-Aufrufe ein Boxing/Unboxing durchführen. Der Performance-Einfluss ist bei der erwarteten Anzahl an Log-Instanzen vernachlässigbar, aber semantisch unschön.

***

## 9. Sicherheitsanalyse

### 9.1 PowerShell `hidden` ist kein echter Zugriffsschutz

Das Schlüsselwort `hidden` verhindert nur die Anzeige in IntelliSense und `Get-Member`-Ausgaben — kein echter Zugriffsschutz wie `private` in C#. Die Klassen-Dokumentation weist explizit darauf hin:

> *"IMPORTANT: PowerShell classes do not enforce true access control. 'hidden' merely suppresses the member from IntelliSense and Get-Member output."*

Ein bewusster Caller kann `_data` und `_details` direkt manipulieren:

```powershell
$log._data.Clear()          # Umgeht Reset()-Logik, kein Metadata-Update
$log._details._totalEntries = 999  # Korrumpiert Metadaten
```

**Einschätzung:** Für ein PowerShell-Modul, das innerhalb kontrollierter Skript-Umgebungen eingesetzt wird, ist dies akzeptabel. `hidden` kommuniziert klar die Design-Intention und schützt gegen versehentliche direkte Manipulation. Für sicherheitskritische Szenarien wäre eine C#-basierte Wrapper-Klasse mit echten `private`-Membern nötig — der Aufwand übersteigt den Nutzen in diesem Kontext deutlich.

### 9.2 Keine Thread-Safety / Parallel-Execution

VPDLX verwendet `List<string>` und `Dictionary<string, object>` ohne jegliche Synchronisationsmechanismen. Bei Verwendung in `ForEach-Object -Parallel` (PowerShell 7.x) sind Race Conditions auf `_data.Add()` und `_registry` möglich.

Das `[NoRunspaceAffinity()]`-Attribut (verfügbar ab PS 7.4) würde die Runspace-Bindung aufheben, löst aber nicht das grundlegende Problem der unsynchronisierten Datenstrukturen. Für Thread-Safety wäre `ConcurrentDictionary` und `ConcurrentBag` oder ein `ReaderWriterLockSlim` erforderlich.

**Empfehlung:** In der Dokumentation klar deklarieren, dass VPDLX **nicht** für parallele Ausführung ausgelegt ist, und dies als bekannte Einschränkung in der README.md festhalten.

### 9.3 Unbegrenzte In-Memory-Wachstum

Es gibt kein `MaxEntries`-Limit. Ein Caller, der `Write()` oder `Print()` in einer Endlosschleife aufruft, füllt ohne Gegenwehr den verfügbaren Arbeitsspeicher auf.

**Empfehlung:** Einen optionalen `MaxCapacity`-Parameter im `Logfile`-Konstruktor einführen, mit einem sinnvollen Default (z.B. 100.000). Bei Überschreitung könnte ein konfigurierbares Overflow-Verhalten greifen (Exception / Circular Buffer / Oldest-Entry-Drop).

### 9.4 Log Injection

Die `ValidateMessage()`-Methode prüft ausschließlich auf Nicht-Leer und Mindestlänge, nicht auf Inhalt. Ein Caller könnte bewusst mehrzeilige Nachrichten (`\n`, `\r`) einschleusen, die das Log-Format korrumpieren:

```powershell
$log.Write('info', "Normal message`n[28.04.2026 | 12:00:00]  [CRITICAL]  ->  Fake entry")
```

**Einschätzung:** In einer reinen In-Memory-Umgebung ohne direkten Sicherheitskontext ist Log Injection ein geringes Risiko. Beim Export in Dateien (zukünftige Funktionalität) sollte jedoch eine Eingabebereinigung erfolgen. Ein explizites Verbot von Newline-Zeichen in Messages wäre eine einfache Absicherung.

### 9.5 `Destroy()` — Dangling Reference

Nach `Destroy()` zeigt die Variable des Callers noch auf das `Logfile`-Objekt:

```powershell
$log = [Logfile]::new('MyLog')
$log.Destroy()
# $log ist NICHT null — der Caller muss $log = $null selbst setzen
$log.Name  # 'MyLog' — noch zugänglich!
$log.Write('info', 'Test')  # NullReferenceException, da _data = $null
```

Die Methode setzt `_data = $null` und `_details = $null`, was nachfolgende Methoden-Aufrufe mit `NullReferenceException` beantwortet — statt einer klaren, nutzerfreundlichen Fehlermeldung. Ein Guard-Pattern in kritischen Methoden wäre empfehlenswert:

```powershell
# Empfehlung: Guard am Anfang aller Schreibmethoden
hidden [void] GuardDestroyed() {
    if ($null -eq $this._data) {
        throw [System.ObjectDisposedException]::new(
            $this.Name, 
            "This Logfile instance has been destroyed. Set the variable to `$null."
        )
    }
}
```

***

## 10. Optimierungsmöglichkeiten — Zusammenfassung

| # | Bereich | Optimierung | Priorität | Aufwand |
|---|---|---|---|---|
| O-01 | **Performance** | `Filter()`: `Where-Object` durch `foreach` + `.Contains()` ersetzen | Mittel | Niedrig |
| O-02 | **Performance** | `Print()`: Einmaligen Timestamp für Batch statt je Entry | Niedrig | Niedrig |
| O-03 | **Performance** | `FileStorage._registry` auf `Dictionary[string,Logfile]` ändern (PS 7.x only) | Niedrig | Mittel |
| O-04 | **Robustheit** | `MaxCapacity`-Parameter im `Logfile`-Konstruktor | Hoch | Mittel |
| O-05 | **Robustheit** | `GuardDestroyed()`-Pattern für alle Methoden nach `Destroy()` | Mittel | Niedrig |
| O-06 | **Sicherheit** | Newline-Zeichen in `ValidateMessage()` verbieten | Mittel | Niedrig |
| O-07 | **Ergonomie** | `IsEmpty()` / `HasEntries()` Methoden | Hoch | Niedrig |
| O-08 | **Ergonomie** | `EntryCount()` Methode direkt auf `Logfile` | Mittel | Niedrig |
| O-09 | **Ergonomie** | `GetRange([int], [int])` Methode für Paginierung | Mittel | Niedrig |
| O-10 | **Parallelität** | `[NoRunspaceAffinity()]`-Attribut + Dokumentation der Einschränkungen | Niedrig | Niedrig |
| O-11 | **Wartbarkeit** | Pfad-Trennzeichen auf Forward-Slash (`/`) für PS Core Kompatibilität | Mittel | Trivial |
| O-12 | **Architektur** | Timestamps als `[datetime]` intern speichern, nur für Ausgabe in String umwandeln | Niedrig | Mittel |

***

## 11. Empfohlene Implementierungsreihenfolge

Die folgende Priorisierung basiert auf Impact/Effort-Verhältnis und logischer Abhängigkeit:

### Sprint 1 — Dokumentation (1–2 Tage)
1. **K-01:** CHANGELOG.md mit v1.01.00-Eintrag + Breaking Change
2. **K-02:** README.md neu schreiben
3. **K-03:** QUICKSTART.md neu schreiben
4. **K-04:** Demo-002.ps1 für v1.01.00 erstellen
5. **N-04:** Badge-Version in README korrigieren

### Sprint 2 — Klassen-Ergänzungen (1 Tag)
6. **W-03:** `IsEmpty()` + `HasEntries()` in `Logfile` (O-07)
7. **W-04:** `EntryCount()` in `Logfile` (O-08)
8. **O-05:** `GuardDestroyed()`-Pattern
9. **O-06:** Newline-Verbot in `ValidateMessage()`
10. **W-05:** Log-Level-Entscheidung und Umsetzung (VERBOSE/TRACE/FATAL)

### Sprint 3 — Public Wrapper & Struktur (1 Tag)
11. **K-05:** `Public/`-Verzeichnis anlegen
12. **W-01:** `Get-VPDLXLogfile` Wrapper
13. **W-02:** `Get-VPDLXLogfileList` Wrapper
14. **O-11:** Pfad-Trennzeichen korrigieren

### Sprint 4 — Performance & Extras (optional, 1–2 Tage)
15. **O-01:** `Filter()` optimieren
16. **O-02:** `Print()` Batch-Timestamp
17. **W-04:** `MaxCapacity`-Parameter
18. **N-02:** `Contains([string])` Suchmethode
19. **N-03:** `GetRange([int], [int])` Paginierung

***

## 12. Fazit

VPDLX v1.01.00 besitzt eine **solide, gut durchdachte klassenbasierte Kernarchitektur**. Die drei Klassen `FileDetails`, `FileStorage` und `Logfile` sind sauber voneinander getrennt, die Verantwortlichkeiten sind klar verteilt, und wichtige technische Entscheidungen (List statt Array, geordnetes Class-Loading, TypeAccelerator-Cleanup, Pre-Validation in `Print()`) sind korrekt und professionell umgesetzt.

Die **größte Schwachstelle** liegt nicht im Code selbst, sondern in der vollständigen Inkonsistenz zwischen der implementierten v1.01.00-API und sämtlichen Begleitdokumenten und Beispielen, die noch die v1.00.00-API beschreiben. Diese Diskrepanz macht das Modul für jeden neuen Nutzer praktisch unbenutzbar ohne direktes Quellcode-Studium.

Nach Abschluss von Sprint 1–3 (Dokumentation + Klassen-Ergänzungen + Public Wrapper) wäre v1.01.00 eine vollständige, produktionsreife Basis für alle virtuellen Logfile-Operationen ohne Export-Funktionalität.