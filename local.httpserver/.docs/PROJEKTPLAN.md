# 📋 Projektplan: local.httpserver

> **Modul:** `local.httpserver`
> **Repository:** [praetoriani/PowerShell.Mods](https://github.com/praetoriani/PowerShell.Mods/tree/main/local.httpserver)
> **Autor:** Praetoriani (a.k.a. M. Sczepanski)
> **Erstellt:** 17.04.2026
**Zuletzt aktualisiert:** 26.04.2026
**Aktueller Status:** ✅ Phase 1 abgeschlossen · ✅ Phase 2 abgeschlossen · ✅ Phase 3 abgeschlossen · Phase 4 kann begonnen werden
---

## 🎯 Projektziel

`local.httpserver` ist ein vollständig autarkes, portables PowerShell-Standalone-Modul, das einen lokalen HTTP-Server auf Basis von `System.Net.HttpListener` bereitstellt. Das Modul soll statische Websites, SPAs und WebApps lokal ausliefern und mittelfristig um Control-Routes, Runspace-Betrieb und IPC erweitert werden.

Das Modul ist bewusst **ohne externe Abhängigkeiten** konzipiert – PowerShell 5.1 oder höher genügt.

---

## 🏗️ Zielarchitektur (Gesamtbild)

```text
local.httpserver/
│
├── local.httpserver.ps1            ← Einstiegspunkt / Server-Launcher
├── local.httpserver.psm1           ← Root-Modul (Bootstrap, Config, Loader)
├── local.httpserver.psd1           ← Modul-Manifest (Exports, Metadaten)
│
├── include/
│   ├── module.config.ps1           ← Zentrale Konfiguration (dot-sourced, aktive Quelle)
│   ├── system.precheck.ps1         ← Voraussetzungs-Prüfung (via ScriptsToProcess)
│   ├── config.httphost.json        ← Referenz-/Alt-Konfiguration
│   ├── config.server.json          ← Referenz-/Alt-Konfiguration
│   └── config.mime.json            ← Referenz-/Alt-Konfiguration für MIME-Typen
│
├── private/
│   ├── OPSreturn.ps1               ← Standardisiertes Return-Objekt (intern)
│   ├── ReadJSON.ps1                ← JSON-Datei-Loader (intern)
│   ├── Invoke-RequestHandler.ps1   ← Request-Verarbeitung
│   ├── [Start-HttpRunspace.ps1]    ← Runspace-Management (geplant)
│   ├── [Invoke-RouteHandler.ps1]   ← Control-Route-Handler (geplant)
│   ├── [Write-ServerLog.ps1]       ← Internes Logging (geplant)
│   └── [Invoke-PipeServer.ps1]     ← Named Pipe IPC (geplant, Phase 4)
│
└── public/
    ├── GetMimeType.ps1             ← MIME-Type-Ermittlung (exportiert)
    ├── ExportServerLog.ps1         ← Log-Export (exportiert, Stub vorhanden)
    ├── Start-HTTPserver.ps1        ← Aktueller synchroner Serverstart
    └── [Stop-LocalHttpServer.ps1]  ← Server stoppen (geplant)
```

> Einträge in `[eckigen Klammern]` sind geplant, aber noch nicht vorhanden.

---

## 📊 Phasenübersicht

| Phase | Bezeichnung | Status | Priorität |
|-------|-------------|--------|-----------|
| **Phase 1** | Fundament & Basisserver | ✅ Technisch funktionsfähig | 🔴 Kritisch |
| **Phase 2** | Steuerung & Sicherheit | ✅ Abgeschlossen | 🔴 Hoch |
| **Phase 3** | Hintergrundmodus & Runspaces | ✅ Abgeschlossen | 🔴 Hoch |
| **Phase 4** | Named Pipes (IPC) | ⬜ Offen | 🟡 Mittel |
| **Phase 5** | Logging & Monitoring | 🚧 Teilweise begonnen | 🟡 Mittel |
| **Phase 6** | Erweiterte Modi (SysTray, Desktop) | ⬜ Offen | 🟢 Niedrig |
| **Phase 7** | Finalisierung & Dokumentation | 🚧 Teilweise begonnen | 🟡 Mittel |

---

## 🔵 Phase 1 – Fundament & Basisserver

> **Ziel:** Eine funktionierende, stabile Basisversion, bei der `http://localhost:<port>/` Dateien aus einem konfigurierten `wwwroot`-Verzeichnis korrekt im Browser ausliefert.

### 1.1 – Precheck vervollständigen (`system.precheck.ps1`)

- [x] PowerShell-Version prüfen (Minimum: 5.1)
- [x] Prüfen ob `System.Net.HttpListener` verfügbar ist
- [x] Prüfen ob das konfigurierte `wwwroot`-Verzeichnis existiert (oder sinnvoller Fallback)
- [x] Klare, lesbare Fehlermeldungen bei fehlgeschlagenen Checks ausgeben
- [x] Bei kritischem Fehler: Modul-Load abbrechen (`throw` / `exit`)

**Statusbewertung:** Erledigt.

---

### 1.2 – Konfigurationsstruktur konsolidieren

- [x] Entscheidung treffen: `module.config.ps1` (PS-Hashtable, dot-sourced) als **Single Source of Truth**
- [x] Konfigurationswerte nach dem Laden in den Script-Scope synchronisieren
- [x] `GetMimeType.ps1` auf `$mimeType`-Hashtable aus der Modulkonfiguration umstellen
- [x] `SetCoreConfig` in `psm1` mit `$httpHost` aus `module.config.ps1` verbinden
- [x] Sicherstellen dass `$httpCore`, `$httpHost`, `$httpRouter` und `$mimeType` nach dem Laden korrekt im Modul-Scope verfügbar sind
- [ ] Alte JSON-Dateien endgültig stilllegen, entfernen oder klar als reine Referenz deklarieren

**Statusbewertung:** Fachlich abgeschlossen, technisches Debt bei den alten JSON-Dateien bleibt bestehen.

---

### 1.3 – Kern-Requesthandler implementieren (`private/Invoke-RequestHandler.ps1`)

- [x] Neue private Funktion `Invoke-RequestHandler` anlegen
- [x] URL-Pfad auf Dateisystempfad mappen (relativ zu `$httpHost.wwwroot`)
- [x] **Path-Traversal-Schutz:** Sicherstellen dass der aufgelöste Pfad immer innerhalb von `wwwroot` liegt (`[System.IO.Path]::GetFullPath` + String-Präfix-Check)
- [x] Wenn Pfad ein Verzeichnis ist: automatisch `index.html` (oder konfigurierten `homepage`-Wert) suchen
- [x] Datei lesen (`[System.IO.File]::ReadAllBytes`) und als Response zurückgeben
- [x] MIME-Type via `GetMimeType` ermitteln und in `ContentType` setzen
- [x] HTTP 404 zurückgeben wenn Datei nicht existiert (mit Custom `404.html`, falls vorhanden)
- [x] HTTP 405 zurückgeben für nicht erlaubte HTTP-Methoden (nur `GET` und `HEAD` erlaubt)
- [x] Security-Response-Header setzen:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Cache-Control: no-cache`
  - `Server`-Header entfernen oder neutralisieren
- [x] Custom `500.html` als Fallback für interne Fehler unterstützen

**Statusbewertung:** Erledigt und funktionsfähig.

---

### 1.4 – HTTP-Listener-Kern implementieren

- [x] `System.Net.HttpListener` instanziieren
- [x] Prefix auf `http://localhost:<port>/` bzw. auf den in der Konfiguration definierten Host binden
- [x] Listener starten (`$listener.Start()`)
- [x] Einfache synchrone Request-Loop implementieren (`$listener.GetContext()`)
- [x] Requests an `Invoke-RequestHandler -Context` delegieren
- [x] Listener sauber stoppen und disposen (`$listener.Stop()` / `$listener.Close()`)
- [x] Grundlegende Fehlerbehandlung (try/catch um die Request-Loop)
- [x] Steuerungsroute für geordnetes Herunterfahren implementieren

**Statusbewertung:** Erledigt. Frühere Inkonsistenzen beim Prefix und beim Aufruf von `Invoke-RequestHandler` sind behoben.

---

### 1.5 – `local.httpserver.ps1` als Launcher fertigstellen

- [x] 3-Step-Pattern vollständig implementieren: `Import-Module` → `SetCoreConfig` → Start-Funktion aufrufen
- [x] `SetCoreConfig` so erweitern, dass die gesetzten Werte in `$httpHost` einfließen (Port, wwwroot, etc.)
- [x] Verzeichnisangabe als Parameter beim Aufruf ermöglichen
- [x] Sinnvolle Standardwerte für Port (`8080`) und `wwwroot`

**Statusbewertung:** Erledigt.

---

### ✅ Abnahmekriterium Phase 1

> Nach Abschluss von Phase 1 muss folgendes funktionieren:
> Modul laden → Server starten → Browser öffnen → `http://localhost:8080/` aufrufen → Inhalt aus konfiguriertem Verzeichnis wird korrekt angezeigt, inklusive korrekter MIME-Typen für HTML, CSS, JS, Bilder und sinnvoller Fehlerbehandlung.

**Aktueller Bewertungsstand:** Dieses Kriterium ist inzwischen technisch erfüllt. Der Server startet, liefert Inhalte aus dem `wwwroot` aus und verarbeitet Datei-, 404-, 405- und 500-Szenarien funktionsfähig. Offen bleibt primär die ergonomische Fertigstellung des Launchers `local.httpserver.ps1`.

---

## 🟠 Phase 2 – Steuerung & Sicherheit

> **Ziel:** Der Server kann über definierte Control-Routes gesteuert werden. Sicherheitsrelevante Aspekte werden weiter gehärtet.

### 2.1 – Control-Route-Handler (`private/Invoke-RouteHandler.ps1`)

- [X] Neue private Funktion `Invoke-RouteHandler` anlegen
- [x] Routen aus `$httpRouter` in `module.config.ps1` zentral definieren
- [x] Route-Matching vor dem File-Handler prüfen (Route hat Vorrang)
- [x] `GET /sys/ctrl/http-shutdown` → geordnetes Herunterfahren implementiert
- [x] `GET /sys/ctrl/http-reboot` → Server neu starten
- [X] `GET /sys/ctrl/http-getstatus` → JSON-Response mit Serverstatus (Uptime, Port, wwwroot, Version)
- [X] `GET /sys/ctrl/http-heartbeat` → Einfaches `{"alive": true}` als Healthcheck
- [X] `GET /sys/ctrl/gethelp` → Liste aller verfügbaren Control-Routen zurückgeben
- [x] `GET /sys/ctrl/gohome` → Redirect zur konfigurierten Homepage
- [x] Unbekannte `/sys/ctrl/`-Routen separat behandeln, statt an den File-Handler zu delegieren
- [X] Optional: Einfache Absicherung der Control-Routen (z. B. nur von `127.0.0.1` oder `::1` erreichbar)

**Statusbewertung:** Erledigt.

---

### 2.2 – HTTP-Methoden einschränken

- [x] Whitelist für erlaubte HTTP-Methoden definieren (initial: `GET`, `HEAD`)
- [x] Alle anderen Methoden (`POST`, `PUT`, `DELETE`, `PATCH`, etc.) mit `405 Method Not Allowed` ablehnen
- [x] `Allow`-Header in der 405-Response setzen

**Statusbewertung:** Erledigt.

---

### 2.3 – Sicherheits-Response-Header (Security Hardening)

- [X] `Content-Security-Policy`-Header setzen (konfigurierbar, sinnvoller Default)
- [X] `Referrer-Policy: no-referrer` setzen
- [X] `Permissions-Policy` setzen
- [x] `X-Content-Type-Options: nosniff`
- [x] `X-Frame-Options: DENY`
- [x] `Cache-Control: no-cache`
- [x] `Server`-Header auf neutralen Wert setzen oder vollständig entfernen

**Statusbewertung:** Erledigt.

---

### 2.4 – Heartbeat & Mutex-basierte Statuskommunikation (Alternative IPC)

- [X] Konzept für Mutex-basierte Kommunikation definieren (Steuerdatei / Named Mutex)
- [X] `New-Object System.Threading.Mutex` für exklusive Instanz-Kontrolle nutzen
- [X] Statusdatei (`httpserver.status.json`) im `include`-Verzeichnis schreiben (PID, Port, Status, Startzeit)
- [X] Externe Prozesse können Status durch Lesen dieser Datei abfragen
- [X] Statusdatei beim sauberen Shutdown löschen

**Statusbewertung:** Erledigt.


---

## 🟣 Phase 3 – Hintergrundmodus & Runspaces

> **Ziel:** Der HTTP-Server läuft vollständig nicht-blockierend im Hintergrund via PowerShell Runspaces. Die Konsole wird bei Bedarf vollständig ausgeblendet.

### 3.1 – Runspace-Architektur (`private/Start-HttpRunspace.ps1`)

- [X] Neue private Funktion `Start-HttpRunspace` anlegen
- [X] `[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()` verwenden
- [X] Runspace mit minimalem `InitialSessionState` konfigurieren (nur benötigte Funktionen übergeben)
- [X] HTTP-Listener-Loop in den Runspace auslagern
- [X] `PowerShell`-Instanz im Runspace asynchron starten (`BeginInvoke`)
- [X] Runspace-Handle und PowerShell-Instanz in `$Script:`-Variable speichern (für späteren Stop)
- [X] Sauberes Stoppen: `EndInvoke` → `Dispose` des Runspaces

**Statusbewertung:** Erledigt.

---

### 3.2 – Öffentliche Start/Stop-Funktionen (`public/`)

- [x] Startfunktion ist öffentlich vorhanden und funktional nutzbar (`Start-HTTPserver.ps1`)
- [X] Öffentliche Stop-Funktion als separate exportierte API implementieren
- [X] Beide Funktionen konsistent in `FunctionsToExport` aufnehmen
- [X] Auf Runspace-Betrieb umstellen

**Statusbewertung:** Erledigt.

---

### 3.3 – Konsolenfenster ausblenden (`hidden`-Mode)

- [X] P/Invoke auf `ShowWindow` / `FreeConsole` aus `user32.dll` / `kernel32.dll` nutzen
- [X] Nur aktivieren wenn `$Script:Config.Mode -eq 'hidden'`
- [X] Sicherstellen dass versteckter Prozess via Task-Manager noch sichtbar und beendbar ist

**Statusbewertung:** Erledigt.

---

### 3.4 – `local.httpserver.ps1` auf Runspace-Architektur umstellen

- [X] Launcher ruft öffentliche Startfunktion auf
- [X] Im `hidden`-Mode: Fenster ausblenden nach erfolgreichem Start
- [X] Im `console`-Mode: Statusanzeige in der Konsole (Uptime, Port, wwwroot)

**Statusbewertung:** Erledigt.

---

## 🟡 Phase 4 – Named Pipes (IPC)

> **Ziel:** `local.httpserver` unterstützt Named Pipes als vollwertigen IPC-Kanal, über den externe Prozesse Kommandos senden und Antworten empfangen können.

### 4.1 – Named Pipe Server (`private/Invoke-PipeServer.ps1`)

- [ ] `System.IO.Pipes.NamedPipeServerStream` implementieren
- [ ] Pipe-Name aus Konfiguration lesen (z. B. `local.httpserver.pipe`)
- [ ] Pipe-Server in separatem Runspace laufen lassen
- [ ] Eingehende Nachrichten als JSON parsen (`command`, `payload`)
- [ ] Kommandos an den HTTP-Server delegieren (Start, Stop, Status, etc.)
- [ ] Antwort als JSON über die Pipe zurückschicken

**Statusbewertung:** Noch nicht begonnen.

---

### 4.2 – Named Pipe Client (Hilfsfunktion)

- [ ] `Invoke-PipeCommand` als private Hilfsfunktion implementieren
- [ ] Ermöglicht anderen PS-Skripten, Kommandos an den laufenden Server zu senden
- [ ] Verwendung in `Stop-LocalHttpServer` (als Alternative zu HTTP-Route)

**Statusbewertung:** Noch nicht begonnen.

---

### 4.3 – Konfiguration erweitern

- [ ] `UseIPC`-Flag in `SetCoreConfig` auswerten
- [ ] Pipe-Name in `module.config.ps1` konfigurierbar machen
- [ ] Pipe-Server nur starten wenn `$Script:Config.UseIPC -eq $true`

**Statusbewertung:** Noch nicht begonnen.

---

## 🟤 Phase 5 – Logging & Monitoring

> **Ziel:** `local.httpserver` schreibt ein strukturiertes Logfile und stellt es über `ExportServerLog` bereit.

### 5.1 – Internes Logging (`private/Write-ServerLog.ps1`)

- [ ] Neue private Funktion `Write-ServerLog` anlegen
- [ ] Log-Einträge im Format: `[TIMESTAMP] [LEVEL] MESSAGE`
- [ ] Log-Level: `INFO`, `WARN`, `ERROR`, `DEBUG`
- [ ] Logfile-Pfad aus der Konfiguration lesen
- [ ] Thread-sicheres Schreiben für Runspace-Betrieb vorsehen
- [ ] Logging nur aktiv wenn konfigurationsseitig aktiviert

**Statusbewertung:** Noch nicht begonnen.

---

### 5.2 – `ExportServerLog.ps1` fertigstellen

- [ ] Funktion liest das interne Logfile
- [ ] Export als `.txt` oder `.log`
- [ ] Optional: Zeitraum-Filter (von/bis)
- [ ] `OPSreturn`-Muster für Rückgabe verwenden

**Statusbewertung:** Noch offen; Stub vorhanden.

---

### 5.3 – Access-Log (HTTP-Request-Logging)

- [x] Requests werden bereits mit Zeitstempel, Methode, URL und RemoteEndPoint in die Konsole geschrieben
- [ ] Statuscode und Bytegröße systematisch mitloggen
- [ ] Format an Apache Combined Log Format anlehnen
- [ ] Separates Access-Log vs. Error-Log erwägen
- [ ] Persistenz in Datei ergänzen

**Statusbewertung:** Begonnen, aber noch nicht vollständig.

---

## 🟢 Phase 6 – Erweiterte Modi

> **Ziel:** Neben `hidden` und `console` werden `systray` und `desktop` als optionale Betriebsmodi implementiert.

### 6.1 – `systray`-Modus (System Tray Icon)

- [ ] `System.Windows.Forms.NotifyIcon` verwenden
- [ ] Icon aus `include/ui.png` laden
- [ ] Kontextmenü mit: Status anzeigen, Server stoppen, Log öffnen
- [ ] Läuft in separatem STA-Runspace (Windows Forms benötigt STA-Thread)

**Statusbewertung:** Noch nicht begonnen.

---

### 6.2 – `desktop`-Modus (WPF/XAML UI)

- [ ] XAML-Definition in `include/ui.xml` anlegen
- [ ] WPF-Fenster mit: Serverstatus, Log-Viewer, Start/Stop-Button, Konfigurationsanzeige
- [ ] Läuft in separatem STA-Runspace

**Statusbewertung:** Noch nicht begonnen.

---

## ⚪ Phase 7 – Finalisierung & Dokumentation

> **Ziel:** Das Modul ist produktionsreif, vollständig dokumentiert und sauber versioniert.

### 7.1 – Modul-Metadaten finalisieren

- [ ] `CHANGELOG.md` mit allen Änderungen pflegen (aktuell leer)
- [ ] `README.md` vollständig ausschreiben (Installation, Quickstart, Konfiguration, API-Referenz)
- [ ] Versionsnummer in `psd1`, `psm1` und `module.config.ps1` synchronisieren
- [ ] `FileList` in `psd1` auf alle tatsächlich vorhandenen Dateien aktualisieren

**Statusbewertung:** Teilweise begonnen.

---

### 7.2 – Tests & Validierung

- [x] Manuelle End-to-End-Tests für Basisserver, Fehlerfälle und Control-Routing wurden bereits durchgeführt
- [ ] Edge Cases testen: leeres `wwwroot`, ungültige Pfade, Port bereits belegt, parallele Requests
- [ ] Path-Traversal-Angriffe systematisch testen und verifizieren
- [ ] PowerShell 5.1 und PowerShell 7.x Kompatibilität formell verifizieren

**Statusbewertung:** Begonnen.

---

### 7.3 – Portabilität sicherstellen

- [ ] Verifizieren dass der gesamte Modul-Ordner kopiert werden kann (beliebiges Verzeichnis)
- [x] Zentrale Pfadauflösung basiert bereits weitgehend auf Root-/Join-Path-Logik
- [ ] Alle Pfade abschließend auf vollständige Relative-/Root-Sicherheit prüfen
- [ ] Modul funktioniert ohne vorherige Installation (kein `Install-Module` erforderlich)

**Statusbewertung:** Teilweise begonnen.

---

### 7.4 – MIME-Konfiguration bereinigen

- [ ] Tippfehler in MIME-Konfiguration prüfen und ggf. korrigieren (`.wasm` etc.)
- [ ] MIME-Typen auf Vollständigkeit prüfen (`.webmanifest`, `.wasm`, `.br`, `.gz`)
- [ ] Alt-/Referenzkonfigurationen mit der aktiven Hashtable synchronisieren oder verwerfen

**Statusbewertung:** Noch offen.

---

## 📝 Bekannte Issues & Tech Debt

| ID | Beschreibung | Priorität | Phase | Status |
|----|--------------|-----------|-------|--------|
| TD-01 | JSON-Konfigurationsdateien bestehen weiterhin parallel zu `module.config.ps1` und sind noch nicht final als Referenz/Backup eingeordnet | 🔴 Hoch | 1.2 | weiterhin offen |
| TD-04 | `ExportServerLog.ps1` ist weiterhin nur Stub / unvollständig | 🟡 Mittel | 5.2 | weiterhin offen |
| TD-05 | MIME-Konfiguration sollte auf Vollständigkeit und eventuelle Tippfehler geprüft werden | 🟢 Niedrig | 7.4 | weiterhin offen |
| TD-06 | Alt-/Referenzdateien (`config.httphost.json`, `config.server.json`, `config.mime.json`) sind noch nicht bereinigt bzw. dokumentiert | 🟢 Niedrig | 7.1 | weiterhin offen |
| TD-10 | `local.httpserver.ps1` implementiert das 3-Step-Pattern noch nicht vollständig bis zum tatsächlichen Serverstart | 🔴 Hoch | 1.5 | ✓ Erledigt |
| TD-11 | Dedizierter `Invoke-RouteHandler` für Control-Routes fehlt noch | 🟡 Mittel | 2.1 | ✓ Erledigt |
| TD-12 | Öffentliche Stop-Funktion und Runspace-Architektur fehlen noch | 🔴 Hoch | 3 | ✓ Erledigt |

---

## 🔑 Legende

| Symbol | Bedeutung |
|--------|-----------|
| ✅ | Erledigt |
| 🚧 | In Arbeit |
| ⬜ | Offen / Noch nicht begonnen |
| 🔴 | Kritische / Hohe Priorität |
| 🟡 | Mittlere Priorität |
| 🟢 | Niedrige Priorität |

---

*Dieser Projektplan wurde am 26.04.2026 auf Basis des aktuellen Implementierungsstands und der zuletzt behobenen Fehler im Server- und Error-Handling aktualisiert.*
