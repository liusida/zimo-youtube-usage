/**
 * Standalone WhatsApp pairing (CLI QR). Uses the same auth dir as server.js.
 *
 * Do NOT run while the main server is also running Baileys on this folder.
 * Set WHATSAPP_DISABLE=1 on the service, restart once, run this script, then
 * unset and restart (see Server/README.md).
 *
 * Usage (from Server/, e.g. ~/zimo-usage):
 *   node pair-whatsapp.mjs
 *   node pair-whatsapp.mjs --list-groups   # after link: print group names + JIDs
 *
 * Env:
 *   WHATSAPP_AUTH_DIR — override; default: ./data/whatsapp-auth (next to this file)
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { Boom } from '@hapi/boom';
import pino from 'pino';
import qrcode from 'qrcode-terminal';
import makeWASocket, {
  DisconnectReason,
  useMultiFileAuthState
} from '@whiskeysockets/baileys';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const authDir =
  (process.env.WHATSAPP_AUTH_DIR || '').trim() ||
  path.join(__dirname, 'data', 'whatsapp-auth');
const listGroups = process.argv.includes('--list-groups');

let reconnectTimer = null;
/** @type {import('@whiskeysockets/baileys').WASocket | null} */
let sock = null;
let finishing = false;

function scheduleReconnect(ms) {
  if (reconnectTimer || finishing) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    startSocket();
  }, ms);
}

function clearReconnectTimer() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

async function afterOpen() {
  if (listGroups && sock) {
    try {
      console.log('\nGroups you are in (use the JID for WHATSAPP_GROUP_JID):\n');
      const groups = await sock.groupFetchAllParticipating();
      const rows = Object.entries(groups).sort((a, b) =>
        String(a[1]?.subject || '').localeCompare(String(b[1]?.subject || ''))
      );
      for (const [jid, meta] of rows) {
        console.log(`${meta?.subject || '(no name)'}\t${jid}`);
      }
      if (rows.length === 0) console.log('(none)');
    } catch (e) {
      console.error('Could not list groups:', e.message || e);
    }
  }

  console.log('\nDone. Exiting in 2s.');
  await new Promise((r) => setTimeout(r, 2000));
  process.exit(0);
}

function startSocket() {
  if (finishing) return;
  clearReconnectTimer();

  useMultiFileAuthState(authDir)
    .then(({ state, saveCreds }) => {
      sock = makeWASocket({
        auth: state,
        logger: pino({ level: 'silent' }),
        syncFullHistory: false,
        markOnlineOnConnect: true
      });

      sock.ev.on('creds.update', saveCreds);

      sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect, qr } = update;

        if (qr) {
          console.log('[pair-whatsapp] Scan with WhatsApp → Linked devices:\n');
          qrcode.generate(qr, { small: true });
        }

        if (connection === 'open') {
          if (finishing) return;
          finishing = true;
          clearReconnectTimer();
          console.log('[pair-whatsapp] Session open — credentials saved.');
          afterOpen().catch((e) => {
            console.error(e);
            process.exit(1);
          });
        }

        if (connection === 'close') {
          const err = lastDisconnect?.error;
          const code =
            err instanceof Boom ? err.output?.statusCode : undefined;
          const loggedOut = code === DisconnectReason.loggedOut;
          console.log(
            '[pair-whatsapp] Connection closed',
            code !== undefined ? `(code ${code})` : err?.message || ''
          );
          if (loggedOut) {
            console.log(
              '[pair-whatsapp] Logged out. Delete the auth folder and run again to re-pair.'
            );
            process.exit(1);
          }
          if (!finishing) scheduleReconnect(3000);
        }
      });
    })
    .catch((e) => {
      console.error('[pair-whatsapp] Error:', e);
      if (!finishing) scheduleReconnect(5000);
    });
}

if (!fs.existsSync(authDir)) {
  fs.mkdirSync(authDir, { recursive: true });
}

console.error(
  '[pair-whatsapp] Auth directory:',
  authDir,
  '\nIf zimo-usage is running with WhatsApp enabled, stop Baileys first (WHATSAPP_DISABLE=1 + restart service).\n'
);

startSocket();
