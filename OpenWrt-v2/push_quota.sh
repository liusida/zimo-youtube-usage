#!/bin/sh
# POST current usage to the server.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/quota_common.sh"

get_effective_usage

USAGE_KB=$((USAGE / 1024))
USAGE_MB=$((USAGE / 1024 / 1024))
QUOTA_MB="${QUOTA_MB:-$((QUOTA_BYTES / 1024 / 1024))}"
if [ -z "$USAGE_SERVER_URL" ]; then
    logger -t youtube_quota "USAGE_SERVER_URL is not set in youtube_quota.conf"
    exit 1
fi
SERVER_URL="$USAGE_SERVER_URL"
LISTENER_SCRIPT="$SCRIPT_DIR/listen_on_network.sh"

IP_SNAPSHOT="[]"
if [ -x "$LISTENER_SCRIPT" ]; then
    SNAPSHOT_RAW="$("$LISTENER_SCRIPT" 2>/dev/null | tr -d '\n\r')"
    case "$SNAPSHOT_RAW" in
        \[*\]) IP_SNAPSHOT="$SNAPSHOT_RAW" ;;
    esac
fi

if curl -s -X POST "$SERVER_URL" \
    -H "Content-Type: application/json" \
    -d "{\"iface\":\"br-zimo\",\"used_kb\":$USAGE_KB,\"used_mb\":$USAGE_MB,\"quota_mb\":$QUOTA_MB,\"ip_snapshot\":$IP_SNAPSHOT}" \
    >/dev/null 2>&1; then
    logger -t youtube_quota "Pushed ${USAGE_MB} MB to $SERVER_URL"
else
    logger -t youtube_quota "Failed to push to $SERVER_URL"
fi
