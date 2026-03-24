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

**On the server**, app files live under **`~/zimo-usage/`** (contents of this `Server/` directory: `server.js`, `package.json`, `package-lock.json`, `public/`, etc.). Run `npm install --omit=dev` or `npm ci --omit=dev` there, then keep the process alive with **systemd** (`WorkingDirectory` should be that folder), **pm2**, or similar.

Optional: for `scp`-based deploy, copy [`upload.sh.example`](upload.sh.example) to `upload.sh`, set `USER@YOUR_HOST` (paths already use `~/zimo-usage/`), and run it. `upload.sh` is gitignored so deploy targets stay local.

**GitHub Actions:** pushes to `main` that touch `Server/` rsync to **`~/zimo-usage/`** on the host configured in [`.github/workflows/deploy-server.yml`](../.github/workflows/deploy-server.yml). Required secrets: `SSH_HOST`, `SSH_USER`, `SSH_KEY`. The workflow runs `ssh-keyscan` to fill `known_hosts` (no `SSH_KNOWN_HOSTS` secret). Optional: `SSH_PORT`, `DEPLOY_POST_CMD` (e.g. `systemctl --user restart zimo-usage.service`). Remove the `DEPLOY_PATH` secret if you added it earlier; it is no longer used.

For **`SSH_KEY`**, paste the **entire** private key file into the secret (from `-----BEGIN` through `-----END`), with normal line breaks—do not paste a single line with the text `\n`, and do not wrap the value in quotes. The workflow uses `webfactory/ssh-agent` to load the key (avoids `libcrypto` errors from writing the key to disk incorrectly).
