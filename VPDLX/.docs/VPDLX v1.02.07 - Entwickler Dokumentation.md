# VPDLX v1.02.07 — Entwickler Dokumentation

> **Projekt:** VPDLX (*Virtual PowerShell Data-Logger eXtension*)
> **Version:** 1.02.07
> **Stand:** 30.10.2026
> **Autor:** Praetoriani (M. Sczepanski)
> **Dokumentationsversion:** 1.0 — Nachfolger von *v1.01.00* und *v1.01.02 Entwickler Dokumentation*
> **Begleitdokument:** `VPDLX v1.02.07 - Developer ToDo-Liste.md`

***

## 1. Executive Summary

VPDLX ist ein klassenbasiertes, virtuelles Logging-Modul für Windows PowerShell 5.1 und PowerShell Core. Beliebig viele Logfiles werden im Arbeitsspeicher geführt; physische Dateien entstehen durch Export (Schnappschuss) oder — neu in v1.02.07 — durch **fortlaufendes Anhängen** (*Attach*).

Der Release **v1.02.07** ist ein Kernfeature-Release:

- **Puffer-Limit (`MaxEntries`)**: Logfiles halten nur noch eine begrenzte Anzahl Einträge im Speicher (Standard in `VPDLXnewlogfile`: 100).
- **Anhängen an physische Dateien**: Ist ein Ziel konfiguriert, werden volle Puffer-Blöcke automatisch an eine Datei angehängt (`txt`, `log`, `csv`, `ndjson`). Ohne Ziel arbeitet der Puffer als **Ringpuffer**.
- **Neue Funktion `VPDLXattachlogfile`** für manuelles Anhängen.
- **Drei Bugfixes** aus dem Code-Review (`LevelSeverity`, `VPDLXdroplogfile`, `FilterByLevel()`).
- **Refactoring**: zentraler Parser `VPDLXparseentry`, gemeinsame Append-Logik `VPDLXappendcore`.
- **Test**: Testlauf 003 — 43 von 43 Tests bestanden (siehe Abschnitt 9).

***

## 2. Modul-Übersicht

### 2.1 Versionsverlauf

| Version | Datum | Inhalt |
| :-- | :-- | :-- |
| 1.00.00 | 05.04.2026 | Erstveröffentlichung (drei Klassen, Basis-Wrapper) |
| 1.01.00 | 06.04.2026 | Stabilisierung, erste Entwickler-Dokumentation |
| 1.01.01 | 06.04.2026 | Korrekturen |
| 1.01.02 | 06.04.2026 | Entwickler-Dokumentation mit Issue-Analyse (10 Issues) |
| 1.02.03 | 11.04.2026 | Issues \#1–\#10 behoben (Destroy, FilterByLevel, ToString, Manifest, ValidateRange, Klassen-Konsolidierung, Print-Diagnose, DestroyAll) |
| 1.02.04 | 11.04.2026 | Precheck-Skript, `-NoBOM`, `MaxMessageLength` |
| 1.02.05 | 11.04.2026 | `VPDLXgetalllogfiles`, `VPDLXresetlogfile`, `VPDLXfilterlogfile`, `VPDLXcore -KeyID 'stats'` |
| 1.02.06 | 17.04.2026 | Export HTML + NDJSON, konfigurierbarer Mindest-Log-Level, Wrapper-Bugfixes |
| **1.02.07** | **30.10.2026** | **`MaxEntries`, Attach, Ringpuffer, `VPDLXattachlogfile`, Bugfixes, Parser-Refactoring** |

### 2.2 Voraussetzungen

- Windows PowerShell **5.1** oder PowerShell Core/7 (Prüfung durch `VPDLX.Precheck.ps1` via `ScriptsToProcess`).
- Keine externen Abhängigkeiten.
- Kodierung der Attach-Dateien: UTF-8 (BOM nur beim Anlegen der Datei, außer `-NoBOM`).

