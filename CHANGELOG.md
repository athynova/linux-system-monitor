# Changelog

## [1.1.0] - unreleased
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
