# Linux System Monitoring Tool

A modular, local Linux command-line monitor written in GNU Bash. It collects CPU, RAM, filesystem and process information, evaluates configurable thresholds, prints a report, and appends reports/events to local files.

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
Linux Mint 22.3 or compatible Linux; GNU Bash; `awk`, `df`, `head`, `hostname`, `ps`, `sleep`, `uname`, `uptime`; mounted `/proc`.

## Install
Extract the ZIP under `~/Projects`, then:
```bash
cd ~/Projects/linux-system-monitor
chmod +x monitor.sh tests/test_modules.sh
```

## Run
```bash
./monitor.sh
./monitor.sh --help
./monitor.sh --interval 2 --top 3
./monitor.sh --mount /home
./monitor.sh --continuous
```
`--interval` is the CPU sampling window (1–60 seconds). Continuous mode waits `MONITOR_INTERVAL` seconds between cycles. Stop with Ctrl+C.

## Configuration
Edit `config/monitor.conf`:
```ini
CPU_THRESHOLD=80
RAM_THRESHOLD=85
DISK_THRESHOLD=90
MONITOR_INTERVAL=5
TOP_PROCESS_COUNT=5
```
Thresholds accept integers 0–100; continuous interval 1–3600 seconds; process count 1–20. Config is parsed as data, never sourced as executable shell code.

## Output
- `logs/monitor.log`: timestamped warnings and cycle events.
- `reports/system-report-YYYY-MM-DD.log`: reports appended by date.

The application creates these directories on first run. Run as your normal user, not with `sudo` by default. Review/rotate logs periodically.

## Test
```bash
./tests/test_modules.sh
./monitor.sh --interval 1 --top 3
```
Compare with `free -h`, `df -h /`, and `ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head`.

## Metric notes
CPU usage uses the change between two aggregate `/proc/stat` samples; idle includes idle and iowait. RAM used is `MemTotal - MemAvailable`, not `MemTotal - MemFree`. `df -Pk` supplies stable numeric filesystem fields. Per-process `%CPU` from `ps` has a different measurement basis from interval system CPU usage.

## Security and limitations
The application reads system metrics and writes its own reports/logs. It does not modify system settings or running processes. Do not publish reports containing sensitive host or process details. This beginner utility is not a production observability platform.

## Future enhancements
CSV export, hardware temperatures, network metrics, cron/systemd scheduling, remote monitoring and a GUI are future work, not v1.0.
