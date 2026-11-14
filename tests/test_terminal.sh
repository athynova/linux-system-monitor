#!/usr/bin/env bash
# Terminal helper tests (v1.2). Nothing here needs a real terminal.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
make_sandbox
source "$TEST_ROOT/modules/terminal.sh"
OUTF="$SANDBOX/out.txt"
has() { [[ "$(<"$OUTF")" == *"$1"* ]]; }

# --- size ---------------------------------------------------------------------
( export LINES=40 COLUMNS=120; term_size; [[ $TERM_ROWS -eq 40 && $TERM_COLS -eq 120 ]] ) \
    && pass "term_size honours LINES/COLUMNS" || fail "term_size honours LINES/COLUMNS"
( unset LINES COLUMNS; term_size >/dev/null; [[ $TERM_ROWS -eq 24 && $TERM_COLS -eq 80 ]] ) \
    && pass "term_size falls back to 24x80" || fail "term_size falls back to 24x80"
( export LINES=abc COLUMNS=-5; term_size >/dev/null; [[ $TERM_ROWS -eq 24 && $TERM_COLS -eq 80 ]] ) \
    && pass "term_size ignores invalid LINES/COLUMNS" || fail "term_size ignores invalid LINES/COLUMNS"
( TERM_COLS=60 TERM_ROWS=18; term_big_enough ) && pass "60x18 is big enough" || fail "60x18 is big enough"
( TERM_COLS=59 TERM_ROWS=24; ! term_big_enough ) && pass "59 columns is too small" || fail "59 columns is too small"
( TERM_COLS=80 TERM_ROWS=17; ! term_big_enough ) && pass "17 rows is too small" || fail "17 rows is too small"

# --- locale and colour ----------------------------------------------------------
( unset LC_CTYPE; export LC_ALL=C.UTF-8; term_utf8 ) && pass "UTF-8 locale detected" || fail "UTF-8 locale detected"
( unset LC_ALL LC_CTYPE; export LANG=sw_TZ.utf8; term_utf8 ) && pass "LANG=...utf8 detected" || fail "LANG=...utf8 detected"
( export LC_ALL=C; ! term_utf8 ) && pass "C locale is not UTF-8" || fail "C locale is not UTF-8"
( unset NO_COLOR; USE_COLOR=1; [[ "$(paint crit X)" == $'\e[31mX\e[0m' ]] ) && pass "paint adds colour codes" || fail "paint adds colour codes"
( unset NO_COLOR; USE_COLOR=1; [[ "$(paint ok X)" == $'\e[32mX\e[0m' && "$(paint warn X)" == $'\e[33mX\e[0m' ]] ) && pass "ok=green, warn=yellow" || fail "ok=green, warn=yellow"
( export NO_COLOR=1; USE_COLOR=1; [[ "$(paint crit X)" == X ]] ) && pass "NO_COLOR disables colour" || fail "NO_COLOR disables colour"
( unset NO_COLOR; USE_COLOR=0; [[ "$(paint crit X)" == X ]] ) && pass "--no-color disables colour" || fail "--no-color disables colour"
( unset NO_COLOR; USE_COLOR=1; [[ "$(paint nonsense X)" == X ]] ) && pass "Unknown level prints plain text" || fail "Unknown level prints plain text"

# --- screen ownership -----------------------------------------------------------
term_enter > "$OUTF"
[[ $TERM_ACTIVE -eq 1 ]] && has $'\e[?1049h' && has $'\e[?25l' && pass "term_enter: alternate screen, cursor hidden" || fail "term_enter: alternate screen, cursor hidden"
term_enter > "$OUTF"
[[ ! -s "$OUTF" ]] && pass "term_enter twice prints nothing the second time" || fail "term_enter twice prints nothing the second time"
term_leave > "$OUTF"
[[ $TERM_ACTIVE -eq 0 ]] && has $'\e[?1049l' && has $'\e[?25h' && has $'\e[?7h' && pass "term_leave: screen, cursor and wrapping restored" || fail "term_leave: screen, cursor and wrapping restored"
term_leave > "$OUTF"
[[ ! -s "$OUTF" ]] && pass "term_leave is idempotent" || fail "term_leave is idempotent"

# --- flicker-free frame ---------------------------------------------------------
term_frame $'one\ntwo' > "$OUTF"
[[ "$(<"$OUTF")" == $'\e[Hone\e[K\ntwo\e[K\e[J' ]] && pass "term_frame: home, per-line clear, clear below" || fail "term_frame: home, per-line clear, clear below"

finish
