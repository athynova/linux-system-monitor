#!/usr/bin/env bash
read_cpu_counters() {
    local label user nice system idle iowait irq softirq steal rest
    IFS=' ' read -r label user nice system idle iowait irq softirq steal rest < /proc/stat || return 1
    [[ "$label" == cpu ]] || return 1
    CPU_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
    CPU_IDLE=$((idle + iowait))
}
get_cpu_usage() {
    local interval="${1:-1}" total1 idle1 total2 idle2 td id busy
    [[ "$interval" =~ ^[1-9][0-9]*$ ]] && (( interval <= 60 )) || {
        echo "Error: CPU interval must be 1-60 seconds." >&2; return 2;
    }
    read_cpu_counters || { echo "Error: Cannot read /proc/stat." >&2; return 1; }
    total1=$CPU_TOTAL; idle1=$CPU_IDLE
    sleep "$interval"
    read_cpu_counters || { echo "Error: Cannot read second CPU sample." >&2; return 1; }
    total2=$CPU_TOTAL; idle2=$CPU_IDLE
    td=$((total2-total1)); id=$((idle2-idle1))
    (( td > 0 && id >= 0 && id <= td )) || { echo "Error: Invalid CPU counter delta." >&2; return 1; }
    busy=$((td-id))
    awk -v b="$busy" -v t="$td" 'BEGIN {printf "%.2f", (b/t)*100}'
}
