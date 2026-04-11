<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# VPDLX v1.02.03 — Developer ToDo-Liste


***

## 🔴 Priorität 1 — Kritische Bugfixes (Sofort)

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ✅ | **`Destroy()` — Vollständige Härtung** | `Logfile.Destroy()` erhält `GuardDestroyed()` am Anfang (Issue \#1) **und** ein `try/catch/finally`-Konstrukt um `storage.Remove()` (Issue \#6) — beide Fixes in einem einzigen Commit umgesetzt (**v1.02.03, 11.04.2026**) | 3 |

**Unter-Tasks:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ✅ | `GuardDestroyed()` in `Destroy()` einbauen | Erster Aufruf in `Destroy()` ist nun `$this.GuardDestroyed()` — altes `if`-Konstrukt entfernt (**v1.02.03**) | 1 |
| ✅ | `try/catch/finally` um `storage.Remove()` | `finally`-Block setzt `_data` und `_details` **immer** auf `$null`, `catch`-Block schreibt `Write-Verbose`-Warnung (**v1.02.03**) | 2 |
| ✅ | Altes `if ($null -ne $this._data)`-Konstrukt entfernen | Nach Einbau von `GuardDestroyed()` redundant — entfernt (**v1.02.03**) | 1 |


***

## 🔴 Priorität 2 — Bugfix-Duo `FilterByLevel()` + `RecordFilter()`

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | **`FilterByLevel()` + `RecordFilter()` — Zwei-in-einem Fix** | `RecordFilter()` an die korrekte Position verschieben (Issue \#2) **und** den Label-String `'Filter'` auf `'FilterByLevel'` aktualisieren (Issue \#4) — beide Fixes betreffen dieselben Dateien und gehören in einen Commit | 2 |

**Unter-Tasks:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | `RecordFilter()`-Aufruf nach die `foreach`-Schleife verschieben | In `Logfile.FilterByLevel()` den `$this._details.RecordFilter()`-Aufruf von **vor** die Schleife auf **nach** die Schleife und vor `return` versetzen | 1 |
| ☐ | Label-String in `FileDetails.RecordFilter()` korrigieren | `$this._lastAccessType = 'Filter'` ändern zu `$this._lastAccessType = 'FilterByLevel'` | 1 |
| ☐ | (Optional) `RecordFilter()` in `RecordFilterByLevel()` umbenennen | Kosmetische interne Umbenennung der `hidden`-Methode + Update des einzigen Call-Site in `Logfile.ps1` | 1 |


***

## 🟠 Priorität 3 — `ToString()` nach `Destroy()` absichern

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ✅ | **`ToString()` NullReferenceException beheben** | `Logfile.ToString()` wirft nach `Destroy()` eine `NullReferenceException` durch unbewachten Zugriff auf `_details.GetCreated()` — `GuardDestroyed()` an erster Stelle eingebaut (Issue \#3, **v1.02.03, 11.04.2026**) | 2 |

**Unter-Tasks:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ✅ | `GuardDestroyed()` in `ToString()` einbauen | Erster Aufruf in `ToString()` ist nun `$this.GuardDestroyed()` (**v1.02.03**) | 1 |
| ✅ | Partielle `_data`-Nullprüfung in `ToString()` entfernen | `if/else`-Konstrukt entfernt — `_data` ist nach `GuardDestroyed()` garantiert non-null (**v1.02.03**) | 1 |


***

## 🟠 Priorität 4 — Export-Konfigurationskonflikt auflösen

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | **`FunctionsToExport` — Einzelne Autorität festlegen** | Den Konflikt zwischen `VPDLX.psd1`-Manifest und `Export-ModuleMember` in `VPDLX.psm1` auflösen — Manifest als alleinige Quelle der Wahrheit festlegen (Issue \#5) | 3 |

**Unter-Tasks:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | `FunctionsToExport` in `VPDLX.psd1` vollständig und korrekt pflegen | Explizite Liste **aller** aktuell vorhandenen Public-Funktionen eintragen und einen Hinweis-Kommentar ergänzen: *„Neue Public-Funktionen HIER eintragen"* | 2 |
| ☐ | `Export-ModuleMember`-Aufruf in `VPDLX.psm1` entfernen / kommentieren | Sektion 7 in `VPDLX.psm1` bereinigen — der Aufruf wird durch das Manifest vollständig überschrieben und ist irreführend | 2 |
| ☐ | Dynamische `$PublicFunctions`-Logik in Sektion 7 dokumentieren | Kommentar ergänzen, der klar erklärt, warum Manifest Vorrang hat — für zukünftige Entwickler | 1 |


***

## 🟡 Priorität 5 — `VPDLXreturn` Erweiterbarkeit sicherstellen

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | **`[ValidateSet(0, -1)]` durch `[ValidateRange]` ersetzen** | Den hard-codierten `[ValidateSet(0, -1)]`-Constraint in `VPDLXreturn.ps1` durch `[ValidateRange(-99, 99)]` ersetzen und Status-Code-Konventionen im Code-Kommentar dokumentieren (Issue \#8) | 2 |

**Unter-Tasks:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | `[ValidateRange(-99, 99)]` einbauen | Attribut in der `$Code`-Parameterdeklaration ersetzen | 1 |
| ☐ | Status-Code-Konvention dokumentieren | Kommentar über `$Code` ergänzen: `0` = Erfolg, `-1` = Allg. Fehler, `1..99` = Partial-Success, `-2..-99` = Typisierte Fehler | 1 |


***

## 🟡 Priorität 6 — Typsicherheit `FileStorage.Get()` verbessern

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | **`FileStorage` Typsicherheit — Architekturentscheidung treffen und umsetzen** | `FileStorage.Get()` gibt `[object]` zurück statt `[Logfile]` — Forward-Reference-Problem aus PS 5.1-Kompatibilität lösen (Issue \#9) | 6 |

**Unter-Tasks:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | Entscheidung: Eine Datei vs. drei Dateien | Architekturelle Entscheidung treffen: Option A (alle drei Klassen in `VPDLXClasses.ps1`) vs. Option B (Minimal-Fix mit Runtime-Typprüfung in `Add()`) | 2 |
| ☐ | **(Option A)** Klassen in `VPDLXClasses.ps1` zusammenführen | `FileDetails.ps1`, `FileStorage.ps1`, `Logfile.ps1` in eine einzige Datei in korrekter Reihenfolge zusammenführen | 5 |
| ☐ | **(Option A)** `FileList`-Eintrag in `VPDLX.psd1` aktualisieren | Manifest-`FileList` auf die neue einzelne Klassendatei anpassen | 1 |
| ☐ | **(Option A)** `$script:ClassFiles`-Array in `VPDLX.psm1` anpassen | Sektion 2 in `VPDLX.psm1` auf die neue Datei umstellen | 1 |
| ☐ | **(Option B)** Runtime-Typprüfung in `FileStorage.Add()` einbauen | `if ($instance -isnot [Logfile]) { throw ... }` als sofortigen Schutz — unabhängig von der Architekturentscheidung sinnvoll | 2 |
| ☐ | `Get()`-Methode mit Kommentar und Cast-Beispiel dokumentieren | Unabhängig von Option A oder B: Aufrufenden Code klar dokumentieren, dass manueller Cast `[Logfile] $store.Get(...)` notwendig ist (bis Option A umgesetzt) | 1 |


***

## 🟡 Priorität 7 — `Print()` Diagnose verbessern

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | **`Print()` Validierungsfehler mit Element-Index anreichern** | Die `foreach`-Schleife in `Logfile.Print()` um Index-Tracking ergänzen, sodass eine `ArgumentException` bei Batch-Validierung den 0-basierten Index und einen Preview des fehlerhaften Wertes enthält (Issue \#7) | 3 |

**Unter-Tasks:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | Index-Counter `$idx` in die `foreach`-Schleife einbauen | `[int] $idx = 0` vor der Schleife, `$idx++` am Ende jedes Schleifendurchlaufs | 1 |
| ☐ | `try/catch [ArgumentException]` um `ValidateMessage()` wickeln | Im `catch`-Block neue Exception mit angereicherter Meldung `"messages[$idx]: ..."` werfen — `ValidateMessage()` selbst bleibt unverändert | 2 |
| ☐ | Wert-Preview im Fehlertext implementieren | Offending-Value-Vorschau: `(null)`, `(leerer String)` oder escaped/gekürzter String (max. 40 Zeichen, `\r`/`\n` sichtbar machen) | 2 |


***

## 🔵 Priorität 8 — Globaler Session-Cleanup (`DestroyAll`)

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | **`DestroyAll()` implementieren und in `OnRemove` integrieren** | `FileStorage.DestroyAll()`-Methode erstellen, in `OnRemove`-Handler von `VPDLX.psm1` aufrufen und optional über `VPDLXcore -KeyID 'destroyall'` zugänglich machen (Issue \#10) — hängt von Issue \#1/\#6-Fixes ab! | 4 |

**Unter-Tasks:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | `DestroyAll()`-Methode in `FileStorage.ps1` implementieren | Über alle `_registry`-Keys iterieren (Snapshot vor Iteration!), `Destroy()` auf jede Instanz aufrufen, `catch` für Fehler pro Instanz, abschließend `_registry.Clear()` + `_names.Clear()` | 3 |
| ☐ | `OnRemove`-Handler in `VPDLX.psm1` um `DestroyAll()` erweitern | Vor der TypeAccelerator-Entfernung `$script:storage.DestroyAll()` aufrufen, mit `try/catch` absichern | 2 |
| ☐ | (Optional) `VPDLXcore -KeyID 'destroyall'` implementieren | Neuen `switch`-Case in `VPDLXcore.ps1` ergänzen, der `$script:storage.DestroyAll()` aufruft und einen `VPDLXreturn`-Rückgabewert liefert | 2 |


***

## 🔵 Priorität 9 — Performance \& Qualitätsverbesserungen

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | **`ScriptsToProcess` Precheck-Skript erstellen** | `VPDLX.Precheck.ps1` anlegen und in `VPDLX.psd1` unter `ScriptsToProcess` eintragen — prüft PS-Version und gibt klare Fehlermeldungen vor dem Modul-Load | 3 |
| ☐ | **Encoding-Option für Export verbessern** | Export-Funktionen um BOM-freie UTF-8-Option erweitern (`New-Object System.Text.UTF8Encoding($false)`) für Kompatibilität mit externen Log-Aggregatoren | 4 |
| ☐ | **Eingabelängen-Limit für Nachrichten** | In `ValidateMessage()` eine konfigurierbare maximale Nachrichtenlänge einbauen (Standard: 8.192 Zeichen) zum Schutz vor Speicher-Flooding | 3 |

**Unter-Tasks für Precheck-Skript:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | `VPDLX.Precheck.ps1` erstellen | PS-Versionscheck (`Major -ge 5`, `Minor -ge 1`), aussagekräftige `Write-Error`-/`Write-Warning`-Meldungen | 2 |
| ☐ | `ScriptsToProcess` in `VPDLX.psd1` aktivieren | Auskommentierten Eintrag aktivieren und auf `'VPDLX.Precheck.ps1'` setzen | 1 |


***

## 🟢 Priorität 10 — Neue Features \& Erweiterungen

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | **`VPDLXgetalllogfiles` implementieren** | Public Wrapper der alle aktiven Logfile-Instanzen als `[PSCustomObject]`-Array mit Name, EntryCount, Erstell- und Aktualisierungszeit zurückgibt | 4 |
| ☐ | **`VPDLXresetlogfile` implementieren** | Public Wrapper für `Logfile.Reset()` — Logfile-Inhalt leeren, Metadaten aktualisieren, strukturierten `VPDLXreturn`-Rückgabewert liefern | 3 |
| ☐ | **`VPDLXfilterlogfile` implementieren** | Public Wrapper für `Logfile.FilterByLevel()` — nach Level filtern, gefilterte Einträge als strukturierten Rückgabewert liefern | 4 |
| ☐ | **Neue Export-Formate: HTML + NDJSON** | Export-System um `html` (formatierter Log-Bericht mit CSS) und `ndjson` (Newline-Delimited JSON für Log-Streaming) erweitern | 6 |
| ☐ | **Konfigurierbarer Mindest-Log-Level** | Beim Erstellen eines Logfiles ein minimales Level festlegbar machen (`[Logfile]::new('ProdLog', 'warning')`) — Einträge unterhalb dieses Levels werden verworfen | 6 |
| ☐ | **`VPDLXcore -KeyID 'stats'` — Modul-Statistiken** | Neuer Core-Key liefert modul-weite Statistiken: Gesamtanzahl erstellter/aktiver Logfiles, Summe aller Einträge, Anzahl Exporte | 4 |


***

## ⚪ Priorität 11 — Qualitätssicherung \& Dokumentation

| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | **Pester-Test-Suite erstellen** | Vollständige Pester-v5-Testsuite für alle Klassen und Public-Wrapper-Funktionen anlegen — Basis für CI/CD-Integration | 8 |
| ☐ | **`CHANGELOG.md` für v1.01.02 pflegen** | Alle behobenen Issues und neuen Features mit Versionsnummer, Datum und Beschreibung eintragen | 2 |
| ☐ | **Inline-Dokumentation vervollständigen** | Alle Public-Funktionen und Klassen-Methoden mit vollständigen Comment-Based-Help-Blöcken (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`) versehen | 5 |

**Unter-Tasks Pester-Test-Suite:**


| Status | Aufgabe | Beschreibung | Schweregrad |
| :-- | :-- | :-- | :-- |
| ☐ | Teststruktur und `Tests/`-Verzeichnis anlegen | `Tests/Unit/`, `Tests/Integration/` anlegen, `Pester`-Dependency in `psd1` oder separatem `requirements.psd1` deklarieren | 3 |
| ☐ | `[Logfile]`-Klasse testen | Konstruktor-Validierung, `Write/Print/Read/Reset/FilterByLevel/Destroy` — inkl. Post-Destroy-Verhalten und Doppel-Destroy | 6 |
| ☐ | `[FileStorage]`-Klasse testen | `Add/Get/Remove/Contains/GetCount/GetNames` — inkl. Fehlerszenarien (Duplikat-Name, nicht vorhandener Name) | 4 |
| ☐ | `[FileDetails]`-Klasse testen | Alle `Record*()`-Methoden, `ToHashtable()`, Timestamp-Format-Validierung | 4 |
| ☐ | Public-Wrapper-Funktionen testen | Je eine `Describe`-Suite pro Wrapper-Funktion — Happy-Path + Fehlerpfade | 5 |
| ☐ | TypeAccelerator-Registrierung testen | Sicherstellen dass `[Logfile]` und `[FileDetails]` nach `Import-Module` existieren und nach `Remove-Module` entfernt werden | 3 |


***

> **Hinweis zur Bearbeitungsreihenfolge:** Die Prioritäten 1–4 bilden eine logische Kette und sollten streng sequenziell abgearbeitet werden — Priorität 1 zuerst, da alle anderen Fixes auf einem korrekten `Destroy()` aufbauen. Prioritäten 5–7 sind voneinander unabhängig und können parallel angegangen werden. Priorität 8 setzt die erfolgreiche Umsetzung von Priorität 1 voraus. Die Prioritäten 9–11 sind Qualitäts- und Zukunftsthemen, die unabhängig vom Bug-Fix-Zyklus begonnen werden können.

