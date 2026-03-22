# Traffic quota for OpenWrt (v2)

Enforces a daily traffic quota for **`br-zimo`** using **nftables** (`inet ytmon`). When usage exceeds the limit, forwarded traffic from that bridge is blocked (IPv4/IPv6 via `block_quota`, plus a UDP drop rule). Usage is computed from nft counters **`LAN_total_zimo`** and **`WAN_total_zimo`**.

**Persistence across reboot:** `quota_common.sh` keeps effective usage via `quota_last_usage.txt` and `quota_carry.txt` when counter totals drop after a reboot. Midnight `reset_quota.sh` clears carry, updates the baseline in `START_FILE`, and unblocks.

## Setup

1. Copy this folder on the router (e.g. `/root/youtube/`).
2. In `/etc/config/firewall` add:
   ```
   config include
           option type 'script'
           option path '/root/youtube/firewall.ytmon'
           option fw4_compatible '1'
   ```
3. Reload firewall: `/etc/init.d/firewall reload`
4. Install cron entries from `crontab.txt` (daily reset at 00:00; `check_quota.sh` and `push_quota.sh` every 3 minutes).
5. Ensure **`curl`** is installed (`opkg install curl`). For per-IP snapshots on push, install **`iftop`** and keep `listen_on_network.sh` executable (optional; push still works with an empty `ip_snapshot`).

## Scripts and config

| File | Role |
|------|------|
| `youtube_quota.conf` | `QUOTA_MB`, `QUOTA_BYTES` (derived from MB if set), `START_FILE`, `USAGE_SERVER_URL`. |
| `quota_common.sh` | Shared config, `get_total_bytes`, `get_effective_usage` (carry / reboot logic). |
| `firewall.ytmon` | Creates table/chains, counters, default jump to `block_quota` until `check_quota.sh` clears it; handles counter-vs-baseline edge cases on reload vs reboot. |
| `check_quota.sh` | If usage exceeds quota → `quota_block.sh on`. If under quota and no `reset_detected.flag` → `quota_block.sh off`. |
| `push_quota.sh` | POSTs JSON to `USAGE_SERVER_URL` with `iface`, `used_kb`, `used_mb`, `quota_mb`, and optional `ip_snapshot` from `listen_on_network.sh`. |
| `listen_on_network.sh` | Short **iftop** sample on `br-zimo` → JSON array `[{ "ip", "cumulative_bytes" }, …]`. |
| `reset_quota.sh` | New baseline in `START_FILE`, clears `quota_carry.txt`, removes `reset_detected.flag` if present, unblocks. |
| `quota_block.sh` | `on` / `off` / `status` — insert or delete the nft rules that enforce blocking. |
| `crontab.txt` | Example cron lines for the above schedule. |


Edit **`youtube_quota.conf`** for quota size and server URL.