### 2.3 Exportierte Funktionen (11)

| Funktion | Zweck |
| :-- | :-- |
| `VPDLXcore` | Read-only-Zugriff auf Modulinterna (KeyIDs `appinfo`, `storage`, `export`, `destroyall`, `stats`) |
| `VPDLXnewlogfile` | Neues Logfile anlegen (inkl. `-MinLevel`, `-MaxEntries`, `-AttachPath`, `-AttachAs`, `-DailyFile`) |
| `VPDLXislogfile` | Existenzprüfung |
| `VPDLXdroplogfile` | Logfile zerstören (Restpuffer wird zuvor angehängt) |
| `VPDLXreadlogfile` | Einzelne Zeile lesen |
| `VPDLXwritelogfile` | Eintrag schreiben |
| `VPDLXexportlogfile` | Schnappschuss-Export (`txt`, `log`, `csv`, `json`, `html`, `ndjson`) |
| `VPDLXgetalllogfiles` | Übersicht aller aktiven Logfiles |
| `VPDLXresetlogfile` | Puffer leeren (verwirft Inhalt, kein Flush) |
| `VPDLXfilterlogfile` | Einträge nach Level filtern |
| `VPDLXattachlogfile` | **Neu:** Puffer an physische Datei anhängen (`-LogPath`, `-AttachAs`, `-NoBOM`, `-Clear`) |

***

## 3. Repository-Struktur (IST)

```
VPDLX\
├── VPDLX.psd1                 Manifest (Single Source of Truth für FunctionsToExport)
├── VPDLX.psm1                 Modul-Loader (Sektionen 1–8)
├── VPDLX.Precheck.ps1         Versionsprüfung (ScriptsToProcess)
├── Classes\
│   └── VPDLXClasses.ps1       FileDetails, FileStorage, Logfile (eine Datei, ~1350 Zeilen)
├── Private\
│   ├── VPDLXreturn.ps1        Einheitliches Rückgabeobjekt {code, msg, data}
│   ├── VPDLXparseentry.ps1    NEU: zentraler Zeilen-Parser
│   └── VPDLXappendcore.ps1    NEU: gemeinsame Append-Logik
├── Public\                    10 Wrapper-Funktionen (VPDLXcore wird in psm1 definiert)
├── Examples\                  Demo-001.ps1, Demo-002.ps1 (Attach/MaxEntries)
├── .docs\                     Entwicklerdokumentation (historisch + aktuell)
├── .backup\                   Sicherungs-Snapshots vor jeder Änderung
├── CHANGELOG.md  README.md  QUICKSTART.md  HANDBOOK.md
├── PROCESS-BOARD.MD           Arbeitsprotokoll
├── UNIT-TESTING.MD            Testprotokoll
└── LICENSE  NOTICE            Apache 2.0
```

***

## 4. Architektur

### 4.1 `VPDLX.psm1`

Acht Sektionen: (1) Metadaten, (2) Laden der Klassen (Reihenfolge kritisch), (3) `FileStorage`-Singleton, (4) Laden von Private/Public, (5) `VPDLXcore`, (6) TypeAccelerator-Registrierung, (7) Export-Deklaration (das Manifest hat Vorrang), (8) `OnRemove`-Handler. `OnRemove` ruft `DestroyAll()` auf — dadurch werden beim Entfernen des Moduls alle Restpuffer **geflusht**, bevor die TypeAccelerator entfernt werden.

### 4.2 `[FileDetails]`

Metadaten-Begleiter jeder Logfile-Instanz (Created, Updated, LastAccessed, AccessCount, letzter Zugriffstyp). Unverändert gegenüber v1.02.06; der Entry-Zähler spiegelt ab v1.02.07 die **aktuelle Puffergröße**.

### 4.3 `[FileStorage]`

Registry-Singleton (Name → Instanz), `Add/Get/Remove/Contains/GetCount/GetNames/DestroyAll`. `Get()` liefert typsicher `[Logfile]` (seit v1.02.03). Unverändert in v1.02.07.

