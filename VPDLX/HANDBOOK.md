# VPDLX Handbook

**Virtual PowerShell Data-Logger eXtension &mdash; Operational Guide**

This handbook provides in-depth operational guidance, best practices, and advanced usage scenarios for the **VPDLX** module. While the `README.md` serves as a technical reference, this document focuses on how to effectively integrate VPDLX into your automation workflows.

---

## 1. Core Concepts

### Virtual In-Memory Logging
VPDLX operates on the principle of **RAM-first logging**. Each log entry is stored in a private `List[string]` inside a `[Logfile]` instance. This has several implications:
- **Zero I/O overhead:** Writing a log entry is nearly instantaneous.
- **Volatility:** Logs are lost when the PowerShell session ends unless explicitly exported.
- **Isolation:** Each log file is a separate object with its own metadata and storage.

### Standardised Returns
Except for existence checks, all VPDLX functions return a `VPDLXreturn` object. Always follow this pattern for robust scripts:
```powershell
$res = VPDLXnewlogfile -Logfile 'MyLog'
if ($res.code -ne 0) {
    throw "Failed to create log: $($res.msg)"
}
$logName = $res.data
```

---

## 2. Advanced Features (v1.02.06)

### Minimum Log Level Filtering
You can now control log verbosity at the instance level. This is ideal for production scripts where you only want to record critical events but keep the same code that also emits debug info.

**Severity Order:**
`trace(0)` < `debug(1)` < `verbose(2)` < `info(3)` < `warning(4)` < `error(5)` < `critical(6)` < `fatal(7)`

**Usage:**
```powershell
# Only record Warning, Error, Critical, and Fatal
$log = [Logfile]::new('ProdLog', 'warning')

$log.Info("Starting...")   # Silently ignored
$log.Error("Failed!")      # Recorded
```

### Modern Export Formats
VPDLX v1.02.06 introduced two powerful new formats for external integration:

#### HTML (Visual Reports)
Generates a standalone, styled report. Perfect for sending via email or as a build artifact.
- **Feature:** Level-specific row colouring.
- **Feature:** Fully XSS safe (all content is HTML-encoded).

#### NDJSON (Log Pipelines)
The standard format for log aggregators (ELK, Loki, AWS).
- **Format:** One compact JSON object per line.
- **Tip:** Use the `-NoBOM` switch when exporting for Linux-based log collectors.

---

## 3. Best Practices

### The "Export-on-Exit" Pattern
Since logs are in-memory, you should always ensure they are exported if a script fails or finishes.
```powershell
try {
    VPDLXnewlogfile -Logfile 'TaskLog'
    # ... your logic ...
}
finally {
    # Ensure logs are saved even on failure
    VPDLXexportlogfile -Logfile 'TaskLog' -LogPath 'C:\Logs' -ExportAs 'json' -Override
    VPDLXdroplogfile -Logfile 'TaskLog'
}
```

### Large Log Management
While VPDLX is fast, extremely large logs (100k+ entries) will consume RAM.
- **Message Length:** Use `[Logfile]::MaxMessageLength` to prevent accidental memory flooding.
- **Rotation:** Use `VPDLXresetlogfile` to clear entries periodically after an export.

---

## 4. Troubleshooting

| Symptom | Cause | Solution |
|---|---|---|
| `TypeNotFound: [Logfile]` | Module not imported | Run `Import-Module VPDLX` |
| `ObjectDisposedException` | Log was destroyed | Do not call methods on a log after `VPDLXdroplogfile` |
| Export fails on Unix | UTF-8 BOM issue | Use the `-NoBOM` switch in `VPDLXexportlogfile` |
| Entries missing | Min-Level filter | Check `$log.GetMinLogLevel()` to see if a filter is active |

---

<div align="center">
  <sub>VPDLX Handbook &bull; Version 1.02.06 &bull; 17.04.2026</sub>
</div>
