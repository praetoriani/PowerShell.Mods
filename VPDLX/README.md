# VPDLX &mdash; Virtual PowerShell Data-Logger eXtension

<div align="center">
  <img src="VPDLX.Logo.v1.svg" alt="VPDLX Logo" width="480" />
</div>

<br />

<div align="center">

![Version](https://img.shields.io/badge/Version-1.02.06-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-orange)

</div>

**VPDLX** is a fully class-based, **in-memory** virtual logging system for PowerShell. Instead of writing log entries to disk immediately, VPDLX keeps any number of named log instances alive in RAM for the duration of the current PowerShell session &mdash; enabling fast, structured, and flexible logging without immediate file-system I/O.

When you are ready to persist a log, the built-in export function writes it to disk with a single command &mdash; in your choice of **6 output formats**.

#### Key Features

| Feature | Details |
|---|---|
| Architecture | Fully class-based OOP (`[Logfile]`, `[FileDetails]`, `[FileStorage]`) |
| Log storage | 100% in-memory &mdash; no disk I/O during runtime |
| Public API | 9 wrapper functions with consistent return objects |
| Export formats | `txt` &bull; `log` &bull; `csv` &bull; `json` &bull; `html` &bull; `ndjson` |
| Minimum log level | Per-instance severity filter (new in v1.02.06) |
| Log levels | `trace` `debug` `verbose` `info` `warning` `error` `critical` `fatal` |
| BOM control | `-NoBOM` switch for Unix-compatible UTF-8 output |
| Requirements | PowerShell 5.1+ &bull; Windows 10/11 &bull; No admin rights needed |

#### Quick Start

```powershell
# Import the module
Import-Module .\VPDLX\VPDLX.psd1

# Create a new in-memory log file
$r = VPDLXnewlogfile -Logfile 'AppLog'

# Write entries
VPDLXwritelogfile -Logfile 'AppLog' -Level 'info'    -Message 'Service started.'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'warning' -Message 'Retry count is 0.'
VPDLXwritelogfile -Logfile 'AppLog' -Level 'error'   -Message 'Connection attempt failed.'

# Export to disk as HTML (opens in browser)
$r = VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'html'
if ($r.code -eq 0) { Start-Process $r.data }

# Export as NDJSON for log pipelines (BOM-free)
VPDLXexportlogfile -Logfile 'AppLog' -LogPath 'C:\Logs' -ExportAs 'ndjson' -NoBOM

# Remove the log from memory when done
VPDLXdroplogfile -Logfile 'AppLog'
```

#### Public Wrapper Functions

| Function | Description |
|---|---|
| `VPDLXnewlogfile` | Creates a new named virtual log file |
| `VPDLXislogfile` | Checks whether a named log file exists (returns `[bool]`) |
| `VPDLXdroplogfile` | Permanently removes a log file from memory |
| `VPDLXreadlogfile` | Reads a single entry by 1-based line index |
| `VPDLXwritelogfile` | Appends a formatted entry to a log file |
| `VPDLXexportlogfile` | Exports a log file to disk in the chosen format |
| `VPDLXgetalllogfiles` | Lists all active log files with their metadata |
| `VPDLXresetlogfile` | Clears all entries without destroying the log file |
| `VPDLXfilterlogfile` | Returns entries filtered by log level |

#### Entry Format

Every log entry follows this fixed format:

```
[dd.MM.yyyy | HH:mm:ss] [LEVEL] -> MESSAGE
```

Example:

```
[17.04.2026 | 10:00:01] [INFO]    -> Service started.
[17.04.2026 | 10:00:02] [WARNING] -> Disk usage at 81 percent.
[17.04.2026 | 10:00:03] [ERROR]   -> Database connection failed.
```

#### Version History

| Version | Date | Summary |
|---|---|---|
| 1.02.06 | 17.04.2026 | HTML + NDJSON export formats, minimum log level filter |
| 1.02.05 | 11.04.2026 | `VPDLXgetalllogfiles`, `VPDLXresetlogfile`, `VPDLXfilterlogfile`, core stats |
| 1.02.04 | 11.04.2026 | Precheck script, `MaxMessageLength`, `-NoBOM` switch |
| 1.02.03 | 11.04.2026 | 10 critical bugfixes (priorities 1&ndash;8) |
| 1.01.02 | 06.04.2026 | Public wrapper layer + export functions |
| 1.01.01 | 06.04.2026 | Bugfix: TypeAccelerator registration |
| 1.01.00 | 06.04.2026 | Full OOP rewrite (breaking change) |
| 1.00.00 | 05.04.2026 | Initial release |

#### Documentation & Download

- **[Full Documentation (VPDLX/README.md)](./VPDLX/README.md)** &mdash; Complete API reference, class documentation, and examples
- **[Changelog (VPDLX/CHANGELOG.md)](./VPDLX/CHANGELOG.md)** &mdash; Detailed version history
- **[Releases](https://github.com/praetoriani/PowerShell.Mods/releases)** &mdash; Download the latest release ZIP

---

## Repository Structure

```
PowerShell.Mods/
├── VPDLX/                    # Virtual PowerShell Data-Logger eXtension
│   ├── Classes/              # PowerShell class definitions
│   ├── Private/              # Internal helper functions
│   ├── Public/               # Public wrapper functions (9 total)
│   ├── Examples/             # Demo scripts
│   ├── VPDLX.psm1            # Root module
│   ├── VPDLX.psd1            # Module manifest
│   ├── CHANGELOG.md          # Version history
│   └── README.md             # Full module documentation
└── .github/
    └── workflows/
        └── vpdlx-release.yml # GitHub Actions release workflow
```

---

## License

<br>

<b>__________________________________________________________________________________</b><br>

> [!NOTE]
> This project is licensed under the <u>**Apache License, Version 2.0**</u>
> You can find the 📜 LICENSE [**here**](https://github.com/praetoriani/PowerShell.Mods/blob/main/VPDLX/LICENSE) and the corresponding 📌 NOTICE [**here**](https://github.com/praetoriani/PowerShell.Mods/blob/main/VPDLX/NOTICE)


<b>‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾</b><br>

<br><br>

---

<div align="center">
  <sub>Maintained by <a href="https://github.com/praetoriani">praetoriani</a></sub>
</div>
