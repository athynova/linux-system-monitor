#!/usr/bin/env bash
# Interactive terminal dashboard (v1.2): live CPU and RAM bars with history sparklines.
# Rendering functions only print text; sampling functions only set DASH_* variables.
# Needs terminal.sh, cpu_monitor.sh and memory_monitor.sh to be sourced first.

DASH_REFRESH=2            # seconds between frames (may be fractional)
DASH_HISTORY_MAX=120      # samples kept for the sparklines
DASH_CPU=0; DASH_RAM=0
DASH_MEM_TOTAL=0; DASH_MEM_USED=0
DASH_PREV_TOTAL=0; DASH_PREV_IDLE=0
DASH_HOST=localhost
DASH_STATE=LIVE
DASH_PAUSED=0; DASH_HELP=0
DASH_REFRESH_US=2000000   # DASH_REFRESH in microseconds
DASH_DEADLINE=0           # when the next sample is due (microseconds since the epoch)
DASH_RESIZED=0            # set by the SIGWINCH trap
DASH_KEY=""
declare -a DASH_CPU_HIST=() DASH_RAM_HIST=()
declare -a DASH_ALERTS=()
declare -a DASH_DISKS=()      # "mount<TAB>percent<TAB>used_kib<TAB>total_kib"
declare -a DASH_PROCS=()      # "pid cpu mem command..."
DASH_SORT=cpu                 # cpu | mem
DASH_N_DISKS=0; DASH_N_PROCS=5

# ---- pure rendering helpers ---------------------------------------------------------

# dash_level PERCENT THRESHOLD -> ok | warn (>= 80% of threshold) | crit (>= threshold)
dash_level() {
    awk -v p="${1:-0}" -v t="${2:-100}" 'BEGIN { if (p >= t) print "crit"; else if (p >= t*0.8) print "warn"; else print "ok" }'
}

# dash_bar PERCENT WIDTH [LEVEL] -> a bar exactly WIDTH cells wide
dash_bar() {
    local pct=$1 width=$2 level=${3:-none} filled i full empty fill_s="" empty_s=""
    filled=$(awk -v p="$pct" -v w="$width" 'BEGIN { p += 0; if (p < 0) p = 0; if (p > 100) p = 100; printf "%d", (p / 100 * w) + 0.5 }')
    (( filled > width )) && filled=$width
    if term_utf8; then full='█'; empty='░'; else full='#'; empty='-'; fi
    for ((i = 0; i < filled; i++)); do fill_s+=$full; done
    for ((i = filled; i < width; i++)); do empty_s+=$empty; done
    paint "$level" "$fill_s"; paint dim "$empty_s"
}

# dash_spark WIDTH VALUES... -> sparkline of the last WIDTH values (0-100), newest on the right
dash_spark() {
    local width=$1; shift
    local -a vals=("$@") glyphs
    local n=${#vals[@]} start=0 i v idx out=""
    if term_utf8; then glyphs=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █); else glyphs=(_ . - : = + '*' '#'); fi
    (( n > width )) && start=$((n - width))
    for ((i = start; i < n; i++)); do
        v=${vals[i]%%.*}; [[ "$v" =~ ^[0-9]+$ ]] || v=0
        idx=$(( v * 8 / 100 )); (( idx > 7 )) && idx=7
        out+=${glyphs[idx]}
    done
    printf '%*s%s' $((width - (n - start))) '' "$out"
}

# dash_gib KIB -> "x.y" GiB using integer maths (no forks)
dash_gib() { local t=$(( ${1:-0} * 10 / 1048576 )); printf '%d.%d' $((t / 10)) $((t % 10)); }

# dash_rule -> a horizontal rule as wide as the usable area
dash_rule() {
    local w=$1 ch='-' out
    term_utf8 && ch='─'
    printf -v out '%*s' "$w" ''
    printf '%s' "${out// /$ch}"
}