### 4.4 `[Logfile]`

**Statische Member**

| Member | Wert / Bedeutung |
| :-- | :-- |
| `MaxMessageLength` | 8192 |
| `LogLevels` | zulässige Level-Namen |
| `LevelSeverity` | trace=0 … fatal=7 (**in v1.02.07 erstmals tatsächlich definiert**) |
| `AttachExtensions` | `txt`, `log`, `csv`, `ndjson` |

**Versteckte Felder:** `_data`, `_details`, `_minLevelIndex`, `_minLevelName` sowie neu `_maxEntries`, `_attachPath`, `_attachAs`, `_dailyFile`.

**Konstruktoren**

| Signatur | Verhalten |
| :-- | :-- |
| `new(name)` | unbegrenzt (`maxEntries = 0`), abwärtskompatibel |
| `new(name, minLevel)` | unbegrenzt, mit Mindest-Level |
| `new(name, minLevel, maxEntries, attachPath, attachAs, dailyFile)` | neu in v1.02.07 |

**Neue Methoden:** `GetMaxEntries()`, `GetAttachPath()`, `GetAttachAs()`, `GetAttachFile()`; versteckt: `ResolveAttachFile()`, `_Flush([bool]$final)`.

**Flush-Semantik** (aufgerufen in `Write()`, `Print()`, `Destroy()` mit `final = $true`):

| Situation | Verhalten |
| :-- | :-- |
| Ziel konfiguriert | Es werden Blöcke von genau `MaxEntries` Zeilen angehängt; `Print()` mit großen Stapeln wird in Blöcken geschrieben, Reihenfolge bleibt erhalten |
| `Destroy()` / `DestroyAll()` / Modul-Entfernung | Restpuffer wird angehängt |
| `Reset()` | Puffer wird **verworfen** (kein Flush) |
| Kein Ziel | **Ringpuffer** — der älteste Eintrag wird verworfen (`RemoveRange`) |
| Schreibfehler | Keine Exception: Puffer bleibt erhalten, `Write-Warning`, nächster Flush versucht es erneut |
| `MaxEntries = 0` | unbegrenzt, kein Flush |

**Zeilenformat:** `<Timestamp, 23 Zeichen>  ->  [LEVEL]  ->  <Nachricht>`; das Level steht an fester Position (Offset 25) — `FilterByLevel()` vergleicht ab v1.02.07 genau dort und nicht mehr per Teilstring.

### 4.5 `VPDLXreturn`

Unverändert: `{ code, msg, data }`, `[ValidateRange(-99, 99)]` (0 = Erfolg, -1 = Fehler, 1..99 Teilerfolg, -2..-99 typisierte Fehler).

### 4.6 `VPDLXcore`

KeyIDs: `appinfo`, `storage`, `export`, `destroyall`, `stats`.

### 4.7 Neue private Helfer

**`VPDLXparseentry`** — zerlegt eine Logzeile an `'  ->  '` in Timestamp, Level und Message. Fallback bei nicht parsbaren Zeilen: Level `RAW` oder `UNKNOWN`. Wird von `VPDLXexportlogfile` und `VPDLXappendcore` genutzt; vier duplizierte Parser-Blöcke im Export entfielen.

**`VPDLXappendcore`** — gemeinsame Append-Logik für `Logfile._Flush()` und `VPDLXattachlogfile`:

- `txt`/`log`: Zeilen unverändert,
- `csv`: Kopfzeile **nur** bei neuer oder leerer Datei,
- `ndjson`: `ConvertTo-Json -Compress` je Zeile,
- Schreiben per `[System.IO.File]::AppendAllText` (UTF-8, BOM nur beim Anlegen, außer `-NoBOM`).

`json` und `html` sind nicht anhängbar und bleiben Schnappschuss-Formate (`VPDLXexportlogfile`).

