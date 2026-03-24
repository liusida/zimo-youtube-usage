# Zimo usage server

Node.js **Express** app: receives usage POSTs from the router, stores them in **SQLite** (`better-sqlite3`), and serves the **`public/`** dashboard (static files). Listens on **`0.0.0.0:8080`** (see `PORT` in `server.js`).

## Run

```sh
cd Server
npm install
npm start
```

Default script is `node server.js` (see `package.json`).

## HTTP API

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/zimo-usage` | Ingest usage. **Required JSON:** `iface`, `used_kb`. **Optional:** `quota_mb`, `quota_kb`, `ip_snapshot` (array of `{ "ip": "x.x.x.x", "cumulative_bytes": number }`). Saves to DB, appends `data/usage.log`, overwrites `data/usage.json`. |
| `GET` | `/zimo-usage` | Latest entry from `data/usage.json` (same shape as stored fields: `timestamp`, `iface`, `used_kb`, `used_mb`, optional quota fields). |
| `GET` | `/zimo-usage/history` | DB history. Query: `start`, `end` (ISO timestamps), `iface`, `limit` (default 1000, max 50000). Response: `{ "data": [ … ] }` rows with `ip_snapshot` and `has_watch_ip` for charts. |
| `GET` | `/zimo-usage/watch-ips` | `{ "data": [ "ip", … ] }` — IPs highlighted in the UI. |
| `POST` | `/zimo-usage/watch-ips` | Body `{ "ip": "a.b.c.d" }` — add to watch list. |
| `DELETE` | `/zimo-usage/watch-ips/:ip` | Remove IP (URL-encoded). |
| `GET` | `/health` | `{ "status": "ok", "port": 8080 }`. |
| `GET` | `/` | Serves `public/index.html`. |

Other files under `public/` (e.g. `ip.html`) are served by `express.static('public')`.

**CORS:** `Access-Control-Allow-Origin: *` for `GET`, `POST`, `OPTIONS`.

## Data files

| Path | Role |
|------|------|
| `data/usage.db` | SQLite: `usage_data`, `usage_ip_data`, `watch_ips`. |
| `data/usage.json` | Latest sample (updated on each POST). |
| `data/usage.log` | One line per POST (text log). |

The `data/` directory is created on startup if missing.

## Deploy / process manager

Copy `server.js`, `package.json`, `package-lock.json`, and `public/` to the host, run `npm install --omit=dev` if you only need production deps, then keep the process alive with **systemd**, **pm2**, or similar.

Optional: for `scp`-based deploy, copy [`upload.sh.example`](upload.sh.example) to `upload.sh`, set your `USER@HOST:path`, and run it. `upload.sh` is gitignored so deploy targets stay local.
