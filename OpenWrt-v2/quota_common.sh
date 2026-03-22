#!/bin/sh
# Shared config and helpers for quota scripts. Source this: . "$SCRIPT_DIR/quota_common.sh"

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONFIG="$SCRIPT_DIR/youtube_quota.conf"

if [ ! -f "$CONFIG" ]; then
    echo "Missing config: $CONFIG" >&2
    exit 1
fi
. "$CONFIG"

# Quota in bytes (default 2 MB if unset)
QUOTA_BYTES="${QUOTA_BYTES:-$((2 * 1024 * 1024))}"

# Start file: if relative, make it under SCRIPT_DIR
if [ -n "$START_FILE" ] && [ "${START_FILE#/}" = "$START_FILE" ]; then
    START_FILE="$SCRIPT_DIR/$START_FILE"
elif [ -z "$START_FILE" ]; then
    START_FILE="$SCRIPT_DIR/quota_start.txt"
fi

RESET_FLAG="$SCRIPT_DIR/reset_detected.flag"
QUOTA_BLOCK="$SCRIPT_DIR/quota_block.sh"
LAST_USAGE_FILE="$SCRIPT_DIR/quota_last_usage.txt"
CARRY_FILE="$SCRIPT_DIR/quota_carry.txt"

# Print total bytes from nft counters (LAN + WAN for br-zimo)
get_total_bytes() {
    _sum=0
    for _b in $(nft list chain inet ytmon forward 2>/dev/null | \
        grep -E '(LAN_total_zimo|WAN_total_zimo)' | \
        sed -n 's/.*bytes \([0-9]\+\).*/\1/p'); do
        _sum=$((_sum + _b))
    done
    echo $_sum
}

# Print baseline bytes from START_FILE (or 0)
get_start_value() {
    if [ -f "$START_FILE" ]; then
        cat "$START_FILE" 2>/dev/null | tr -d '\n' | grep -E '^[0-9]+$' || echo 0
    else
        echo 0
    fi
}

# Read numeric value from file (or 0)
_read_num_file() {
    [ -f "$1" ] && cat "$1" 2>/dev/null | tr -d '\n' | grep -E '^[0-9]+$' || echo 0
}

# Compute effective usage (persists across reboot via last_usage + carry).
# Sets USAGE (bytes). Call from check_quota and push_quota.
# Once carry > 0 (post-reboot), we stay in carry mode until reset_quota clears it.
get_effective_usage() {
    TOTAL=$(get_total_bytes)
    START=$(get_start_value)
    carry=$(_read_num_file "$CARRY_FILE")

    if [ "$carry" -gt 0 ]; then
        # Post-reboot: keep using carry until midnight reset clears it (don't switch to "normal")
        USAGE=$((TOTAL + carry))
    elif [ "$TOTAL" -ge "$START" ] && [ "$TOTAL" -gt 0 ]; then
        # Normal: no carry, counters valid
        USAGE=$((TOTAL - START))
        echo "$USAGE" > "$LAST_USAGE_FILE"
        echo "0" > "$CARRY_FILE"
    else
        # Reboot: counters reset, copy last_usage into carry
        carry=$(_read_num_file "$LAST_USAGE_FILE")
        echo "$carry" > "$CARRY_FILE"
        USAGE=$((TOTAL + carry))
    fi
}
