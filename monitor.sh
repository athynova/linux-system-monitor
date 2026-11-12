#!/usr/bin/env bash
set -uo pipefail
VERSION="1.1.2"
export LC_NUMERIC=C   # CSV and awk output must always use "." as the decimal separator
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$ROOT/config/monitor.conf"
LOG_DIR="$ROOT/logs"; REPORT_DIR="$ROOT/reports"; EVENT_LOG="$LOG_DIR/monitor.log"
DATA_DIR="$ROOT/data"; HISTORY_FILE="$DATA_DIR/history.csv"

for name in system_info cpu_monitor memory_monitor disk_monitor process_monitor alert_manager report_manager history_manager terminal; do
    f="$ROOT/modules/${name}.sh"
    [[ -r "$f" ]] || { echo "Error: Missing module $f" >&2; exit 1; }
    source "$f"
done

usage() {
cat <<'EOF'
Linux System Monitoring Tool
Usage: ./monitor.sh [options]
  --interval SECONDS  CPU sample interval, 1-60 (default 1)
  --mount PATH        Filesystem path to inspect (default /)
  --top NUMBER        Processes per list, 1-20 (default from config)
  --continuous        Repeat using MONITOR_INTERVAL from config
  --show-history N    Print the last N recorded history rows (1-1000) and exit
  --help              Show this help
  --version           Show the version
Examples:
  ./monitor.sh
  ./monitor.sh --interval 2 --top 3
  ./monitor.sh --mount /home
  ./monitor.sh --continuous
  ./monitor.sh --show-history 20
EOF
}
error() { echo "Error: $1" >&2; exit 2; }

# Documented defaults are retained if an optional setting is omitted.
CPU_THRESHOLD=80
RAM_THRESHOLD=85
DISK_THRESHOLD=90
MONITOR_INTERVAL=5
TOP_PROCESS_COUNT=5
HISTORY_ENABLED=true
HISTORY_MAX_ROWS=100000

