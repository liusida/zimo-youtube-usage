# Traffic Quota for OpenWrt

Enforces a total traffic quota for a specific network interface (default: `br-zimo`) using nftables. When the quota is exceeded, all forwarded traffic from that network is blocked, effectively cutting off internet access for devices on that network.

## Setup

Add to `/etc/config/firewall`:
```
config include
        option type 'script'
        option path '/root/youtube/firewall.ytmon'
        option fw4_compatible '1'
```

Then reload firewall:
```bash
/etc/init.d/firewall reload
```

## Manual Operation

```bash
./quota_block.sh on     # Enable blocking (blocks all traffic from br-zimo)
./quota_block.sh off    # Disable blocking (restores internet access)
./quota_block.sh status # Check current blocking status
```

## Verify Rules

```bash
nft list chain inet ytmon forward
nft list chain inet ytmon block_quota
```

Example output:
```
table inet ytmon {
        chain forward {
                type filter hook forward priority filter; policy accept;
                iifname "br-zimo" meta l4proto udp drop comment "quota_block_udp"
                iifname "br-zimo" jump block_quota comment "quota_block_enabled"
                iifname "br-zimo" counter packets 359 bytes 105926 comment "LAN_total_zimo"
                oifname "br-zimo" counter packets 354 bytes 556733 comment "WAN_total_zimo"
        }
        chain block_quota {
                meta protocol ip drop comment "block_quota_v4"
                meta protocol ip6 drop comment "block_quota_v6"
        }
}
```

## How It Works

- **Counting**: All forwarded traffic on the `br-zimo` interface is counted using nftables counters (`LAN_total_zimo` for outbound, `WAN_total_zimo` for inbound).
- **Quota Enforcement**: The `check_quota.sh` script runs periodically (via cron every 3 minutes) and compares total traffic usage against the configured quota.
- **Blocking**: When quota is exceeded, `quota_block.sh on` is called, which inserts rules to drop all forwarded traffic from `br-zimo`, effectively cutting off internet access for that network.
- **Reset**: The `reset_quota.sh` script resets the baseline, typically run daily at midnight via cron.

## Configuration

Edit `youtube_quota.conf` to set:
- `QUOTA_MB`: Quota limit in megabytes (default: 20)
- `START_FILE`: Baseline file path (default: `quota_start.txt`)
- `USAGE_SERVER_URL`: Server endpoint for usage reporting (optional)