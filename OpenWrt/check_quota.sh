#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/youtube_quota.conf"

# Load global config
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
else
    echo "Missing config: $CONFIG"
    exit 1
fi

# Use config values (with defaults if not set)
QUOTA="${QUOTA_BYTES:-$((2 * 1024 * 1024))}"
# If START_FILE is relative, make it relative to script directory
if [ -n "$START_FILE" ] && [ "${START_FILE#/}" = "$START_FILE" ]; then
    START_FILE="$SCRIPT_DIR/$START_FILE"
elif [ -z "$START_FILE" ]; then
    START_FILE="$SCRIPT_DIR/quota_start.txt"
fi
QUOTA_BLOCK="$SCRIPT_DIR/quota_block.sh"
RESET_FLAG="$SCRIPT_DIR/reset_detected.flag"

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

# Read start value (default to 0 if file doesn't exist)
START=0
if [ -f "$START_FILE" ]; then
    START=$(cat "$START_FILE" 2>/dev/null || echo 0)
fi

# Calculate usage since start
USAGE=$((TOTAL - START))
# Adjust for 1x speed
USAGE=$((USAGE * 1))

# Handle counter reset (e.g., after reboot): block and set flag until root runs reset_quota.sh
if [ "$USAGE" -lt 0 ]; then
    echo "Counter reset detected (Total: ${TOTAL} < Start: ${START}), blocking network"
    echo "Total: ${TOTAL} bytes (0 MB), Start: ${START} bytes ($((START / 1024 / 1024)) MB)"
    echo "Run reset_quota.sh to allow usage for this day."
    : > "$RESET_FLAG"
    "$QUOTA_BLOCK" on
    exit 1
fi

# Convert to MB (divide by 1024*1024)
USAGE_MB=$((USAGE / 1024 / 1024))
QUOTA_MB=$((QUOTA / 1024 / 1024))
TOTAL_MB=$((TOTAL / 1024 / 1024))
START_MB=$((START / 1024 / 1024))

# Check quota
if [ "$USAGE" -gt "$QUOTA" ]; then
    echo "Quota exceeded: ${USAGE} bytes (${USAGE_MB} MB) used (quota: ${QUOTA} bytes / ${QUOTA_MB} MB)"
    echo "Total: ${TOTAL} bytes (${TOTAL_MB} MB), Start: ${START} bytes (${START_MB} MB)"
    "$QUOTA_BLOCK" on
    exit 1
else
    # Do not unblock if reset was detected (router reboot): require explicit reset_quota.sh
    if [ -f "$RESET_FLAG" ]; then
        echo "Quota OK but reset pending: run reset_quota.sh to allow usage"
        echo "Total: ${TOTAL} bytes (${TOTAL_MB} MB), Start: ${START} bytes (${START_MB} MB)"
        "$QUOTA_BLOCK" on
        exit 1
    fi
    echo "Quota OK: ${USAGE} bytes (${USAGE_MB} MB) / ${QUOTA} bytes (${QUOTA_MB} MB) used"
    echo "Total: ${TOTAL} bytes (${TOTAL_MB} MB), Start: ${START} bytes (${START_MB} MB)"
    "$QUOTA_BLOCK" off
    exit 0
fi
