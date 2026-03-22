#!/bin/sh
# Capture top outbound sources on br-zimo and emit JSON snapshot.

IFACE="${IFACE:-br-zimo}"
DURATION_SECONDS="${DURATION_SECONDS:-10}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-12}"

timeout "$TIMEOUT_SECONDS" iftop -i "$IFACE" -t -n -N -s "$DURATION_SECONDS" 2>/dev/null | \
awk '
function to_bytes(v, num, unit, factor) {
    num = v
    gsub(/[[:space:]]+/, "", num)
    sub(/[KMGkmg][bB]?$/, "", num)
    unit = v
    gsub(/^[0-9.]+/, "", unit)
    unit = toupper(unit)
    factor = 1
    if (unit ~ /^KB?$/) factor = 1024
    else if (unit ~ /^MB?$/) factor = 1024 * 1024
    else if (unit ~ /^GB?$/) factor = 1024 * 1024 * 1024
    return int((num * factor) + 0.5)
}
BEGIN {
    print "["
    first = 1
}
/=>/ {
    if (match($0, /([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*=>[[:space:]].*[[:space:]]([0-9.]+[KMGkmg]?[bB]?)/, m)) {
        ip = m[1]
        bytes = to_bytes(m[2])
        if (!first) {
            printf(",")
        }
        printf("{\"ip\":\"%s\",\"cumulative_bytes\":%d}", ip, bytes)
        first = 0
    }
}
END {
    print "]"
}
'
