# Zimo Usage Server

Simple Node.js server to receive and store Internet usage data from OpenWrt router.

`scp -O *.* dictionary@dict.liusida.com:~/zimo-usage/`

## Setup

```sh
npm install
npm start
```

Server runs on port 8080.

## Endpoints

- `POST /zimo-usage` - Receive usage data from router
  - Body: `{ "iface": "br-zimo", "used_kb": 1234 }`
  
- `GET /zimo-usage` - Get latest usage data
  
- `GET /zimo-usage/history?lines=50` - Get usage history (last N lines)
  
- `GET /health` - Health check

## Data Storage

- `data/usage.json` - Latest usage entry (JSON)
- `data/usage.log` - Historical log file (text)

## Running as a Service

Use `pm2` or `systemd` to keep it running:

```sh
# With pm2
npm install -g pm2
pm2 start server.js --name zimo-usage
pm2 save
pm2 startup
```

