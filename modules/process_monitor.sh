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
# Drop the "ps" process itself: it is measured the instant it starts, so it
# reports a misleading ~100% CPU and would otherwise top the list.
exclude_ps_rows() {
    awk '!(NF==4 && $4=="ps")'
}
get_top_cpu_processes() {
    local n="${1:-5}"; validate_process_limit "$n" || return $?
    ps -eo pid=,%cpu=,%mem=,comm= --sort=-%cpu | exclude_ps_rows | head -n "$n" | format_process_rows
}
get_top_memory_processes() {
    local n="${1:-5}"; validate_process_limit "$n" || return $?
    ps -eo pid=,%cpu=,%mem=,comm= --sort=-%mem | exclude_ps_rows | head -n "$n" | format_process_rows
}
