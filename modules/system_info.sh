#!/usr/bin/env bash
get_system_info() {
    local os_name="Unknown"
    [[ -r /etc/os-release ]] && os_name=$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-Unknown}")
    printf 'Hostname: %s\n' "$(hostname 2>/dev/null || echo Unavailable)"
    printf 'Operating system: %s\n' "$os_name"
    printf 'Kernel: %s\n' "$(uname -r 2>/dev/null || echo Unavailable)"
    printf 'Architecture: %s\n' "$(uname -m 2>/dev/null || echo Unavailable)"
    printf 'Uptime: %s\n' "$(uptime -p 2>/dev/null || echo Unavailable)"
    printf 'Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
}
