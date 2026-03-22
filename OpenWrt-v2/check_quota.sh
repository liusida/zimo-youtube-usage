#!/bin/sh
# Compare usage to quota; block or unblock br-zimo accordingly.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/quota_common.sh"

get_effective_usage
echo "DEBUG: USAGE=$USAGE (persisted across reboot)"

USAGE_MB=$((USAGE / 1024 / 1024))
QUOTA_MB=$((QUOTA_BYTES / 1024 / 1024))

if [ "$USAGE" -gt "$QUOTA_BYTES" ]; then
    echo "Quota exceeded: ${USAGE_MB} MB / ${QUOTA_MB} MB"
    "$QUOTA_BLOCK" on
    exit 1
fi

# Do not unblock if we are in reset-pending state (legacy flag)
if [ -f "$RESET_FLAG" ]; then
    echo "Quota OK but reset pending. Run reset_quota.sh."
    "$QUOTA_BLOCK" on
    exit 1
fi

echo "Quota OK: ${USAGE_MB} MB / ${QUOTA_MB} MB"
"$QUOTA_BLOCK" off
exit 0
