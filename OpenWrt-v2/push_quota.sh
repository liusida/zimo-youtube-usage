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

# Memory snapshot from /proc/meminfo (KiB). More detail than `free` — helps with OOM analysis.
# Emits one JSON object with snake_case keys ending in _kb (e.g. mem_total_kb, mem_available_kb).
MEM_OBJ=""
if [ -r /proc/meminfo ]; then
    MEM_OBJ="$(awk '
    function to_snake(s,    i, c, out) {
        out = ""
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == "_") {
                out = out "_"
                continue
            }
            if (c ~ /[A-Z]/ && i > 1) out = out "_"
            if (c ~ /[A-Za-z0-9]/) out = out tolower(c)
        }
        return out
    }
    function norm_key(raw,    t) {
        t = raw
        gsub(/[^A-Za-z0-9]+/, "_", t)
        gsub(/^_+|_+$/, "", t)
        gsub(/_+/, "_", t)
        return to_snake(t) "_kb"
    }
    /^[^:]+:[[:space:]]+[0-9]+[[:space:]]+kB/ {
        split($0, kv, ":")
        key = kv[1]
        val = $2
        if (val !~ /^[0-9]+$/) next
        jkey = norm_key(key)
        if (jkey == "_kb" || jkey == "kb") next
        if (!first) printf ","
        first = 0
        printf "\"%s\":%d", jkey, val + 0
    }
    BEGIN { first = 1 }
    ' /proc/meminfo)"
    if [ -n "$MEM_OBJ" ]; then
        MEM_OBJ="{${MEM_OBJ}}"
    fi
fi
if [ -n "$MEM_OBJ" ]; then
    META_BODY="{\"mem\":$MEM_OBJ}"
else
    META_BODY="{}"
fi

if curl -s -X POST "$SERVER_URL" \
    -H "Content-Type: application/json" \
    -d "{\"iface\":\"br-zimo\",\"used_kb\":$USAGE_KB,\"used_mb\":$USAGE_MB,\"quota_mb\":$QUOTA_MB,\"ip_snapshot\":$IP_SNAPSHOT,\"meta_data\":$META_BODY}" \
    >/dev/null 2>&1; then
    logger -t youtube_quota "Pushed ${USAGE_MB} MB to $SERVER_URL"
else
    logger -t youtube_quota "Failed to push to $SERVER_URL"
fi