# Trim leading/trailing whitespace of $1 into TRIMMED (no subshell needed).
trim() {
    TRIMMED=$1
    TRIMMED=${TRIMMED#"${TRIMMED%%[![:space:]]*}"}
    TRIMMED=${TRIMMED%"${TRIMMED##*[![:space:]]}"}
}
load_config() {
    local line key value lineno=0 seen=" "
    [[ -r "$CONFIG" ]] || error "Configuration missing or unreadable: $CONFIG"
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno+1))
        line=${line//$'\r'/}                      # tolerate Windows line endings
        ((lineno==1)) && line=${line#$'\xef\xbb\xbf'}  # tolerate a UTF-8 BOM
        trim "$line"; line=$TRIMMED
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || error "Config line $lineno is malformed (expected KEY=VALUE)."
        key=${line%%=*}; value=${line#*=}
        trim "$key"; key=$TRIMMED
        value=${value%%[[:space:]]#*}               # allow a trailing "# comment"
        trim "$value"; value=$TRIMMED
        [[ "$seen" == *" $key "* ]] && error "Config line $lineno: duplicate setting $key."
        seen+="$key "
        case "$key" in
            CPU_THRESHOLD) CPU_THRESHOLD=$value ;;
            RAM_THRESHOLD) RAM_THRESHOLD=$value ;;
            DISK_THRESHOLD) DISK_THRESHOLD=$value ;;
            MONITOR_INTERVAL) MONITOR_INTERVAL=$value ;;
            TOP_PROCESS_COUNT) TOP_PROCESS_COUNT=$value ;;
            HISTORY_ENABLED) HISTORY_ENABLED=$value ;;
            HISTORY_MAX_ROWS) HISTORY_MAX_ROWS=$value ;;
            *) error "Config line $lineno: unknown setting '$key'." ;;
        esac
    done < "$CONFIG"
}
validate_config() {
    local key value
    for key in CPU_THRESHOLD RAM_THRESHOLD DISK_THRESHOLD; do
        value=${!key}
        [[ "$value" =~ ^([0-9]{1,2}|100)$ ]] || error "$key must be 0-100."
    done
    [[ "$MONITOR_INTERVAL" =~ ^[1-9][0-9]*$ ]] && (( MONITOR_INTERVAL <= 3600 )) || error "MONITOR_INTERVAL must be 1-3600."
    [[ "$TOP_PROCESS_COUNT" =~ ^[1-9][0-9]*$ ]] && (( TOP_PROCESS_COUNT <= 20 )) || error "TOP_PROCESS_COUNT must be 1-20."
    [[ "$HISTORY_ENABLED" == true || "$HISTORY_ENABLED" == false ]] || error "HISTORY_ENABLED must be true or false."
    [[ "$HISTORY_MAX_ROWS" =~ ^[1-9][0-9]*$ ]] && (( HISTORY_MAX_ROWS >= 100 && HISTORY_MAX_ROWS <= 1000000 )) || error "HISTORY_MAX_ROWS must be 100-1000000."
}
# ---- Graceful shutdown ------------------------------------------------------
# SIGINT (Ctrl+C) and SIGTERM only set a flag; the main loop stops at a safe
# point, logs the stop, and exits with 130 (INT) or 143 (TERM).
SHUTDOWN_SIGNAL=""
CYCLES_COMPLETED=0
on_signal() { SHUTDOWN_SIGNAL=$1; }
stop_requested() { [[ -n "$SHUTDOWN_SIGNAL" ]]; }
cleanup() { term_leave 2>/dev/null; rm -f -- "${HISTORY_FILE}.tmp.$$" 2>/dev/null; }
graceful_stop() {
    local code=130
    [[ "$SHUTDOWN_SIGNAL" == TERM ]] && code=143
    printf '\nMonitor stopped by SIG%s after %d completed cycle(s).\n' "$SHUTDOWN_SIGNAL" "$CYCLES_COMPLETED" >&2
    mkdir -p "$LOG_DIR" 2>/dev/null
    printf '[%s] Monitor stopped by SIG%s. Cycles completed=%d\n' "$(date '+%F %T')" "$SHUTDOWN_SIGNAL" "$CYCLES_COMPLETED" >> "$EVENT_LOG" 2>/dev/null
    exit "$code"
}
# Sleep that a signal can interrupt immediately (plain "sleep" would delay the trap).
interruptible_sleep() {
    local pid
    sleep "$1" & pid=$!
    wait "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 0
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap cleanup EXIT

run_cycle() {
    local interval="$1" mount="$2" count="$3" cpu mem disk ram_pct disk_pct report saved status=NORMAL
    local warning_count=0 rc history_note=""
    local -a warnings=()
    cpu=$(get_cpu_usage "$interval") || return 1
    mem=$(get_memory_metrics) || return 1
    disk=$(get_disk_metrics "$mount") || return $?
    ram_pct=$(awk -F= '$1=="MEM_PERCENT"{print $2}' <<< "$mem")
    disk_pct=$(awk -F= '$1=="DISK_PERCENT"{print $2}' <<< "$disk")
    mkdir -p "$LOG_DIR" "$REPORT_DIR" || return 1

    check_threshold CPU "$cpu" "$CPU_THRESHOLD" "$EVENT_LOG" || {
        rc=$?; if ((rc==1)); then warnings+=("CPU ${cpu}% >= ${CPU_THRESHOLD}%"); warning_count=$((warning_count+1)); else return "$rc"; fi
    }
    check_threshold RAM "$ram_pct" "$RAM_THRESHOLD" "$EVENT_LOG" || {
        rc=$?; if ((rc==1)); then warnings+=("RAM ${ram_pct}% >= ${RAM_THRESHOLD}%"); warning_count=$((warning_count+1)); else return "$rc"; fi
    }
    check_threshold DISK "$disk_pct" "$DISK_THRESHOLD" "$EVENT_LOG" || {
        rc=$?; if ((rc==1)); then warnings+=("DISK ${disk_pct}% >= ${DISK_THRESHOLD}%"); warning_count=$((warning_count+1)); else return "$rc"; fi
    }
    (( warning_count > 0 )) && status=WARNING

    # Record history before building the report so a report failure cannot lose the sample.
    if [[ "$HISTORY_ENABLED" == true ]]; then
        if history_append "$HISTORY_FILE" "$cpu" "$ram_pct" "$disk_pct" "$mount" "$status" "$HISTORY_MAX_ROWS"; then
            history_note="History recorded: $HISTORY_FILE"
        else
            echo "Warning: could not record history to $HISTORY_FILE." >&2
            printf '[%s] WARNING: history write failed (%s).\n' "$(date '+%F %T')" "$HISTORY_FILE" >> "$EVENT_LOG" 2>/dev/null
        fi
    fi

    report="$(cat <<EOF
============================================================
LINUX SYSTEM MONITORING REPORT
============================================================
$(get_system_info)

===== CPU =====
CPU utilization: ${cpu}%
CPU threshold: ${CPU_THRESHOLD}%

===== MEMORY =====
$(awk -F= '
$1=="MEM_TOTAL_KIB"{t=$2} $1=="MEM_USED_KIB"{u=$2}
$1=="MEM_AVAILABLE_KIB"{a=$2} $1=="MEM_PERCENT"{p=$2}
END {printf "Total: %.2f GiB\nUsed: %.2f GiB\nAvailable: %.2f GiB\nUsage: %s%%\n",t/1048576,u/1048576,a/1048576,p}
' <<< "$mem")
RAM threshold: ${RAM_THRESHOLD}%

===== DISK =====
$(awk -F= '
$1=="DISK_FILESYSTEM"{f=$2} $1=="DISK_MOUNT"{m=$2}
$1=="DISK_TOTAL_KIB"{t=$2} $1=="DISK_USED_KIB"{u=$2}
$1=="DISK_AVAILABLE_KIB"{a=$2} $1=="DISK_PERCENT"{p=$2}
END {printf "Filesystem: %s\nMount: %s\nTotal: %.2f GiB\nUsed: %.2f GiB\nAvailable: %.2f GiB\nUsage: %s%%\n",f,m,t/1048576,u/1048576,a/1048576,p}
' <<< "$disk")
Disk threshold: ${DISK_THRESHOLD}%

===== TOP ${count} CPU PROCESSES =====
$(get_top_cpu_processes "$count")

===== TOP ${count} MEMORY PROCESSES =====
$(get_top_memory_processes "$count")

===== ALERTS =====
$([[ $warning_count -eq 0 ]] && echo "No threshold warnings." || printf '%s\n' "${warnings[@]}")
Overall status: ${status}
============================================================
EOF
)"
    # Ctrl+C during report assembly kills the substitution above and can leave the
    # report empty or cut short. Never save or print a partial report: abandon quietly.
    # (A complete report always ends with the status line and the closing rule.)
    if [[ "$report" != *"Overall status: ${status}"$'\n'"============================================================" ]]; then
        return 1
    fi
    printf '%s\n' "$report"
    saved=$(save_report "$report" "$REPORT_DIR") || return 1
    printf '\nReport saved: %s\n' "$saved"
    [[ -z "$history_note" ]] || printf '%s\n' "$history_note"
    printf '[%s] Monitoring cycle completed. Status=%s\n' "$(date '+%F %T')" "$status" >> "$EVENT_LOG" ||
        echo "Warning: event log could not be written." >&2
}
main() {
    local interval=1 mount=/ continuous=0 count="" show_history="" rc=0
    # Arguments are parsed first so --help works even if the config is broken.
    while (($#)); do
        case "$1" in
            --help) usage; return 0 ;;
            --version) echo "Linux System Monitoring Tool $VERSION"; return 0 ;;
            --interval) (($#>=2)) || error "--interval needs a value"; interval=$2; shift 2 ;;
            --mount) (($#>=2)) || error "--mount needs a path"; mount=$2; shift 2 ;;
            --top) (($#>=2)) || error "--top needs a value"; count=$2; shift 2 ;;
            --continuous) continuous=1; shift ;;
            --show-history) (($#>=2)) || error "--show-history needs a value"; show_history=$2; shift 2 ;;
            *) error "Unknown option: $1 (use --help)" ;;
        esac
    done
    load_config; validate_config
    if [[ -n "$show_history" ]]; then
        [[ "$show_history" =~ ^[1-9][0-9]{0,3}$ ]] && ((show_history<=1000)) || error "--show-history must be 1-1000."
        history_show "$HISTORY_FILE" "$show_history"
        return $?
    fi
    [[ -n "$count" ]] || count=$TOP_PROCESS_COUNT
    [[ "$interval" =~ ^[1-9][0-9]*$ ]] && ((interval<=60)) || error "--interval must be 1-60."
    [[ "$count" =~ ^[1-9][0-9]*$ ]] && ((count<=20)) || error "--top must be 1-20."
    [[ -d "$mount" ]] || error "Mount path is not an accessible directory: $mount"
    if ((continuous)); then
        while true; do
            if run_cycle "$interval" "$mount" "$count"; then
                CYCLES_COMPLETED=$((CYCLES_COMPLETED+1))
            elif ! stop_requested; then
                echo "Monitoring cycle failed; retrying in ${MONITOR_INTERVAL}s." >&2
            fi
            stop_requested && graceful_stop
            interruptible_sleep "$MONITOR_INTERVAL"
            stop_requested && graceful_stop
        done
    else
        run_cycle "$interval" "$mount" "$count"; rc=$?
        ((rc==0)) && CYCLES_COMPLETED=1
        stop_requested && graceful_stop
        return "$rc"
    fi
}
main "$@"
