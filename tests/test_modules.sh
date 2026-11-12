#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
pass(){ echo "PASS: $1"; }
fail(){ echo "FAIL: $1"; fails=$((fails+1)); }
for f in "$ROOT/monitor.sh" "$ROOT"/modules/*.sh; do
    bash -n "$f" && pass "Syntax $(basename "$f")" || fail "Syntax $(basename "$f")"
done
source "$ROOT/modules/memory_monitor.sh"
get_memory_metrics | grep -q '^MEM_PERCENT=' && pass "Memory metrics" || fail "Memory metrics"
source "$ROOT/modules/disk_monitor.sh"
get_disk_metrics / | grep -q '^DISK_PERCENT=' && pass "Root disk metrics" || fail "Root disk metrics"
get_disk_metrics /no-such-mount-for-monitor-test >/dev/null 2>&1
rc=$?; [[ $rc -eq 2 ]] && pass "Invalid mount rejected" || fail "Invalid mount exit status"
source "$ROOT/modules/process_monitor.sh"
get_top_cpu_processes 3 | awk 'NR>1{n++} END{exit !(n>0 && n<=3)}' && pass "CPU process limit" || fail "CPU process limit"
# Regression: command names containing spaces must not shift the numeric columns.
rows=$(printf '%s\n' "  101  55.0  4.0 Web Content" "  102   1.0  0.1 bash" | format_process_rows)
echo "$rows" | awk 'NR==2 {exit !($1==101 && $2=="Web" && $3=="Content" && $4=="55.0" && $5=="4.0")}' \
    && pass "Spaced command name keeps columns" || fail "Spaced command name keeps columns"
echo "$rows" | awk 'NR==3 {exit !($1==102 && $2=="bash" && $3=="1.0" && $4=="0.1")}' \
    && pass "Plain command name keeps columns" || fail "Plain command name keeps columns"
# The monitor's own "ps" must not appear, but similar names such as "psql" must.
kept=$(printf '%s\n' "  9  100.0  0.0 ps" " 10   5.0  1.0 psql" " 11   2.0  1.0 bash" | select_process_rows 10)
awk '$4=="ps" {found=1} END {exit found}' <<< "$kept" && [[ "$kept" == *psql* && "$kept" == *bash* ]] && pass "Own ps row excluded, psql/bash kept" || fail "Own ps row excluded, psql/bash kept"
# Regression (v1.1.1): on a busy machine ps output is large; the pipeline must still
# succeed under pipefail (no SIGPIPE from stopping early). 5000 synthetic rows.
( set -o pipefail; awk 'BEGIN{for(i=1;i<=5000;i++) printf "%d 1.0 1.0 proc%d\n", i, i}' \
    | select_process_rows 3 | format_process_rows > /tmp/lsm_big.$$ )
rc=$?; lines=$(wc -l < /tmp/lsm_big.$$); rm -f /tmp/lsm_big.$$
[[ $rc -eq 0 && $lines -eq 4 ]] && pass "Large process list: pipeline succeeds, 3 rows kept" || fail "Large process list: pipeline succeeds (rc=$rc, lines=$lines)"
get_top_memory_processes abc >/dev/null 2>&1
rc=$?; [[ $rc -eq 2 ]] && pass "Invalid process count rejected" || fail "Invalid process count exit status"
source "$ROOT/modules/alert_manager.sh"
tmp=$(mktemp)
check_threshold TEST 90 80 "$tmp" >/dev/null
rc=$?; [[ $rc -eq 1 ]] && grep -q 'WARNING: TEST' "$tmp" && pass "Threshold warning logged" || fail "Threshold warning"
check_threshold TEST 10 80 "$tmp" >/dev/null
rc=$?; [[ $rc -eq 0 ]] && pass "Normal threshold" || fail "Normal threshold"
check_threshold TEST abc 80 "$tmp" >/dev/null 2>&1
rc=$?; [[ $rc -eq 2 ]] && pass "Invalid metric rejected" || fail "Invalid metric validation"
rm -f "$tmp"
"$ROOT/monitor.sh" --help >/dev/null && pass "Help option" || fail "Help option"
"$ROOT/monitor.sh" --unknown >/dev/null 2>&1
rc=$?; [[ $rc -eq 2 ]] && pass "Unknown option rejected" || fail "Unknown option exit status"
"$ROOT/monitor.sh" --interval 0 >/dev/null 2>&1
rc=$?; [[ $rc -eq 2 ]] && pass "Invalid interval rejected" || fail "Invalid interval exit status"
echo "Test summary: $fails failure(s)"
(( fails == 0 ))
