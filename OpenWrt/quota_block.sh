#!/bin/sh

CHAIN="inet ytmon forward"
COMMENT="quota_block_enabled"
UDP_COMMENT="quota_block_udp"

get_handle() {
    nft -a list chain inet ytmon forward \
      | sed -n 's/.*comment "'$COMMENT'".*# handle \([0-9]\+\).*/\1/p'
}

get_udp_handle() {
    nft -a list chain inet ytmon forward \
      | sed -n 's/.*comment "'$UDP_COMMENT'".*# handle \([0-9]\+\).*/\1/p'
}

case "$1" in
  on)
    if [ -z "$(get_handle)" ]; then
      nft insert rule inet ytmon forward iifname "br-zimo" jump block_quota comment "$COMMENT"
      echo "Network blocking ENABLED"
    else
      echo "Network blocking already ON"
    fi
    if [ -z "$(get_udp_handle)" ]; then
      nft insert rule inet ytmon forward iifname "br-zimo" meta l4proto udp drop comment "$UDP_COMMENT"
      echo "UDP blocking ENABLED"
    else
      echo "UDP blocking already ON"
    fi
    ;;
  off)
    HANDLE="$(get_handle)"
    if [ -n "$HANDLE" ]; then
      nft delete rule inet ytmon forward handle "$HANDLE"
      echo "Network blocking DISABLED"
    else
      echo "Network blocking already OFF"
    fi
    UDP_HANDLE="$(get_udp_handle)"
    if [ -n "$UDP_HANDLE" ]; then
      nft delete rule inet ytmon forward handle "$UDP_HANDLE"
      echo "UDP blocking DISABLED"
    else
      echo "UDP blocking already OFF"
    fi
    ;;
  status)
    if [ -n "$(get_handle)" ] && [ -n "$(get_udp_handle)" ]; then
      echo "Network blocking is ON (all traffic blocked)"
    elif [ -n "$(get_handle)" ]; then
      echo "Network blocking is ON (IPv4/IPv6 blocked)"
    elif [ -n "$(get_udp_handle)" ]; then
      echo "Network blocking is ON (UDP only)"
    else
      echo "Network blocking is OFF"
    fi
    ;;
  *)
    echo "Usage: quota_block {on|off|status}"
    ;;
esac
