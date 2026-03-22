#!/bin/sh
# Turn blocking on/off for br-zimo: insert or delete nft rules by comment.

COMMENT="quota_block_enabled"
UDP_COMMENT="quota_block_udp"

# Get nft rule handle for the rule with this comment (used to delete it)
get_handle() {
    nft -a list chain inet ytmon forward 2>/dev/null | \
        sed -n 's/.*comment "'"$1"'".*# handle \([0-9]\+\).*/\1/p'
}

case "$1" in
    on)
        if [ -z "$(get_handle "$COMMENT")" ]; then
            nft insert rule inet ytmon forward iifname "br-zimo" jump block_quota comment "$COMMENT"
            echo "Blocking ON"
        fi
        if [ -z "$(get_handle "$UDP_COMMENT")" ]; then
            nft insert rule inet ytmon forward iifname "br-zimo" meta l4proto udp drop comment "$UDP_COMMENT"
        fi
        ;;
    off)
        H=$(get_handle "$COMMENT")
        [ -n "$H" ] && nft delete rule inet ytmon forward handle "$H" && echo "Blocking OFF"
        H=$(get_handle "$UDP_COMMENT")
        [ -n "$H" ] && nft delete rule inet ytmon forward handle "$H"
        ;;
    status)
        if [ -n "$(get_handle "$COMMENT")" ]; then
            echo "Blocking is ON"
        else
            echo "Blocking is OFF"
        fi
        ;;
    *)
        echo "Usage: quota_block.sh on|off|status"
        exit 1
        ;;
esac
