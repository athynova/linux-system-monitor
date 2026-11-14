# Test Plan and Results

Run `./tests/run_all.sh` (all five suites), then run `./monitor.sh --interval 1 --top 3` on the target Linux Mint machine.

| ID | Scenario | Expected result |
|---|---|---|
| UT-01 | Bash syntax | All scripts parse |
| UT-02 | Memory collection | Total/used/available/percentage returned |
| UT-03 | Root filesystem | Numeric disk metrics returned |
| UT-04 | Invalid mount | Error, exit 2 |
| UT-05 | Top CPU process list | At most requested number shown |
| UT-06 | Invalid process count | Error, exit 2 |
| UT-07 | Value above threshold | Warning emitted and logged |
| UT-08 | Value below threshold | No warning |
| UT-09 | Non-numeric metric | Rejected, exit 2 |
| INT-01 | `--help` | Usage printed |
| INT-02 | Unknown option | Rejected, exit 2 |
| INT-03 | Invalid CPU interval | Rejected, exit 2 |
| INT-04 | Full monitoring cycle | Report displayed and saved |
| INT-05 | Continuous mode | Repeated cycles until Ctrl+C |
| UT-10 | Process name containing a space | Columns stay aligned (v1.1) |
| UT-12 | Terminal helpers: size, UTF-8, colour switches, enter/leave, frame codes | `test_terminal.sh` |
| DSH-01..67 | Dashboard bars, sparklines, levels, sampling, disk/process panels, layout at every size, CLI options | `test_dashboard.sh` (fake `df`/`ps`) |
| KEY-01..32 | Key handling, refresh stepping, help, pause, EOF stdin | `test_controls.sh` |
| PTY-01..21 | Real pseudo-terminal: screen/cursor/echo restored, colours, exit codes 0/130/143, prompt Ctrl+C and resize, too-small window | `test_interactive.sh` |
| UT-11 | The monitor's own `ps` row | Excluded; `psql` and other names kept (v1.1.1) |
| CFG-01..23 | Config parsing: CRLF, BOM, spaces, comments, bad/duplicate/unknown keys, range limits, `--help` with broken config | Accepted or rejected with a clear message (`test_config.sh`) |
| HIS-01..30 | CSV header/rows, ISO timestamps, quoting, validation, trimming, `--show-history`, `HISTORY_ENABLED=false` | See `test_history.sh` |
| SHD-01..15 | SIGINT exit 130, SIGTERM exit 143, stop logged, CSV intact, prompt stop while sleeping | See `test_shutdown.sh` |
| EDG-01..15 | Foreign/empty/unterminated history file, 5 concurrent writers, unwritable data dir, CPU counter anomalies | See `test_edge_cases.sh` |

## Results record
Do not claim target-machine tests passed until you run them on Linux Mint 22.3 and record actual output here.

| Test group | Result |
|---|---|
| Automated test suites (`run_all.sh`) | v1.1.0: all 5 suites passed on Linux Mint 22.3 (11 Nov 2026). v1.1.1: 1 failure on Mint (`CPU process limit`, SIGPIPE on a busy process table), fixed in v1.1.2. v1.1.2: re-run pending |
| Manual: history CSV opens in a spreadsheet | Pending: open `data/history.csv` in LibreOffice Calc and confirm the 6 columns |
| Manual: Ctrl+C in continuous mode | Passed on Linux Mint 22.3; exit message and history correct. Found a spurious error when Ctrl+C lands during report assembly, fixed in v1.1.1 |
| Full integration run | Passed on Linux Mint 22.3: report displayed and saved, history row recorded |
| Continuous mode | Passed on Linux Mint 22.3: repeated cycles until Ctrl+C, 3 history rows written |
| Report/log inspection | Pending target-machine execution |
| Automated suites for v1.2 (`run_all.sh`, 9 suites, about 250 checks) | Pending: run on Linux Mint 22.3 and paste the result here |
| Manual: dashboard looks right in the Mint terminal (colours, block characters, sparklines) | Pending |
| Manual: drag the window smaller and larger while the dashboard runs | Pending |
| Manual: Ctrl+C and `q` leave the terminal normal (cursor visible, typing echoes) | Pending |

## Additional manual checks
```bash
free -h
df -h /
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head
tail -n 30 logs/monitor.log
ls -lh reports/
```

The suite is a starting point, not exhaustive. Later add fixtures/mocks for corrupted `/proc` data, failed commands, unwritable output paths, CPU counter anomalies and multiple filesystems.
