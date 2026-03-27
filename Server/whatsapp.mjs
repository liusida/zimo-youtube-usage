import fs from 'fs';
import { Boom } from '@hapi/boom';
import pino from 'pino';
import qrcode from 'qrcode-terminal';
import makeWASocket, {
  DisconnectReason,
  useMultiFileAuthState
} from '@whiskeysockets/baileys';

let authDirResolved = '';
let sock = null;
let connectionOpen = false;
let reconnectTimer = null;

function scheduleReconnect(ms) {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    startSocket();
  }, ms);
}

function startSocket() {
  useMultiFileAuthState(authDirResolved)
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
          console.log('[WhatsApp] Scan QR code with WhatsApp → Linked devices:');
          qrcode.generate(qr, { small: true });
        }

        if (connection === 'open') {
          connectionOpen = true;
          console.log('[WhatsApp] session open');
        }

        if (connection === 'close') {
          connectionOpen = false;
          const err = lastDisconnect?.error;
          const code =
            err instanceof Boom ? err.output?.statusCode : undefined;
          const loggedOut = code === DisconnectReason.loggedOut;
          console.log(
            '[WhatsApp] connection closed',
            code !== undefined ? `(code ${code})` : err?.message || ''
          );
          if (loggedOut) {
            console.log(
              '[WhatsApp] Logged out. Remove the whatsapp-auth folder and restart to pair again.'
            );
            return;
          }
          scheduleReconnect(3000);
        }
      });
    })
    .catch((e) => {
      console.error('[WhatsApp] auth/connect error:', e);
      scheduleReconnect(5000);
    });
}

/**
 * @param {{ authDir: string }} opts
 */
export function initWhatsApp(opts) {
  authDirResolved = opts.authDir;
  if (!fs.existsSync(authDirResolved)) {
    fs.mkdirSync(authDirResolved, { recursive: true });
  }
  startSocket();
}

/**
 * @param {string} jid Group JID ending in @g.us
 * @param {string} text
 * @returns {Promise<boolean>}
 */
export async function sendGroupMessage(jid, text) {
  if (!jid || typeof text !== 'string' || !text.trim()) return false;
  if (!sock || !connectionOpen) {
    console.warn('[WhatsApp] send skipped (not connected)');
    return false;
  }
  try {
    await sock.sendMessage(jid, { text: text.trim() });
    return true;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error('[WhatsApp] sendMessage failed:', msg);
    return false;
  }
}
