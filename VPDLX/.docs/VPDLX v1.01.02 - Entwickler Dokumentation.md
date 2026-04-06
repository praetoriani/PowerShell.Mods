<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# VPDLX v1.01.02 — Entwickler Dokumentation

**Dokumentationsversion:** 1.0 | **Erstellt:** 06.04.2026 | **Autor:** basierend auf vollständiger Analyse des GitHub-Repositorys [praetoriani/PowerShell.Mods](https://github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX)

***

## 1. Projekteinleitung

**VPDLX** (kurz für *Virtual PowerShell Data-Logger eXtension*) ist ein vollständig klassenbasiertes, virtuelles Logging-Modul für PowerShell 5.1 und PowerShell Core. Es ermöglicht das Erstellen, Verwalten und Abfragen beliebig vieler virtueller Log-Dateien gleichzeitig — ausschließlich im Arbeitsspeicher, ohne unmittelbaren Zugriff auf das Dateisystem. Erst bei Bedarf werden die in-memory gehaltenen Logs in ein physisches Format exportiert.

Das Modul verfolgt einen modernen OOP-Ansatz in PowerShell: Sämtliche Kernfunktionalität ist in drei PowerShell-Klassen kapselisiert, die als TypeAcceleratoren registriert werden, sodass sie nach einem einfachen `Import-Module VPDLX` unmittelbar als `[Logfile]`, `[FileDetails]` und `[FileStorage]` verwendet werden können — ohne das umständliche `using module`-Konstrukt.  Das Projekt befindet sich aktuell in einer frühen, aber architektonisch soliden Phase (v1.01.02) und wurde am 05.–06.04.2026 von Grund auf neu entwickelt.

***

## 2. Aktueller Funktionsumfang (Grobe Übersicht)

Die aktuelle Version v1.01.02 bietet folgende Kernbestandteile:

**Klassen-Schicht (Classes/)**

- `[Logfile]` — Hauptklasse; erstellt und verwaltet einen virtuellen Log-Eintrag im Speicher
- `[FileDetails]` — Metadaten-Begleiter jeder Logfile-Instanz (Timestamps, Interaktionszähler)
- `[FileStorage]` — Zentrales Registry-Singleton für alle aktiven Logfile-Instanzen

**Public Wrapper Layer (Public/)**

- `VPDLXnewlogfile` — neue virtuelle Log-Datei anlegen
- `VPDLXislogfile` — Prüfen ob eine Log-Datei existiert
- `VPDLXdroplogfile` — Logfile dauerhaft entfernen
- `VPDLXreadlogfile` — einzelne Zeile lesen (1-basiert, mit Clamping)
- `VPDLXwritelogfile` — Eintrag anhängen
- `VPDLXexportlogfile` — Export auf Disk als `txt`, `log`, `csv` oder `json`

**Infrastruktur**

- `VPDLXcore` — kontrollierter Read-Only-Accessor für modulinterne Variablen (`appinfo`, `storage`, `export`)

***

## 3. Issue-Abarbeitung

Zum Zeitpunkt dieser Dokumentation sind im GitHub Issue-Tracker **10 offene Issues** vorhanden.  Sie werden nachfolgend nach Priorität gruppiert und mit konkreten Umsetzungsempfehlungen versehen.

### 3.1 Kritische Bugs (Sofortiger Handlungsbedarf)


***

#### Issue \#1 — `Logfile.Destroy()` ruft `GuardDestroyed()` nicht auf (Stilles Doppel-Destroy)

**Schweregrad:** Hoch | **Datei:** `Classes/Logfile.ps1`

**Problem:** `Destroy()` ist die einzige öffentliche Methode der `[Logfile]`-Klasse, die **nicht** mit `$this.GuardDestroyed()` beginnt. Ein zweiter Aufruf von `Destroy()` auf einer bereits zerstörten Instanz läuft lautlos durch, weil die interne `if ($null -ne $this._data)`-Prüfung einfach übersprungen wird. Alle anderen Methoden (`Write`, `Print`, `Read`, `Reset` etc.) werfen korrekt eine `ObjectDisposedException`.

**Konkrete Auswirkung:** Logikfehler im aufrufenden Code bleiben vollständig unsichtbar. Doppeltes Aufrufen von `Destroy()` führt zu keiner Fehlermeldung.

**Empfohlene Umsetzung:**

```powershell
[void] Destroy() {
    # Guard gegen Doppel-Destroy — konsistent mit allen anderen public Methoden
    $this.GuardDestroyed()

    $script:storage.Remove($this.Name)
    $this._data.Clear()
    $this._data    = $null
    $this._details = $null
}
```

Mit dem `GuardDestroyed()`-Aufruf an erster Stelle ist das umschließende `if`-Konstrukt redundant und kann entfernt werden. **Wichtig:** Issue \#1 und Issue \#6 betreffen dieselbe Methode und sollten zwingend zusammen in einem einzelnen Commit gelöst werden.

***

#### Issue \#6 — `Logfile.Destroy()` hat kein try/catch um `storage.Remove()` — Halbzerstörter Zustand möglich

**Schweregrad:** Mittel–Hoch | **Datei:** `Classes/Logfile.ps1`

**Problem:** `FileStorage.Remove()` wirft by Design eine `InvalidOperationException`, wenn der Name nicht im Registry gefunden wird (z. B. nach manueller Entfernung via `VPDLXcore -KeyID 'storage'`). Wenn diese Exception geworfen wird, werden die nachfolgenden Cleanup-Zeilen `$this._data = $null` und `$this._details = $null` **nie erreicht**. Die Instanz verbleibt in einem halbzerstörten Zustand: aus dem Storage entfernt, aber mit vollem `_data`-Inhalt im Speicher.

**Empfohlene Umsetzung (kombiniert mit Issue \#1):**

```powershell
[void] Destroy() {
    $this.GuardDestroyed()  # Fix für Issue #1

    try {
        $script:storage.Remove($this.Name)
    }
    catch [System.InvalidOperationException] {
        Write-Verbose (
            "VPDLX: Destroy() konnte '$($this.Name)' nicht aus FileStorage entfernen " +
            "(bereits entfernt oder Registry-Inkonsistenz): $($_.Exception.Message)"
        )
    }
    finally {
        # Immer ausführen — unabhängig ob Remove() erfolgreich war oder nicht
        $this._data.Clear()
        $this._data    = $null
        $this._details = $null
    }
}
```

Der `finally`-Block garantiert, dass `_data` und `_details` **immer** auf `$null` gesetzt werden, was `GuardDestroyed()` bei anschließenden Zugriffen korrekt auslösen lässt.

***

#### Issue \#3 — `Logfile.ToString()` wirft `NullReferenceException` nach `Destroy()`

**Schweregrad:** Mittel | **Datei:** `Classes/Logfile.ps1`

**Problem:** `ToString()` enthält eine partielle Null-Prüfung für `_data`, greift aber anschließend **bedingungslos** auf `$this._details.GetCreated()` zu. Da `Destroy()` beide Felder auf `$null` setzt, führt jeder implizite Aufruf von `ToString()` nach `Destroy()` — sei es durch String-Interpolation (`"$log"`), `Write-Host`, Pipeline-Ausgabe oder einfaches Eingeben der Variable in der Konsole — zu einer unhilfreichen `NullReferenceException` statt der erwarteten `ObjectDisposedException`.

**Empfohlene Umsetzung (Option A — konsistent mit allen anderen Methoden):**

```powershell
[string] ToString() {
    $this.GuardDestroyed()
    return "Logfile: '$($this.Name)' | Entries: $($this._data.Count) | Created: $($this._details.GetCreated())"
}
```

**Alternative (Option B — nie werfend, für Debug-Szenarien):**

```powershell
[string] ToString() {
    if ($null -eq $this._data -or $null -eq $this._details) {
        return "Logfile: '$($this.Name)' | DESTROYED"
    }
    return "Logfile: '$($this.Name)' | Entries: $($this._data.Count) | Created: $($this._details.GetCreated())"
}
```

Option A ist für die Konsistenz des API-Vertrages vorzuziehen.

***

#### Issue \#2 — `RecordFilter()` wird **vor** dem Filtervorgang aufgerufen — Vorzeitige Metadaten-Aktualisierung

**Schweregrad:** Mittel | **Datei:** `Classes/Logfile.ps1`

**Problem:** In `FilterByLevel()` wird `$this._details.RecordFilter()` **vor** der eigentlichen `foreach`-Schleife aufgerufen. Alle anderen Methoden der Klasse aktualisieren die Metadaten erst **nach** dem Abschluss der eigentlichen Operation. Wenn die Schleife aus irgendwelchen Gründen (z. B. Threading in zukünftigen Versionen) fehlschlagen würde, hätte `FileDetails` bereits eine nicht stattgefundene Interaktion gezählt.

**Empfohlene Umsetzung:**

```powershell
[string[]] FilterByLevel([string] $level) {
    $this.GuardDestroyed()
    [string] $normalizedLevel = $this.ValidateLevel($level)
    [string] $marker          = "[$($normalizedLevel.ToUpper())]"

    $results = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $this._data) {
        if ($line.Contains($marker)) {
            $results.Add($line)
        }
    }

    # RecordFilter() NACH der Operation — konsistent mit allen anderen Methoden
    $this._details.RecordFilter()
    return $results.ToArray()
}
```


***

#### Issue \#4 — `FileDetails.RecordFilter()` setzt veraltetes Label `'Filter'` statt `'FilterByLevel'`

**Schweregrad:** Niedrig–Mittel | **Datei:** `Classes/FileDetails.ps1`

**Problem:** In v1.01.00 wurde `Filter()` zu `FilterByLevel()` umbenannt (da `filter` ein reserviertes PowerShell-Keyword ist). Der interne Label-String in `RecordFilter()` wurde jedoch nicht aktualisiert und gibt weiterhin `'Filter'` zurück. Jeder Aufrufer, der `GetLastAccessType()` auf `'FilterByLevel'` prüft, wird nie eine Übereinstimmung finden. Das stale Label wird auch in `ToHashtable()` und damit in JSON/CSV-Exporten ausgegeben.

**Empfohlene Umsetzung:**

```powershell
# FileDetails.ps1 — RecordFilter() korrigiertes Label
hidden [void] RecordFilter() {
    $this._lastAccessed   = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
    $this._lastAccessType = 'FilterByLevel'  # War: 'Filter' — stale nach Rename
    $this._axcount++
}
```

**Optional (kosmetisch):** Die Methode selbst von `RecordFilter()` in `RecordFilterByLevel()` umbenennen und den einzigen Call-Site in `Logfile.ps1` entsprechend aktualisieren.

***

### 3.2 Architekturelle Warnungen (Mittelfristiger Handlungsbedarf)


***

#### Issue \#5 — `FunctionsToExport` in `.psd1` und `.psm1` — Manifest überschreibt dynamischen Export stillschweigend

**Schweregrad:** Mittel (stilles Versagen) | **Dateien:** `VPDLX.psd1` + `VPDLX.psm1`

**Problem:** `VPDLX.psd1` enthält eine statische `FunctionsToExport`-Liste mit nur `'VPDLXcore'`. Gleichzeitig baut `VPDLX.psm1` (Sektion 7) dynamisch eine Liste aller Dateien in `Public/` auf und übergibt sie an `Export-ModuleMember`. Das Problem: **Wenn ein Manifest vorhanden ist und `FunctionsToExport` explizit gesetzt ist, ignoriert PowerShell die `Export-ModuleMember`-Angabe in der `.psm1` vollständig**. Jede neue Funktion in `Public/` wird geladen, aber **nicht exportiert** — ohne Fehlermeldung, ohne Warnung.

> **Beobachtung:** In v1.01.02 wurden die Public Wrapper Funktionen tatsächlich im Manifest korrekt nachgepflegt. Das Problem ist dennoch als strukturelles Risiko zu dokumentieren, da die dynamische `.psm1`-Logik eine falsche Sicherheit vermittelt.

**Empfohlene Umsetzung (Strategy A — Manifest als einzige Autorität):**

Manifest als Single Source of Truth pflegen und den `Export-ModuleMember`-Aufruf in der `.psm1` entfernen oder durch einen Kommentar ersetzen:

```powershell
# VPDLX.psd1 — vollständige explizite Liste
FunctionsToExport = @(
    'VPDLXcore'
    'VPDLXnewlogfile'
    'VPDLXislogfile'
    'VPDLXdroplogfile'
    'VPDLXreadlogfile'
    'VPDLXwritelogfile'
    'VPDLXexportlogfile'
    # Neue Public-Funktionen HIER eintragen
)
```

Alternativ `FunctionsToExport = '*'` im Manifest und die `.psm1`-Logik als alleinige Kontrolle belassen (Strategy B).

***

#### Issue \#8 — `[ValidateSet(0, -1)]` in `VPDLXreturn` blockiert zukünftige Erweiterbarkeit

**Schweregrad:** Niedrig | **Datei:** `Private/VPDLXreturn.ps1`

**Problem:** Der `$Code`-Parameter in `VPDLXreturn` ist mit `[ValidateSet(0, -1)]` hart codiert. Jede zukünftige Notwendigkeit, einen dritten Status-Code zu kommunizieren (z. B. `1` für partial success, oder `-2` für einen spezifischen Fehlertyp), macht diese Validierungsattribute zu einer **Breaking Change**, selbst wenn es sich inhaltlich nur um eine Erweiterung handelt.

**Empfohlene Umsetzung (Option A):**

```powershell
# Ersetzt [ValidateSet(0, -1)] mit einem Bereich
[Parameter(Mandatory = $false)]
[ValidateRange(-99, 99)]
[int] $Code = -1,
```

**Dokumentationskonvention:**

- `0` = Erfolg
- `-1` = Allgemeiner Fehler
- `1..99` = Reserviert für Partial-Success-Varianten
- `-2..-99` = Reserviert für typisierte Fehlerkategorien

***

#### Issue \#9 — `FileStorage.Get()` gibt `[object]` zurück statt `[Logfile]` — Typsicherheit verloren

**Schweregrad:** Niedrig–Mittel | **Datei:** `Classes/FileStorage.ps1`

**Problem:** `FileStorage.Get()` ist mit Rückgabetyp `[object]` deklariert, weil `[FileStorage]` vor `[Logfile]` geladen wird und PowerShell 5.1 Forward-References in Klassen-Signaturen nicht auflösen kann. Callers erhalten ein ungetyptes `[object]` ohne IntelliSense-Support und müssen manuell nach `[Logfile]` casten — eine Anforderung, die nirgendwo dokumentiert und nicht erzwungen wird.

**Empfohlene Umsetzung (Option A — langfristig, alle drei Klassen in eine einzige Datei):**

Alle drei Klassen (`FileDetails`, `FileStorage`, `Logfile`) in eine einzige Datei `Classes/VPDLXClasses.ps1` zusammenführen:

```powershell
# VPDLXClasses.ps1 — korrekte Reihenfolge in einer Datei
class FileDetails { ... }  # 1. FileDetails
class FileStorage {        # 2. FileStorage
    hidden [System.Collections.Generic.Dictionary[string, Logfile]] $_registry
    [Logfile] Get([string] $name) { ... }  # Jetzt vollständig typisiert
}
class Logfile { ... }      # 3. Logfile
```

**Kurzfristig (Option B — Runtime-Typprüfung in `Add()`):**

```powershell
[void] Add([string] $name, [object] $instance) {
    if ($instance -isnot [Logfile]) {
        throw [System.ArgumentException]::new(
            "FileStorage.Add(): 'instance' muss ein [Logfile]-Objekt sein. " +
            "Empfangener Typ: $($instance.GetType().FullName).", 'instance'
        )
    }
    # ... Rest unverändert
}
```


***

#### Issue \#10 — Kein globaler Session-Cleanup-Mechanismus — `DestroyAll()` fehlt in `FileStorage`

**Schweregrad:** Mittel | **Dateien:** `Classes/FileStorage.ps1` + `VPDLX.psm1`

**Problem:** VPDLX bietet aktuell keine Möglichkeit, alle aktiven `[Logfile]`-Instanzen auf einmal zu zerstören. Jede Instanz muss einzeln via `$log.Destroy()` bereinigt werden. Wenn eine Instanz innerhalb einer Funktion erstellt wird und die Funktion ohne `Destroy()`-Aufruf verlässt, ist die Instanz in `FileStorage` registriert, aber der Caller hat die Referenz verloren. Der `OnRemove`-Handler in `VPDLX.psm1` entfernt zwar die TypeAcceleratoren, ruft aber **kein** `Destroy()` auf irgendwelchen Logfile-Instanzen auf. In lang laufenden Sessions (z. B. Automatisierungsprozesse) kann das zu messbarem Speicherwachstum führen.

**Empfohlene Umsetzung — Teil 1: `DestroyAll()` in `FileStorage`:**

```powershell
# FileStorage.ps1 — neue Methode
[void] DestroyAll() {
    if ($this._registry.Count -eq 0) { return }

    [string[]] $names = $this._registry.Keys.ToArray()  # Snapshot vor Iteration
    foreach ($name in $names) {
        $instance = $this._registry[$name]
        if ($null -ne $instance) {
            try {
                ([Logfile] $instance).Destroy()
            }
            catch {
                Write-Verbose "VPDLX: DestroyAll() konnte '$name' nicht zerstören: $($_.Exception.Message)"
            }
        }
    }
    $this._registry.Clear()
    $this._names.Clear()
}
```

**Empfohlene Umsetzung — Teil 2: `OnRemove`-Handler in `VPDLX.psm1` erweitern:**

```powershell
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    # Schritt 1: Alle aktiven Logfile-Instanzen vor dem Entladen zerstören
    if ($null -ne $script:storage -and $script:storage.Count() -gt 0) {
        try { $script:storage.DestroyAll() }
        catch { Write-Verbose "VPDLX OnRemove: DestroyAll() Fehler: $($_.Exception.Message)" }
    }

    # Schritt 2: TypeAcceleratoren entfernen (unverändert)
    foreach ($Type in $script:ExportableTypes) {
        if ($script:TypeAcceleratorsClass::Get.ContainsKey($Type.Name)) {
            $script:TypeAcceleratorsClass::Remove($Type.Name) | Out-Null
        }
    }
}.GetNewClosure()
```

**Optional:** `DestroyAll()` auch über `VPDLXcore` zugänglich machen:

```powershell
# In VPDLXcore — neuer KeyID
'destroyall' {
    $script:storage.DestroyAll()
    return VPDLXreturn -Code 0 -Message 'Alle Logfile-Instanzen erfolgreich zerstört.'
}
```


***

#### Issue \#7 — `Logfile.Print()` Validierungsfehler identifiziert nicht das fehlschlagende Element

**Schweregrad:** Niedrig | **Datei:** `Classes/Logfile.ps1`

**Problem:** Bei `Print()` mit einem großen Array werden alle Nachrichten vor dem Schreiben validiert (transaktionale Semantik). Wenn die Validierung fehlschlägt, teilt die Exception nur mit *was* falsch ist, aber nicht *an welcher Position* im Array. Bei hundert Einträgen muss der Entwickler das Array manuell durchsuchen.

**Empfohlene Umsetzung:**

```powershell
# Angereicherte Fehlerinfo mit Index
[int] $idx = 0
foreach ($msg in $messages) {
    try {
        $this.ValidateMessage($msg)
    }
    catch [System.ArgumentException] {
        [string] $preview = if ($null -eq $msg) { '(null)' }
                            elseif ($msg.Length -eq 0) { '(leerer String)' }
                            else {
                                $esc = $msg -replace "`r", '\r' -replace "`n", '\n'
                                if ($esc.Length -gt 40) { $esc = $esc.Substring(0, 40) + '...' }
                                "'$esc'"
                            }
        throw [System.ArgumentException]::new(
            "messages[$idx]: $($_.Exception.Message) Problematischer Wert: $preview",
            'messages'
        )
    }
    $idx++
}
```


***

### 3.3 Empfohlene Reihenfolge der Issue-Abarbeitung

Für maximale Stabilität und minimale Abhängigkeitskonflikte wird folgende Bearbeitungsreihenfolge empfohlen:


| Schritt | Issues | Begründung |
| :-- | :-- | :-- |
| 1 | \#1 + \#6 | Beide betreffen `Destroy()` — müssen als ein Commit gelöst werden |
| 2 | \#2 + \#4 | Beide betreffen `FilterByLevel()` + `RecordFilter()` — ein Commit |
| 3 | \#3 | `ToString()` ist isolierter Fix, schnell lösbar |
| 4 | \#5 | Vor dem nächsten Public-API-Ausbau dringend lösen |
| 5 | \#8 | Vor der Nutzung von `VPDLXreturn` in neuen Wrapper-Funktionen |
| 6 | \#9 | Architekturentscheidung (eine Datei vs. drei Dateien) — bewusst planen |
| 7 | \#10 | Baut auf \#9 und \#1/\#6 auf — zuletzt implementieren |
| 8 | \#7 | Verbesserung der Diagnose, kann jederzeit eingebaut werden |


***

## 4. Performance \& Optimierungen

### 4.1 `List<string>` — bereits korrekte Wahl, Optimierungspotenzial bei großen Logs

Die aktuelle Implementierung nutzt `[System.Collections.Generic.List[string]]` für den internen Datenspeicher von `[Logfile]`. Das ist eine bewusst gute Entscheidung: `List.Add()` hat amortisierte O(1)-Kosten, während PowerShell-Array-Verkettung (`+=`) O(n) kostet und bei großen Logs erheblichen Overhead erzeugt.

Für sehr große Log-Dateien (>100.000 Einträge) bieten sich in zukünftigen Versionen folgende Optimierungen an:

- **Initiale Kapazitätsvorgabe beim Konstruktor:** `[System.Collections.Generic.List[string]]::new(1000)` reduziert die Anzahl interner Array-Reallokatierungen deutlich, wenn die ungefähre Log-Größe bekannt ist
- **`StringBuilder` für Export-Operationen:** Statt `Set-Content` mit einem String-Array könnte ein `StringBuilder` mit anschließendem `File.WriteAllText()` den Export erheblich beschleunigen, da weniger Strings konkateniert werden
- **Lazy-Evaluation bei `FilterByLevel()`:** Die aktuelle `foreach`-Schleife mit `String.Contains()` ist schneller als ein LINQ-/`Where-Object`-Ansatz. Für extrem große Logs könnte jedoch eine parallele Suche mittels `Parallel.ForEach` in einer zukünftigen Version (PS 7+ only) erwogen werden


### 4.2 Timestamp-Generierung in `BuildEntry()` und `FileDetails`

Aktuell wird `(Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')` bei jedem einzelnen `Write()`-Aufruf neu erzeugt. Das ist korrekt und bewusst so gestaltet (jeder Eintrag erhält seinen exakten Zeitstempel), hat jedoch bei Batch-Operationen über `Print()` zur Folge, dass `Get-Date` für jeden Eintrag einzeln aufgerufen wird.

**Optimierungsvorschlag für `Print()`:** Einen einzigen Timestamp-Snapshot zu Beginn der Batch-Operation erfassen und für alle Einträge des Batches verwenden — oder dieses Verhalten als konfigurierbaren Parameter (`-BatchTimestamp`) anbieten:

```powershell
# Optionale Optimierung: einmaliger Timestamp pro Print()-Batch
[void] Print([string] $level, [string[]] $messages) {
    # ... Validierung ...
    [string] $batchTimestamp = (Get-Date).ToString('[dd.MM.yyyy | HH:mm:ss]')
    [string] $prefix         = [Logfile]::LogLevels[$normalizedLevel]
    foreach ($msg in $messages) {
        $this._data.Add("$batchTimestamp$prefix$msg")
    }
    # ...
}
```


### 4.3 `FileStorage._registry` — Dictionary-Lookup ist bereits O(1)

`FileStorage` verwendet intern ein `Dictionary<string, object>` mit `OrdinalIgnoreCase`-Comparer. Das garantiert O(1)-Lookups für `Contains()` und `Get()`, was auch bei Hunderten von gleichzeitig aktiven Logfiles keine Performance-Einbußen verursacht.

Eine zukünftige Ergänzung wäre eine optionale **maximale Kapazitätsgrenze** (`MaxInstances`), die verhindert, dass in einem Fehlerfall unendlich viele Logfiles angelegt werden.

### 4.4 Export-Performance

Für den `csv`- und `json`-Export parst `VPDLXexportlogfile` jede Log-Zeile mit String-Split-Operationen.  Dieser Ansatz ist korrekt, hat aber bei sehr großen Logs (>10.000 Einträge) messbare Kosten. Eine strukturierte Log-Speicherung (d. h. Einträge als `[PSCustomObject]` statt als formatierter String) würde den Export-Schritt eliminieren — allerdings zu Lasten der Lesbarkeit der in-memory-Daten. Das ist eine bewusste Architekturentscheidung, die für zukünftige Versionen diskutiert werden sollte.

***

## 5. Sicherheit

### 5.1 Aktuell implementierte Sicherheitsmaßnahmen

Die aktuelle Version enthält bereits mehrere sinnvolle Sicherheitsmechanismen:

- **Log-Injection-Schutz:** `ValidateMessage()` prüft explizit auf `\r`- und `\n`-Zeichen und wirft eine `ArgumentException`, wenn ein Newline-Zeichen in einer Nachricht enthalten ist. Das verhindert, dass ein Angreifer gefälschte Log-Einträge durch Zeilenumbrüche in Nachrichten einschleust.
- **Namensvalidierung:** `[Logfile]`-Namen werden auf 3–64 Zeichen und erlaubte Zeichen (`[a-zA-Z0-9_\-\.]`) geprüft, was Path-Traversal-artigen Angriffen bei Export-Operationen vorbeugt
- **Mindestlänge für Nachrichten:** Nachrichten müssen mindestens 3 Non-Whitespace-Zeichen enthalten, was triviale/leere Einträge verhindert
- **CSV RFC 4180-Konformität:** Im Export werden Doppelzeichen in CSV-Feldern korrekt escaped (`"` → `""`)
- **`GuardDestroyed()`-Pattern:** Alle öffentlichen Methoden prüfen, ob die Instanz bereits zerstört wurde, und werfen eine `ObjectDisposedException` mit informativer Meldung


### 5.2 Zu implementierende Sicherheitsmaßnahmen in zukünftigen Versionen

**Eingabelängenbegrenzung für Nachrichten:** Aktuell gibt es keine obere Längengrenze für Log-Nachrichten. Eine sehr lange Nachricht (z. B. 10 MB) könnte theoretisch den Speicher belasten. Empfohlen: eine konfigurierbare maximale Nachrichtenlänge (Standard: 8.192 Zeichen):

```powershell
# In ValidateMessage() — zukünftige Erweiterung
if ($message.Length -gt $script:MaxMessageLength) {
    throw [System.ArgumentException]::new(
        "Parameter 'message' darf maximal $script:MaxMessageLength Zeichen lang sein. " +
        "Aktuelle Länge: $($message.Length).", 'message'
    )
}
```

**Pfadvalidierung in `VPDLXexportlogfile`:** Der `LogPath`-Parameter akzeptiert aktuell beliebige Pfade und erstellt diese mit `New-Item -Force`. In restriktiven Umgebungen (Unternehmens-GPO, JEA) sollte eine Whitelist erlaubter Ausgabepfade implementierbar sein.

**Thread-Safety:** Die Dokumentation vermerkt explizit, dass VPDLX **nicht** für parallele Ausführung konzipiert ist.  Für Unternehmensszenarien, in denen `ForEach-Object -Parallel` oder `Start-ThreadJob` eingesetzt wird, fehlt eine `[System.Threading.SemaphoreSlim]`- oder `[System.Threading.Mutex]`-basierte Synchronisierung. Das sollte in der Dokumentation noch prominenter hervorgehoben werden und ist als Sicherheits- wie auch Korrektheitsproblem zu klassifizieren.

**Export-Pfad-Escape:** Für Windows-Umgebungen mit Sonderzeichen in Pfaden ist die aktuelle Verwendung von `LiteralPath` in allen Filesystem-Operationen bereits korrekt. Für zukünftige Linux/macOS-Unterstützung (PowerShell Core) sollten Pfadtrennzeichen immer mit `[System.IO.Path]::DirectorySeparatorChar` oder `Join-Path` gebildet werden — das ist bereits der Fall, aber es sollte als explizite Richtlinie festgehalten werden.

**Encoding-Konsistenz:** Der aktuelle Export verwendet `UTF8`, was auf PowerShell Core korrekt ohne BOM ist, auf Windows PowerShell 5.1 aber eine BOM-präfixierte UTF-8-Datei erzeugt. Für Systeme, die BOM-freie UTF-8-Dateien erwarten (z. B. bestimmte Log-Aggregatoren), sollte `New-Object System.Text.UTF8Encoding($false)` als Encoding-Option angeboten werden.

***

## 6. `ScriptsToProcess` — Empfehlungen für zukünftige Versionen

In `VPDLX.psd1` ist `ScriptsToProcess` aktuell auskommentiert mit dem Kommentar: *„Not used — class loading is handled directly in VPDLX.psm1 to ensure correct load order."*  Diese Entscheidung ist technisch korrekt und sollte beibehalten werden. Dennoch bietet das `ScriptsToProcess`-Feld interessante Möglichkeiten für zukünftige Erweiterungen.

### Was `ScriptsToProcess` tut

Skripte in `ScriptsToProcess` werden **im Caller-Scope** ausgeführt (nicht im Modul-Scope), noch bevor `VPDLX.psm1` geladen wird. Das macht sie geeignet für:

- Voraussetzungs-Checks (PowerShell-Version, Betriebssystem)
- Setzen von session-weiten Variablen im Caller-Scope
- Benutzer-Benachrichtigungen beim ersten Laden


### Empfohlene Implementierungen

**Szenario 1 — Prerequisite-Check-Skript (`VPDLX.Precheck.ps1`):**

Ein vorgelagertes Skript könnte die PowerShell-Version, .NET-Version und Berechtigungen prüfen und dem Benutzer eine klare Fehlermeldung geben, bevor der Modullade-Prozess abbricht:

```powershell
# VPDLX.Precheck.ps1 (ScriptsToProcess)
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "VPDLX erfordert PowerShell 5.1 oder höher. Aktuell: $($PSVersionTable.PSVersion)"
    return
}
if ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1) {
    Write-Warning "VPDLX wurde für PS 5.1 optimiert. Verhalten auf älteren Versionen kann abweichen."
}
Write-Verbose "VPDLX Precheck: PowerShell $($PSVersionTable.PSVersion) — OK"
```

**Szenario 2 — Session-Defaults setzen:**

`ScriptsToProcess` könnte genutzt werden, um optionale VPDLX-Konfigurationsvariablen im Caller-Scope zu setzen, falls sie nicht bereits definiert sind:

```powershell
# Nur setzen wenn noch nicht vorhanden
if (-not (Get-Variable -Name 'VPDLXDefaultExportPath' -Scope Global -ErrorAction SilentlyContinue)) {
    Set-Variable -Name 'VPDLXDefaultExportPath' -Value "$env:TEMP\VPDLXLogs" -Scope Global
}
```

**Szenario 3 — Deprecation- und Migrationshinweise:**

Bei Versions-Upgrades kann ein `ScriptsToProcess`-Skript prüfen, ob der Caller veraltete Variablen oder Funktionsnamen aus Vorgänger-Versionen nutzt, und Warnungen ausgeben.

> **Wichtige Einschränkung:** Da `ScriptsToProcess` im Caller-Scope läuft, haben diese Skripte keinen Zugriff auf `$script:*`-Variablen des Moduls. Sie eignen sich daher **nicht** für Modul-Initialisierung — das bleibt Aufgabe von `VPDLX.psm1`. Die Klassen-Ladereihenfolge muss weiterhin in der `.psm1` gesteuert werden.

***

## 7. Feature-Requests \& Zukunftsaussichten

### 7.1 `VPDLXgetalllogfiles` — Übersicht aller aktiven Log-Instanzen

Eine Funktion, die alle aktuell registrierten Logfile-Instanzen als strukturierte Ausgabe zurückgibt, wäre für Diagnose und Monitoring sehr wertvoll:

```powershell
function VPDLXgetalllogfiles {
    $store = (VPDLXcore -KeyID 'storage').data
    $result = foreach ($name in $store.GetNames()) {
        $log = [Logfile] $store.Get($name)
        [PSCustomObject]@{
            Name         = $log.Name
            EntryCount   = $log.EntryCount()
            Created      = $log.GetDetails().GetCreated()
            LastUpdated  = $log.GetDetails().GetUpdated()
            IsEmpty      = $log.IsEmpty()
        }
    }
    return VPDLXreturn -Code 0 -Message "OK" -Data $result
}
```


### 7.2 `VPDLXresetlogfile` — Wrapper zum Leeren eines Logs

Aktuell ist `Reset()` nur über den direkten Klassen-Aufruf (`$log.Reset()`) verfügbar. Eine Public-Wrapper-Funktion würde das Verhalten konsistent mit dem restlichen Public API machen und einen strukturierten Return-Wert liefern.

### 7.3 `VPDLXfilterlogfile` — Filter als Public Wrapper Funktion

`FilterByLevel()` ist aktuell nur direkt über die Klasse nutzbar. Ein Public Wrapper `VPDLXfilterlogfile -Logfile 'AppLog' -Level 'error'` würde das PowerShell-idiomatische Arbeiten ohne direkten Klassenzugriff ermöglichen.

### 7.4 `VPDLXexportlogfile` — Erweiterung um `xml`- und `html`-Format

Das Export-System ist erweiterbar konzipiert: neue Formate werden durch Hinzufügen eines Keys in `$script:export` und einem `switch`-Case in `VPDLXexportlogfile.ps1` ergänzt.  Sinnvolle neue Formate wären:

- **XML:** Strukturiertes Format für Enterprise-Log-Aggregatoren
- **HTML:** Lesbare, formatierte Log-Berichte mit CSS-Styling für die direkte Weitergabe
- **NDJSON (Newline-Delimited JSON):** Für Log-Streaming-Systeme (z. B. Elastic Stack)


### 7.5 Konfigurierbarer Log-Level-Filter beim Erstellen

Beim Erstellen eines Logfiles könnte ein minimales Log-Level gesetzt werden, unterhalb dessen keine Einträge geschrieben werden (ähnlich wie `$Env:LOG_LEVEL` in anderen Frameworks):

```powershell
$log = [Logfile]::new('ProdLog', 'warning')  # schreibt nur Warning, Error, Critical, Fatal
$log.Debug('Wird ignoriert.')      # kein Eintrag
$log.Warning('Wichtig!')           # Eintrag wird erstellt
```


### 7.6 Log-Rotation / maximale Eintragsanzahl

Für lang laufende Scripts könnten Logfiles eine maximale Eintragsanzahl erhalten. Bei Überschreitung werden entweder die ältesten Einträge verworfen (Ring-Buffer-Semantik) oder automatisch ein Export ausgelöst:

```powershell
$log = [Logfile]::new('RollingLog', -MaxEntries 10000, -OnFull 'AutoExport')
```


### 7.7 Log-Tagging und strukturierte Felder

Aktuell besteht ein Log-Eintrag aus Timestamp, Level und Message. Eine optionale, strukturierte Erweiterung mit Metadaten-Tags würde VPDLX zu einem mächtigeren diagnostischen Werkzeug machen:

```powershell
$log.Write('info', 'User logged in', @{ UserId = 'u123'; Source = 'AuthModule' })
# Ausgabe in JSON: { "Timestamp": "...", "Level": "INFO", "Message": "User logged in",
#                   "Tags": { "UserId": "u123", "Source": "AuthModule" } }
```


### 7.8 `VPDLXcore -KeyID 'stats'` — Modul-weite Statistiken

Ein neuer `VPDLXcore`-Key könnte eine Übersicht der modul-weiten Aktivität liefern:

```powershell
$stats = (VPDLXcore -KeyID 'stats').data
# $stats.TotalLogfiles     — Anzahl jemals erstellter Logfiles in dieser Session
# $stats.ActiveLogfiles    — aktuell registrierte Instanzen
# $stats.TotalEntries      — Summe aller Einträge über alle aktiven Logfiles
# $stats.TotalExports      — Anzahl durchgeführter Exporte
```


### 7.9 Pester-Test-Suite

Für eine produktionsreife Veröffentlichung auf PowerShell Gallery sollte eine vollständige Pester-Test-Suite (v5+) erstellt werden. Prioritäre Testbereiche wären:

- Konstruktor-Validierung (`[Logfile]::new()` mit invaliden Namen)
- `Destroy()`-Verhalten (einfach, doppelt, nach `Remove()` aus Storage)
- `FilterByLevel()` mit allen 8 Log-Levels
- Export-Formate (Struktur-Validierung für CSV und JSON)
- TypeAccelerator-Registrierung und -Bereinigung beim Laden/Entladen des Moduls

***

*Diese Dokumentation basiert auf einer vollständigen Code-Analyse des GitHub-Repositories [praetoriani/PowerShell.Mods — VPDLX](https://github.com/praetoriani/PowerShell.Mods/tree/main/VPDLX)  sowie dem zugehörigen [Issue-Tracker](https://github.com/praetoriani/PowerShell.Mods/issues)  zum Stand 06.04.2026. Sie ist als lebende Dokumentation konzipiert und sollte mit jeder neuen Version aktualisiert werden.*
