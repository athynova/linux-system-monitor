#!/usr/bin/env bash
# Interactive dashboard tests (v1.2) inside a real pseudo-terminal (util-linux "script").
# These prove what the piped tests cannot: the screen and cursor are restored on every
# way out, colours really appear on a terminal, and a window resize redraws at once.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
make_sandbox
if ! command -v script >/dev/null 2>&1; then echo "SKIP: 'script' (util-linux) not installed"; exit 0; fi
export LC_ALL=C.UTF-8 LC_NUMERIC=C
unset NO_COLOR COLUMNS LINES
write_conf 'MONITOR_INTERVAL=1\n'
OUTF="$SANDBOX/pty.out"; PIDF="$SANDBOX/pid"
ENTER=$'\e[?1049h'; LEAVE=$'\e[?1049l'; SHOW=$'\e[?25h'; HIDE=$'\e[?25l'

# pty DELAY KEYS COMMAND: run COMMAND on a 100x30 pseudo-terminal, send KEYS after DELAY seconds.
pty() {
    ( sleep "$1"; printf '%b' "$2"; sleep 0.6 ) | timeout 25 script -qec "stty rows 30 cols 100; $3" /dev/null > "$OUTF" 2>&1
    PTY_RC=${PIPESTATUS[1]}
}
has()   { [[ "$(<"$OUTF")" == *"$1"* ]]; }
# last_pos NEEDLE -> byte offset of the LAST occurrence (-1 if none), for ordering checks
last_pos() { local t; t=$(<"$OUTF"); local rest=${t%"$1"*}; [[ "$rest" == "$t" ]] && echo -1 || echo ${#rest}; }
first_pos() { local t; t=$(<"$OUTF"); local rest=${t%%"$1"*}; [[ "$rest" == "$t" ]] && echo -1 || echo ${#rest}; }
DASH="$APP/monitor.sh --dashboard --refresh 1"

# --- normal quit -------------------------------------------------------------------
pty 1.5 q "$DASH"
[[ $PTY_RC -eq 0 ]] && pass "q: exit status 0" || fail "q: exit status 0 (got $PTY_RC)"
has "$ENTER" && has "$HIDE" && pass "enters the alternate screen and hides the cursor" || fail "enters the alternate screen and hides the cursor"
(( $(last_pos "$LEAVE") > $(first_pos "$ENTER") && $(first_pos "$ENTER") >= 0 )) && has "$SHOW" && pass "q: leaves the alternate screen and shows the cursor again" || fail "q: leaves the alternate screen and shows the cursor again"
has "Linux System Monitor" && has "PROCESSES" && pass "a real frame was drawn on the terminal" || fail "a real frame was drawn on the terminal"
has $'\e[32m' && pass "colours are used on a terminal (green = normal)" || fail "colours are used on a terminal"
has "█" || has "░" && pass "UTF-8 block characters are used in a UTF-8 locale" || fail "UTF-8 block characters are used in a UTF-8 locale"

# --- colour switches ----------------------------------------------------------------
pty 1.5 q "$DASH --no-color"
! has $'\e[32m' && ! has $'\e[31m' && ! has $'\e[36m' && pass "--no-color: no colour codes" || fail "--no-color: no colour codes"
pty 1.5 q "NO_COLOR=1 $DASH"
! has $'\e[32m' && pass "NO_COLOR environment variable respected" || fail "NO_COLOR environment variable respected"
pty 1.5 q "LC_ALL=C $DASH"
! has "█" && ! has "░" && pass "C locale: ASCII bars instead of block characters" || fail "C locale: ASCII bars instead of block characters"

# --- terminal settings are put back -------------------------------------------------
pty 1.5 q "$DASH; stty -a"
{ grep -qE '(^|[ ;])echo([ ;]|$)' "$OUTF" && ! grep -qE '(^|[ ;])-echo([ ;]|$)' "$OUTF"; } && pass "echo is switched back on after quitting" || fail "echo is switched back on after quitting"

# --- Ctrl+C (a real ^C byte typed on the pty) --------------------------------------
pty 1.5 '\003' "$DASH"
[[ $PTY_RC -eq 130 ]] && pass "Ctrl+C: exit status 130" || fail "Ctrl+C: exit status 130 (got $PTY_RC)"
(( $(last_pos "$LEAVE") >= 0 )) && has "$SHOW" && pass "Ctrl+C: screen and cursor restored" || fail "Ctrl+C: screen and cursor restored"
(( $(last_pos "Monitor stopped by SIGINT") > $(last_pos "$LEAVE") )) && pass "Ctrl+C: the stop message is printed on the normal screen" || fail "Ctrl+C: the stop message is printed on the normal screen"
grep -q 'Monitor stopped by SIGINT. Frames completed=' "$APP/logs/monitor.log" && pass "Ctrl+C: dashboard stop is logged" || fail "Ctrl+C: dashboard stop is logged"

# --- Ctrl+C is prompt even with a long refresh interval (read -t alone would wait it out) ---
start=$SECONDS
pty 1.5 '\003' "$APP/monitor.sh --dashboard --refresh 30"
(( PTY_RC == 130 && SECONDS - start <= 8 )) && pass "Ctrl+C is prompt with --refresh 30 ($((SECONDS - start)) s)" || fail "Ctrl+C is prompt with --refresh 30 (rc=$PTY_RC, $((SECONDS - start)) s)"
start=$SECONDS
pty 1.5 q "$APP/monitor.sh --dashboard --refresh 30"
(( PTY_RC == 0 && SECONDS - start <= 8 )) && pass "q is prompt with --refresh 30 ($((SECONDS - start)) s)" || fail "q is prompt with --refresh 30 (rc=$PTY_RC)"

# --- SIGTERM from outside ----------------------------------------------------------------
rm -f "$PIDF"
( sleep 1.5; kill -TERM "$(cat "$PIDF")"; sleep 1 ) | timeout 25 script -qec "stty rows 30 cols 100; echo \$\$ > $PIDF; exec $DASH" /dev/null > "$OUTF" 2>&1
rc=${PIPESTATUS[1]}
[[ $rc -eq 143 ]] && pass "SIGTERM: exit status 143" || fail "SIGTERM: exit status 143 (got $rc)"
(( $(last_pos "$LEAVE") >= 0 )) && has "$SHOW" && pass "SIGTERM: screen and cursor restored" || fail "SIGTERM: screen and cursor restored"

# --- window resize redraws immediately (refresh is 30 s, so only SIGWINCH can cause it) -
rm -f "$PIDF"
( sleep 1.5; for i in 1 2 3; do kill -WINCH "$(cat "$PIDF")"; sleep 0.3; done; printf q; sleep 0.6 ) \
    | timeout 25 script -qec "stty rows 30 cols 100; echo \$\$ > $PIDF; exec $APP/monitor.sh --dashboard --refresh 30" /dev/null > "$OUTF" 2>&1
draws=$(grep -o $'\e\[H' "$OUTF" | wc -l)
(( draws >= 5 )) && pass "resize (SIGWINCH) redraws at once, not after the 30 s refresh ($draws draws)" || fail "resize redraws at once (only $draws draws)"

# --- too-small window -----------------------------------------------------------------
( sleep 0.5 ) | timeout 25 script -qec "stty rows 10 cols 40; $DASH" /dev/null > "$OUTF" 2>&1; rc=${PIPESTATUS[1]}
[[ $rc -eq 2 ]] && has "Terminal too small" && ! has "$ENTER" && pass "too-small terminal: refused with exit 2, screen never switched" || fail "too-small terminal refused (rc=$rc)"

# --- the dashboard only watches: it writes no history, reports or logs of samples -----------
rm -rf "$APP/data" "$APP/reports"
OUT=$("$APP/monitor.sh" --dashboard --frames 2 --refresh 0.3 --no-color 2>&1 < /dev/null)
[[ ! -e "$APP/data/history.csv" && ! -e "$APP/reports" ]] && pass "dashboard records no history and saves no reports" || fail "dashboard records no history and saves no reports"

finish
