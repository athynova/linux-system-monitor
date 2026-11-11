#!/usr/bin/env bash
# History manager: records one CSV row per monitoring cycle.
# Return codes: 0 success, 1 I/O or lock failure, 2 invalid input.

HISTORY_COLUMNS="timestamp,cpu_percent,ram_percent,disk_percent,mount,status"

# Quote a CSV field when needed and neutralise spreadsheet formula injection.
csv_escape() {
    local v="${1-}"
    [[ "$v" == [=+@-]* ]] && v="'$v"
    if [[ "$v" == *[,\"$'\n\r']* ]]; then
        v=${v//\"/\"\"}
        v="\"$v\""
    fi
    printf '%s' "$v"
}

# Make sure the file exists, starts with the expected header and ends with a newline.
_history_prepare() {
    local file="$1" first="" aside
    if [[ ! -s "$file" ]]; then
        printf '%s\n' "$HISTORY_COLUMNS" > "$file" || return 1
        return 0
    fi
    IFS= read -r first < "$file" || true
    first=${first//$'\r'/}
    if [[ "$first" != "$HISTORY_COLUMNS" ]]; then
        # Never mix schemas: keep the foreign file aside and start a fresh one.
        aside="${file%.csv}-$(date +%Y%m%d-%H%M%S).old"
        mv -- "$file" "$aside" || return 1
        echo "Warning: unexpected header in $file; moved it to $aside." >&2
        printf '%s\n' "$HISTORY_COLUMNS" > "$file" || return 1
        return 0
    fi
    # Repair a last line left unterminated by an interrupted write.
    if [[ -n "$(tail -c1 "$file")" ]]; then
        printf '\n' >> "$file" || return 1
    fi
}

# Keep the file bounded: once it exceeds max rows by 10%, drop the oldest rows.
_history_trim() {
    local file="$1" max="$2" lines tmp
    (( max > 0 )) || return 0
    lines=$(wc -l < "$file") || return 1
    lines=${lines//[[:space:]]/}
    (( lines - 1 > max + max / 10 )) || return 0
    tmp="${file}.tmp.$$"
    { head -n 1 "$file"; tail -n "$max" "$file"; } > "$tmp" || { rm -f -- "$tmp"; return 1; }
    mv -f -- "$tmp" "$file" || { rm -f -- "$tmp"; return 1; }
}

# history_append FILE CPU RAM DISK MOUNT STATUS [MAX_ROWS]
history_append() {
    local file="${1:-}" cpu="${2:-}" ram="${3:-}" disk="${4:-}" mount="${5:-}" status="${6:-}" max_rows="${7:-0}"
    local num='^[0-9]+([.][0-9]+)?$' stamp row
    [[ -n "$file" && "$cpu" =~ $num && "$ram" =~ $num && "$disk" =~ $num &&
       -n "$mount" && "$status" =~ ^(NORMAL|WARNING)$ && "$max_rows" =~ ^[0-9]+$ ]] || {
        echo "Error: Invalid history record." >&2; return 2;
    }
    stamp=$(date -Iseconds) || return 1
    row="${stamp},${cpu},${ram},${disk},$(csv_escape "$mount"),${status}"
    mkdir -p -- "$(dirname -- "$file")" || return 1
    (
        umask 077
        if command -v flock >/dev/null 2>&1; then
            exec 9>>"${file}.lock" || exit 1
            flock -w 10 9 || { echo "Error: Timed out waiting for history lock." >&2; exit 1; }
        fi
        _history_prepare "$file" || exit 1
        printf '%s\n' "$row" >> "$file" || exit 1
        _history_trim "$file" "$max_rows" || exit 1
    )
}

# history_show FILE COUNT : print the header and the last COUNT records.
history_show() {
    local file="${1:-}" n="${2:-10}" total
    if [[ ! -s "$file" ]]; then
        echo "No history recorded yet ($file)."
        return 0
    fi
    total=$(( $(wc -l < "$file") - 1 ))
    printf 'History file: %s (%d record(s)); showing the last %d.\n' "$file" "$total" "$n"
    head -n 1 "$file"
    tail -n +2 "$file" | tail -n "$n"
}
