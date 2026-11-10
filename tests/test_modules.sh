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
