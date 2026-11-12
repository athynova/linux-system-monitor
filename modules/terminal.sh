#!/usr/bin/env bash
# Terminal helpers for the v1.2 dashboard.
# Plain ANSI escape codes only: no ncurses, no tput, no extra packages.

TERM_ACTIVE=0              # 1 while the dashboard owns the screen
TERM_ROWS=24; TERM_COLS=80
USE_COLOR=1                # the dashboard sets this to 0 for --no-color
TERM_MIN_COLS=60; TERM_MIN_ROWS=18

# term_size: set TERM_ROWS/TERM_COLS. Asks the terminal when stdout is one,
# otherwise honours exported LINES/COLUMNS, otherwise falls back to 24x80.
term_size() {
    local r c
    if [[ -t 1 ]] && read -r r c < <(stty size <&1 2>/dev/null) &&
       [[ "$r" =~ ^[1-9][0-9]*$ && "$c" =~ ^[1-9][0-9]*$ ]]; then
        TERM_ROWS=$r; TERM_COLS=$c; return 0
    fi
    if [[ "${LINES:-}" =~ ^[1-9][0-9]*$ && "${COLUMNS:-}" =~ ^[1-9][0-9]*$ ]]; then
        TERM_ROWS=$LINES; TERM_COLS=$COLUMNS; return 0
    fi
    TERM_ROWS=24; TERM_COLS=80; return 1
}

# term_big_enough: true when the window can hold the dashboard layout.
term_big_enough() { (( TERM_COLS >= TERM_MIN_COLS && TERM_ROWS >= TERM_MIN_ROWS )); }

# term_utf8: true when the locale can display the block and sparkline characters.
term_utf8() {
    local l="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    [[ "$l" == *[Uu][Tt][Ff]-8* || "$l" == *[Uu][Tt][Ff]8* ]]
}

# term_color_on: colour is on unless --no-color or the NO_COLOR convention says no.
term_color_on() { (( USE_COLOR )) && [[ -z "${NO_COLOR:-}" ]]; }

# paint LEVEL TEXT: print TEXT in the colour for LEVEL (plain text when colour is off).
paint() {
    local code=0
    case "$1" in
        ok) code=32 ;; warn) code=33 ;; crit) code=31 ;;
        info) code=36 ;; bold) code=1 ;; dim) code=2 ;;
    esac
    if (( code )) && term_color_on; then
        printf '\e[%sm%s\e[0m' "$code" "$2"
    else
        printf '%s' "$2"
    fi
}

# term_enter: switch to the alternate screen, hide the cursor, stop line wrapping.
term_enter() {
    (( TERM_ACTIVE )) && return 0
    printf '\e[?1049h\e[?25l\e[?7l\e[2J\e[H'
    TERM_ACTIVE=1
}

# term_leave: undo term_enter. Safe to call any number of times, from any trap.
term_leave() {
    (( TERM_ACTIVE )) || return 0
    printf '\e[0m\e[?7h\e[?25h\e[?1049l'
    TERM_ACTIVE=0
}

# term_frame TEXT: draw a whole frame at once. Moving home and clearing each line's
# tail (instead of clearing the screen first) is what avoids flicker.
term_frame() {
    local text=$1
    text=${text//$'\n'/$'\e[K\n'}
    printf '\e[H%s\e[K\e[J' "$text"
}
