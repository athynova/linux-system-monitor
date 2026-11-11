#!/usr/bin/env bash
# Edge-case and failure-path tests (v1.1): corrupt data, concurrency,
# unwritable output, CPU counter anomalies, and status recording.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
make_sandbox
source "$TEST_ROOT/modules/history_manager.sh"
source "$TEST_ROOT/modules/cpu_monitor.sh"
HDR="$HISTORY_COLUMNS"
all_rows_have_6_fields() { awk -F, 'NF!=6 {exit 1}' "$1"; }

# --- history file damage -------------------------------------------------------
F="$SANDBOX/foreign/history.csv"; mkdir -p "$(dirname "$F")"
printf 'date,value\n2026-01-01,5\n' > "$F"
history_append "$F" 1 2 3 / NORMAL 100 2>/dev/null
[[ $(head -n1 "$F") == "$HDR" && $(wc -l < "$F") -eq 2 ]] && pass "Foreign header: fresh file started" || fail "Foreign header: fresh file started"
ls "$(dirname "$F")" | grep -q '\.old$' && pass "Foreign header: old file kept aside (.old)" || fail "Foreign header: old file kept aside (.old)"

U="$SANDBOX/unterminated/history.csv"; mkdir -p "$(dirname "$U")"
printf '%s\n2026-01-01T00:00:00+00:00,1.00,1.00,1,/,NORMAL' "$HDR" > "$U"   # no trailing newline
history_append "$U" 2 2 2 / NORMAL 100
[[ $(wc -l < "$U") -eq 3 ]] && all_rows_have_6_fields "$U" && pass "Unterminated last line repaired, rows not merged" || fail "Unterminated last line repaired, rows not merged"

E="$SANDBOX/empty/history.csv"; mkdir -p "$(dirname "$E")"; : > "$E"
history_append "$E" 1 1 1 / NORMAL 100
[[ $(head -n1 "$E") == "$HDR" && $(wc -l < "$E") -eq 2 ]] && pass "Empty file gets a header" || fail "Empty file gets a header"

# --- concurrent writers --------------------------------------------------------
C="$SANDBOX/concurrent/history.csv"
for w in 1 2 3 4 5; do
    ( for i in $(seq 1 20); do history_append "$C" "$w.$i" 10 10 / NORMAL 0; done ) &
done
wait
[[ $(wc -l < "$C") -eq 101 ]] && all_rows_have_6_fields "$C" \
    && pass "5 concurrent writers x 20 rows: 100 intact rows + header" || fail "5 concurrent writers x 20 rows (got $(wc -l < "$C") lines)"

# --- unwritable output ---------------------------------------------------------
if [[ $(id -u) -ne 0 ]]; then
    RO="$SANDBOX/readonly"; mkdir -p "$RO"; chmod 500 "$RO"
    history_append "$RO/history.csv" 1 1 1 / NORMAL 100 2>/dev/null; rc=$?
    chmod 700 "$RO"
    [[ $rc -eq 1 ]] && pass "Read-only data directory: append fails with exit 1" || fail "Read-only data directory: append fails with exit 1 (got $rc)"
else
    echo "SKIP: read-only directory test (running as root ignores permissions)"
fi

write_conf 'MONITOR_INTERVAL=1\n'
touch "$APP/data"                       # a FILE where the data directory should be
run_app --interval 1 --top 1
[[ $RC -eq 0 && "$OUT" == *"could not record history"* && "$OUT" == *"Report saved"* ]] \
    && pass "History failure warns but the cycle and report still succeed" || fail "History failure warns but the cycle and report still succeed"
grep -q 'history write failed' "$APP/logs/monitor.log" && pass "History failure is written to the event log" || fail "History failure is written to the event log"
rm -f "$APP/data"

# --- status and mount recorded correctly ----------------------------------------
write_conf 'CPU_THRESHOLD=0\nMONITOR_INTERVAL=1\n'      # 0% threshold: every sample is a WARNING
run_app --interval 1 --top 1
tail -n1 "$APP/data/history.csv" | grep -q ',WARNING$' && pass "WARNING cycles are recorded with status WARNING" || fail "WARNING cycles are recorded with status WARNING"

write_conf 'MONITOR_INTERVAL=1\n'
mkdir -p "$SANDBOX/a,b"
run_app --interval 1 --top 1 --mount "$SANDBOX/a,b"
tail -n1 "$APP/data/history.csv" | grep -q ",\"$SANDBOX/a,b\",NORMAL\$" && pass "Mount path containing a comma is quoted in CSV" || fail "Mount path containing a comma is quoted in CSV"
run_app --interval 1 --mount "$SANDBOX/does-not-exist"
[[ $RC -eq 2 ]] && pass "Non-existent mount rejected (exit 2)" || fail "Non-existent mount rejected (exit 2)"

# --- CPU counter anomalies (simulated by overriding the counter reader) ---------
read_cpu_counters() { return 1; }
get_cpu_usage 1 >/dev/null 2>&1; [[ $? -eq 1 ]] && pass "Unreadable /proc/stat: exit 1" || fail "Unreadable /proc/stat: exit 1"
read_cpu_counters() { CPU_TOTAL=1000; CPU_IDLE=500; }                # counters did not move
get_cpu_usage 1 >/dev/null 2>&1; [[ $? -eq 1 ]] && pass "Stalled CPU counters (zero delta): exit 1" || fail "Stalled CPU counters (zero delta): exit 1"
n=0; read_cpu_counters() { n=$((n+1)); if ((n==1)); then CPU_TOTAL=1000; CPU_IDLE=500; else CPU_TOTAL=900; CPU_IDLE=400; fi; }
get_cpu_usage 1 >/dev/null 2>&1; [[ $? -eq 1 ]] && pass "Counters going backwards: exit 1" || fail "Counters going backwards: exit 1"
get_cpu_usage 0 >/dev/null 2>&1; [[ $? -eq 2 ]] && pass "CPU interval 0 rejected: exit 2" || fail "CPU interval 0 rejected: exit 2"

finish
