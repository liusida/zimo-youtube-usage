#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/youtube_quota.conf"

# Load global config
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
fi

# Use config value (with default if not set)
# If START_FILE is relative, make it relative to script directory
if [ -n "$START_FILE" ] && [ "${START_FILE#/}" = "$START_FILE" ]; then
    START_FILE="$SCRIPT_DIR/$START_FILE"
elif [ -z "$START_FILE" ]; then
    START_FILE="$SCRIPT_DIR/quota_start.txt"
fi

# Get bytes from traffic counters
get_bytes() {
    nft list chain inet ytmon forward 2>/dev/null | \
        grep -E '(LAN_total_zimo|WAN_total_zimo)' | \
        sed -n 's/.*bytes \([0-9]\+\).*/\1/p'
}

# Sum all bytes
TOTAL=0
for bytes in $(get_bytes); do
    TOTAL=$((TOTAL + bytes))
done

# Save current total as new start value and clear reset flag (allows usage for this day)
echo "$TOTAL" > "$START_FILE"
RESET_FLAG="$SCRIPT_DIR/reset_detected.flag"
[ -f "$RESET_FLAG" ] && rm -f "$RESET_FLAG"
echo "Quota reset: Start value set to ${TOTAL} bytes"
# Restore network access (in case we were in reset-pending state)
[ -x "$SCRIPT_DIR/quota_block.sh" ] && "$SCRIPT_DIR/quota_block.sh" off
