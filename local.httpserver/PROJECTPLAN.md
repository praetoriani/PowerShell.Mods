# local.httpserver — Projektplan

> **Modul:** `local.httpserver`
> **Autor:** Praetoriani (a.k.a. M.Sczepanski)
> **Erstellt:** 17.04.2026
> **Letztes Update:** 17.04.2026
> **Version:** v1.00.00

---

## Inhaltsverzeichnis

1. [Projektziel & Vision](#1-projektziel--vision)
2. [Architekturübersicht](#2-architekturübersicht)
3. [Aktueller Stand (Ist-Zustand)](#3-aktueller-stand-ist-zustand)
4. [Phasenplan](#4-phasenplan)
   - [Phase 1 — Solide Basisfunktionalität](#phase-1--solide-basisfunktionalität)
   - [Phase 2 — Steuerung & Kommunikation](#phase-2--steuerung--kommunikation)
   - [Phase 3 — Sicherheit & Härtung](#phase-3--sicherheit--härtung)
   - [Phase 4 — Hintergrundmodus & Runspaces](#phase-4--hintergrundmodus--runspaces)
   - [Phase 5 — Named Pipes / IPC](#phase-5--named-pipes--ipc)
   - [Phase 6 — UI-Modi & UX](#phase-6--ui-modi--ux)
   - [Phase 7 — Polish, Tests & Dokumentation](#phase-7--polish-tests--dokumentation)
5. [Fortschrittsübersicht](#5-fortschrittsübersicht)
6. [Dateistruktur-Zielzustand](#6-dateistruktur-zielzustand)
7. [Konventionen & Hinweise](#7-konventionen--hinweise)

---

## 1. Projektziel & Vision

`local.httpserver` ist ein **vollständig autarkes, portables PowerShell-Modul**, das einen lokalen HTTP-Server auf Basis von `System.Net.HttpListener` bereitstellt. Es wurde aus dem übergeordneten Projekt *PowerEdge* ausgegliedert, um Scope-Probleme zu vermeiden und als eigenständiges AiO-Package zu fungieren.

**Kernziele:**

- Statische Dateien (HTML, CSS, JS, Assets) aus einem konfigurierbaren `wwwroot`-Verzeichnis servieren
- SPAs (Single Page Applications) mit clientseitigem Routing unterstützen
- Vollständig im Hintergrund laufen — ohne Konsolenfenster, ohne Freezes
- Portable Deployment: Modul-Ordner kopieren → fertig
- Sicherheit: Path-Traversal-Schutz, Localhost-Binding, abgesicherte Control-Endpoints
- Mittelfristig: Named Pipes als IPC-Mechanismus
- Langfristig: Mehrere UI-Modi (hidden, console, systray, desktop/WPF)

---

## 2. Architekturübersicht

```
local.httpserver/
│
├── local.httpserver.ps1       ← Einstiegspunkt: lädt Modul, konfiguriert, startet Server
├── local.httpserver.psm1      ← Root-Modul: Bootstrap, Config-Schema ($Script:Config)
├── local.httpserver.psd1      ← Modul-Manifest: Exporte, Metadaten, Precheck-Hook
│
├── include/
│   ├── module.config          ← Dot-Sourced Config: $httpCore, $httpHost, $httpRouter, $mimeType
│   ├── system.precheck.ps1    ← Wird via ScriptsToProcess vor Modulload ausgeführt
│   ├── config.httphost.json   ← (Legacy/Backup) JSON-Konfiguration HTTP-Host
│   ├── config.server.json     ← (Legacy/Backup) JSON-Konfiguration Server
│   └── config.mime.json       ← (Legacy/Backup) MIME-Type-Tabelle als JSON
│
├── private/                   ← Interne Hilfsfunktionen (nicht exportiert)
│   ├── OPSreturn.ps1          ← Standardisiertes Return-Objekt {code, msg, data}
│   └── ReadJSON.ps1           ← JSON-Datei einlesen mit Fehlerbehandlung
│
└── public/                    ← Exportierte Funktionen
    ├── GetMimeType.ps1         ← MIME-Type per Dateiendung ermitteln
    └── ExportServerLog.ps1    ← Serverlog exportieren
```

**Datenfluss (geplant):**
```
local.httpserver.ps1
  └─► Import-Module
        └─► system.precheck.ps1   (ScriptsToProcess)
        └─► local.httpserver.psm1
              └─► module.config   (dot-sourced)
              └─► private/*.ps1   (dot-sourced, intern)
              └─► public/*.ps1    (dot-sourced, exportiert)
  └─► SetCoreConfig -PathPointer ... -Mode 'hidden' ...
  └─► Start-HttpServer           ← [ZU ENTWICKELN]
        └─► Runspace
              └─► HttpListener-Loop
                    └─► Request-Handler
                          ├─► Control-Router  (/sys/ctrl/...)
                          └─► File-Router     (wwwroot → Datei servieren)
```

---

## 3. Aktueller Stand (Ist-Zustand)

| Datei / Komponente | Status | Anmerkung |
|---|---|---|
| `local.httpserver.psd1` | ✅ Vorhanden | Manifest vollständig, Exports definiert |
| `local.httpserver.psm1` | ✅ Vorhanden | Bootstrap, Config-Schema, Dot-Sourcing |
| `local.httpserver.ps1` | ✅ Vorhanden | 3-Step-Pattern angelegt (Schritt 3 leer) |
| `include/module.config` | ✅ Vorhanden | `$httpCore`, `$httpHost`, `$httpRouter`, `$mimeType` definiert |
| `include/system.precheck.ps1` | ⚠️ Stub | Datei existiert, Inhalt leer — Logik fehlt |
| `private/OPSreturn.ps1` | ✅ Fertig | Standardisiertes Return-Objekt |
| `private/ReadJSON.ps1` | ✅ Vorhanden | JSON-Reader mit Fehlerbehandlung |
| `public/GetMimeType.ps1` | ✅ Vorhanden | MIME-Lookup implementiert |
| `public/ExportServerLog.ps1` | ⚠️ Stub | Grundstruktur vorhanden, Logik fehlt |
| `CHANGELOG.md` | ⚠️ Leer | Noch kein Inhalt |
| **HTTP-Listener-Kern** | ❌ Fehlt | Noch nicht implementiert |
| **Runspace-Wrapper** | ❌ Fehlt | Noch nicht implementiert |
| **Request-Handler** | ❌ Fehlt | Noch nicht implementiert |
| **File-Router** | ❌ Fehlt | Noch nicht implementiert |
| **Control-Router** | ❌ Fehlt | Noch nicht implementiert |
| **Path-Traversal-Schutz** | ❌ Fehlt | Noch nicht implementiert |
| **Start/Stop-Funktionen** | ❌ Fehlt | Noch nicht implementiert |

---

## 4. Phasenplan

---

### Phase 1 — Solide Basisfunktionalität

> **Ziel:** Ein funktionierender HTTP-Server, der im Browser unter `http://localhost/` Dateien aus einem wwwroot-Verzeichnis ausliefert.

#### 1.1 — `system.precheck.ps1` vervollständigen

- [ ] PowerShell-Version prüfen (Minimum: 5.1)
- [ ] Verfügbarkeit von `System.Net.HttpListener` sicherstellen
- [ ] Betriebssystem prüfen (Windows-Kompatibilität)
- [ ] Bei Fehler: klare Fehlermeldung ausgeben und Modulload abbrechen

#### 1.2 — Private Hilfsfunktionen ergänzen

- [ ] `private/WriteLog.ps1` erstellen
  - Thread-sichere Logging-Funktion (für Runspace-Kontext geeignet)
  - Schreiben in `include/httpserver.log` (falls `UseLogging = 1`)
  - Format: `[YYYY-MM-DD HH:mm:ss] [LEVEL] Message`
- [ ] `private/ResolvePath.ps1` erstellen
  - Sicheres Auflösen von Request-Pfaden gegen wwwroot
  - **Path-Traversal-Schutz** (Block `../`, absolute Pfade, encoded sequences)

#### 1.3 — Kern-Implementierung: HTTP-Listener

- [ ] `private/HttpListenerCore.ps1` erstellen
  - `System.Net.HttpListener` initialisieren
  - Binding ausschließlich auf `http://localhost:<port>/`
  - `GetContextAsync()` in einer `while`-Schleife verwenden (non-blocking)
  - Fehlerbehandlung: Listener-Stop bei Exception, Cleanup

#### 1.4 — Request-Handler

- [ ] `private/HandleRequest.ps1` erstellen
  - HTTP-Methoden einschränken: nur `GET` und `HEAD` erlaubt
  - URL-Dekodierung und Normalisierung des Request-Pfads
  - Weiterleitung an File-Router oder Control-Router (anhand URL-Prefix)
  - Standard-Response-Header setzen (`X-Content-Type-Options`, `X-Frame-Options`, `Cache-Control` etc.)

#### 1.5 — File-Router

- [ ] `private/ServeFile.ps1` erstellen
  - Auflösung des Request-Pfads gegen `$httpHost.wwwroot`
  - Fallback: `index.html` bei Verzeichnis-Request (`/` → `index.html`)
  - SPA-Fallback: falls Datei nicht gefunden → `index.html` zurückgeben (für clientseitiges Routing)
  - MIME-Type via `GetMimeType` ermitteln und im `Content-Type`-Header setzen
  - 404-Response bei fehlendem SPA-Fallback
  - 304 Not Modified (ETag / Last-Modified) — optional in Phase 1, Pflicht ab Phase 3

#### 1.6 — Öffentliche Start/Stop-Funktionen

- [ ] `public/Start-HttpServer.ps1` erstellen
  - Validierung der Konfiguration (`$Script:Config` und `$httpHost`)
  - wwwroot-Pfad prüfen (existiert, ist lesbar)
  - HTTP-Listener starten
  - Port-Konflikt erkennen und sinnvolle Fehlermeldung ausgeben
- [ ] `public/Stop-HttpServer.ps1` erstellen
  - Listener sauber stoppen und alle Ressourcen freigeben
- [ ] Exports in `local.httpserver.psd1` nachpflegen

#### 1.7 — `local.httpserver.ps1` Schritt 3 vervollständigen

- [ ] `Start-HttpServer` nach `SetCoreConfig` aufrufen
- [ ] Grundlegenden Startablauf testen

#### ✅ Abnahmekriterium Phase 1

> Browser öffnen → `http://localhost:8080/` eingeben → HTML-Datei aus `wwwroot` wird korrekt angezeigt. CSS, JS und Assets werden mit korrekten MIME-Types ausgeliefert.

---

### Phase 2 — Steuerung & Kommunikation

> **Ziel:** Den laufenden Server über definierte Control-Routen steuern und seinen Status abfragen können.

#### 2.1 — Control-Router implementieren

- [ ] `private/HandleControlRoute.ps1` erstellen
  - Routen aus `$httpRouter` auswerten
  - Endpunkte implementieren:
    - `GET /sys/ctrl/http-heartbeat` → JSON `{status: "alive", uptime: ..., ...}`
    - `GET /sys/ctrl/http-getstatus` → JSON mit aktuellem Server-Status, wwwroot, Port, etc.
    - `POST /sys/ctrl/http-shutdown` → Server geordnet herunterfahren
    - `POST /sys/ctrl/http-reboot` → Server neu starten
    - `GET /sys/ctrl/gethelp` → Hilfetext (JSON oder HTML)
    - `GET /sys/ctrl/gohome` → Redirect zu `/`
  - Control-Routen absichern (Token, Secret oder localhost-only Check)

#### 2.2 — Mutex / Steuerdatei als Alternative

- [ ] Konzept für Mutex-basierte Kommunikation ausarbeiten
  - Named Mutex als Signal für Stop/Restart
  - Status-Datei (`httpserver.status.json`) im `include`-Verzeichnis
  - Heartbeat-Funktion schreibt regelmäßig in Status-Datei

#### 2.3 — `ExportServerLog.ps1` vervollständigen

- [ ] Logfile aus `include/httpserver.log` in angegebenes Zielverzeichnis exportieren
- [ ] Optionaler Timestamp im Dateinamen

#### ✅ Abnahmekriterium Phase 2

> `Invoke-RestMethod http://localhost:8080/sys/ctrl/http-heartbeat` gibt ein valides JSON-Objekt mit Server-Status zurück. `http-shutdown` stoppt den Server sauber.

---

### Phase 3 — Sicherheit & Härtung

> **Ziel:** Den Server gegen gängige Angriffsvektoren absichern.

#### 3.1 — Path-Traversal-Schutz (vertiefen)

- [ ] URL-Encoding angriffe abfangen (`%2e%2e%2f`, `..%2F`, etc.)
- [ ] Symbolische Links / Junction Points aus wwwroot ausschließen
- [ ] Canonical Path Validation: aufgelöster Pfad muss innerhalb von wwwroot liegen

#### 3.2 — HTTP-Methoden-Restriktion

- [ ] Whitelist für erlaubte Methoden pro Route-Typ (`GET`, `HEAD` für Files; `GET`/`POST` für Control)
- [ ] `405 Method Not Allowed` mit korrektem `Allow`-Header zurückgeben

#### 3.3 — Response-Header absichern

- [ ] `X-Content-Type-Options: nosniff`
- [ ] `X-Frame-Options: SAMEORIGIN`
- [ ] `Content-Security-Policy` (konfigurierbar)
- [ ] `Referrer-Policy: strict-origin-when-cross-origin`
- [ ] `Cache-Control` für statische Assets vs. HTML differenzieren

#### 3.4 — Control-Endpoint-Absicherung

- [ ] Optional: Secret-Token im Request-Header (`X-Local-HS-Token`)
- [ ] Token wird beim Serverstart generiert und in Status-Datei geschrieben
- [ ] Localhost-Only-Validierung der Remote-Adresse für Control-Routen

#### 3.5 — Rate-Limiting (einfach)

- [ ] Maximale Requests pro Sekunde (konfigurierbarer Threshold)
- [ ] Bei Überschreitung: `429 Too Many Requests`

#### ✅ Abnahmekriterium Phase 3

> Path-Traversal-Versuche werden mit `403 Forbidden` abgewiesen. Alle Security-Header sind in den Responses vorhanden. Nicht erlaubte Methoden geben `405` zurück.

---

### Phase 4 — Hintergrundmodus & Runspaces

> **Ziel:** Den HTTP-Server vollständig in einem Runspace auslagern, sodass er non-blocking und unsichtbar im Hintergrund läuft.

#### 4.1 — Runspace-Architektur

- [ ] `private/RunspaceManager.ps1` erstellen
  - `[runspacefactory]::CreateRunspace()` mit minimalem `InitialSessionState`
  - Notwendige Variablen und Funktionen in den Runspace-Scope übergeben
  - `PowerShell`-Instanz im Runspace starten (`BeginInvoke`)
  - Handle (`AsyncResult`) für späteres Cleanup speichern

#### 4.2 — Konsole verstecken (`hidden`-Modus)

- [ ] Bei `Mode = 'hidden'`: Konsolenfenster via `[Console.Window]` / P/Invoke ausblenden
  - `ShowWindow(GetConsoleWindow(), SW_HIDE)` über `Add-Type` mit P/Invoke
- [ ] Bei `Mode = 'console'`: Fenster sichtbar lassen (Standard-Verhalten)

#### 4.3 — Thread-Sicherheit

- [ ] Shared State (Log-Buffer, Status-Objekt) über `[System.Collections.Concurrent.ConcurrentQueue]` absichern
- [ ] Runspace-zu-Main-Thread-Kommunikation via `[System.Collections.Concurrent.ConcurrentDictionary]` für Status-Daten

#### 4.4 — Graceful Shutdown

- [ ] Stop-Signal über Shared-Variable (`[System.Threading.CancellationTokenSource]`) an Runspace senden
- [ ] Runspace wartet auf alle aktiven Requests, bevor er terminiert
- [ ] Listener wird sauber geschlossen, Runspace disposed

#### ✅ Abnahmekriterium Phase 4

> `Start-HttpServer` kehrt sofort zurück. Kein Konsolenfenster sichtbar (bei `hidden`). Server beantwortet Requests aus dem Runspace heraus. `Stop-HttpServer` wartet auf sauberen Shutdown.

---

### Phase 5 — Named Pipes / IPC

> **Ziel:** Kommunikation mit dem laufenden Server-Runspace über Named Pipes ermöglichen.

#### 5.1 — Named Pipe Server (im Runspace)

- [ ] `private/PipeServer.ps1` erstellen
  - `[System.IO.Pipes.NamedPipeServerStream]` im Runspace als parallelen Listener
  - Pipe-Name: konfigurierbar (Default: `local.httpserver.<pid>`)
  - Protokoll: JSON-basierte Kommandos (`{"cmd": "status"}`, `{"cmd": "stop"}` etc.)

#### 5.2 — Named Pipe Client (öffentliche Funktion)

- [ ] `public/Send-ServerCommand.ps1` erstellen
  - `[System.IO.Pipes.NamedPipeClientStream]` zum Senden von Kommandos
  - Antwort lesen und als `OPSreturn`-Objekt zurückgeben

#### 5.3 — IPC-Aktivierung

- [ ] Pipe-Server nur starten, wenn `$Script:Config.UseIPC = $true`
- [ ] Pipe-Name in Status-Datei/Heartbeat-Response veröffentlichen

#### ✅ Abnahmekriterium Phase 5

> `Send-ServerCommand -Command status` gibt den aktuellen Server-Status zurück, ohne HTTP-Request. `Send-ServerCommand -Command stop` fährt den Server sauber herunter.

---

### Phase 6 — UI-Modi & UX

> **Ziel:** Die verschiedenen in `SetCoreConfig` definierten UI-Modi implementieren.

#### 6.1 — `console`-Modus (Standard)

- [ ] Strukturierte Konsolenausgabe beim Start (Server-Info, Port, wwwroot-Pfad)
- [ ] Live-Request-Log in der Konsole (optional via `UseLogging`)

#### 6.2 — `systray`-Modus

- [ ] System-Tray-Icon via `[System.Windows.Forms.NotifyIcon]`
- [ ] Kontextmenü: Status, Restart, Stop
- [ ] Balloon-Tooltip beim Start

#### 6.3 — `desktop`-Modus (WPF)

- [ ] WPF-Fenster via XAML (analog PowerEdge-Pattern)
- [ ] Anzeige: Status, uptime, Request-Log, Config
- [ ] Steuerbuttons: Start, Stop, Restart

#### 6.4 — `hidden`-Modus (Phase 4 bereits erledigt)

- [ ] Nur Runspace, keine UI — vollständiger Hintergrundbetrieb

#### ✅ Abnahmekriterium Phase 6

> Alle vier Modi starten ohne Fehler. `systray` zeigt Icon in der Taskleiste. `desktop` zeigt WPF-Fenster mit Live-Daten.

---

### Phase 7 — Polish, Tests & Dokumentation

> **Ziel:** Modul release-ready machen.

#### 7.1 — Pester-Tests

- [ ] `tests/`-Verzeichnis anlegen
- [ ] Unit-Tests für `GetMimeType`, `OPSreturn`, `ResolvePath`
- [ ] Integrations-Test: Server starten → Request senden → Response validieren
- [ ] Security-Test: Path-Traversal-Versuche → erwarte `403`

#### 7.2 — Dokumentation

- [ ] `README.md` vollständig ausschreiben (Installation, Usage, Konfigurationsreferenz)
- [ ] `CHANGELOG.md` mit Versionshistorie befüllen
- [ ] Comment-Based-Help für alle öffentlichen Funktionen vervollständigen
- [ ] `docs/`-Verzeichnis mit ausführlicher API-Referenz

#### 7.3 — `module.config` Konsolidierung

- [ ] Prüfen ob `config.httphost.json` / `config.server.json` / `config.mime.json` noch benötigt werden oder entfernt werden können (aktuell durch `module.config` ersetzt)
- [ ] `module.config` um Versionscheck erweitern (Modul-Version vs. Config-Version)

#### 7.4 — PowerShell Gallery Vorbereitung

- [ ] `psd1` auf Vollständigkeit prüfen
- [ ] `FileList` in `psd1` auf neue Dateien aktualisieren
- [ ] Tags und Metadaten finalisieren

#### ✅ Abnahmekriterium Phase 7

> Alle Pester-Tests grün. README deckt alle Use-Cases ab. Modul kann mit `Install-Module` oder manuellem Copy-Deploy ohne weitere Schritte genutzt werden.

---

## 5. Fortschrittsübersicht

| Phase | Titel | Status | Fortschritt |
|:---:|---|:---:|:---:|
| 1 | Solide Basisfunktionalität | 🔄 In Arbeit | 20% |
| 2 | Steuerung & Kommunikation | ⏳ Ausstehend | 0% |
| 3 | Sicherheit & Härtung | ⏳ Ausstehend | 0% |
| 4 | Hintergrundmodus & Runspaces | ⏳ Ausstehend | 0% |
| 5 | Named Pipes / IPC | ⏳ Ausstehend | 0% |
| 6 | UI-Modi & UX | ⏳ Ausstehend | 0% |
| 7 | Polish, Tests & Dokumentation | ⏳ Ausstehend | 0% |

**Legende:** ✅ Abgeschlossen · 🔄 In Arbeit · ⏳ Ausstehend · 🚫 Blockiert

---

## 6. Dateistruktur-Zielzustand

Die folgende Struktur zeigt den angestrebten finalen Zustand des Moduls nach Abschluss aller Phasen:

```
local.httpserver/
│
├── local.httpserver.ps1           ← Einstiegspunkt (3-Step-Pattern)
├── local.httpserver.psm1          ← Root-Modul (Bootstrap + Config)
├── local.httpserver.psd1          ← Modul-Manifest
├── PROJECTPLAN.md                 ← Diese Datei
├── README.md                      ← Nutzerdokumentation
├── CHANGELOG.md                   ← Versionshistorie
├── LICENSE                        ← Lizenzinformation
├── NOTICE                         ← Copyright-Hinweise
│
├── include/
│   ├── module.config              ← Dot-Sourced Config-Datei
│   ├── system.precheck.ps1        ← Precheck (ScriptsToProcess)
│   ├── httpserver.log             ← Laufzeit-Log (wird generiert)
│   └── httpserver.status.json     ← Laufzeit-Status (wird generiert)
│
├── private/
│   ├── OPSreturn.ps1              ← Return-Objekt Helper
│   ├── ReadJSON.ps1               ← JSON-Reader
│   ├── WriteLog.ps1               ← Thread-sicheres Logging      [Phase 1]
│   ├── ResolvePath.ps1            ← Path-Traversal-sicherer Resolver [Phase 1+3]
│   ├── HttpListenerCore.ps1       ← HttpListener-Kern             [Phase 1]
│   ├── HandleRequest.ps1          ← Request-Dispatcher            [Phase 1]
│   ├── ServeFile.ps1              ← File-Router                   [Phase 1]
│   ├── HandleControlRoute.ps1     ← Control-Router                [Phase 2]
│   ├── RunspaceManager.ps1        ← Runspace-Wrapper              [Phase 4]
│   └── PipeServer.ps1             ← Named Pipe Server             [Phase 5]
│
├── public/
│   ├── GetMimeType.ps1            ← MIME-Type-Lookup
│   ├── ExportServerLog.ps1        ← Log-Export
│   ├── Start-HttpServer.ps1       ← Server starten                [Phase 1]
│   ├── Stop-HttpServer.ps1        ← Server stoppen                [Phase 1]
│   └── Send-ServerCommand.ps1     ← IPC Pipe-Client               [Phase 5]
│
└── tests/
    ├── GetMimeType.Tests.ps1      ← Unit-Test MIME                [Phase 7]
    ├── ResolvePath.Tests.ps1      ← Unit-Test Path-Resolver       [Phase 7]
    └── Integration.Tests.ps1      ← Integrations-Tests            [Phase 7]
```

---

## 7. Konventionen & Hinweise

### Coding-Konventionen

- **Return-Werte:** Alle privaten und öffentlichen Funktionen verwenden `OPSreturn` für konsistente Rückgabeobjekte (`{code, msg, data}`).
- **Fehlerbehandlung:** `try/catch`-Blöcke in allen I/O-Operationen. Fehler nie still schlucken — immer via `OPSreturn -Code -1` zurückmelden.
- **Scope:** Modul-weite Variablen ausschließlich als `$Script:Variable`. Kein Gebrauch von `$Global:`.
- **Exports:** Ausschließlich über `FunctionsToExport` in `local.httpserver.psd1` steuern. Kein `Export-ModuleMember` in `.psm1`.
- **Kommentare:** Comment-Based-Help (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`, `.NOTES`) für alle öffentlichen Funktionen verpflichtend.

### Sicherheitshinweise

- Der HTTP-Listener bindet **ausschließlich** auf `http://localhost:<port>/` — niemals auf `0.0.0.0` oder externe Interfaces.
- Control-Routen sind unter dem Prefix `/sys/ctrl/` zusammengefasst und müssen gesondert abgesichert werden.
- Jeder Request-Pfad wird durch `ResolvePath` gegen wwwroot kanonisiert — kein direktes String-Concatenation für Dateipfade.

### Versionierung

- Dieses Dokument wird parallel zur Entwicklung gepflegt.
- Bei Abschluss einer Phase: Fortschrittsübersicht aktualisieren, `CHANGELOG.md` befüllen, `psd1`-Version erhöhen.
- Format: `MAJOR.MINOR.PATCH` — Breaking Changes erhöhen MAJOR, neue Features MINOR, Bugfixes PATCH.

---

*Projektplan erstellt am 17.04.2026 — local.httpserver v1.00.00*
