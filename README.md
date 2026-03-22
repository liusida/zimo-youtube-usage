# Zimo YouTube Usage

Daily traffic quota on OpenWrt (nftables) for a dedicated bridge, with a small Node server that receives usage posts and serves the dashboard.

## Layout

| Directory | Role |
|-----------|------|
| **`OpenWrt-v2/`** | **Current** router scripts: quota, cron, firewall hook, push to server. Deploy this tree to the router (see its README). |
| **`Server/`** | **Backend + static UI**: Express app, SQLite, `public/` pages. Run with `npm install` and `npm start` (default port **8080**). |
| **`OpenWrt/`** | **Deprecated** earlier implementation; kept for reference only—not used on the router. |

## Flow

1. Router scripts measure usage against `youtube_quota.conf` (`QUOTA_MB`, `USAGE_SERVER_URL`, etc.).
2. `push_quota.sh` POSTs JSON to the server’s `/zimo-usage`.
3. The server stores data and the web UI reads it via the HTTP API.

For setup details, see **`OpenWrt-v2/README.md`** and **`Server/README.md`**.
