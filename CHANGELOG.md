# Changelog

## [1.2.0] - 2026-11-14
### Added
- Interactive terminal dashboard: `--dashboard`, `--refresh SECONDS`, `--frames N`, `--no-color`.
- Live CPU and RAM meters with history sparklines, disk usage bars, sortable process list.
- Keys: `q` quit, `p` pause, `c`/`m` sort, `+`/`-` refresh speed, `h` help.
- New modules `modules/terminal.sh` and `modules/dashboard.sh`.
- Test suites `test_terminal.sh`, `test_dashboard.sh`, `test_controls.sh` and `test_interactive.sh` (real pseudo-terminal).

### Notes
- The dashboard is read-only: it writes no history or reports.
- The stop message and event-log entry say "frame(s)" instead of "cycle(s)" when the dashboard was running.
- The `CHANGELOG.md` shipped inside the v1.2.0 tag was accidentally empty; restored in v1.2.1.

## [1.1.2] - 2026-11-11
### Fixed
- On a busy system (hundreds of processes) the top-process pipeline was killed by SIGPIPE and reported as failed under `pipefail`; the `CPU process limit` test failed on Linux Mint 22.3. The pipeline now reads all `ps` output (regression introduced in v1.1.1).

### Testing
- New regression test feeds 5000 synthetic process rows through the pipeline under `pipefail`.

## [1.1.1] - 2026-11-11
### Fixed
- Ctrl+C during report assembly printed a spurious `Report content and directory are required` error; a partial report is now never printed or saved.
- The monitor's own `ps` process (always ~100% CPU) no longer appears in the top-process lists.

### Documentation
- Graceful-shutdown behaviour described precisely: Ctrl+C after sampling but before the report completes can leave a history row without a report.
- Test plan records the v1.1 results on Linux Mint 22.3.

## [1.1.0] - 2026-11-11
### Added
- Historical CPU, RAM and disk metrics stored in `data/history.csv` (new `modules/history_manager.sh`).
- `HISTORY_ENABLED` and `HISTORY_MAX_ROWS` settings; `--show-history N` and `--version` options.
- Graceful shutdown on Ctrl+C (exit 130) and SIGTERM (exit 143) with an event-log entry.
- Configuration parser: whitespace, CRLF, BOM and trailing comments tolerated; duplicate and unknown keys rejected with line numbers.
- Test suites `test_config.sh`, `test_history.sh`, `test_shutdown.sh`, `test_edge_cases.sh`, shared `tests/lib.sh`, and `tests/run_all.sh`.

### Fixed
- Process tables misaligned for command names containing spaces (e.g. `Web Content`).
- `--help` no longer fails when the configuration file is invalid.

### Changed
- Arguments are parsed before the configuration is loaded.
- `LC_NUMERIC=C` is forced so decimals always use a dot, whatever the system locale.

## [1.0.0] - 2026-11-10
- Initial release: CPU/RAM/disk/process monitoring, thresholds, reports, event log, continuous mode.
