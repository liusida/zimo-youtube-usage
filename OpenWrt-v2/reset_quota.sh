#!/bin/sh
# Set baseline to current total (e.g. run daily at midnight). Clears carry and starts new period.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/quota_common.sh"

TOTAL=$(get_total_bytes)
# Don't set baseline to 0 (e.g. after reboot); keep previous so usage is preserved until next real reset
if [ "$TOTAL" -gt 0 ]; then
    echo "$TOTAL" > "$START_FILE"
fi
echo "0" > "$CARRY_FILE"
[ -f "$RESET_FLAG" ] && rm -f "$RESET_FLAG"
echo "Quota reset: start = $TOTAL bytes, carry cleared"
[ -x "$QUOTA_BLOCK" ] && "$QUOTA_BLOCK" off
