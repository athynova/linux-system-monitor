#!/usr/bin/env bash
# Graceful shutdown tests (v1.1): SIGINT (Ctrl+C) and SIGTERM handling.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
make_sandbox
write_conf 'MONITOR_INTERVAL=1\n'
LOG="$APP/logs/monitor.log"; CSV="$APP/data/history.csv"; OUTF="$SANDBOX/out.txt"

# Every CSV line must have exactly 6 fields (no torn or interleaved rows).
csv_wellformed() { [[ -s "$CSV" ]] && awk -F, 'NF!=6 {exit 1}' "$CSV"; }
no_temp_files() { ! ls "$APP/data" 2>/dev/null | grep -q '\.tmp\.'; }
wait_for_text() { local i; for i in $(seq 1 100); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; return 1; }

# --- SIGINT to the whole process group (what Ctrl+C does) --------------------
timeout --preserve-status -s INT 4 "$APP/monitor.sh" --continuous --interval 1 --top 1 > "$OUTF" 2>&1; rc=$?
[[ $rc -eq 130 ]] && pass "Ctrl+C exits with status 130" || fail "Ctrl+C exits with status 130 (got $rc)"
grep -q 'Monitor stopped by SIGINT' "$OUTF" && pass "Ctrl+C prints a clean stop message" || fail "Ctrl+C prints a clean stop message"
grep -q 'Monitor stopped by SIGINT' "$LOG" && pass "Ctrl+C is recorded in the event log" || fail "Ctrl+C is recorded in the event log"
csv_wellformed && pass "History CSV intact after Ctrl+C" || fail "History CSV intact after Ctrl+C"
no_temp_files && pass "No temp files left after Ctrl+C" || fail "No temp files left after Ctrl+C"

# --- SIGTERM to the main process while a cycle is running: cycle finishes -----
rm -rf "$APP/data" "$APP/logs"
"$APP/monitor.sh" --continuous --interval 2 --top 1 > "$OUTF" 2>&1 &
pid=$!
sleep 0.8; kill -TERM "$pid"; wait "$pid"; rc=$?   # signal arrives mid-sample (2 s window)
[[ $rc -eq 143 ]] && pass "SIGTERM exits with status 143" || fail "SIGTERM exits with status 143 (got $rc)"
grep -q 'Monitor stopped by SIGTERM after 1 completed cycle' "$OUTF" && pass "In-flight cycle completes before stopping" || fail "In-flight cycle completes before stopping"
csv_wellformed && [[ $(wc -l < "$CSV") -eq 2 ]] && pass "In-flight cycle was recorded (header + 1 row)" || fail "In-flight cycle was recorded (header + 1 row)"

# --- Signal while sleeping between cycles: stops promptly --------------------
write_conf 'MONITOR_INTERVAL=60\n'
rm -rf "$APP/data" "$APP/logs"
"$APP/monitor.sh" --continuous --interval 1 --top 1 > "$OUTF" 2>&1 &
pid=$!
wait_for_text "$OUTF" 'Report saved' ; start=$SECONDS
kill -TERM "$pid"; wait "$pid"; rc=$?
(( SECONDS - start <= 3 )) && [[ $rc -eq 143 ]] && pass "Sleeping monitor stops promptly (not after 60 s)" || fail "Sleeping monitor stops promptly (took $((SECONDS-start)) s, rc=$rc)"

# --- Ctrl+C during a one-shot run: nothing half-written ----------------------
rm -rf "$APP/data" "$APP/logs" "$APP/reports"
timeout --preserve-status -s INT 1 "$APP/monitor.sh" --interval 5 --top 1 > "$OUTF" 2>&1; rc=$?
[[ $rc -eq 130 ]] && pass "Ctrl+C during a one-shot run exits with 130" || fail "Ctrl+C during a one-shot run exits with 130 (got $rc)"
[[ ! -e "$APP/data/history.csv" && ! -e "$APP/reports" ]] && pass "Interrupted cycle writes no partial history or report" || fail "Interrupted cycle writes no partial history or report"

# --- Normal one-shot run is unaffected ---------------------------------------
write_conf 'MONITOR_INTERVAL=1\n'
run_app --interval 1 --top 1
[[ $RC -eq 0 ]] && pass "Normal one-shot run still exits 0" || fail "Normal one-shot run still exits 0 (got $RC)"

finish
