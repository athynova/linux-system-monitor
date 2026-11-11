# System Design

## Components
| Module | Responsibility | Data source |
|---|---|---|
| Main controller | CLI, config, orchestration | `monitor.sh` |
| System information | Host, OS, kernel, uptime, timestamp | `hostname`, `/etc/os-release`, `uname`, `uptime`, `date` |
| CPU | Two-sample busy percentage | `/proc/stat` |
| Memory | Total/used/available and percentage | `/proc/meminfo` |
| Disk | Selected filesystem capacity and percentage | `df -Pk` |
| Processes | Top N CPU and memory processes | `ps` |
| Alert manager | Threshold comparison and warning events | `logs/monitor.log` |
| Report manager | Append report by date | `reports/system-report-YYYY-MM-DD.log` |
| History manager (v1.1) | Append one CSV row per cycle, trim, display | `data/history.csv` |

## Workflow
```mermaid
flowchart TD
 A[Start] --> B[Parse options]
 B --> C[Read and validate config]
 C --> D[Load modules]
 D --> E[Sample CPU twice]
 E --> F[Collect RAM, disk, processes]
 F --> G[Evaluate thresholds]
 G --> G2[Append history row to data/history.csv]
 G2 --> H[Build and display report]
 H --> I[Append report and event log]
 I --> J{Continuous?}
 J -- Yes --> K[Sleep configured interval]
 K --> E
 J -- No --> L[Exit]
 SIG[SIGINT / SIGTERM] -.-> M[Set stop flag]
 M -.-> N[Log stop, exit 130/143]
```

## Design decisions
1. CPU is measured across an interval, not from a single instantaneous sample.
2. RAM used is `MemTotal - MemAvailable`.
3. `df -Pk` is parsed for stable numeric filesystem data.
4. Configuration is parsed as key/value data and never executed.
5. Thresholds and CLI values are validated.
6. No unnecessary root privileges are required.
7. The program never kills processes or modifies system settings.
8. Reports and events append rather than overwrite.

### Added in v1.1
9. History uses plain CSV: no database or extra dependency, readable by any spreadsheet or script, and a stable base for later analytics and a terminal dashboard.
10. History is written before the report is built, so a report failure cannot lose a sample; a history failure only warns and never stops monitoring.
11. Concurrent writers are serialized with `flock`; size is bounded by `HISTORY_MAX_ROWS` using an atomic temp-file rename.
12. Signals set a flag instead of exiting mid-write; the main loop stops at a safe point (graceful shutdown, exit 130/143).
13. Arguments are parsed before the configuration is loaded, so `--help` and `--version` never depend on config validity.

## Boundaries
Local Linux host only; no GUI, remote agents, cloud ingestion, network traffic analysis, notifications or predictive analytics in v1.1.