### 4.8 `VPDLXexportlogfile`

Acht Stufen (Validierung bis Schreiben), Parameter `Logfile`, `LogPath`, `ExportAs`, `Override`, `NoBOM`. Ausgabe unverändert gegenüber v1.02.06.

### 4.9 TypeAccelerator

`[Logfile]`, `[FileDetails]`, `[FileStorage]` — registriert beim Import, entfernt in `OnRemove`.

***

## 5. Design-Entscheidungen in v1.02.07

| Nr. | Entscheidung | Begründung |
| :-- | :-- | :-- |
| 1 | Anhängen statt Rotieren: Block-Flush in feste Datei | Manuelle Rotation (`Reset`) entfällt weitgehend |
| 2 | Ringpuffer ohne Ziel | Speicher bleibt begrenzt, Neuestes bleibt erhalten |
| 3 | Schreibfehler werfen nie aus der Klasse | Logging darf die aufrufende Anwendung nicht abbrechen |
| 4 | `Reset()` verwirft | Reset bedeutet bewusst „leeren", kein verstecktes Schreiben |
| 5 | Nur zeilenorientierte Formate anhängbar | `json`/`html` sind nicht append-fähig |
| 6 | `-DailyFile` → `<Name>_yyyy-MM-dd.<ext>` | Tageswechsel ohne Eingriff des Anwenders |
| 7 | UTF-8 mit BOM nur beim Anlegen | Konsistente Datei ohne BOM mitten im Stream |
| 8 | `EntryCount` = Puffergröße | Spiegelt tatsächlich im Speicher gehaltene Einträge |
| 9 | Default `MaxEntries = 100` in `VPDLXnewlogfile`, direkter Konstruktor bleibt unbegrenzt | Sinnvoller Standard für den Wrapper, Abwärtskompatibilität für Klassenverwender |

> **Migrationshinweis:** `VPDLXnewlogfile` ohne `-AttachPath` begrenzt den Puffer jetzt auf 100 Einträge (ältester wird verworfen). `-MaxEntries 0` stellt das frühere Verhalten wieder her.

***

## 6. Behobene Issues

### 6.1 In v1.02.07 (Block A)

| Nr. | Problem | Lösung |
| :-- | :-- | :-- |
| A1 | `[Logfile]::LevelSeverity` wurde an sieben Stellen verwendet, war aber nicht definiert; der Mindest-Level-Filter funktionierte dadurch nicht | Statische Hashtable definiert (trace=0 … fatal=7) |
| A2 | `VPDLXdroplogfile`: Erfolgsmeldung nicht geklammert, wurde u. U. falsch an `VPDLXreturn` übergeben | Ausdruck korrekt geklammert |
| A3 | `FilterByLevel()` fand Level per Teilstring; Nachrichten mit z. B. `[ERROR]` erzeugten Fehltreffer | Vergleich an fester Position (Offset 25) |

### 6.2 Frühere Issues

Die Issues \#1–\#10 aus der *v1.01.02 Entwickler Dokumentation* wurden in v1.02.03 – v1.02.04 behoben (siehe dortige Abschnitte und `CHANGELOG.md`). Details stehen in der ToDo-Liste, Prioritäten 1–9.

***

## 7. Performance & Sicherheit

**Performance**

- `AppendAllText` je Block statt Zeile für Zeile: Dateizugriffe sinken auf ca. einen je `MaxEntries` Einträge.
- Ringpuffer nutzt `RemoveRange` am Listenanfang (O(n) je Überlauf, bei Puffer-Obergrenzen im Bereich 10²–10⁴ unkritisch).
- `ndjson` und `csv` werden pro Block aufgebaut, nicht pro Zeile geöffnet.

**Sicherheit**

