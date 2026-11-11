#!/usr/bin/env bash
# Configuration parsing and validation tests (v1.1).
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
make_sandbox

VALID='CPU_THRESHOLD=80\nRAM_THRESHOLD=85\nDISK_THRESHOLD=90\nMONITOR_INTERVAL=5\nTOP_PROCESS_COUNT=5\n'

# A config is "accepted" when the run proceeds past config loading and only
# stops at the deliberately invalid --interval 0 (no monitoring cycle runs).
config_accepted() { run_app --interval 0; [[ $RC -eq 2 && "$OUT" == *"--interval must be 1-60"* ]]; }
config_rejected() { run_app --interval 0; [[ $RC -eq 2 && "$OUT" != *"--interval must be"* ]]; }

write_conf "$VALID";                                       check "Default-style config accepted" config_accepted
write_conf "# comment\n\n$VALID";                          check "Comments and blank lines ignored" config_accepted
write_conf 'CPU_THRESHOLD = 80\n  RAM_THRESHOLD=85  \n';  check "Spaces around keys and values trimmed" config_accepted
write_conf 'CPU_THRESHOLD=80\r\nRAM_THRESHOLD=85\r\n';     check "Windows (CRLF) line endings accepted" config_accepted
write_conf '\xef\xbb\xbfCPU_THRESHOLD=80\n';               check "UTF-8 BOM accepted" config_accepted
write_conf 'CPU_THRESHOLD=80  # warn at 80\n';             check "Trailing comment accepted" config_accepted
write_conf '';                                             check "Empty config uses documented defaults" config_accepted

write_conf 'CPU_THRESHOLD=101\n';       check "CPU_THRESHOLD above 100 rejected" config_rejected
write_conf 'RAM_THRESHOLD=abc\n';       check "Non-numeric RAM_THRESHOLD rejected" config_rejected
write_conf 'DISK_THRESHOLD=-5\n';       check "Negative DISK_THRESHOLD rejected" config_rejected
write_conf 'CPU_THRESHOLD=\n';          check "Empty value rejected" config_rejected
write_conf 'MONITOR_INTERVAL=0\n';      check "MONITOR_INTERVAL 0 rejected" config_rejected
write_conf 'MONITOR_INTERVAL=3601\n';   check "MONITOR_INTERVAL above 3600 rejected" config_rejected
write_conf 'TOP_PROCESS_COUNT=21\n';    check "TOP_PROCESS_COUNT above 20 rejected" config_rejected
write_conf 'CPU_THRESHOLD=99999999999999999999\n'; check "Overflowing number rejected" config_rejected
write_conf 'BOGUS_SETTING=1\n';         check "Unknown setting rejected" config_rejected
write_conf 'CPU_THRESHOLD=80\nCPU_THRESHOLD=90\n'; check "Duplicate setting rejected" config_rejected
write_conf 'just some words\n';         check "Line without = rejected" config_rejected

write_conf 'CPU_THRESHOLD=80\nBOGUS=1\n'; run_app --interval 0
[[ "$OUT" == *"line 2"* ]] && pass "Error message names the offending line" || fail "Error message names the offending line"

rm -f "$APP/config/monitor.conf"
run_app --interval 0
[[ $RC -eq 2 && "$OUT" == *"missing or unreadable"* ]] && pass "Missing config reported" || fail "Missing config reported"

# --help must work even when the configuration is broken.
write_conf 'CPU_THRESHOLD=banana\n'
run_app --help
[[ $RC -eq 0 && "$OUT" == *"Usage:"* ]] && pass "--help works with a broken config" || fail "--help works with a broken config"
rm -f "$APP/config/monitor.conf"
run_app --help
[[ $RC -eq 0 && "$OUT" == *"Usage:"* ]] && pass "--help works with no config file" || fail "--help works with no config file"

finish
