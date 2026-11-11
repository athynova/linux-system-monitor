#!/usr/bin/env bash
validate_process_limit() {
    local n="${1:-5}"
    [[ "$n" =~ ^[1-9][0-9]*$ ]] && (( n <= 20 )) || {
        echo "Error: Process count must be 1-20." >&2; return 2;
    }
}

# Reads "PID %CPU %MEM COMMAND..." lines on stdin and prints an aligned table.
# The command name is the LAST field because it may contain spaces
# (for example "Web Content"); the three numeric fields come first.
format_process_rows() {
    awk 'BEGIN {printf "%-8s %-24s %10s %10s\n","PID","COMMAND","CPU%","MEM%"}
         {
             pid=$1; cpu=$2; mem=$3
             $1=""; $2=""; $3=""
             sub(/^[[:space:]]+/, "")
             printf "%-8s %-24.24s %10s %10s\n", pid, $0, cpu, mem
         }'
}
get_top_cpu_processes() {
    local n="${1:-5}"; validate_process_limit "$n" || return $?
    ps -eo pid=,%cpu=,%mem=,comm= --sort=-%cpu | head -n "$n" | format_process_rows
}
get_top_memory_processes() {
    local n="${1:-5}"; validate_process_limit "$n" || return $?
    ps -eo pid=,%cpu=,%mem=,comm= --sort=-%mem | head -n "$n" | format_process_rows
}
