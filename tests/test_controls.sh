#!/usr/bin/env bash
# Dashboard keyboard-control tests (v1.2). Keys are fed through stdin in --frames mode.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
make_sandbox
export LC_ALL=C LC_NUMERIC=C COLUMNS=80 LINES=24
eq() { [[ "$1" == "$2" ]] && pass "$3" || fail "$3 (got '$1', expected '$2')"; }

# ---- unit tests: key handler and refresh stepping (modules sourced directly) -----------
VERSION=test; CPU_THRESHOLD=80; RAM_THRESHOLD=85; DISK_THRESHOLD=90
SHUTDOWN_SIGNAL=""; interruptible_sleep() { :; }
for m in cpu_monitor memory_monitor process_monitor terminal dashboard; do source "$TEST_ROOT/modules/$m.sh"; done
USE_COLOR=0; unset NO_COLOR
dash_sample_procs() { :; }

dash_handle_key q; eq "$?" 1 "key q asks to quit"
dash_handle_key Q; eq "$?" 1 "key Q asks to quit"
for k in x 1 ESC ' '; do dash_handle_key "$k"; [[ $? -eq 0 ]] || fail "unknown key '$k' must be ignored"; done; pass "unknown keys are ignored"
DASH_PAUSED=0; dash_handle_key p; eq "$DASH_PAUSED/$DASH_STATE" "1/PAUSED" "key p pauses"
dash_handle_key p; eq "$DASH_PAUSED/$DASH_STATE" "0/LIVE" "key p again resumes"
DASH_HELP=0; dash_handle_key h; eq "$DASH_HELP" 1 "key h opens help"; dash_handle_key '?'; eq "$DASH_HELP" 0 "key ? closes help"
dash_handle_key m; eq "$DASH_SORT" mem "key m sorts by memory"; dash_handle_key c; eq "$DASH_SORT" cpu "key c sorts by CPU"

step() { DASH_REFRESH=$1; dash_step_refresh "$2"; echo "$DASH_REFRESH"; }
eq "$(step 2 faster)"   1   "refresh: 2 s faster -> 1 s"
eq "$(step 2 slower)"   3   "refresh: 2 s slower -> 3 s"
eq "$(step 0.7 faster)" 0.5 "refresh: off-preset value steps to the next preset (faster)"
eq "$(step 0.7 slower)" 1   "refresh: off-preset value steps to the next preset (slower)"
eq "$(step 0.2 faster)" 0.2 "refresh: cannot go below 0.2 s"
eq "$(step 60 slower)"  60  "refresh: cannot go above 60 s"
dash_set_refresh 0.25; eq "$DASH_REFRESH_US" 250000 "refresh converted to microseconds"
TERM_COLS=50 TERM_ROWS=10; [[ "$(dash_small_frame)" == *"too small: 50x10"*"at least 60x18"* ]] && pass "small-window message names both sizes" || fail "small-window message names both sizes"
TERM_COLS=80 TERM_ROWS=24; DASH_ALERTS=(); [[ "$(dash_section_footer 79)" == *"q quit  p pause  c/m sort  +/- speed  h help"* ]] && pass "footer lists the keys" || fail "footer lists the keys"
DASH_HELP=1; DASH_CPU_HIST=(); DASH_RAM_HIST=(); h=$(dash_build_frame); [[ "$h" == *KEYS* && "$h" != *" CPU  ["* ]] && pass "help replaces the meters" || fail "help replaces the meters"
DASH_HELP=0

# ---- integration: real monitor.sh, keys piped in -----------------------------------------
write_conf 'MONITOR_INTERVAL=1\n'
run_keys() { local keys=$1; shift; OUT=$(printf '%b' "$keys" | "$APP/monitor.sh" --dashboard --no-color --refresh 1 "$@" 2>&1); RC=$?; }
frame_n() { awk -v n="$1" '$0 == "=== frame " n " ===" { on = 1; next } /^=== frame / { on = 0 } on' <<< "$OUT"; }

run_keys 'm' --frames 2
[[ "$(frame_n 1)" == *"sorted by CPU"* && "$(frame_n 2)" == *"sorted by MEM"* ]] && pass "m switches the process panel to memory order" || fail "m switches the process panel to memory order"
run_keys 'mc' --frames 3
[[ "$(frame_n 3)" == *"sorted by CPU"* ]] && pass "c switches back to CPU order" || fail "c switches back to CPU order"
run_keys 'h' --frames 2
[[ "$(frame_n 2)" == *KEYS* && "$(frame_n 2)" != *PROCESSES* ]] && pass "h shows the help screen" || fail "h shows the help screen"
run_keys 'hh' --frames 3
[[ "$(frame_n 3)" == *PROCESSES* && "$(frame_n 3)" != *KEYS* ]] && pass "second h hides the help screen" || fail "second h hides the help screen"
run_keys 'p' --frames 2
[[ "$(frame_n 1)" == *LIVE* && "$(frame_n 2)" == *PAUSED* ]] && pass "p marks the header PAUSED" || fail "p marks the header PAUSED"
run_keys 'pp' --frames 3
[[ "$(frame_n 3)" == *LIVE* ]] && pass "second p resumes (LIVE)" || fail "second p resumes (LIVE)"
run_keys '+' --frames 2 --refresh 2
[[ "$(frame_n 1)" == *"refresh 2s"* && "$(frame_n 2)" == *"refresh 1s"* ]] && pass "+ speeds the refresh up" || fail "+ speeds the refresh up"
run_keys '-' --frames 2 --refresh 2
[[ "$(frame_n 2)" == *"refresh 3s"* ]] && pass "- slows the refresh down" || fail "- slows the refresh down"
run_keys 'q' --frames 9
[[ $RC -eq 0 && "$OUT" == *"=== frame 1 ==="* && "$OUT" != *"=== frame 2 ==="* ]] && pass "q quits at once with exit 0" || fail "q quits at once with exit 0 (rc=$RC)"
run_keys 'Q' --frames 9
[[ $RC -eq 0 && "$OUT" != *"=== frame 2 ==="* ]] && pass "capital Q quits too" || fail "capital Q quits too"
run_keys '\e[A\e[B\e[C' --frames 2
[[ $RC -eq 0 && "$OUT" == *"=== frame 2 ==="* && "$(frame_n 2)" == *PROCESSES* ]] && pass "arrow keys are ignored" || fail "arrow keys are ignored"
run_keys 'xyz123' --frames 2
[[ $RC -eq 0 && "$OUT" == *"=== frame 2 ==="* ]] && pass "unknown keys are ignored" || fail "unknown keys are ignored"

start=$SECONDS
OUT=$("$APP/monitor.sh" --dashboard --no-color --refresh 0.4 --frames 3 < /dev/null 2>&1); RC=$?
(( RC == 0 && SECONDS - start <= 6 )) && [[ "$OUT" == *"=== frame 3 ==="* ]] && pass "empty stdin (EOF) still paces frames without spinning" || fail "empty stdin (EOF) handling (rc=$RC)"

finish
