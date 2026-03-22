# Traffic Quota for OpenWrt (v2)

Enforces a daily traffic quota for interface `br-zimo` with nftables. When exceeded, traffic from that interface is blocked.

## Setup

1. Copy this folder to the router (e.g. `/root/youtube/`).
2. In `/etc/config/firewall` add:
   ```
   config include
           option type 'script'
           option path '/root/youtube/firewall.ytmon'
           option fw4_compatible '1'
   ```
3. Reload firewall: `/etc/init.d/firewall reload`
4. Install cron entries from `crontab.txt`.

## Files

| File | Purpose |
|------|--------|
| `quota_common.sh` | Shared config and helpers (sourced by other scripts). |
| `firewall.ytmon` | nftables: counters + block chain; run on firewall reload. |
| `check_quota.sh` | Compare usage to quota; call `quota_block.sh on/off`. |
| `push_quota.sh` | POST usage to server. |
| `reset_quota.sh` | Set new baseline (e.g. daily at midnight). |
| `quota_block.sh` | Turn blocking on/off (insert/delete nft rules). |
| `youtube_quota.conf` | `QUOTA_MB`, `START_FILE`, `USAGE_SERVER_URL`. |

## Manual

```bash
./quota_block.sh on      # Block br-zimo
./quota_block.sh off     # Unblock
./quota_block.sh status  # Show state
```

## Config

Edit `youtube_quota.conf`: `QUOTA_MB`, `START_FILE`, `USAGE_SERVER_URL`.
