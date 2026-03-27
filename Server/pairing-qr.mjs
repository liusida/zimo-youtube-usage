/**
 * Baileys emits raw QR payload strings on connection.update only; it does not
 * render terminals. The old printQRInTerminal socket option is deprecated and
 * does nothing useful. We render ASCII QR via qrcode-terminal.
 */
import qrcode from 'qrcode-terminal';

/**
 * @param {string | undefined} qr from connection.update
 * @param {string} title line printed before the QR
 */
export function printPairingQr(qr, title) {
  if (!qr) return;
  console.log(title);
  qrcode.generate(qr, { small: true });
}
