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
# Keep the first N rows and drop the "ps" process itself (it is measured the
# instant it starts, so it reports a misleading ~100% CPU and would top the list).
# This deliberately reads ALL of its input instead of stopping early (as "head"
# would): quitting early makes ps die from SIGPIPE on a busy system, and
# "set -o pipefail" then reports the whole pipeline as failed.
select_process_rows() {
    awk -v n="$1" '!(NF==4 && $4=="ps") && count<n {print; count++}'
}
get_top_cpu_processes() {
    local n="${1:-5}"; validate_process_limit "$n" || return $?
    ps -eo pid=,%cpu=,%mem=,comm= --sort=-%cpu | select_process_rows "$n" | format_process_rows
}
get_top_memory_processes() {
    local n="${1:-5}"; validate_process_limit "$n" || return $?
    ps -eo pid=,%cpu=,%mem=,comm= --sort=-%mem | select_process_rows "$n" | format_process_rows
}
