# 📋 Projektplan: local.httpserver

> **Modul:** `local.httpserver`
> **Repository:** [praetoriani/PowerShell.Mods](https://github.com/praetoriani/PowerShell.Mods/tree/main/local.httpserver)
> **Autor:** Praetoriani (a.k.a. M. Sczepanski)
> **Erstellt:** 17.04.2026
> **Zuletzt aktualisiert:** 18.04.2026
> **Aktueller Status:** ✅ Phase 1 - Punkte 1.1-1.4 abgeschlossen, 1.5 teilweise umgesetzt (18.04.2026)
---

## 🎯 Projektziel

`local.httpserver` ist ein vollständig autarkes, portables PowerShell-Standalone-Modul, das einen lokalen HTTP-Server auf Basis von `System.Net.HttpListener` bereitstellt. Das Modul läuft vollständig im Hintergrund (via PowerShell Runspaces), unterstützt das Hosting von statischen Websites, SPAs und WebApps, und bietet mittelfristig Steuerung via Control-Routes sowie Named Pipes (IPC).

Das Modul ist bewusst **ohne externe Abhängigkeiten** konzipiert – es genügt PowerShell 5.1 oder höher.

---

## 🏗️ Zielarchitektur (Gesamtbild)

```
local.httpserver/
│
├── local.httpserver.ps1          ← Einstiegspunkt / Server-Launcher
├── local.httpserver.psm1         ← Root-Modul (Bootstrap, Config, Loader)
├── local.httpserver.psd1         ← Modul-Manifest (Exports, Metadaten)
│
├── include/
│   ├── module.config             ← Zentrale Konfiguration (dot-sourced)
│   ├── system.precheck.ps1       ← Voraussetzungs-Prüfung (via ScriptsToProcess)
│   ├── config.httphost.json      ← App-Metadaten (Referenz-Konfiguration)
│   ├── config.server.json        ← Server-Konfiguration (Port, wwwroot, IPC-Routes)
│   └── config.mime.json          ← MIME-Type-Mapping
│
├── private/
│   ├── OPSreturn.ps1             ← Standardisiertes Return-Objekt (intern)
│   ├── ReadJSON.ps1              ← JSON-Datei-Loader (intern)
│   ├── Invoke-RequestHandler.ps1 ← Request-Verarbeitung
│   ├── [Start-HttpRunspace.ps1]  ← Runspace-Management (geplant)
│   ├── [Invoke-RouteHandler.ps1] ← Control-Route-Handler (geplant)
│   ├── [Write-ServerLog.ps1]     ← Internes Logging (geplant)
│   └── [Invoke-PipeServer.ps1]   ← Named Pipe IPC (geplant, Phase 4)
│
└── public/
    ├── GetMimeType.ps1           ← MIME-Type-Ermittlung (exportiert)
    ├── ExportServerLog.ps1       ← Log-Export (exportiert, Stub vorhanden)
    ├── Start-LocalHttpServer.ps1 ← Server starten
    └── [Stop-LocalHttpServer.ps1]  ← Server stoppen (geplant)
```

> Einträge in `[eckigen Klammern]` sind geplant, aber noch nicht vorhanden.

---

## 📊 Phasenübersicht

| Phase | Bezeichnung | Status | Priorität |
|-------|-------------|--------|-----------|
| **Phase 1** | Fundament & Basisserver | 🚧 Weitgehend umgesetzt | 🔴 Kritisch |
| **Phase 2** | Steuerung & Sicherheit | ⬜ Offen | 🔴 Hoch |
| **Phase 3** | Hintergrundmodus & Runspaces | ⬜ Offen | 🔴 Hoch |
| **Phase 4** | Named Pipes (IPC) | ⬜ Offen | 🟡 Mittel |
| **Phase 5** | Logging & Monitoring | ⬜ Offen | 🟡 Mittel |
| **Phase 6** | Erweiterte Modi (SysTray, Desktop) | ⬜ Offen | 🟢 Niedrig |
| **Phase 7** | Finalisierung & Dokumentation | ⬜ Offen | 🟡 Mittel |

---

## 🔵 Phase 1 – Fundament & Basisserver

> **Ziel:** Eine funktionierende, stabile Basisversion, bei der `http://localhost/` Dateien aus einem konfigurierten `wwwroot`-Verzeichnis im Browser ausliefert.

### 1.1 – Precheck vervollständigen (`system.precheck.ps1`)

- [x] PowerShell-Version prüfen (Minimum: 5.1)
- [x] Prüfen ob `System.Net.HttpListener` verfügbar ist
- [x] Prüfen ob das konfigurierte `wwwroot`-Verzeichnis existiert (oder sinnvoller Fallback)
- [x] Klare, lesbare Fehlermeldungen bei fehlgeschlagenen Checks ausgeben
- [x] Bei kritischem Fehler: Modul-Load abbrechen (`throw` / `exit`)

**Betroffene Datei:** `include/system.precheck.ps1`

---

### 1.2 – Konfigurationsstruktur konsolidieren

Aktuell existieren **zwei parallele Konfigurationswege** (JSON-Dateien UND `module.config` via dot-sourcing). Das ist ein technisches Debt, das beseitigt werden muss.

- [x] Entscheidung treffen: `module.config` (PS-Hashtable, dot-sourced) als **Single Source of Truth**
- [x] `config.httphost.json` und `config.server.json` als reine Referenz-/Backup-Dateien behandeln oder entfernen
- [x] `GetMimeType.ps1` anpassen: nutzt aktuell noch den alten JSON-Pfad (`$httpCore.config.mime`) – muss auf `$mimeType`-Hashtable aus `module.config` umgestellt werden
- [x] `SetCoreConfig` in `psm1` mit `$httpHost` aus `module.config` verbinden (PathPointer → `$httpHost.wwwroot` etc.)
- [x] Sicherstellen dass `$httpCore`, `$httpHost`, `$httpRouter` und `$mimeType` nach dem Laden korrekt im Modul-Scope verfügbar sind

**Betroffene Dateien:** `local.httpserver.psm1`, `include/module.config`, `public/GetMimeType.ps1`

---

### 1.3 – Kern-Requesthandler implementieren (`private/Invoke-RequestHandler.ps1`)

- [x] Neue private Funktion `Invoke-RequestHandler` anlegen
- [x] URL-Pfad auf Dateisystempfad mappen (relativ zu `$httpHost.wwwroot`)
- [x] **Path-Traversal-Schutz:** Sicherstellen dass der aufgelöste Pfad immer innerhalb von `wwwroot` liegt (`[System.IO.Path]::GetFullPath` + String-Präfix-Check)
- [x] Wenn Pfad ein Verzeichnis ist: automatisch `index.html` (oder konfigurierten `homepage`-Wert) suchen
- [x] Datei lesen (`[System.IO.File]::ReadAllBytes`) und als Response zurückgeben
- [x] MIME-Type via `GetMimeType` ermitteln und in `ContentType` setzen
- [x] HTTP 404 zurückgeben wenn Datei nicht existiert (mit optionaler custom `404.html`)
- [x] HTTP 405 zurückgeben für nicht erlaubte HTTP-Methoden (nur `GET` und `HEAD` erlaubt)
- [x] Security-Response-Header setzen:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Cache-Control: no-cache` (konfigurierbar)
  - `Server`-Header entfernen oder neutralisieren

**Betroffene Datei:** `private/Invoke-RequestHandler.ps1`

---

### 1.4 – HTTP-Listener-Kern implementieren

- [x] `System.Net.HttpListener` instanziieren
- [ ] Prefix **ausschließlich** auf `http://localhost:<port>/` binden (kein 0.0.0.0, kein `+`)
- [x] Listener starten (`$listener.Start()`)
- [x] Einfache synchrone Request-Loop implementieren (`$listener.GetContext()`)
- [x] Jeden Request an `Invoke-RequestHandler` delegieren
- [x] Listener sauber stoppen und disposen (`$listener.Stop()` / `$listener.Close()`)
- [x] Grundlegende Fehlerbehandlung (try/catch um die Request-Loop)

**Betroffene Datei:** `public/Start-LocalHttpServer.ps1`

---

### 1.5 – `local.httpserver.ps1` als Launcher fertigstellen

- [ ] 3-Step-Pattern vollständig implementieren: `Import-Module` → `SetCoreConfig` → Start-Funktion aufrufen
- [x] `SetCoreConfig` so erweitern, dass die gesetzten Werte in `$httpHost` einfließen (Port, wwwroot, etc.)
- [ ] Verzeichnisangabe als Parameter beim Aufruf ermöglichen
- [x] Sinnvolle Standardwerte für Port (`8080`) und wwwroot

**Betroffene Datei:** `local.httpserver.ps1`

---

### ✅ Abnahmekriterium Phase 1

> Nach Abschluss von Phase 1 muss folgendes funktionieren:
> `local.httpserver.ps1` starten → Browser öffnen → `http://localhost:8080/` aufrufen → Inhalt aus konfiguriertem Verzeichnis wird korrekt angezeigt, inkl. korrekter MIME-Types für HTML, CSS, JS, Bilder.

**Aktueller Bewertungsstand:** Der technische Unterbau für Phase 1 ist weitgehend vorhanden, aber Phase 1 ist noch **nicht vollständig abnahmefähig**, weil der Listener aktuell auf `http://+:<port>/` statt ausschließlich auf `localhost` bindet und der Launcher `local.httpserver.ps1` die Start-Funktion noch nicht tatsächlich aufruft.

---

## 🟠 Phase 2 – Steuerung & Sicherheit

> **Ziel:** Der Server kann über definierte Control-Routes gesteuert werden. Sicherheitsrelevante Aspekte werden gehärtet.

### 2.1 – Control-Route-Handler (`private/Invoke-RouteHandler.ps1`)

- [ ] Neue private Funktion `Invoke-RouteHandler` anlegen
- [ ] Routen aus `$httpRouter` in `module.config` auslesen
- [ ] Implementierung der folgenden Steuerungsrouten:
  - `GET /sys/ctrl/http-shutdown` → Server geordnet herunterfahren
  - `GET /sys/ctrl/http-reboot` → Server neu starten
  - `GET /sys/ctrl/http-getstatus` → JSON-Response mit Serverstatus (Uptime, Port, wwwroot, Version)
  - `GET /sys/ctrl/http-heartbeat` → Einfaches `{"alive": true}` als Healthcheck
  - `GET /sys/ctrl/gethelp` → Liste aller verfügbaren Control-Routen zurückgeben
  - `GET /sys/ctrl/gohome` → Redirect zur konfigurierten Homepage
- [ ] Route-Matching vor dem File-Handler prüfen (Route hat Vorrang)
- [ ] Optional: Einfache Absicherung der Control-Routen (z. B. nur von `127.0.0.1` erreichbar)

**Betroffene Datei:** `private/Invoke-RouteHandler.ps1` (neu anlegen)

---

### 2.2 – HTTP-Methoden einschränken

- [x] Whitelist für erlaubte HTTP-Methoden definieren (initial: `GET`, `HEAD`)
- [x] Alle anderen Methoden (`POST`, `PUT`, `DELETE`, `PATCH`, etc.) mit `405 Method Not Allowed` ablehnen
- [x] `Allow`-Header in der 405-Response setzen

---

### 2.3 – Sicherheits-Response-Header (Security Hardening)

- [ ] `Content-Security-Policy`-Header setzen (konfigurierbar, sinnvoller Default)
- [ ] `Referrer-Policy: no-referrer` setzen
- [ ] `Permissions-Policy` setzen
- [x] `X-Content-Type-Options: nosniff` (bereits in 1.3 – hier als Test verifizieren)
- [x] `Server`-Header auf neutralen Wert setzen oder vollständig entfernen

---

### 2.4 – Heartbeat & Mutex-basierte Statuskommunikation (Alternative IPC)

- [ ] Konzept für Mutex-basierte Kommunikation definieren (Steuerdatei / Named Mutex)
- [ ] `New-Object System.Threading.Mutex` für exklusive Instanz-Kontrolle nutzen
- [ ] Statusdatei (`httpserver.status.json`) im `include`-Verzeichnis schreiben (PID, Port, Status, Startzeit)
- [ ] Externe Prozesse können Status durch Lesen dieser Datei abfragen
- [ ] Statusdatei beim sauberen Shutdown löschen

---

## 🟣 Phase 3 – Hintergrundmodus & Runspaces

> **Ziel:** Der HTTP-Server läuft vollständig nicht-blockierend im Hintergrund via PowerShell Runspaces. Die Konsole wird bei Bedarf vollständig ausgeblendet.

### 3.1 – Runspace-Architektur (`private/Start-HttpRunspace.ps1`)

- [ ] Neue private Funktion `Start-HttpRunspace` anlegen
- [ ] `[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()` verwenden
- [ ] Runspace mit minimalem `InitialSessionState` konfigurieren (nur benötigte Funktionen übergeben)
- [ ] HTTP-Listener-Loop in den Runspace auslagern
- [ ] `PowerShell`-Instanz im Runspace asynchron starten (`BeginInvoke`)
- [ ] Runspace-Handle und PowerShell-Instanz in `$Script:`-Variable speichern (für späteren Stop)
- [ ] Sauberes Stoppen: `EndInvoke` → `Dispose` des Runspaces

**Betroffene Datei:** `private/Start-HttpRunspace.ps1` (neu anlegen)

---

### 3.2 – Öffentliche Start/Stop-Funktionen (`public/`)

- [x] `Start-LocalHttpServer` implementieren:
  - Konfiguration validieren
  - Runspace starten
  - Statusmeldung ausgeben (oder bei `hidden`-Mode unterdrücken)
- [ ] `Stop-LocalHttpServer` implementieren:
  - Control-Route `/sys/ctrl/http-shutdown` intern aufrufen ODER
  - Runspace direkt stoppen und Listener schließen
- [ ] Beide Funktionen in `FunctionsToExport` in `local.httpserver.psd1` aufnehmen

**Betroffene Dateien:** `public/Start-LocalHttpServer.ps1`, `public/Stop-LocalHttpServer.ps1` (neu), `local.httpserver.psd1`

**Hinweis:** Die vorhandene `Start-LocalHttpServer`-Funktion startet derzeit noch synchron/blockierend und noch **nicht** via Runspace. Der Punkt ist daher nur funktional teilweise erfüllt.

---

### 3.3 – Konsolenfenster ausblenden (`hidden`-Mode)

- [ ] P/Invoke auf `ShowWindow` / `FreeConsole` aus `user32.dll` / `kernel32.dll` nutzen
- [ ] Nur aktivieren wenn `$Script:Config.Mode -eq 'hidden'`
- [ ] Sicherstellen dass versteckter Prozess via Task-Manager noch sichtbar und beendbar ist

---

### 3.4 – `local.httpserver.ps1` auf Runspace-Architektur umstellen

- [ ] Launcher ruft `Start-LocalHttpServer` auf (statt direkt den Listener)
- [ ] Im `hidden`-Mode: Fenster ausblenden nach erfolgreichem Start
- [ ] Im `console`-Mode: Statusanzeige in der Konsole (Uptime, Port, wwwroot)

---

## 🟡 Phase 4 – Named Pipes (IPC)

> **Ziel:** `local.httpserver` unterstützt Named Pipes als vollwertigen IPC-Kanal, über den externe Prozesse (z. B. PowerEdge) Kommandos senden und Antworten empfangen können.

### 4.1 – Named Pipe Server (`private/Invoke-PipeServer.ps1`)

- [ ] `System.IO.Pipes.NamedPipeServerStream` implementieren
- [ ] Pipe-Name aus Konfiguration lesen (z. B. `local.httpserver.pipe`)
- [ ] Pipe-Server in separatem Runspace laufen lassen
- [ ] Eingehende Nachrichten als JSON parsen (`command`, `payload`)
- [ ] Kommandos an den HTTP-Server delegieren (Start, Stop, Status, etc.)
- [ ] Antwort als JSON über die Pipe zurückschicken

**Betroffene Datei:** `private/Invoke-PipeServer.ps1` (neu anlegen)

---

### 4.2 – Named Pipe Client (Hilfsfunktion)

- [ ] `Invoke-PipeCommand` als private Hilfsfunktion implementieren
- [ ] Ermöglicht anderen PS-Skripten, Kommandos an den laufenden Server zu senden
- [ ] Verwendung in `Stop-LocalHttpServer` (als Alternative zu HTTP-Route)

---

### 4.3 – Konfiguration erweitern

- [ ] `UseIPC`-Flag in `SetCoreConfig` auswerten
- [ ] Pipe-Name in `module.config` konfigurierbar machen
- [ ] Pipe-Server nur starten wenn `$Script:Config.UseIPC -eq $true`

---

## 🟤 Phase 5 – Logging & Monitoring

> **Ziel:** `local.httpserver` schreibt ein strukturiertes Logfile und stellt es über `ExportServerLog` bereit.

### 5.1 – Internes Logging (`private/Write-ServerLog.ps1`)

- [ ] Neue private Funktion `Write-ServerLog` anlegen
- [ ] Log-Einträge im Format: `[TIMESTAMP] [LEVEL] MESSAGE`
- [ ] Log-Level: `INFO`, `WARN`, `ERROR`, `DEBUG`
- [ ] Logfile-Pfad aus `$httpCore.config.log` lesen
- [ ] Thread-sicheres Schreiben (wichtig bei Runspace-Betrieb): `[System.IO.File]::AppendAllText` mit Lock-Mechanismus oder `StreamWriter` mit `AutoFlush`
- [ ] Logging nur aktiv wenn `$Script:Config.UseLogging -eq 1`

**Betroffene Datei:** `private/Write-ServerLog.ps1` (neu anlegen)

---

### 5.2 – `ExportServerLog.ps1` fertigstellen

- [ ] Funktion liest das interne Logfile
- [ ] Export als `.txt` oder `.log` (Parameter `FileFormat` bereits vorhanden)
- [ ] Optional: Zeitraum-Filter (von/bis)
- [ ] `OPSreturn`-Muster für Rückgabe verwenden

**Betroffene Datei:** `public/ExportServerLog.ps1` (Stub vorhanden, implementieren)

---

### 5.3 – Access-Log (HTTP-Request-Logging)

- [ ] Jeden verarbeiteten Request mit Methode, URL, Statuscode, Bytes, Timestamp loggen
- [ ] Format an Apache Combined Log Format anlehnen
- [ ] Separates Access-Log vs. Error-Log erwägen

---

## 🟢 Phase 6 – Erweiterte Modi

> **Ziel:** Neben `hidden` und `console` werden `systray` und `desktop` als optionale Betriebsmodi implementiert.

### 6.1 – `systray`-Modus (System Tray Icon)

- [ ] `System.Windows.Forms.NotifyIcon` verwenden
- [ ] Icon aus `include/ui.png` laden
- [ ] Kontextmenü mit: Status anzeigen, Server stoppen, Log öffnen
- [ ] Läuft in separatem STA-Runspace (Windows Forms benötigt STA-Thread)

---

### 6.2 – `desktop`-Modus (WPF/XAML UI)

- [ ] XAML-Definition in `include/ui.xml` anlegen
- [ ] WPF-Fenster mit: Serverstatus, Log-Viewer, Start/Stop-Button, Konfigurationsanzeige
- [ ] Läuft in separatem STA-Runspace

---

## ⚪ Phase 7 – Finalisierung & Dokumentation

> **Ziel:** Das Modul ist produktionsreif, vollständig dokumentiert und sauber versioniert.

### 7.1 – Modul-Metadaten finalisieren

- [ ] `CHANGELOG.md` mit allen Änderungen pflegen (aktuell leer)
- [ ] `README.md` vollständig ausschreiben (Installation, Quickstart, Konfiguration, API-Referenz)
- [ ] Versionsnummer in `psd1`, `psm1` und `module.config` synchronisieren
- [ ] `FileList` in `psd1` auf alle tatsächlich vorhandenen Dateien aktualisieren

---

### 7.2 – Tests & Validierung

- [ ] Manuelle End-to-End-Tests für alle Phasen durchführen
- [ ] Edge Cases testen: leeres wwwroot, ungültige Pfade, Port bereits belegt, parallele Requests
- [ ] Path-Traversal-Angriffe manuell testen und blockieren verifizieren
- [ ] PowerShell 5.1 und PowerShell 7.x Kompatibilität verifizieren

---

### 7.3 – Portabilität sicherstellen

- [ ] Verifizieren dass der gesamte Modul-Ordner kopiert werden kann (beliebiges Verzeichnis)
- [ ] Alle Pfade sind relativ zu `$PSScriptRoot` (kein hardcodierter absoluter Pfad im Code)
- [ ] Modul funktioniert ohne vorherige Installation (kein `Install-Module` erforderlich)

---

### 7.4 – `config.mime.json` bereinigen

- [ ] Aktuell existiert `.wasm` ohne führenden Punkt (Tippfehler in `module.config`) → korrigieren zu `".wasm"`
- [ ] MIME-Types auf Vollständigkeit prüfen (z.B. `.webmanifest`, `.wasm`, `.br`, `.gz` für Brotli/Gzip)

---

## 📝 Bekannte Issues & Tech Debt

| ID | Beschreibung | Priorität | Phase |
|----|-------------|-----------|-------|
| TD-01 | JSON-Konfigurationsdateien bestehen weiterhin parallel zu `module.config` und sind noch nicht final als Referenz/Backup eingeordnet | 🔴 Hoch | 1.2 |
| TD-04 | `ExportServerLog.ps1` ist weiterhin nur Stub / unvollständig | 🟡 Mittel | 5.2 |
| TD-05 | Tippfehler in `module.config`: `"wasm"` fehlt führender Punkt | 🟢 Niedrig | 7.4 |
| TD-06 | `config.httphost.json` referenziert `include\ui.xml\` mit falschem Backslash-Trailing | 🟢 Niedrig | 7.1 |
| TD-08 | `Start-LocalHttpServer.ps1` bindet aktuell auf `http://+:<port>/` statt ausschließlich auf `localhost` | 🔴 Hoch | 1.4 |
| TD-09 | `Start-LocalHttpServer.ps1` ruft `Invoke-RequestHandler` mit `-Request/-Response` auf, die Implementierung erwartet jedoch `-Context` | 🔴 Hoch | 1.4 |
| TD-10 | `local.httpserver.ps1` implementiert das 3-Step-Pattern noch nicht vollständig bis zum tatsächlichen Serverstart | 🔴 Hoch | 1.5 |

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

*Dieser Projektplan wurde anhand des aktuellen Repository-Zustands auf den tatsächlichen Implementierungsstand abgeglichen und aktualisiert.*
