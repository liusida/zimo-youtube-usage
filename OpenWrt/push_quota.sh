#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/youtube_quota.conf"

# Load global config
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
else
    logger -t youtube_quota "Missing config: $CONFIG"
    exit 1
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

# Read start value (default to 0 if file doesn't exist)
START=0
if [ -f "$START_FILE" ]; then
    START=$(cat "$START_FILE" 2>/dev/null || echo 0)
fi

# Calculate usage since start
USAGE=$((TOTAL - START))
# Adjust for 1x speed
USAGE=$((USAGE * 1))

if [ "$USAGE" -lt 0 ]; then
    logger -t youtube_quota "Negative usage (counter wrap); skipping push"
    exit 1
fi

USAGE_KB=$((USAGE / 1024))
USAGE_MB=$((USAGE / 1024 / 1024))

# Get quota from config (default to 20MB if not set)
QUOTA_MB="${QUOTA_MB:-20}"
QUOTA_KB=$((QUOTA_MB * 1024))

# Server URL (required in youtube_quota.conf)
if [ -z "$USAGE_SERVER_URL" ]; then
    logger -t youtube_quota "USAGE_SERVER_URL is not set in youtube_quota.conf"
    exit 1
fi
SERVER_URL="$USAGE_SERVER_URL"

# Send usage data (requires curl package: opkg install curl)
curl -s -X POST "$SERVER_URL" \
    -H "Content-Type: application/json" \
    -d "{\"iface\":\"br-zimo\",\"used_kb\":$USAGE_KB,\"used_mb\":$USAGE_MB,\"quota_mb\":$QUOTA_MB,\"quota_kb\":$QUOTA_KB,\"total_bytes\":$TOTAL,\"start_bytes\":$START}" \
    >/dev/null 2>&1

if [ $? -eq 0 ]; then
    logger -t youtube_quota "Pushed usage: ${USAGE_KB} KB (${USAGE_MB} MB) to $SERVER_URL"
else
    logger -t youtube_quota "Failed to push usage to $SERVER_URL"
fi
