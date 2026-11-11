#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$ROOT/config/monitor.conf"
LOG_DIR="$ROOT/logs"; REPORT_DIR="$ROOT/reports"; EVENT_LOG="$LOG_DIR/monitor.log"

for name in system_info cpu_monitor memory_monitor disk_monitor process_monitor alert_manager report_manager; do
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
  --help              Show this help
Examples:
  ./monitor.sh
  ./monitor.sh --interval 2 --top 3
  ./monitor.sh --mount /home
  ./monitor.sh --continuous
EOF
}
error() { echo "Error: $1" >&2; exit 2; }

# Documented defaults are retained if an optional setting is omitted.
CPU_THRESHOLD=80
RAM_THRESHOLD=85
DISK_THRESHOLD=90
MONITOR_INTERVAL=5
TOP_PROCESS_COUNT=5

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
}
run_cycle() {
    local interval="$1" mount="$2" count="$3" cpu mem disk ram_pct disk_pct report saved status=NORMAL
    local warning_count=0 rc
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
    printf '%s\n' "$report"
    saved=$(save_report "$report" "$REPORT_DIR") || return 1
    printf '\nReport saved: %s\n' "$saved"
    printf '[%s] Monitoring cycle completed. Status=%s\n' "$(date '+%F %T')" "$status" >> "$EVENT_LOG" ||
        echo "Warning: event log could not be written." >&2
}
main() {
    local interval=1 mount=/ continuous=0 count=""
    # Arguments are parsed first so --help works even if the config is broken.
    while (($#)); do
        case "$1" in
            --help) usage; return 0 ;;
            --interval) (($#>=2)) || error "--interval needs a value"; interval=$2; shift 2 ;;
            --mount) (($#>=2)) || error "--mount needs a path"; mount=$2; shift 2 ;;
            --top) (($#>=2)) || error "--top needs a value"; count=$2; shift 2 ;;
            --continuous) continuous=1; shift ;;
            *) error "Unknown option: $1 (use --help)" ;;
        esac
    done
    load_config; validate_config
    [[ -n "$count" ]] || count=$TOP_PROCESS_COUNT
    [[ "$interval" =~ ^[1-9][0-9]*$ ]] && ((interval<=60)) || error "--interval must be 1-60."
    [[ "$count" =~ ^[1-9][0-9]*$ ]] && ((count<=20)) || error "--top must be 1-20."
    [[ -d "$mount" ]] || error "Mount path is not an accessible directory: $mount"
    if ((continuous)); then
        while true; do
            run_cycle "$interval" "$mount" "$count" || echo "Monitoring cycle failed; retrying in ${MONITOR_INTERVAL}s." >&2
            sleep "$MONITOR_INTERVAL"
        done
    else
        run_cycle "$interval" "$mount" "$count"
    fi
}
main "$@"