- Pfade für Attach/Export werden nicht gegen eine Whitelist geprüft (offen, siehe ToDo Priorität 15).
- HTML-Export kodiert Inhalte (XSS-sicher, seit v1.02.06).
- Nachrichtenlänge begrenzt (`MaxMessageLength`).
- Keine Secrets im Modul; Dateirechte richten sich nach dem Zielverzeichnis.

**Bekannte Einschränkungen**

- Keine Thread-Safety (Puffer und Zieldatei ohne Sperre) — in README, HANDBOOK und CHANGELOG dokumentiert.
- Bei dauerhaftem Schreibfehler wächst der Puffer weiter, sofern `MaxEntries = 0`; mit Limit greift die Flush-Logik erneut beim nächsten Block.
- Tests bisher nur unter Windows PowerShell 5.1.

***

## 8. Dokumentations-Inkonsistenzen (offen)

- (Erledigt am 30.10.2026) `HANDBOOK.md` bereinigt: Class Architecture korrigiert, Best Practice 6 als optional/manuell gekennzeichnet; Migrations- und Thread-Safety-Hinweis ergänzt.
- Die Dokumente in `.docs\` zu v1.01.00 und v1.01.02 sind historisch und bewusst unverändert.
- (Erledigt am 30.10.2026) `.gitignore`: Eintrag `TODO.TXT` entfernt.

***

## 9. Teststatus

Protokoll: `UNIT-TESTING.MD`.

| Lauf | Ergebnis |
| :-- | :-- |
| 001, 002 | Erste Läufe, gefundene Fehler und Lösungsansätze dokumentiert |
| **003** | **43 / 43 Tests bestanden** |
| **004** | Windows PowerShell 5.1: Last-/Flush-/Fehlertests 11/11, `-Override` 14/14; PowerShell 7.6.9 Core: Basistests 5/5, Run004 11/11, Override 14/14 und Demo-002, Orchestrator **GESAMT: BESTANDEN** (Anwenderlauf 31.10.2026) |

**Hinweise zur Testumgebung:** Die Sandbox verweigert das Löschen im Temp-Ordner; Tests mit Löschvorgängen müssen im Workspace laufen. Der `-Override`-Export wurde in Lauf 004 unter Windows PowerShell 5.1 und PowerShell 7.6.9 Core erfolgreich getestet. Der PowerShell-7-Anwenderlauf und Demo-002 endeten mit GESAMT: BESTANDEN. Testskripte liegen in `Tests\`. Eine Pester-Suite existiert noch nicht.

***

## 10. Offene Punkte & Ausblick

Siehe `VPDLX v1.02.07 - Developer ToDo-Liste.md`:

- **Priorität 13:** Pester-Suite, Inline-Dokumentation.
- **Priorität 14:** Dauer-/Tageswechseltest, Performance-Profil je `MaxEntries`, Thread-Safety (`SemaphoreSlim`/`Mutex`). PowerShell 7 wurde am 31.10.2026 unter 7.6.9 Core erfolgreich geprüft. Cleanup in Demo-002 lief im Anwenderlauf erfolgreich.
- **Priorität 15 (optional):** XML-Export, Log-Tagging mit strukturierten Feldern, `MaxInstances`-Limit, Whitelist für Exportpfade, `-OnFull AutoExport`.

***

## 11. Fazit

Mit v1.02.07 ist VPDLX von einem reinen In-Memory-Logger zu einem Logger mit begrenztem Speicherbedarf und dauerhafter Dateiablage geworden, ohne bestehenden Klassencode zu brechen. Die letzte Testrunde (43/43) deckt die neuen Mechanismen ab. Die nächsten Schritte sind die Automatisierung der Tests (Pester), die Absicherung gegen Parallelzugriffe und die Bereinigung der Begleitdokumente.

*Diese Dokumentation wurde am 30.10.2026 auf Basis des aktuellen Codestands, des `CHANGELOG.md`, der Protokolle `PROCESS-BOARD.MD`/`UNIT-TESTING.MD` und der Vorgänger-Dokumente erstellt.*
