#!/usr/bin/env bash
get_disk_metrics() {
    local mount="${1:-/}" line fs total used avail pct
    [[ -d "$mount" ]] || { printf 'Error: Invalid mount point: %s\n' "$mount" >&2; return 2; }
    line=$(df -Pk "$mount" 2>/dev/null | awk 'NR==2 {print $1, $2, $3, $4, $5}')
    [[ -n "$line" ]] || { echo "Error: Cannot read filesystem data." >&2; return 1; }
    read -r fs total used avail pct <<< "$line"
    pct=${pct%%%}
    [[ "$total" =~ ^[0-9]+$ && "$used" =~ ^[0-9]+$ && "$avail" =~ ^[0-9]+$ && "$pct" =~ ^[0-9]+$ ]] || {
        echo "Error: Unexpected df output." >&2; return 1;
    }
    printf 'DISK_FILESYSTEM=%s\nDISK_MOUNT=%s\nDISK_TOTAL_KIB=%s\nDISK_USED_KIB=%s\nDISK_AVAILABLE_KIB=%s\nDISK_PERCENT=%s\n' "$fs" "$mount" "$total" "$used" "$avail" "$pct"
}
