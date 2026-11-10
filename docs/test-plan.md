# Test Plan and Results

Run `./tests/test_modules.sh`, then run `./monitor.sh --interval 1 --top 3` on the target Linux Mint machine.

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

## Results record
Do not claim target-machine tests passed until you run them on Linux Mint 22.3 and record actual output here.

| Test group | Result |
|---|---|
| Automated module tests | Pending target-machine execution |
| Full integration run | Pending target-machine execution |
| Continuous mode | Pending target-machine execution |
| Report/log inspection | Pending target-machine execution |

## Additional manual checks
```bash
free -h
df -h /
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head
tail -n 30 logs/monitor.log
ls -lh reports/
```

The suite is a starting point, not exhaustive. Later add fixtures/mocks for corrupted `/proc` data, failed commands, unwritable output paths, CPU counter anomalies and multiple filesystems.
