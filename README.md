# Linux System Monitoring Tool

A modular, local Linux command-line monitor written in GNU Bash. It collects CPU, RAM, filesystem and process information, evaluates configurable thresholds, prints a report, records historical metrics to CSV, and appends reports/events to local files.

## Version 1.1 additions
- **Historical metrics:** CPU, RAM and disk utilization recorded once per cycle in `data/history.csv`.
- **CSV storage:** structured, spreadsheet-friendly rows with ISO 8601 timestamps; size bounded by `HISTORY_MAX_ROWS`.
- **Graceful shutdown:** Ctrl+C and `kill` stop the monitor cleanly, log the stop, and leave no half-written data.
- **Configuration validation:** whitespace, CRLF line endings, comments, duplicate/unknown keys and out-of-range values are handled with line-numbered errors; `--help` works even with a broken config.
- **Bug fixes:** process tables stay aligned for command names containing spaces (e.g. `Web Content`); the monitor's own `ps` process no longer appears at the top of the CPU list; Ctrl+C never produces a partial report or a spurious error (v1.1.1).
- **Testing:** five automated suites plus `tests/run_all.sh`.

## Version 1.0 scope
- CPU utilization sampled over an interval using `/proc/stat`.
- RAM total, used and available from `/proc/meminfo` (`MemAvailable`).
- Filesystem usage for a selected path using `df -Pk`.
- Top CPU and memory processes using `ps`.
- Configurable CPU/RAM/disk thresholds and warnings.
- Timestamped event log and daily append-only reports.
- One-shot and continuous monitoring.
- Input validation and error handling.

Local host only. No GUI, remote/cloud monitoring, email/SMS, network traffic inspection, process termination, automatic remediation or ML prediction.

## Requirements
Linux Mint 22.3 or compatible Linux; GNU Bash; `awk`, `date` (GNU), `df`, `flock`, `head`, `hostname`, `ps`, `sleep`, `tail`, `uname`, `uptime`, `wc`; mounted `/proc`. All are standard on Linux Mint.

## Install
Extract the ZIP under `~/Projects`, then:
```bash
cd ~/Projects/linux-system-monitor
chmod +x monitor.sh tests/*.sh
```

## Run
```bash
./monitor.sh
./monitor.sh --help
./monitor.sh --interval 2 --top 3
./monitor.sh --mount /home
./monitor.sh --continuous
./monitor.sh --show-history 20
./monitor.sh --version
```
`--interval` is the CPU sampling window (1–60 seconds). Continuous mode waits `MONITOR_INTERVAL` seconds between cycles. Stop with Ctrl+C (see *Graceful shutdown*). `--show-history N` prints the last N recorded rows (1-1000).

## Configuration
Edit `config/monitor.conf`:
```ini
CPU_THRESHOLD=80
RAM_THRESHOLD=85
DISK_THRESHOLD=90
MONITOR_INTERVAL=5
TOP_PROCESS_COUNT=5
HISTORY_ENABLED=true
HISTORY_MAX_ROWS=100000
```
Thresholds accept integers 0–100; continuous interval 1–3600 seconds; process count 1–20; `HISTORY_ENABLED` is `true` or `false`; `HISTORY_MAX_ROWS` is 100–1000000. Spaces around `=`, a trailing `# comment`, blank lines and Windows line endings are accepted. Unknown or duplicated settings and invalid values stop the program with an error naming the problem. Config is parsed as data, never sourced as executable shell code.

## Output
- `logs/monitor.log`: timestamped warnings and cycle events.
- `reports/system-report-YYYY-MM-DD.log`: reports appended by date.
- `data/history.csv`: one row per cycle (see below).

The application creates these directories on first run. Run as your normal user, not with `sudo` by default. Review/rotate logs periodically.

## Historical data
Every monitoring cycle appends one row to `data/history.csv` (mode 600):

```csv
timestamp,cpu_percent,ram_percent,disk_percent,mount,status
2026-11-11T08:15:02+03:00,12.40,41.87,38,/,NORMAL
2026-11-11T08:15:09+03:00,83.10,42.02,38,/,WARNING
```
- `status` is `NORMAL` or `WARNING` (any threshold reached in that cycle); `mount` is the path given to `--mount`.
- The file opens directly in LibreOffice Calc, Excel, `column -s, -t`, pandas, etc.
- Writes are serialized with `flock`, so several monitors can share one file safely.
- When the file exceeds `HISTORY_MAX_ROWS` by 10 %, the oldest rows are dropped. Set `HISTORY_ENABLED=false` to turn recording off.
- A history failure (for example a full disk) prints a warning and is logged, but never stops monitoring.
- If the file has an unexpected header it is renamed to `history-<date>.old` and a fresh file is started.
- `data/` contents are gitignored; back up or export the CSV yourself if you need it kept.

## Graceful shutdown
`Ctrl+C` (SIGINT) and `kill <pid>` (SIGTERM) stop the monitor cleanly: the program reports how many cycles completed, writes a "Monitor stopped" line to `logs/monitor.log`, and exits with status 130 (INT) or 143 (TERM). Reports are written only when complete and history trimming uses an atomic rename, so an interruption never leaves a half-written file. Ctrl+C during CPU sampling discards the cycle. Ctrl+C after sampling has finished but before the report is complete discards the report, but the history row for that cycle (a valid measurement) may already be recorded. A `kill` (SIGTERM) lets the running cycle finish first.

## Test
```bash
./tests/run_all.sh                 # all suites, about 30-60 seconds
./tests/test_config.sh             # or run one suite at a time
./monitor.sh --interval 1 --top 3
```
The tests run against a temporary copy of the program, so they never touch your real `logs/`, `reports/`, `data/` or `config/`.
Compare with `free -h`, `df -h /`, and `ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head`.

## Metric notes
CPU usage uses the change between two aggregate `/proc/stat` samples; idle includes idle and iowait. RAM used is `MemTotal - MemAvailable`, not `MemTotal - MemFree`. `df -Pk` supplies stable numeric filesystem fields. Per-process `%CPU` from `ps` has a different measurement basis from interval system CPU usage.

## Security and limitations
The application reads system metrics and writes its own reports/logs. It does not modify system settings or running processes. Do not publish reports containing sensitive host or process details. This beginner utility is not a production observability platform.

## Future enhancements
Analytics over the history (averages, peaks, trends), a terminal dashboard, hardware temperatures, network metrics, cron/systemd scheduling, remote monitoring and a GUI are future work, not v1.1.
