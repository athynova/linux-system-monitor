#!/usr/bin/env bash
save_report() {
    local content="${1:-}" dir="${2:-}" file
    [[ -n "$content" && -n "$dir" ]] || { echo "Error: Report content and directory are required." >&2; return 2; }
    mkdir -p -- "$dir" || return 1
    file="$dir/system-report-$(date +%F).log"
    (umask 077; printf '%s\n\n' "$content" >> "$file") || {
        printf 'Error: Cannot append report to %s\n' "$file" >&2; return 1;
    }
    printf '%s\n' "$file"
}
