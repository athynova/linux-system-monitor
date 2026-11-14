#!/usr/bin/env bash
# Dashboard tests (v1.2): rendering helpers, sampling, frame layout, CLI options.
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
make_sandbox
export LC_ALL=C LC_NUMERIC=C           # ASCII glyphs and "." decimals make exact comparisons possible
VERSION=test; CPU_THRESHOLD=80; RAM_THRESHOLD=85
for m in cpu_monitor memory_monitor terminal dashboard; do source "$TEST_ROOT/modules/$m.sh"; done
USE_COLOR=0; unset NO_COLOR            # after sourcing: terminal.sh sets its own default
eq() { [[ "$1" == "$2" ]] && pass "$3" || fail "$3 (got '$1', expected '$2')"; }

# --- dash_level -------------------------------------------------------------------
eq "$(dash_level 50 80)"   ok   "level: 50% of 80% threshold is ok"
eq "$(dash_level 63.9 80)" ok   "level: just under 80% of threshold is ok"
eq "$(dash_level 64 80)"   warn "level: 80% of threshold is warn"
eq "$(dash_level 79.9 80)" warn "level: just under threshold is warn"
eq "$(dash_level 80 80)"   crit "level: at threshold is crit"
eq "$(dash_level 100 80)"  crit "level: 100% is crit"

