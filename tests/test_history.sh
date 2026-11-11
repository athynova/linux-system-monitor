#!/usr/bin/env bash
# Historical metrics tests (v1.1): CSV format, escaping, trimming, integration.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
make_sandbox
source "$TEST_ROOT/modules/history_manager.sh"

H="$SANDBOX/unit/history.csv"
ISO='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$'

# --- csv_escape -------------------------------------------------------------
[[ $(csv_escape "/home") == "/home" ]]                 && pass "csv_escape: plain value unchanged"    || fail "csv_escape: plain value unchanged"
[[ $(csv_escape "/a,b") == '"/a,b"' ]]                 && pass "csv_escape: comma is quoted"          || fail "csv_escape: comma is quoted"
[[ $(csv_escape 'a"b') == '"a""b"' ]]                  && pass "csv_escape: quote is doubled"         || fail "csv_escape: quote is doubled"
[[ $(csv_escape "=cmd") == "'=cmd" ]]                  && pass "csv_escape: formula prefix neutralised" || fail "csv_escape: formula prefix neutralised"

# --- header and row format --------------------------------------------------
history_append "$H" 29.19 19.90 1 / NORMAL 100; rc=$?
[[ $rc -eq 0 ]] && pass "First append succeeds (creates directory and file)" || fail "First append succeeds"
[[ $(head -n1 "$H") == "timestamp,cpu_percent,ram_percent,disk_percent,mount,status" ]] \
    && pass "Header written" || fail "Header written"
history_append "$H" 5.50 20.00 1 / WARNING 100
[[ $(wc -l < "$H") -eq 3 ]] && pass "Header written once; one row per append" || fail "Header written once; one row per append"
IFS=, read -r ts cpu ram disk mnt st < <(sed -n 2p "$H")
[[ "$ts" =~ $ISO && "$cpu" == 29.19 && "$ram" == 19.90 && "$disk" == 1 && "$mnt" == / && "$st" == NORMAL ]] \
    && pass "Row fields correct and timestamp is ISO 8601" || fail "Row fields correct and timestamp is ISO 8601"
[[ $(stat -c %a "$H") == 600 ]] && pass "History file permissions are 600" || fail "History file permissions are 600"

# --- input validation -------------------------------------------------------
history_append "$H" abc 1 1 / NORMAL 2>/dev/null;   [[ $? -eq 2 ]] && pass "Non-numeric CPU rejected (exit 2)"  || fail "Non-numeric CPU rejected"
history_append "$H" 1 1 1 / BOGUS 2>/dev/null;      [[ $? -eq 2 ]] && pass "Unknown status rejected (exit 2)"   || fail "Unknown status rejected"
history_append "" 1 1 1 / NORMAL 2>/dev/null;       [[ $? -eq 2 ]] && pass "Empty file path rejected (exit 2)"  || fail "Empty file path rejected"
history_append "$H" 1 1 1 "" NORMAL 2>/dev/null;    [[ $? -eq 2 ]] && pass "Empty mount rejected (exit 2)"      || fail "Empty mount rejected"
[[ $(wc -l < "$H") -eq 3 ]] && pass "Rejected records are not written" || fail "Rejected records are not written"

# --- mount path with a comma stays one CSV field ----------------------------
history_append "$H" 1 1 1 "/mnt/a,b" NORMAL 100
tail -n1 "$H" | grep -q ',"/mnt/a,b",NORMAL$' && pass "Comma in mount path is quoted in the file" || fail "Comma in mount path is quoted in the file"

# --- trimming keeps the file bounded and keeps the newest rows ---------------
T="$SANDBOX/trim/history.csv"
for i in $(seq 1 115); do history_append "$T" "$i.00" 10 10 / NORMAL 100; done
rows=$(( $(wc -l < "$T") - 1 ))
(( rows >= 100 && rows <= 110 )) && pass "Trim keeps 100-110 rows (got $rows)" || fail "Trim keeps 100-110 rows (got $rows)"
[[ $(head -n1 "$T") == "$HISTORY_COLUMNS" ]] && pass "Header survives trimming" || fail "Header survives trimming"
[[ $(tail -n1 "$T" | cut -d, -f2) == 115.00 ]] && pass "Newest row survives trimming" || fail "Newest row survives trimming"
ls "$SANDBOX/trim" | grep -q '\.tmp\.' && fail "No temp files left behind" || pass "No temp files left behind"

# --- history_show -----------------------------------------------------------
out=$(history_show "$T" 3)
[[ $(wc -l <<< "$out") -eq 5 && "$out" == *"timestamp,cpu_percent"* ]] && pass "history_show prints summary, header and N rows" || fail "history_show prints summary, header and N rows"
out=$(history_show "$SANDBOX/nope.csv" 3)
[[ "$out" == *"No history recorded yet"* ]] && pass "history_show handles a missing file" || fail "history_show handles a missing file"

# --- integration: full cycles through monitor.sh ----------------------------
write_conf 'MONITOR_INTERVAL=1\n'
run_app --interval 1 --top 1
[[ $RC -eq 0 && "$OUT" == *"History recorded:"* ]] && pass "Cycle reports history recorded" || fail "Cycle reports history recorded"
run_app --interval 1 --top 1
[[ $(wc -l < "$APP/data/history.csv") -eq 3 ]] && pass "Two cycles produce header + 2 rows" || fail "Two cycles produce header + 2 rows"
run_app --show-history 1
[[ $RC -eq 0 && "$OUT" == *"showing the last 1"* ]] && pass "--show-history prints records" || fail "--show-history prints records"
run_app --show-history 0;    [[ $RC -eq 2 ]] && pass "--show-history 0 rejected" || fail "--show-history 0 rejected"
run_app --show-history abc;  [[ $RC -eq 2 ]] && pass "--show-history abc rejected" || fail "--show-history abc rejected"

rm -rf "$APP/data"
write_conf 'HISTORY_ENABLED=false\n'
run_app --interval 1 --top 1
[[ $RC -eq 0 && ! -e "$APP/data/history.csv" && "$OUT" != *"History recorded"* ]] \
    && pass "HISTORY_ENABLED=false records nothing" || fail "HISTORY_ENABLED=false records nothing"
write_conf 'HISTORY_ENABLED=maybe\n'; run_app --show-history 1; [[ $RC -eq 2 ]] && pass "Invalid HISTORY_ENABLED rejected" || fail "Invalid HISTORY_ENABLED rejected"
write_conf 'HISTORY_MAX_ROWS=5\n';    run_app --show-history 1; [[ $RC -eq 2 ]] && pass "HISTORY_MAX_ROWS below 100 rejected" || fail "HISTORY_MAX_ROWS below 100 rejected"
write_conf 'HISTORY_MAX_ROWS=2000000\n'; run_app --show-history 1; [[ $RC -eq 2 ]] && pass "HISTORY_MAX_ROWS above 1000000 rejected" || fail "HISTORY_MAX_ROWS above 1000000 rejected"

finish
