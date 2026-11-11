#!/usr/bin/env bash
# Shared helpers for the v1.1 tests. Source this file; do not execute it.
# Each test works on a throw-away copy of the application, so tests never
# touch your real logs/, reports/, data/ or config/ directories.

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS+1)); }

# check "description" command [args...]  -> PASS if the command succeeds
check() { local name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

# make_sandbox: copy the application into a temp dir.
# Sets SANDBOX (temp dir) and APP (the copied application root).
make_sandbox() {
    SANDBOX=$(mktemp -d) || exit 1
    APP="$SANDBOX/app"
    mkdir -p "$APP"
    cp -r "$TEST_ROOT/monitor.sh" "$TEST_ROOT/modules" "$TEST_ROOT/config" "$APP/"
    trap 'rm -rf "$SANDBOX"' EXIT
}

# write_conf "line1\nline2" : replace the sandbox config (printf %b escapes allowed)
write_conf() { printf '%b' "$1" > "$APP/config/monitor.conf"; }

# run_app args... : run the sandbox monitor, capturing stdout+stderr in OUT and status in RC
run_app() { OUT=$("$APP/monitor.sh" "$@" 2>&1); RC=$?; }

finish() {
    echo "Test summary: $FAILS failure(s)"
    (( FAILS == 0 ))
}