# --- dash_bar ---------------------------------------------------------------------
eq "$(dash_bar 0 10)"    "----------" "bar: 0%"
eq "$(dash_bar 50 10)"   "#####-----" "bar: 50%"
eq "$(dash_bar 100 10)"  "##########" "bar: 100%"
eq "$(dash_bar 150 10)"  "##########" "bar: above 100% is clamped"
eq "$(dash_bar -20 10)"  "----------" "bar: negative is clamped"
eq "$(dash_bar abc 10)"  "----------" "bar: non-numeric treated as 0"
ok=1; for w in 8 17 34 59; do for p in 0 3.3 49.9 50 99.5 100; do b=$(dash_bar "$p" "$w"); [[ ${#b} -eq $w ]] || ok=0; done; done
(( ok )) && pass "bar: always exactly WIDTH cells" || fail "bar: always exactly WIDTH cells"
( LC_ALL=C.UTF-8; b=$(dash_bar 50 10); [[ "$b" == "█████░░░░░" && ${#b} -eq 10 ]] ) && pass "bar: UTF-8 block characters" || fail "bar: UTF-8 block characters"
( USE_COLOR=1; unset NO_COLOR; [[ "$(dash_bar 50 10 crit)" == $'\e[31m#####\e[0m\e[2m-----\e[0m' ]] ) && pass "bar: filled part coloured by level" || fail "bar: filled part coloured by level"

# --- dash_spark -------------------------------------------------------------------
eq "$(dash_spark 5 0 50 100)"   "  _=#" "spark: padded left, 0/50/100 map to _ = #"
eq "$(dash_spark 3 0 0 0 0 100)" "__#"  "spark: only the newest WIDTH values"
eq "$(dash_spark 4)"            "    "  "spark: no values gives blanks"
eq "$(dash_spark 3 12.9 13 abc)" "_._"  "spark: decimals truncated, junk treated as 0"
( LC_ALL=C.UTF-8; [[ "$(dash_spark 3 0 50 100)" == "▁▅█" ]] ) && pass "spark: UTF-8 glyphs" || fail "spark: UTF-8 glyphs"

# --- misc helpers -----------------------------------------------------------------
eq "$(dash_gib 8000000)" 7.6 "gib: 8000000 KiB"
eq "$(dash_gib 0)" 0.0       "gib: zero"
eq "$(dash_gib 1048576)" 1.0 "gib: exactly 1 GiB"
eq "$(dash_rule 5)" "-----"  "rule: width"
DASH_HISTORY_MAX=120; arr=(); for i in $(seq 1 130); do dash_push arr "$i"; done
[[ ${#arr[@]} -eq 120 && ${arr[0]} -eq 11 && ${arr[119]} -eq 130 ]] && pass "history keeps the newest 120 samples" || fail "history keeps the newest 120 samples"

# --- sampling ---------------------------------------------------------------------
DASH_PREV_TOTAL=1000; DASH_PREV_IDLE=500
read_cpu_counters() { CPU_TOTAL=1100; CPU_IDLE=550; }
dash_sample_cpu; eq "$DASH_CPU" 50.00 "cpu delta: 50 busy of 100"
read_cpu_counters() { CPU_TOTAL=1100; CPU_IDLE=550; }                 # no movement since last sample
dash_sample_cpu; eq "$DASH_CPU" 50.00 "cpu delta: stalled counters keep the previous value"
read_cpu_counters() { CPU_TOTAL=900; CPU_IDLE=400; }                  # went backwards
dash_sample_cpu; eq "$DASH_CPU" 50.00 "cpu delta: backwards counters keep the previous value"
read_cpu_counters() { return 1; }
dash_sample_cpu; [[ $? -eq 1 ]] && pass "cpu delta: unreadable /proc/stat reported" || fail "cpu delta: unreadable /proc/stat reported"
source "$TEST_ROOT/modules/cpu_monitor.sh"                            # restore the real reader
dash_sample_mem
[[ "$DASH_RAM" =~ ^[0-9]+([.][0-9]+)?$ && $DASH_MEM_TOTAL -gt 0 && $DASH_MEM_USED -le $DASH_MEM_TOTAL ]] && pass "memory sample is sane" || fail "memory sample is sane"

dash_sample_cpu() { DASH_CPU=95.00; }; dash_sample_mem() { DASH_RAM=10.00; DASH_MEM_TOTAL=8000000; DASH_MEM_USED=800000; }
DASH_CPU_HIST=(); DASH_RAM_HIST=(); dash_sample
[[ ${#DASH_ALERTS[@]} -eq 1 && "${DASH_ALERTS[0]}" == "CPU 95.00% >= 80%" ]] && pass "alerts: only the metric over its threshold" || fail "alerts: only the metric over its threshold"
dash_sample_cpu() { DASH_CPU=5.00; }; dash_sample
[[ ${#DASH_ALERTS[@]} -eq 0 ]] && pass "alerts: cleared when back to normal" || fail "alerts: cleared when back to normal"

# --- frame layout -----------------------------------------------------------------
too_wide=0
for cols in 60 80 100 140; do
    TERM_COLS=$cols; TERM_ROWS=30; DASH_CPU_HIST=(5 20 90); DASH_RAM_HIST=(10 11 12); DASH_CPU=95.00; dash_sample_cpu() { DASH_CPU=95.00; }; dash_sample
    max=$(dash_build_frame | awk '{ if (length($0) > m) m = length($0) } END { print m }')
    (( max <= cols - 1 )) || too_wide=1
done
(( too_wide == 0 )) && pass "no line wider than the terminal (60-140 columns)" || fail "no line wider than the terminal"
TERM_COLS=80; frame=$(dash_build_frame)
[[ "$frame" == *"Linux System Monitor test"* && "$frame" == *" CPU  ["* && "$frame" == *" RAM  ["* && "$frame" == *"WARNING: CPU 95.00% >= 80%"* ]] \
    && pass "frame has header, CPU, RAM and the warning status" || fail "frame has header, CPU, RAM and the warning status"
dash_sample_cpu() { DASH_CPU=5.00; }; dash_sample; frame=$(dash_build_frame)
[[ "$frame" == *"Status: NORMAL"* ]] && pass "frame shows NORMAL when nothing is over threshold" || fail "frame shows NORMAL when nothing is over threshold"
DASH_ALERTS=("CPU 95% >= 80%"); ( USE_COLOR=1; unset NO_COLOR; [[ "$(dash_build_frame)" == *$'\e[31m'* ]] ) && pass "frame uses colour when enabled" || fail "frame uses colour when enabled"
bars=$(dash_build_frame | grep -E '^ (CPU|RAM) ' | awk '{ print index($0, "]") }' | sort -u | wc -l)
[[ $bars -eq 1 ]] && pass "CPU and RAM bars line up" || fail "CPU and RAM bars line up"

# --- command line (real monitor.sh in the sandbox) --------------------------------
write_conf 'MONITOR_INTERVAL=1\n'
export COLUMNS=80 LINES=24
run_app --dashboard --frames 2 --refresh 0.3 --no-color
[[ $RC -eq 0 && "$OUT" == *"=== frame 1 ==="* && "$OUT" == *"=== frame 2 ==="* && "$OUT" == *" CPU  ["* ]] \
    && pass "--dashboard --frames 2 draws two frames and exits 0" || fail "--dashboard --frames 2 (rc=$RC)"
[[ "$OUT" != *$'\e'* ]] && pass "captured output contains no escape codes" || fail "captured output contains no escape codes"
run_app --dashboard;                      [[ $RC -eq 2 && "$OUT" == *"needs a terminal"* ]] && pass "--dashboard without a terminal or --frames is refused" || fail "--dashboard without a terminal is refused"
run_app --dashboard --frames 1 --refresh 0.1; [[ $RC -eq 2 ]] && pass "--refresh below 0.2 rejected" || fail "--refresh below 0.2 rejected"
run_app --dashboard --frames 1 --refresh 61;  [[ $RC -eq 2 ]] && pass "--refresh above 60 rejected" || fail "--refresh above 60 rejected"
run_app --dashboard --frames 1 --refresh abc; [[ $RC -eq 2 ]] && pass "--refresh abc rejected" || fail "--refresh abc rejected"
run_app --dashboard --frames abc;             [[ $RC -eq 2 ]] && pass "--frames abc rejected" || fail "--frames abc rejected"
run_app --dashboard --frames 0 --refresh 1;   [[ $RC -eq 2 ]] && pass "--frames 0 without a terminal rejected" || fail "--frames 0 without a terminal rejected"
run_app --refresh 1;                          [[ $RC -eq 2 && "$OUT" == *"need --dashboard"* ]] && pass "--refresh without --dashboard rejected" || fail "--refresh without --dashboard rejected"
run_app --dashboard --continuous --frames 1;  [[ $RC -eq 2 ]] && pass "--dashboard with --continuous rejected" || fail "--dashboard with --continuous rejected"
run_app --help; [[ "$OUT" == *"--dashboard"* ]] && pass "--help documents --dashboard" || fail "--help documents --dashboard"

finish
