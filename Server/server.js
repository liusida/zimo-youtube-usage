const express = require('express');
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

const app = express();
const PORT = 8080;

// Data directory
const dataDir = path.join(__dirname, 'data');
const usageFile = path.join(dataDir, 'usage.json');
const logFile = path.join(dataDir, 'usage.log');
const dbPath = path.join(dataDir, 'usage.db');

// Ensure data directory exists
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// Initialize SQLite database
const db = new Database(dbPath);
db.exec(`
  CREATE TABLE IF NOT EXISTS usage_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    iface TEXT NOT NULL,
    used_kb INTEGER NOT NULL,
    used_mb REAL NOT NULL,
    quota_mb INTEGER,
    quota_kb INTEGER
  );
  
  CREATE INDEX IF NOT EXISTS idx_timestamp ON usage_data(timestamp);
  CREATE INDEX IF NOT EXISTS idx_iface_timestamp ON usage_data(iface, timestamp);

  CREATE TABLE IF NOT EXISTS usage_ip_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    usage_id INTEGER NOT NULL,
    ip TEXT NOT NULL,
    cumulative_bytes INTEGER NOT NULL,
    FOREIGN KEY (usage_id) REFERENCES usage_data(id) ON DELETE CASCADE
  );

  CREATE INDEX IF NOT EXISTS idx_usage_ip_usage_id ON usage_ip_data(usage_id);
  CREATE INDEX IF NOT EXISTS idx_usage_ip_ip ON usage_ip_data(ip);

  CREATE TABLE IF NOT EXISTS watch_ips (
    ip TEXT PRIMARY KEY
  );

  CREATE TABLE IF NOT EXISTS youtube_notify_sent (
    local_date TEXT PRIMARY KEY
  );
`);

// Prepare statement for inserts
const insertStmt = db.prepare(`
  INSERT INTO usage_data (timestamp, iface, used_kb, used_mb, quota_mb, quota_kb)
  VALUES (?, ?, ?, ?, ?, ?)
`);
const insertIpStmt = db.prepare(`
  INSERT INTO usage_ip_data (usage_id, ip, cumulative_bytes)
  VALUES (?, ?, ?)
`);
const upsertWatchIpStmt = db.prepare(`
  INSERT OR IGNORE INTO watch_ips (ip)
  VALUES (?)
`);
const deleteWatchIpStmt = db.prepare(`
  DELETE FROM watch_ips
  WHERE ip = ?
`);
const listWatchIpsStmt = db.prepare(`
  SELECT ip FROM watch_ips ORDER BY ip ASC
`);
const insertYoutubeNotifyDayStmt = db.prepare(`
  INSERT OR IGNORE INTO youtube_notify_sent (local_date) VALUES (?)
`);
const deleteYoutubeNotifyDayStmt = db.prepare(`
  DELETE FROM youtube_notify_sent WHERE local_date = ?
`);
const insertWithIpSnapshot = db.transaction((entry, ipSnapshot) => {
  const usageInfo = insertStmt.run(
    entry.timestamp,
    entry.iface,
    entry.used_kb,
    entry.used_mb,
    entry.quota_mb,
    entry.quota_kb
  );

  for (const row of ipSnapshot) {
    insertIpStmt.run(usageInfo.lastInsertRowid, row.ip, row.cumulative_bytes);
  }

  return usageInfo.lastInsertRowid;
});

function sanitizeIpSnapshot(rawSnapshot) {
  if (!Array.isArray(rawSnapshot)) return [];

  const rows = [];
  const ipRegex = /^(\d{1,3}\.){3}\d{1,3}$/;
  for (const item of rawSnapshot) {
    if (!item || typeof item !== 'object') continue;
    if (typeof item.ip !== 'string') continue;
    const ip = item.ip.trim();
    if (!ipRegex.test(ip)) continue;

    const bytes = Number.parseInt(item.cumulative_bytes, 10);
    if (!Number.isFinite(bytes) || bytes < 0) continue;

    rows.push({ ip, cumulative_bytes: bytes });
  }

  rows.sort((a, b) => b.cumulative_bytes - a.cumulative_bytes);
  return rows;
}

/** @returns {number[]|null} four octets 0–255 */
function parseIpv4Octets(ip) {
  if (typeof ip !== 'string') return null;
  const s = ip.trim();
  if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(s)) return null;
  const parts = s.split('.').map((p) => parseInt(p, 10));
  if (parts.some((n) => !Number.isFinite(n) || n < 0 || n > 255)) return null;
  return parts;
}

/**
 * Watch list entry: four dot-separated parts, each `*` or 0–255 (digits only).
 * @returns {(number|null)[]|null} null = wildcard octet
 */
