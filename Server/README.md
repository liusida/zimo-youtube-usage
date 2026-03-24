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
| `GET` | `/zimo-usage/history` | DB history. Query: `start`, `end` (ISO timestamps), `iface`, `limit` (default 1000, max 50000). Response: `{ "data": [ … ] }` rows with `ip_snapshot` and `has_watch_ip` (true if any snapshot IP matches a watch IPv4 or `*` pattern). |
| `GET` | `/zimo-usage/watch-ips` | `{ "data": [ "entry", … ] }` — watch list (IPv4 and/or patterns) used for chart highlight. |
| `POST` | `/zimo-usage/watch-ips` | Body `{ "ip": "a.b.c.d" }` or pattern `{ "ip": "210.10.78.*" }` — four dot-separated parts, each `*` or 0–255; stored normalized. |
| `DELETE` | `/zimo-usage/watch-ips/:ip` | Remove entry (URL-encoded). |
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

**GitHub Actions:** pushes to `main` that touch `Server/` rsync to **`~/zimo-usage/`** on the host configured in [`.github/workflows/deploy-server.yml`](../.github/workflows/deploy-server.yml). Required secrets: `SSH_HOST`, `SSH_USER`, `DEPLOY_SSH_KEY`. The workflow runs `ssh-keyscan` to fill `known_hosts` (no `SSH_KNOWN_HOSTS` secret). Optional: `SSH_PORT`, `DEPLOY_POST_CMD` (e.g. `systemctl --user restart zimo-usage.service`). Remove the `DEPLOY_PATH` secret if you added it earlier; it is no longer used.

**`DEPLOY_NPM_BIN` (recommended):** set a repository **secret** or **variable** (same name) to the **full path of `npm`**, or to the **`bin` directory** for that Node (e.g. `.../v22.18.0/bin/npm` or `.../v22.18.0/bin`). The workflow prefers the **secret** if both are set. Use `command -v npm` on the server with the same Node as `ExecStart`. Avoid typos: a value like `.../bin` without `/npm` used to break pairing with `node` (fixed in workflow); still best to paste the full `npm` path. Without `DEPLOY_NPM_BIN`, SSH often uses `/usr/bin/npm` (e.g. Node 18) and breaks **better-sqlite3**.

For **`DEPLOY_SSH_KEY`**, add it under **Secrets** (not Variables—private keys must be secrets). Paste the **entire** private key file (from `-----BEGIN` through `-----END`), with normal line breaks—do not paste a single line with the text `\n`, and do not wrap the value in quotes. The workflow uses `webfactory/ssh-agent` to load the key (avoids `libcrypto` errors from writing the key to disk incorrectly).

**Native modules (`better-sqlite3`):** set **`DEPLOY_NPM_BIN`** (see above). If you see `NODE_MODULE_VERSION` / `ERR_DLOPEN_FAILED`, rebuild with the service’s Node, e.g.  
`/path/to/npm --prefix ~/zimo-usage ci --omit=dev`, then restart the unit.
