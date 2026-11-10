#!/usr/bin/env bash
# Return 0 for normal, 1 for threshold warning, 2 for invalid input.
check_threshold() {
    local metric="${1:-}" value="${2:-}" threshold="${3:-}" log_file="${4:-}"
    [[ -n "$metric" && "$value" =~ ^[0-9]+([.][0-9]+)?$ && "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
        echo "Error: Invalid threshold arguments." >&2; return 2;
    }
    if awk -v v="$value" -v t="$threshold" 'BEGIN {exit !(v >= t)}'; then
        local stamp message
        stamp=$(date '+%Y-%m-%d %H:%M:%S')
        message="WARNING: ${metric} utilization is ${value}% (threshold ${threshold}%)."
        echo "$message"
        if [[ -n "$log_file" ]]; then
            printf '[%s] %s\n' "$stamp" "$message" >> "$log_file" || return 1
        fi
        return 1
    fi
    return 0
}