function parseWatchPattern(raw) {
  if (typeof raw !== 'string') return null;
  const segs = raw.trim().split('.');
  if (segs.length !== 4) return null;
  const out = [];
  for (const seg of segs) {
    if (seg === '*') {
      out.push(null);
    } else if (/^\d{1,3}$/.test(seg)) {
      const n = parseInt(seg, 10);
      if (n < 0 || n > 255) return null;
      out.push(n);
    } else {
      return null;
    }
  }
  return out;
}

function normalizeWatchPattern(parts) {
  return parts.map((p) => (p === null ? '*' : String(p))).join('.');
}

/** Accepts literal IPv4 or pattern like 210.10.78.* */
function sanitizeWatchPattern(rawIp) {
  const parts = parseWatchPattern(rawIp);
  if (!parts) return null;
  return normalizeWatchPattern(parts);
}

function ipv4MatchesWatchEntry(ip, storedPattern) {
  const octets = parseIpv4Octets(ip);
  const patternParts = parseWatchPattern(storedPattern);
  if (!octets || !patternParts) return false;
  for (let i = 0; i < 4; i++) {
    if (patternParts[i] === null) continue;
    if (octets[i] !== patternParts[i]) return false;
  }
  return true;
}

function snapshotHasWatchMatch(ipRows, watchPatterns) {
  if (!ipRows.length || !watchPatterns.length) return false;
  return ipRows.some((ipRow) =>
    watchPatterns.some((pat) => ipv4MatchesWatchEntry(ipRow.ip, pat))
  );
}

/** Server-local calendar date YYYY-MM-DD */
function localDateKey(d = new Date()) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function isWhatsAppNotifyEnabled() {
  const groupJid = (process.env.WHATSAPP_GROUP_JID || '').trim();
  const disabled = ['1', 'true', 'yes'].includes(
    String(process.env.WHATSAPP_DISABLE || '').toLowerCase()
  );
  return !!(groupJid && !disabled);
}

// Baileys client (ESM); loaded when WHATSAPP_GROUP_JID is set and WHATSAPP_DISABLE is off.
const whatsappAuthDir = path.join(dataDir, 'whatsapp-auth');
let waModule = null;
if (isWhatsAppNotifyEnabled()) {
  import('./whatsapp.mjs')
    .then((m) => {
      waModule = m;
      m.initWhatsApp({ authDir: whatsappAuthDir });
    })
    .catch((e) => console.error('[WhatsApp] failed to load module:', e));
}

// Middleware
app.use(express.json());
app.use(express.static('public')); // For serving a simple HTML page if needed

// CORS headers (if needed)
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// POST endpoint: receive usage data from router
app.post('/zimo-usage', async (req, res) => {
  const { iface, used_kb, quota_mb, quota_kb, ip_snapshot } = req.body || {};
  
  if (!iface || used_kb === undefined) {
    return res.status(400).json({ error: 'Missing iface or used_kb' });
  }

  const timestamp = new Date().toISOString();
  const entry = {
    timestamp,
    iface,
    used_kb: parseInt(used_kb, 10),
    used_mb: parseFloat((used_kb / 1024).toFixed(2)),
    quota_mb: quota_mb ? parseInt(quota_mb, 10) : null,
    quota_kb: quota_kb ? parseInt(quota_kb, 10) : null
  };
  const ipSnapshot = sanitizeIpSnapshot(ip_snapshot);

  // Insert into SQLite database
  try {
    insertWithIpSnapshot(entry, ipSnapshot);
  } catch (err) {
    console.error('Database insert error:', err);
    return res.status(500).json({ error: 'Failed to save to database' });
  }

  const watchPatterns = listWatchIpsStmt.all().map((row) => row.ip);
  const nowMatch = snapshotHasWatchMatch(ipSnapshot, watchPatterns);
  let whatsapp_notified = false;

  if (nowMatch && isWhatsAppNotifyEnabled() && waModule) {
    const localDate = localDateKey();
    const ins = insertYoutubeNotifyDayStmt.run(localDate);
    if (ins.changes === 1) {
      const groupJid = (process.env.WHATSAPP_GROUP_JID || '').trim();
      const msg =
        `It looks like Zimo has started watching YouTube today.`;
      const ok = await waModule.sendGroupMessage(groupJid, msg);
      if (!ok) {
        deleteYoutubeNotifyDayStmt.run(localDate);
      } else {
        whatsapp_notified = true;
        console.log('[WhatsApp] Sent daily first-match notification');
      }
    }
  }

  // Append to log file (for backward compatibility)
  const quotaInfo = entry.quota_mb ? ` quota=${entry.quota_mb}MB` : '';
  const logLine = `${timestamp} iface=${iface} used_kb=${used_kb} (${entry.used_mb.toFixed(2)} MB)${quotaInfo}\n`;
  fs.appendFileSync(logFile, logLine);

  // Update latest usage JSON (for backward compatibility)
  fs.writeFileSync(usageFile, JSON.stringify(entry, null, 2));

  const quotaMsg = entry.quota_mb ? ` (quota: ${entry.quota_mb} MB)` : '';
  console.log(`Received usage: ${used_kb} KB (${entry.used_mb} MB) on ${iface}${quotaMsg}`);
  
  res.json({
    ok: true,
    received: { ...entry, ip_snapshot: ipSnapshot },
    has_watch_ip: nowMatch,
    whatsapp_notified
  });
});

