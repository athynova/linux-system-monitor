#!/usr/bin/env bash
get_memory_metrics() {
    local total available used
    total=$(awk '$1=="MemTotal:" {print $2; exit}' /proc/meminfo)
    available=$(awk '$1=="MemAvailable:" {print $2; exit}' /proc/meminfo)
    [[ "$total" =~ ^[0-9]+$ && "$available" =~ ^[0-9]+$ ]] || {
        echo "Error: Memory values unavailable in /proc/meminfo." >&2; return 1;
    }
    (( total > 0 && available <= total )) || return 1
    used=$((total-available))
    awk -v t="$total" -v u="$used" -v a="$available" 'BEGIN {
        printf "MEM_TOTAL_KIB=%.0f\nMEM_USED_KIB=%.0f\nMEM_AVAILABLE_KIB=%.0f\nMEM_PERCENT=%.2f\n",t,u,a,(u/t)*100
    }'
}