# dash_trunc_left TEXT WIDTH -> TEXT, or "..." plus its tail when too long (paths matter at the end)
dash_trunc_left() {
    local t=$1 w=$2
    if (( ${#t} <= w )); then printf '%s' "$t"
    elif (( w > 3 )); then printf '...%s' "${t: -$((w - 3))}"
    else printf '%s' "${t: -w}"
    fi
}

# dash_push ARRAY_NAME VALUE -> append and keep only the newest DASH_HISTORY_MAX values
dash_push() {
    local -n _dash_arr=$1          # unusual name: a caller's own variable can never clash with it
    _dash_arr+=("$2")
    (( ${#_dash_arr[@]} > DASH_HISTORY_MAX )) && _dash_arr=("${_dash_arr[@]: -DASH_HISTORY_MAX}")
    return 0
}

# ---- sampling -------------------------------------------------------------------------

# dash_sample_cpu: percent busy since the previous call (never blocks, unlike get_cpu_usage)
dash_sample_cpu() {
    local td id
    read_cpu_counters || return 1
    td=$((CPU_TOTAL - DASH_PREV_TOTAL)); id=$((CPU_IDLE - DASH_PREV_IDLE))
    if (( td > 0 && id >= 0 && id <= td )); then
        DASH_CPU=$(awk -v b="$((td - id))" -v t="$td" 'BEGIN { printf "%.2f", (b / t) * 100 }')
    fi   # otherwise keep the previous value
    DASH_PREV_TOTAL=$CPU_TOTAL; DASH_PREV_IDLE=$CPU_IDLE
}

dash_sample_mem() {
    local out k v
    out=$(get_memory_metrics) || return 1
    while IFS== read -r k v; do
        case $k in
            MEM_TOTAL_KIB) DASH_MEM_TOTAL=$v ;;
            MEM_USED_KIB)  DASH_MEM_USED=$v ;;
            MEM_PERCENT)   DASH_RAM=$v ;;
        esac
    done <<< "$out"
}

# dash_sample_disks: real filesystems only, one row per device (bind mounts and
# btrfs subvolumes would otherwise repeat), zero-size entries dropped.
dash_sample_disks() {
    local dev mount total used pct
    local -A seen=()
    DASH_DISKS=()
    while IFS=$'\t' read -r dev mount total used pct; do
        [[ -n "${seen[$dev]:-}" ]] && continue
        seen[$dev]=1
        [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
        DASH_DISKS+=("${mount}"$'\t'"${pct}"$'\t'"${used}"$'\t'"${total}")
    done < <(df -PkT -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x ramfs 2>/dev/null |
        awk 'NR > 1 && $3 + 0 > 0 { m = $7; for (i = 8; i <= NF; i++) m = m " " $i; p = $6; sub(/%/, "", p);
             printf "%s\t%s\t%s\t%s\t%s\n", $1, m, $3, $4, p }')
}

# dash_layout: split the spare rows between the disk and process panels
dash_layout() {
    local avail=$(( TERM_ROWS - 12 )) nd=${#DASH_DISKS[@]} lines
    (( avail < 4 )) && avail=4
    DASH_N_DISKS=$nd
    (( DASH_N_DISKS > 4 )) && DASH_N_DISKS=4
    (( DASH_N_DISKS > avail - 3 )) && DASH_N_DISKS=$(( avail - 3 ))
    lines=$DASH_N_DISKS; (( lines < 1 )) && lines=1          # "no filesystems" still uses a row
    DASH_N_PROCS=$(( avail - lines )); (( DASH_N_PROCS > 15 )) && DASH_N_PROCS=15
}

# dash_sample_procs: top DASH_N_PROCS processes by the current sort key
dash_sample_procs() {
    local key='-%cpu'
    [[ $DASH_SORT == mem ]] && key='-%mem'
    DASH_PROCS=()
    mapfile -t DASH_PROCS < <(ps -eo pid=,%cpu=,%mem=,comm= --sort="$key" 2>/dev/null | select_process_rows "$DASH_N_PROCS")
}

# dash_sample: take one sample of everything and update histories and alerts
dash_sample() {
    local row mount pct
    dash_sample_cpu; dash_sample_mem; dash_sample_disks
    dash_layout; dash_sample_procs
    dash_push DASH_CPU_HIST "$DASH_CPU"; dash_push DASH_RAM_HIST "$DASH_RAM"
    DASH_ALERTS=()
    [[ $(dash_level "$DASH_CPU" "$CPU_THRESHOLD") == crit ]] && DASH_ALERTS+=("CPU ${DASH_CPU}% >= ${CPU_THRESHOLD}%")
    [[ $(dash_level "$DASH_RAM" "$RAM_THRESHOLD") == crit ]] && DASH_ALERTS+=("RAM ${DASH_RAM}% >= ${RAM_THRESHOLD}%")
    for row in "${DASH_DISKS[@]}"; do
        IFS=$'\t' read -r mount pct _ <<< "$row"
        [[ $(dash_level "$pct" "$DISK_THRESHOLD") == crit ]] && DASH_ALERTS+=("DISK ${mount} ${pct}% >= ${DISK_THRESHOLD}%")
    done
    return 0
}

# ---- frame sections (each prints complete lines, none wider than $1 cells) ----------------

dash_section_header() {
    local w=$1 base right now room host="" left pad
    printf -v now '%(%H:%M:%S)T' -1
    base=" Linux System Monitor ${VERSION}"
    right="${DASH_STATE}  refresh ${DASH_REFRESH}s  ${now} "
    (( ${#base} + ${#right} + 1 > w )) && right="${DASH_STATE}  ${DASH_REFRESH}s  ${now} "   # narrow window
    room=$(( w - ${#base} - ${#right} - 3 ))   # 2 spaces before the host + 1 minimum gap
    (( room >= 3 )) && host="  ${DASH_HOST:0:room}"
    left="$base$host"
    pad=$(( w - ${#left} - ${#right} )); (( pad < 1 )) && pad=1
    printf '%s%*s%s\n' "$(paint bold "$left")" "$pad" '' "$(paint info "$right")"
    printf ' %s\n' "$(dash_rule $((w - 1)))"
}

# dash_meter LABEL PERCENT THRESHOLD EXTRA HISTORY_ARRAY_NAME WIDTH
dash_meter() {
    local label=$1 pct=$2 thr=$3 extra=$4 hist_name=$5 w=$6
    local -n _dash_hist=$hist_name
    local level suffix bw
    level=$(dash_level "$pct" "$thr")
    printf -v suffix ' %5.1f%%%s  thr %d%%' "$pct" "$extra" "$thr"
    printf -v suffix '%-34s' "$suffix"          # fixed width so every bar lines up
    bw=$(( w - 8 - ${#suffix} )); (( bw < 8 )) && bw=8
    printf ' %-4s [%s]%s\n' "$label" "$(dash_bar "$pct" "$bw" "$level")" "$(paint "$level" "$suffix")"
    printf '      %s\n' "$(paint info "$(dash_spark $((w - 7)) "${_dash_hist[@]}")")"
}

dash_section_cpu() { dash_meter CPU "$DASH_CPU" "$CPU_THRESHOLD" "" DASH_CPU_HIST "$1"; }
dash_section_ram() {
    dash_meter RAM "$DASH_RAM" "$RAM_THRESHOLD" "  $(dash_gib "$DASH_MEM_USED")/$(dash_gib "$DASH_MEM_TOTAL") GiB" DASH_RAM_HIST "$1"
}

dash_section_disks() {
    local w=$1 i row mount pct used total level suffix bw
    printf ' %s\n' "$(paint bold "DISKS")"
    if (( ${#DASH_DISKS[@]} == 0 )); then printf ' %s\n' "$(paint dim "(no filesystems found)")"; return; fi
    for ((i = 0; i < DASH_N_DISKS; i++)); do
        IFS=$'\t' read -r mount pct used total <<< "${DASH_DISKS[i]}"
        level=$(dash_level "$pct" "$DISK_THRESHOLD")
        printf -v suffix ' %3d%%  %s/%s GiB' "$pct" "$(dash_gib "$used")" "$(dash_gib "$total")"
        printf -v suffix '%-26s' "$suffix"
        bw=$(( w - 18 - ${#suffix} )); (( bw < 8 )) && bw=8
        printf ' %-14s [%s]%s\n' "$(dash_trunc_left "$mount" 14)" "$(dash_bar "$pct" "$bw" "$level")" "$(paint "$level" "$suffix")"
    done
}

dash_section_procs() {
    local w=$1 cw=$(( $1 - 24 )) row pid cpu mem comm cpuh='CPU%' memh='MEM%'
    (( cw > 30 )) && cw=30; (( cw < 8 )) && cw=8
    [[ $DASH_SORT == mem ]] && memh='MEM%v' || cpuh='CPU%v'
    printf ' %s\n' "$(paint bold "PROCESSES  (sorted by ${DASH_SORT^^})")"
    printf ' %s\n' "$(paint dim "$(printf '%-8s %-*s %6s %6s' PID "$cw" COMMAND "$cpuh" "$memh")")"
    for row in "${DASH_PROCS[@]}"; do
        read -r pid cpu mem comm <<< "$row"
        printf ' %-8s %-*.*s %6s %6s\n' "$pid" "$cw" "$cw" "$comm" "$cpu" "$mem"
    done
}

dash_section_help() {
    printf ' %s\n' "$(paint bold "KEYS")"
    printf '   %-10s %s\n' q "quit" p "pause / resume" c "sort processes by CPU" m "sort processes by memory" \
        '+  or  =' "refresh faster" '-' "refresh slower" h "close this help"
    printf '\n %s\n' "Bars: green = normal, yellow = within 20% of the threshold,"
    printf ' %s\n' "red = at or above it. Thresholds come from config/monitor.conf."
    printf ' %s\n' "Ctrl+C also quits."
}

dash_section_footer() {
    local w=$1 status
    if (( ${#DASH_ALERTS[@]} )); then
        status=$(paint crit "WARNING: ${DASH_ALERTS[*]}")
    else
        status=$(paint ok "NORMAL")
    fi
    printf ' %s\n' "$(dash_rule $((w - 1)))"
    printf ' Status: %s\n' "$status"
    printf ' %s\n' "$(paint dim "q quit  p pause  c/m sort  +/- speed  h help")"
}

# dash_build_frame -> the whole frame as text, sized for the current terminal
dash_build_frame() {
    local w=$(( TERM_COLS - 1 ))
    dash_section_header "$w"
    if (( DASH_HELP )); then dash_section_help; dash_section_footer "$w"; return; fi
    dash_section_cpu "$w"
    dash_section_ram "$w"
    dash_section_disks "$w"
    dash_section_procs "$w"
    dash_section_footer "$w"
}

# ---- keyboard ---------------------------------------------------------------------------

# dash_set_refresh SECONDS: change the refresh interval; the next sample is due that long from now
dash_set_refresh() {
    DASH_REFRESH=$1
    DASH_REFRESH_US=$(awk -v r="$1" 'BEGIN { printf "%d", r * 1000000 }')
    DASH_DEADLINE=$(( ${EPOCHREALTIME/./} + DASH_REFRESH_US ))
}

# dash_step_refresh faster|slower: move to the next preset interval
dash_step_refresh() {
    local new
    new=$(awk -v cur="$DASH_REFRESH" -v dir="$1" -v list="0.2 0.5 1 2 3 5 10 30 60" 'BEGIN {
        n = split(list, a, " "); new = cur
        if (dir == "faster") { for (i = n; i >= 1; i--) if (a[i] + 0 < cur + 0) { new = a[i]; break } }
        else                 { for (i = 1; i <= n; i++) if (a[i] + 0 > cur + 0) { new = a[i]; break } }
        print new }')
    dash_set_refresh "$new"
}

# dash_wait_key SECONDS: wait for a key or the timeout; sets DASH_KEY ("" when none).
# Bash's "read -t" is NOT interrupted by a trapped signal, so the wait is cut into slices
# of at most 0.2 s and a stop request (Ctrl+C, kill) or a window resize is noticed between
# slices. That keeps Ctrl+C and resizing responsive even with a 60 s refresh interval.
dash_wait_key() {
    local k rest rc end now left slice s
    DASH_KEY=""
    end=$(( ${EPOCHREALTIME/./} + $(awk -v s="$1" 'BEGIN { printf "%d", s * 1000000 }') ))
    while :; do
        stop_requested && return 0
        (( DASH_RESIZED )) && return 0
        now=${EPOCHREALTIME/./}; left=$(( end - now ))
        (( left <= 0 )) && return 0
        slice=$(( left > 200000 ? 200000 : left ))
        printf -v s '%d.%06d' $(( slice / 1000000 )) $(( slice % 1000000 ))
        IFS= read -rsn1 -t "$s" k 2>/dev/null; rc=$?
        if (( rc == 0 )); then
            if [[ $k == $'\e' ]]; then IFS= read -rsn2 -t 0.01 rest 2>/dev/null; k=ESC; fi   # arrow keys etc: ignored
            DASH_KEY=$k
            return 0
        elif (( rc == 1 )); then
            interruptible_sleep "$s"    # no input available at all (EOF): still wait, never spin
        fi                              # rc > 128: this slice timed out; keep waiting
    done
}

# dash_handle_key KEY: return 1 to quit, 0 to carry on
dash_handle_key() {
    case "$1" in
        q|Q) return 1 ;;
        p|P) if (( DASH_PAUSED )); then
                 DASH_PAUSED=0; DASH_STATE=LIVE
                 read_cpu_counters && { DASH_PREV_TOTAL=$CPU_TOTAL; DASH_PREV_IDLE=$CPU_IDLE; }   # no pause-long average
                 dash_set_refresh "$DASH_REFRESH"
             else
                 DASH_PAUSED=1; DASH_STATE=PAUSED
             fi ;;
        c|C) DASH_SORT=cpu; dash_sample_procs ;;
        m|M) DASH_SORT=mem; dash_sample_procs ;;
        +|=) dash_step_refresh faster ;;
        -|_) dash_step_refresh slower ;;
        h|H|'?') DASH_HELP=$(( 1 - DASH_HELP )) ;;
    esac
    return 0
}

# ---- main loop ----------------------------------------------------------------------------

dash_small_frame() {
    printf ' Terminal too small: %dx%d\n Needs at least %dx%d.\n Resize the window, or press q to quit.\n' \
        "$TERM_COLS" "$TERM_ROWS" "$TERM_MIN_COLS" "$TERM_MIN_ROWS"
}

# run_dashboard REFRESH FRAMES   (FRAMES=0 means run until quit or stopped)
run_dashboard() {
    local max_frames=$2 frame_no=0 frame interactive=0 now wait_us wait_s
    DASH_REFRESH=$1; DASH_PAUSED=0; DASH_HELP=0; DASH_STATE=LIVE
    [[ -t 1 ]] && interactive=1
    DASH_HOST=$(hostname 2>/dev/null) || DASH_HOST=localhost
    DASH_HOST=${DASH_HOST%%.*}
    STOP_UNIT=frame
    term_size
    if (( interactive )) && ! term_big_enough; then
        echo "Error: Terminal too small (${TERM_COLS}x${TERM_ROWS}); the dashboard needs at least ${TERM_MIN_COLS}x${TERM_MIN_ROWS}." >&2
        return 2
    fi
    read_cpu_counters || { echo "Error: Cannot read /proc/stat." >&2; return 1; }
    DASH_PREV_TOTAL=$CPU_TOTAL; DASH_PREV_IDLE=$CPU_IDLE
    DASH_REFRESH_US=$(awk -v r="$DASH_REFRESH" 'BEGIN { printf "%d", r * 1000000 }')
    DASH_DEADLINE=0
    if (( interactive )); then
        trap 'DASH_RESIZED=1' WINCH       # noticed between wait slices, so we redraw within 0.2 s
        term_enter
    fi
    interruptible_sleep 0.25              # the first frame needs a CPU delta to show
    while true; do
        stop_requested && { term_leave; graceful_stop; }
        now=${EPOCHREALTIME/./}
        if (( ! DASH_PAUSED && now >= DASH_DEADLINE )); then
            dash_sample
            DASH_DEADLINE=$(( now + DASH_REFRESH_US ))
        fi
        (( interactive )) && term_size
        if (( interactive )) && ! term_big_enough; then frame=$(dash_small_frame); else frame=$(dash_build_frame); fi
        frame_no=$(( frame_no + 1 )); CYCLES_COMPLETED=$frame_no
        if (( interactive )); then
            term_frame "$frame"
        else
            printf '=== frame %d ===\n%s\n' "$frame_no" "$frame"
        fi
        (( max_frames > 0 && frame_no >= max_frames )) && break
        if (( DASH_PAUSED )); then
            wait_s=1
        else
            wait_us=$(( DASH_DEADLINE - ${EPOCHREALTIME/./} )); (( wait_us < 1000 )) && wait_us=1000
            printf -v wait_s '%d.%06d' $(( wait_us / 1000000 )) $(( wait_us % 1000000 ))
        fi
        dash_wait_key "$wait_s"
        DASH_RESIZED=0
        stop_requested && { term_leave; graceful_stop; }
        if [[ -n "$DASH_KEY" ]]; then
            dash_handle_key "$DASH_KEY" || break
        fi
    done
    (( interactive )) && trap - WINCH
    term_leave
    return 0
}