// GET endpoint: retrieve latest usage
app.get('/zimo-usage', (req, res) => {
  if (!fs.existsSync(usageFile)) {
    return res.json({ error: 'No usage data yet' });
  }

  try {
    const data = JSON.parse(fs.readFileSync(usageFile, 'utf8'));
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: 'Failed to read usage data' });
  }
});

// GET endpoint: retrieve usage history from database
app.get('/zimo-usage/history', (req, res) => {
  const start = req.query.start;
  const end = req.query.end;
  const iface = req.query.iface;
  const limit = Math.min(parseInt(req.query.limit || '1000', 10), 50000);

  let query = 'SELECT * FROM usage_data WHERE 1=1';
  const params = [];

  if (start) {
    query += ' AND timestamp >= ?';
    params.push(start);
  }
  if (end) {
    query += ' AND timestamp <= ?';
    params.push(end);
  }
  if (iface) {
    query += ' AND iface = ?';
    params.push(iface);
  }

  query += ' ORDER BY timestamp DESC LIMIT ?';
  params.push(limit);

  try {
    const stmt = db.prepare(query);
    const rows = stmt.all(...params);
    if (rows.length === 0) {
      return res.json({ data: [] });
    }

    const usageIds = rows.map((r) => r.id);
    const placeholders = usageIds.map(() => '?').join(',');
    const ipRows = db.prepare(
      `SELECT usage_id, ip, cumulative_bytes
       FROM usage_ip_data
       WHERE usage_id IN (${placeholders})
       ORDER BY usage_id ASC, cumulative_bytes DESC`
    ).all(...usageIds);

    const ipByUsageId = new Map();
    for (const row of ipRows) {
      if (!ipByUsageId.has(row.usage_id)) {
        ipByUsageId.set(row.usage_id, []);
      }
      ipByUsageId.get(row.usage_id).push({
        ip: row.ip,
        cumulative_bytes: row.cumulative_bytes
      });
    }
    const watchPatterns = listWatchIpsStmt.all().map((row) => row.ip);

    // Reverse so client gets chronological order (oldest first) for the chart
    const data = rows.reverse().map((row) => ({
      ...row,
      ip_snapshot: ipByUsageId.get(row.id) || [],
      has_watch_ip: snapshotHasWatchMatch(ipByUsageId.get(row.id) || [], watchPatterns)
    }));
    res.json({ data });
  } catch (err) {
    console.error('Database query error:', err);
    res.status(500).json({ error: 'Failed to query database' });
  }
});

// GET/POST/DELETE endpoints: watchlist IPs used for chart highlighting
app.get('/zimo-usage/watch-ips', (req, res) => {
  try {
    const rows = listWatchIpsStmt.all();
    res.json({ data: rows.map((row) => row.ip) });
  } catch (err) {
    console.error('Failed to list watch IPs:', err);
    res.status(500).json({ error: 'Failed to list watch IPs' });
  }
});

app.post('/zimo-usage/watch-ips', (req, res) => {
  const ip = sanitizeWatchPattern((req.body || {}).ip);
  if (!ip) {
    return res.status(400).json({ error: 'Invalid ip or pattern (use IPv4 or e.g. 210.10.78.*)' });
  }

  try {
    upsertWatchIpStmt.run(ip);
    res.json({ ok: true, ip });
  } catch (err) {
    console.error('Failed to add watch IP:', err);
    res.status(500).json({ error: 'Failed to add watch IP' });
  }
});

app.delete('/zimo-usage/watch-ips/:ip', (req, res) => {
  const raw = decodeURIComponent(req.params.ip || '').trim();
  const normalized = sanitizeWatchPattern(raw);
  if (!normalized) {
    return res.status(400).json({ error: 'Invalid ip or pattern' });
  }

  try {
    let result = deleteWatchIpStmt.run(normalized);
    let deletedKey = normalized;
    if (result.changes === 0 && raw !== normalized) {
      result = deleteWatchIpStmt.run(raw);
      if (result.changes > 0) deletedKey = raw;
    }
    res.json({ ok: true, deleted: result.changes > 0, ip: deletedKey });
  } catch (err) {
    console.error('Failed to delete watch IP:', err);
    res.status(500).json({ error: 'Failed to delete watch IP' });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', port: PORT });
});

// Root endpoint - serve the HTML page
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Zimo usage server listening on port ${PORT}`);
  console.log(`Data directory: ${dataDir}`);
});

