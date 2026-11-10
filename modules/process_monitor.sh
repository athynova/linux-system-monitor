#!/usr/bin/env bash
validate_process_limit() {
    local n="${1:-5}"
    [[ "$n" =~ ^[1-9][0-9]*$ ]] && (( n <= 20 )) || {
        echo "Error: Process count must be 1-20." >&2; return 2;
    }
}
get_top_cpu_processes() {
    local n="${1:-5}"; validate_process_limit "$n" || return $?
    ps -eo pid=,comm=,%cpu=,%mem= --sort=-%cpu | head -n "$n" |
        awk 'BEGIN {printf "%-8s %-24s %10s %10s\n","PID","COMMAND","CPU%","MEM%"} {printf "%-8s %-24s %10s %10s\n",$1,$2,$3,$4}'
}
get_top_memory_processes() {
    local n="${1:-5}"; validate_process_limit "$n" || return $?
    ps -eo pid=,comm=,%cpu=,%mem= --sort=-%mem | head -n "$n" |
        awk 'BEGIN {printf "%-8s %-24s %10s %10s\n","PID","COMMAND","CPU%","MEM%"} {printf "%-8s %-24s %10s %10s\n",$1,$2,$3,$4}'
}
