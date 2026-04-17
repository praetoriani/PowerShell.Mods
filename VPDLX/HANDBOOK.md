# VPDLX API-Referenz

**Virtual PowerShell Data-Logger eXtension** — Vollständige Funktionsreferenz und Entwicklerdokumentation

**Version:** 1.02.06  
**Autor:** Praetoriani (M.Sczepanski)  
**Repository:** https://github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX

---

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [Installation](#installation)
3. [Kern-Konzepte](#kern-konzepte)
4. [Standardisierte Rückgabewerte](#standardisierte-rückgabewerte)
5. [Log-Level](#log-level)
6. [Log-Format](#log-format)
7. [Public-Funktionen](#public-funktionen)
8. [Export-Formate](#export-formate)
9. [Klassen-Architektur](#klassen-architektur)
10. [Fehlerbehandlung](#fehlerbehandlung)
11. [Best Practices](#best-practices)

---

## Übersicht

**VPDLX** (Virtual PowerShell Data-Logger eXtension) ist ein hochperformantes In-Memory-Logging-Modul für PowerShell. Es speichert Log-Einträge vollständig im RAM und ermöglicht blitzschnelle Schreibvorgänge ohne Disk-I/O-Latenz.

### Hauptmerkmale

- **In-Memory Logging**: Alle Daten werden in `[Logfile]`-Instanzen im RAM gespeichert
- **Strukturiertes Log-Format**: Festes Format `[Zeitstempel] [Level] -> Nachricht`
- **Multi-Format Export**: TXT, LOG, CSV, JSON, NDJSON, HTML
- **8 Log-Level**: info, debug, verbose, trace, warning, error, critical, fatal
- **Standardisierte API**: Alle Funktionen geben `[PSCustomObject]` mit `.code`, `.msg`, `.data` zurück
- **Keine Exceptions**: Fehlerbehandlung über Rückgabecodes, kein try/catch erforderlich
- **Filter-Funktionen**: Log-Einträge nach Level filtern
- **UTF-8 Support**: BOM-freie UTF-8-Ausgabe für maximale Kompatibilität

---

## Installation

```powershell
# Modul importieren
Import-Module .\VPDLX.psd1

# Verfügbare Funktionen anzeigen
Get-Command -Module VPDLX
```

---

## Kern-Konzepte

### Virtual Log Files

Eine virtuelle Logdatei ist ein **benanntes Objekt** im Arbeitsspeicher:

- **Name**: 3-64 Zeichen, alphanumerisch + `_`, `-`, `.`
- **Eindeutigkeit**: Case-insensitive ("AppLog" = "applog")
- **Lebensdauer**: Session-gebunden (beim Modul-Unload verloren)
- **Speicherort**: `$script:storage` ([FileStorage]-Singleton)

### Namenskonventionen

Alle Public-Funktionen folgen dem **VPDLX-Präfix-Schema** (kein Verb-Noun-Pattern):

```
VPDLX + <Verb> + logfile
```

Beispiele:
- `VPDLXnewlogfile` (erstellen)
- `VPDLXislogfile` (prüfen)
- `VPDLXwritelogfile` (schreiben)

---

## Standardisierte Rückgabewerte

**Alle Public-Funktionen** (außer `VPDLXislogfile`) geben ein `[PSCustomObject]` zurück:

```powershell
@{
    code = [int]     # 0 = Erfolg, -1 = Fehler
    msg  = [string]  # Human-readable Beschreibung
    data = [object]  # Nutzdaten (Erfolg) oder $null (Fehler)
}
```

### Verwendung

```powershell
$result = VPDLXnewlogfile -Logfile 'AppLog'

if ($result.code -eq 0) {
    # Erfolg
    $log = $result.data  # [Logfile]-Instanz
    Write-Host $result.msg
} else {
    # Fehler
    Write-Warning $result.msg
}
```

**Vorteil**: Keine try/catch-Blöcke erforderlich, einfaches if/else-Pattern.

---

## Log-Level

VPDLX unterstützt **8 Log-Level** (case-insensitive):

| Level | Beschreibung | Verwendung |
|-------|--------------|------------|
| `info` | Informativ | Normale Programmabläufe |
| `debug` | Debug | Entwickler-Diagnoseinformationen |
| `verbose` | Ausführlich | Detaillierte Ablaufinformationen |
| `trace` | Trace | Sehr detaillierte Debug-Infos |
| `warning` | Warnung | Potenzielle Probleme |
| `error` | Fehler | Fehlerzustände || `critical` | Kritisch | Kritische Fehler, die sofortiges Handeln erfordern |
| `fatal` | Fatal | Schwerwiegende Fehler, Programmabbruch |

**Severity-Reihenfolge** (aufsteigend):

```
trace < verbose < debug < info < warning < error < critical < fatal
```

---

## Log-Format

Jeder Log-Eintrag folgt diesem **festen Format**:

```
[dd.MM.yyyy | HH:mm:ss] [LEVEL] -> Nachricht
```

### Beispiel

```
[17.04.2026 | 14:32:15] [INFO] -> Application started successfully
[17.04.2026 | 14:32:18] [WARNING] -> Disk space below 10%
[17.04.2026 | 14:32:22] [ERROR] -> Database connection failed
[17.04.2026 | 14:32:25] [FATAL] -> Unrecoverable error, shutting down
```

**Eigenschaften**:
- **Zeitstempel**: Exakte Uhrzeit des `Write()`-Aufrufs
- **Level**: Uppercase (INFO, WARNING, ERROR, ...)
- **Nachricht**: User-definiert, min. 3 Zeichen, keine Newlines

---

## Public-Funktionen

VPDLX exportiert **9 Public-Funktionen** über `Export-ModuleMember`:

### Übersicht

| Funktion | Zweck | Rückgabetyp |
|----------|-------|---------------|
| [VPDLXnewlogfile](#vpdlxnewlogfile) | Neue Logdatei erstellen | PSCustomObject |
| [VPDLXislogfile](#vpdlxislogfile) | Existenzprüfung | bool |
| [VPDLXdroplogfile](#vpdlxdroplogfile) | Logdatei löschen | PSCustomObject |
| [VPDLXwritelogfile](#vpdlxwritelogfile) | Eintrag schreiben | PSCustomObject |
| [VPDLXreadlogfile](#vpdlxreadlogfile) | Eintrag lesen | PSCustomObject |
| [VPDLXfilterlogfile](#vpdlxfilterlogfile) | Nach Level filtern | PSCustomObject |
| [VPDLXexportlogfile](#vpdlxexportlogfile) | Zu Datei exportieren | PSCustomObject |
| [VPDLXresetlogfile](#vpdlxresetlogfile) | Alle Einträge löschen | PSCustomObject |
| [VPDLXgetalllogfiles](#vpdlxgetalllogfiles) | Alle Logdateien auflisten | PSCustomObject |

---

### VPDLXnewlogfile

**Erstellt eine neue virtuelle Logdatei.**

#### Syntax

```powershell
VPDLXnewlogfile -Logfile <string>
```

#### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|-------------|
| `Logfile` | `string` | Ja | Name der Logdatei (3-64 Zeichen, alphanumerisch + `_-.`) |

#### Rückgabe

```powershell
@{
    code = 0        # Erfolg
    msg  = "..."
    data = [Logfile] # Die neue Logdatei-Instanz
}
# oder
@{
    code = -1       # Fehler
    msg  = "..."
    data = $null
}
```

#### Fehler

- **Name zu kurz/lang**: "must be between 3 and 64 characters"
- **Ungültige Zeichen**: "may only contain alphanumeric characters plus underscore, hyphen, and dot"
- **Duplikat**: "already exists in the current session"

#### Beispiele

```powershell
# Neue Logdatei erstellen
$result = VPDLXnewlogfile -Logfile 'AppLog'

if ($result.code -eq 0) {
    $log = $result.data
    Write-Host "Logdatei erstellt: $($log.Name)"
} else {
    Write-Warning $result.msg
}

# Fehlerfall: Duplikat
$r1 = VPDLXnewlogfile -Logfile 'MyLog'  # code 0
$r2 = VPDLXnewlogfile -Logfile 'MyLog'  # code -1, "already exists"
```

---

### VPDLXislogfile

**Prüft, ob eine virtuelle Logdatei existiert.**

#### Syntax

```powershell
VPDLXislogfile -Logfile <string>
```

#### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|-------------|
| `Logfile` | `string` | Ja | Name der zu prüfenden Logdatei |

#### Rückgabe

**Typ**: `bool`

- `$true`: Logdatei existiert
- `$false`: Logdatei nicht gefunden oder Name null/leer

**Besonderheit**: Diese Funktion gibt KEIN `[PSCustomObject]` zurück, sondern direkt `bool`.

#### Beispiele

```powershell
# Existenzprüfung vor Schreibzugriff
if (VPDLXislogfile -Logfile 'AppLog') {
    $result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Ready'
} else {
    $result = VPDLXnewlogfile -Logfile 'AppLog'
}

# Guard-Pattern
if (-not (VPDLXislogfile 'DiagLog')) {
    VPDLXnewlogfile 'DiagLog'
}
```

---

### VPDLXdroplogfile

**Löscht eine virtuelle Logdatei permanent aus dem Speicher.**

#### Syntax

```powershell
VPDLXdroplogfile -Logfile <string>
```

#### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|-------------|
| `Logfile` | `string` | Ja | Name der zu löschenden Logdatei |

#### Rückgabe

```powershell
@{
    code = 0        # Erfolg
    msg  = "..."
    data = $null   # Immer $null (gelöschte Instanz hat keine Nutzdaten)
}
# oder
@{
    code = -1       # Fehler
    msg  = "..."
    data = $null
}
```

#### Warnung

> **DESTRUCTIVE OPERATION**: Diese Aktion ist **unwiderruflich**. Alle Log-Daten gehen permanent verloren. Vor dem Aufruf ggf. `VPDLXexportlogfile` verwenden.

#### Fehler

- **Nicht gefunden**: "does not exist in the current session"
- **Modul nicht initialisiert**: Fehler beim Zugriff auf den internen Speicher

#### Beispiele

```powershell
# Logdatei löschen
$result = VPDLXdroplogfile -Logfile 'AppLog'

if ($result.code -eq 0) {
    Write-Host 'Logdatei erfolgreich gelöscht'
} else {
    Write-Warning $result.msg
}

# Sicheres Pattern: Existenz prüfen vor dem Löschen
if (VPDLXislogfile -Logfile 'TempLog') {
    $result = VPDLXdroplogfile -Logfile 'TempLog'
}

# Fehlerfall: Logdatei existiert nicht
$result = VPDLXdroplogfile -Logfile 'Ghost'  # code -1
```

---

### VPDLXwritelogfile

**Schreibt einen neuen Eintrag in eine virtuelle Logdatei.**

#### Syntax

```powershell
VPDLXwritelogfile -Logfile <string> -Level <string> -Message <string>
```

#### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|-------------|
| `Logfile` | `string` | Ja | Name der Ziel-Logdatei |
| `Level` | `string` | Ja | Log-Level (info/debug/verbose/trace/warning/error/critical/fatal) |
| `Message` | `string` | Ja | Log-Nachricht (min. 3 Nicht-Whitespace-Zeichen, keine Newlines) |

#### Parameter-Details: Level

- **Validierung**: `[ValidateSet]` am PowerShell-Binding-Layer (frühe Ablehnung)
- **Case-insensitiv**: `INFO`, `info`, `Info` sind äquivalent
- **Tab-Completion**: Vollständig unterstützt in ISE und VS Code

**Gültige Werte**: `info` | `debug` | `verbose` | `trace` | `warning` | `error` | `critical` | `fatal`

#### Parameter-Details: Message

- Darf nicht null, leer oder nur Whitespace sein
- Muss **mindestens 3 Nicht-Whitespace-Zeichen** enthalten
- Darf **keine Newlines** enthalten (CR oder LF) — verhindert Log-Injection

#### Rückgabe

```powershell
@{
    code = 0
    msg  = "..."
    data = [int]    # Neue Gesamtanzahl der Einträge
}
# oder
@{
    code = -1
    msg  = "..."
    data = $null
}
```

#### Fehler

- **Logdatei nicht gefunden**: "does not exist in the current session"
- **Ungültiger Level**: "Cannot validate argument on parameter 'Level'"
- **Nachricht zu kurz**: "must contain at least 3 non-whitespace characters"
- **Newline in Nachricht**: "must not contain newline characters"

#### Beispiele

```powershell
# Einfachen Eintrag schreiben
$result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Application started'

if ($result.code -eq 0) {
    Write-Host "Eintrag geschrieben. Gesamt: $($result.data)"
}

# Verschiedene Log-Level
VPDLXwritelogfile -Logfile 'AppLog' -Level 'warning' -Message 'Disk space below 10%'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'error'   -Message 'Connection to DB failed'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'critical' -Message 'Service unavailable'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'fatal'   -Message 'Unrecoverable error'

# Fehlerfall: Ungültiger Level (wird bereits am Binding-Layer abgelehnt)
VPDLXwritelogfile -Logfile 'AppLog' -Level 'notice' -Message 'Test'
# Fehler: "Cannot validate argument on parameter 'Level'..."

# Fehlerfall: Nachricht mit Newline
$result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message "Line1`nLine2"
# $result.code -> -1
```

---

### VPDLXreadlogfile

**Liest einen einzelnen Eintrag aus einer virtuellen Logdatei.**

#### Syntax

```powershell
VPDLXreadlogfile -Logfile <string> -Line <int>
```

#### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|-------------|
| `Logfile` | `string` | Ja | Name der Logdatei |
| `Line` | `int` | Ja | 1-basierte Zeilennummer |

#### Parameter-Details: Line

- **1-basiert**: Erste Zeile = 1
- **Auto-Clamping**: Werte außerhalb des gültigen Bereichs werden automatisch geclampd:
  - Wert < 1 → wird zu 1 (erster Eintrag)
  - Wert > Anzahl Einträge → wird zum letzten Eintrag
- **Kein Out-of-Range-Fehler** für Integer-Eingaben

#### Rückgabe

```powershell
@{
    code = 0
    msg  = "...read line X of Y..."
    data = [string]    # Der Log-Eintrag (vollständiger formatierter String)
}
# oder
@{
    code = -1
    msg  = "..."
    data = $null
}
```

#### Fehler

- **Logdatei nicht gefunden**: "does not exist"
- **Leere Logdatei**: "contains no entries"

#### Beispiele

```powershell
# Zeile 3 lesen
$result = VPDLXreadlogfile -Logfile 'AppLog' -Line 3

if ($result.code -eq 0) {
    Write-Host "Zeile 3: $($result.data)"
}

# Alle Einträge iterieren
$r = VPDLXgetalllogfiles
$log = ($r.data.Files | Where-Object { $_.Name -eq 'AppLog' })
$count = $log.EntryCount

for ($i = 1; $i -le $count; $i++) {
    $entry = VPDLXreadlogfile -Logfile 'AppLog' -Line $i
    Write-Host $entry.data
}

# Clamping in Aktion: Log hat 5 Einträge
$r = VPDLXreadlogfile -Logfile 'AppLog' -Line 0   # Liest Eintrag #1
$r = VPDLXreadlogfile -Logfile 'AppLog' -Line 99  # Liest Eintrag #5 (letzter)
```

---

### VPDLXfilterlogfile

**Filtert Log-Einträge nach einem bestimmten Level.**

#### Syntax

```powershell
VPDLXfilterlogfile -Logfile <string> -Level <string>
```

#### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|-------------|
| `Logfile` | `string` | Ja | Name der Logdatei |
| `Level` | `string` | Ja | Level, nach dem gefiltert werden soll |

**Gültige Werte für Level**: `info` | `debug` | `verbose` | `trace` | `warning` | `error` | `critical` | `fatal`

#### Rückgabe

```powershell
@{
    code = 0
    msg  = "..."
    data = [PSCustomObject]@{
        Entries = [string[]]    # Array der gefundenen Einträge
        Count   = [int]         # Anzahl der Treffer
        Level   = [string]      # Gefilterter Level
    }
}
# oder
@{
    code = -1
    msg  = "..."
    data = $null
}
```

**Hinweis**: Bei code 0 kann `data.Count` auch 0 sein, wenn keine Einträge mit dem Level gefunden wurden.

#### Fehler

- **Logdatei nicht gefunden**: "does not exist"
- **Ungültiger Level**: Am Binding-Layer (ValidateSet)

#### Beispiele

```powershell
# Alle Error-Einträge filtern
$result = VPDLXfilterlogfile -Logfile 'AppLog' -Level 'error'

if ($result.code -eq 0) {
    Write-Host "$($result.data.Count) Error-Einträge gefunden:"
    $result.data.Entries | ForEach-Object { Write-Host $_ }
}

# Nur Warnungen anzeigen
$r = VPDLXfilterlogfile -Logfile 'AppLog' -Level 'warning'
if ($r.code -eq 0 -and $r.data.Count -gt 0) {
    $r.data.Entries | ForEach-Object { Write-Host $_ }
}
```

---

### VPDLXexportlogfile

**Exportiert eine virtuelle Logdatei in eine physische Datei auf der Festplatte.**

#### Syntax

```powershell
VPDLXexportlogfile -Logfile <string> -LogPath <string> -ExportAs <string> [-Override] [-NoBOM]
```

#### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|-------------|
| `Logfile` | `string` | Ja | Name der Logdatei |
| `LogPath` | `string` | Ja | Zielverzeichnis (wird automatisch erstellt, falls nicht vorhanden) |
| `ExportAs` | `string` | Ja | Exportformat (txt/log/csv/json/html/ndjson) |
| `Override` | `switch` | Nein | Bestehende Datei überschreiben |
| `NoBOM` | `switch` | Nein | UTF-8 ohne BOM erzwingen (wichtig für PS 5.1 + Unix-Tools) |

#### Parameter-Details: ExportAs

| Wert | Dateiendung | Beschreibung |
|------|------------|-------------|
| `txt` | `.txt` | Klartext, ein Eintrag pro Zeile |
| `log` | `.log` | Identisch mit txt, andere Endung |
| `csv` | `.csv` | Comma-Separated Values mit Header |
| `json` | `.json` | JSON-Array, in Root-Objekt verpackt |
| `html` | `.html` | Vollständiger HTML-Report mit CSS-Styling (**NEU v1.02.06**) |
| `ndjson` | `.ndjson` | Newline-Delimited JSON (**NEU v1.02.06**) |

#### Datei-Naming

Der Dateiname ergibt sich aus: `<Logfile-Name>.<Endung>`

```
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'csv'
-> C:\Logs\AppLog.csv
```

#### Export-Formate im Detail

**CSV-Format** (`csv`):
```csv
"Timestamp","Level","Message"
"17.04.2026 | 14:32:15","INFO","Application started"
```

**JSON-Format** (`json`):
```json
{
  "LogFile": "AppLog",
  "ExportedAt": "17.04.2026 | 14:32:00",
  "EntryCount": 3,
  "Entries": [
    { "Timestamp": "17.04.2026 | 14:32:15", "Level": "INFO", "Message": "Application started" }
  ]
}
```

**NDJSON-Format** (`ndjson`) — ein JSON-Objekt pro Zeile:
```
{"Timestamp":"17.04.2026 | 14:32:15","Level":"INFO","Message":"Application started"}
{"Timestamp":"17.04.2026 | 14:32:18","Level":"WARNING","Message":"Disk space low"}
```

**HTML-Format** (`html`) — Selbst-enthaltener HTML-Bericht:
- Header mit Log-Name, Export-Zeitstempel und Anzahl Einträge
- Tabelle mit Timestamp/Level/Message
- Level-spezifisches Row-Coloring (Rot=ERROR/FATAL, Orange=WARNING/CRITICAL, Grün=INFO, Blau=DEBUG/VERBOSE/TRACE)
- Responsives Layout, druckbereit

#### -Override Verhalten

| Situation | Ohne -Override | Mit -Override |
|-----------|---------------|---------------|
| Datei existiert nicht | Datei wird erstellt | Datei wird erstellt |
| Datei existiert bereits | code -1 (Fehler) | Alte Datei wird gelöscht, neue erstellt |

#### -NoBOM Verhalten

| PowerShell-Version | Ohne -NoBOM | Mit -NoBOM |
|-------------------|------------|------------|
| Windows PS 5.1 | UTF-8 **mit** BOM (EF BB BF) | UTF-8 ohne BOM |
| PowerShell 7.x | UTF-8 ohne BOM | UTF-8 ohne BOM (kein Unterschied) |

**Empfehlung**: `-NoBOM` immer verwenden bei Verwendung mit Unix-Tools, Filebeat, Fluentd, Grafana Loki, JSON-Parsern.

#### Rückgabe

```powershell
@{
    code = 0
    msg  = "..."
    data = [string]    # Vollständiger Pfad zur erstellten Datei
}
# oder
@{
    code = -1
    msg  = "..."
    data = $null
}
```

#### Fehler

- **Unbekanntes Format**: "is not a supported export format"
- **Logdatei nicht gefunden**: "does not exist"
- **Leere Logdatei**: "contains no entries"
- **Datei existiert + kein -Override**: "already exists. Use -Override to overwrite"
- **Verzeichnis-Erstellung fehlgeschlagen**: "Failed to create target directory"

#### Beispiele

```powershell
# Einfacher Textexport
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'txt'
if ($result.code -eq 0) {
    Write-Host "Exportiert nach: $($result.data)"
}

# CSV-Export mit Auto-Verzeichnis-Erstellung
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\NewDir\Sub' -ExportAs 'csv'

# JSON-Export mit Überschreiben und BOM-frei
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json' -Override -NoBOM

# HTML-Report erstellen (v1.02.06)
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Reports' -ExportAs 'html'

# NDJSON für Log-Streaming-Pipeline (v1.02.06)
$result = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM
```

---

### VPDLXresetlogfile

**Löscht alle Einträge einer Logdatei, behält aber die Logdatei selbst.**

#### Syntax

```powershell
VPDLXresetlogfile -Logfile <string>
```

#### Parameter

| Parameter | Typ | Pflicht | Beschreibung |
|-----------|-----|---------|-------------|
| `Logfile` | `string` | Ja | Name der zurückzusetzenden Logdatei |

#### Unterschied zu VPDLXdroplogfile

| Aktion | VPDLXresetlogfile | VPDLXdroplogfile |
|--------|-------------------|------------------|
| Einträge gelöscht | Ja | Ja |
| Logdatei gelöscht | **Nein** (bleibt registriert) | **Ja** (komplett entfernt) |

#### Rückgabe

```powershell
@{
    code = 0
    msg  = "..."
    data = $null
}
# oder
@{
    code = -1
    msg  = "..."
    data = $null
}
```

#### Fehler

- **Logdatei nicht gefunden**: "does not exist"

#### Beispiele

```powershell
# Log zurücksetzen (Einträge löschen, Objekt behalten)
$result = VPDLXresetlogfile -Logfile 'AppLog'

if ($result.code -eq 0) {
    Write-Host 'Logdatei zurückgesetzt'
    # Log ist weiterhin registriert, bereit für neue Einträge
    VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'New session started'
}

# Pattern: Log exportieren, dann zurücksetzen
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Archive' -ExportAs 'json'
VPDLXresetlogfile  -Logfile 'AppLog'
```

---

### VPDLXgetalllogfiles

**Gibt eine Übersicht aller registrierten virtuellen Logdateien zurück.**

#### Syntax

```powershell
VPDLXgetalllogfiles
```

#### Parameter

Keine Parameter.

#### Rückgabe

```powershell
@{
    code = 0
    msg  = "..."
    data = [PSCustomObject]@{
        Count = [int]             # Anzahl registrierter Logdateien
        Files = [PSCustomObject[]] # Array mit Infos zu jeder Logdatei
        # Jedes Files-Objekt:
        # @{
        #     Name       = [string]
        #     EntryCount = [int]
        # }
    }
}
# oder
@{
    code = -1
    msg  = "..."
    data = $null
}
```

**Hinweis**: Bei code 0 kann `data.Count` auch 0 sein, wenn keine Logdateien registriert sind.

#### Fehler

- Modul nicht initialisiert: Fehler beim Zugriff auf den internen Speicher

#### Beispiele

```powershell
# Alle Logdateien auflisten
$result = VPDLXgetalllogfiles

if ($result.code -eq 0) {
    Write-Host "$($result.data.Count) Logdateien registriert:"
    $result.data.Files | ForEach-Object {
        Write-Host "  - $($_.Name) ($($_.EntryCount) Einträge)"
    }
}

# Alle Logdateien exportieren
$allLogs = VPDLXgetalllogfiles
if ($allLogs.code -eq 0) {
    $allLogs.data.Files | ForEach-Object {
        VPDLXexportlogfile -Logfile $_.Name -LogPath 'C:\Logs' -ExportAs 'json' -Override
    }
}
```

---

## Export-Formate

VPDLX unterstützt **6 Export-Formate** über `VPDLXexportlogfile -ExportAs`:

### Formatvergleich

| Format | Erweiterung | Struktur | Verwendung |
|--------|-------------|----------|------------|
| **txt** | `.txt` | Klartext | Einfache Textansicht |
| **log** | `.log` | Klartext | Tools, die .log-Dateien erwarten |
| **csv** | `.csv` | Strukturiert, Header-Zeile | Excel, SQL-Import, Datenanalyse |
| **json** | `.json` | JSON-Array, Root-Objekt | REST-APIs, Webapps, Archivierung |
| **ndjson** | `.ndjson` | JSON, 1 Objekt pro Zeile | Filebeat, Fluentd, Logstash, Grafana Loki |
| **html** | `.html` | HTML-Tabelle + CSS | Browser-Ansicht, E-Mail, Drucken |

### Wann welches Format?

- **txt/log**: Einfaches Lesen in Texteditoren, Grepping
- **csv**: Import in Excel, SQL-Datenbanken, PowerBI
- **json**: REST-APIs, langfristige Archivierung, strukturierte Analyse
- **ndjson**: Log-Streaming-Pipelines (ELK-Stack, Splunk, Grafana)
- **html**: Management-Reports, E-Mail-Versand, Browser-Anzeige

---

## Klassen-Architektur

VPDLX basiert auf **3 Kernklassen** in `Classes/`:

### [Logfile]

**Hauptklasse** für virtuelle Logdateien.

**Eigenschaften**:
- `Name` (string, read-only): Logdatei-Name
- `LogLevels` (Hashtable, static): Mapping aller 8 Level

**Methoden**:
- `Write(level, message)`: Eintrag hinzufügen
- `Read(line)`: 1-basierten Eintrag lesen (Auto-Clamping)
- `FilterByLevel(level)`: Einträge nach Level filtern
- `GetAllEntries()`: Alle Einträge als `string[]`
- `EntryCount()`: Anzahl der Einträge
- `IsEmpty()`: Prüft, ob leer
- `Reset()`: Alle Einträge löschen
- `Destroy()`: Instanz zerstören (Destructor-Pattern)

### [FileStorage]

**Singleton** für zentrale Logdatei-Verwaltung.

**Eigenschaften**:
- `_files` (Dictionary<string, Logfile>): Interner Speicher

**Methoden**:
- `Add(logfile)`: Logdatei registrieren
- `Get(name)`: Logdatei abrufen
- `Contains(name)`: Existenzprüfung
- `Remove(name)`: Logdatei deregistrieren
- `GetAll()`: Alle Logdateien als Array
- `Count()`: Anzahl registrierter Logdateien

**Verwendung im Modul**:
```powershell
$script:storage = [FileStorage]::new()  # Singleton in VPDLX.psm1
```

### [FileDetails]

**Metadaten-Companion** für `[Logfile]`.

**Eigenschaften**:
- `Created` (DateTime): Erstellungszeitpunkt
- `LastUpdated` (DateTime): Letzte Änderung
- `LastAccessed` (DateTime): Letzter Zugriff
- `LastAccessType` (string): Art des letzten Zugriffs (Write/Read/Filter)
- `AccessCount` (int): Anzahl Zugriffe gesamt
- `EntryCount` (int): Anzahl Einträge (redundant mit Logfile._data.Count)

**Methoden**:
- `RecordWrite()`: Schreibzugriff protokollieren
- `RecordRead()`: Lesezugriff protokollieren
- `RecordFilter()`: Filterzugriff protokollieren

---

## Fehlerbehandlung

### Keine Exceptions!

VPDLX wirft **keine Exceptions** in normalen Fehlersituationen. Alle Fehler werden als `code -1` zurückgegeben.

**Vorteile**:
- Kein try/catch erforderlich
- Einfaches if/else-Pattern
- Vorhersehbare Programmflüsse

**Pattern**:
```powershell
$result = VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Test'

if ($result.code -ne 0) {
    Write-Warning "Log-Fehler: $($result.msg)"
    # Fehlerbehandlung
}
```

### Fehlerarten

| Fehlertyp | code | data | Beispiel msg |
|-----------|------|------|-------------|
| Nicht gefunden | -1 | $null | "does not exist in the current session" |
| Duplikat | -1 | $null | "already exists" |
| Validierung | -1 | $null | "must be between 3 and 64 characters" |
| Leer | -1 | $null | "contains no entries" |
| Modul-Fehler | -1 | $null | "VPDLXcore did not return a valid..." |

---

## Best Practices

### 1. Immer Rückgabewerte prüfen

```powershell
# ✓ GUT
$result = VPDLXnewlogfile -Logfile 'AppLog'
if ($result.code -eq 0) {
    # Weiter mit $result.data
}

# ✗ SCHLECHT (ignoriert Fehler)
VPDLXnewlogfile -Logfile 'AppLog'
```

### 2. Existenzprüfung vor Zugriffen

```powershell
# ✓ GUT
if (-not (VPDLXislogfile 'AppLog')) {
    VPDLXnewlogfile 'AppLog'
}
VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Test'

# ✗ SCHLECHT (wirft code -1, wenn nicht vorhanden)
VPDLXwritelogfile -Logfile 'AppLog' -Level 'info' -Message 'Test'
```

### 3. Export vor Destroy/Reset

```powershell
# ✓ GUT: Daten sichern
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Archive' -ExportAs 'json'
VPDLXdroplogfile -Logfile 'AppLog'

# ✗ SCHLECHT: Daten unwiederbringlich verloren
VPDLXdroplogfile -Logfile 'AppLog'
```

### 4. -NoBOM bei Unix-Tools/Pipelines

```powershell
# ✓ GUT: BOM-frei für Filebeat/Fluentd
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM

# ✗ Problematisch: PS 5.1 schreibt BOM, JSON-Parser können versagen
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'json'
```

### 5. Structured Logging Pattern

```powershell
# ✓ Konsistentes Structured-Logging
function Log-Action {
    param(
        [string]$Action,
        [string]$Level = 'info',
        [hashtable]$Data
    )
    
    $msg = "$Action | $($Data.Keys | ForEach-Object { "$_=$($Data[$_])" } | Join-String -Separator ' | ')"
    VPDLXwritelogfile -Logfile 'AppLog' -Level $Level -Message $msg
}

Log-Action -Action 'UserLogin' -Data @{ User='Admin'; IP='192.168.1.1' }
Log-Action -Action 'FileProcessed' -Data @{ File='data.csv'; Rows=1500 }
```

### 6. Log-Rotation mit Reset

```powershell
# Logs täglich exportieren und zurücksetzen
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
VPDLXexportlogfile -Logfile 'AppLog' -LogPath "C:\Logs\Archive\AppLog_$timestamp" -ExportAs 'json'
VPDLXresetlogfile -Logfile 'AppLog'
```

### 7. Alle Logs beim Skript-Ende exportieren

```powershell
try {
    # Hauptskript
    VPDLXnewlogfile 'AppLog'
    # ... Ihre Logik ...
} finally {
    # Cleanup: Alle Logs exportieren
    $allLogs = VPDLXgetalllogfiles
    if ($allLogs.code -eq 0) {
        $allLogs.data.Files | ForEach-Object {
            VPDLXexportlogfile -Logfile $_.Name -LogPath 'C:\Logs' -ExportAs 'json' -Override -NoBOM
        }
    }
}
```

---

## Vollständiges Beispiel

```powershell
# VPDLX Modul laden
Import-Module .\VPDLX.psd1

# Log erstellen
$r = VPDLXnewlogfile -Logfile 'DeploymentLog'
if ($r.code -ne 0) {
    Write-Error "Konnte Log nicht erstellen: $($r.msg)"
    exit 1
}

# Einträge schreiben
VPDLXwritelogfile -Logfile 'DeploymentLog' -Level 'info'     -Message 'Deployment started'
VPDLXwritelogfile -Logfile 'DeploymentLog' -Level 'verbose' -Message 'Connecting to server'
VPDLXwritelogfile -Logfile 'DeploymentLog' -Level 'warning' -Message 'Server latency high'
VPDLXwritelogfile -Logfile 'DeploymentLog' -Level 'info'    -Message 'Files deployed successfully'

# Einträge filtern
$warnings = VPDLXfilterlogfile -Logfile 'DeploymentLog' -Level 'warning'
if ($warnings.code -eq 0 -and $warnings.data.Count -gt 0) {
    Write-Host "$($warnings.data.Count) Warnungen gefunden"
}

# Als HTML exportieren (für Management-Report)
VPDLXexportlogfile -Logfile 'DeploymentLog' -LogPath 'C:\Reports' -ExportAs 'html'

# Als NDJSON exportieren (für Grafana Loki)
VPDLXexportlogfile -Logfile 'DeploymentLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM

# Cleanup
VPDLXdroplogfile -Logfile 'DeploymentLog'
```

---

## Support & Mitwirken

**Repository**: https://github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX  
**Issues**: https://github.com/praetoriani/PowerShell.Mods/issues  
**Autor**: Praetoriani (M.Sczepanski)

---

*Letzte Aktualisierung: 17.04.2026 (v1.02.06)*
