require('dotenv').config();
const express = require('express');
const cors = require('cors');
const qrcode = require('qrcode');
const pino = require('pino');
const path = require('path');
const fs = require('fs');
const os = require('os');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  downloadMediaMessage
} = require('@whiskeysockets/baileys');

const ocrEngine = require('./ocr-engine');
const bankSlipParser = require('./bank-slip-parser');

const firebaseAdapter = require('./firebase-adapter');

const app = express();
const PORT = process.env.PORT || 3001;
const AUTH_DIR = path.join(__dirname, 'auth_info_baileys');

app.use(cors());
app.use(express.json());

// Device Identification & Multi-Device Preemption
let lastClaimTime = Date.now();
const INSTANCE_ID = `inst_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
function detectDeviceName() {
  if (process.env.DEVICE_NAME && process.env.DEVICE_NAME.trim()) {
    return process.env.DEVICE_NAME.trim();
  }
  const hostname = os.hostname() || '';
  const isAndroid = process.platform === 'android' || !!process.env.TERMUX_VERSION || fs.existsSync('/data/data/com.termux');
  const isWindows = process.platform === 'win32';

  if (isWindows) {
    if (hostname.toUpperCase().includes('REDMI')) {
      return `💻 Laptop Lenovo (${hostname})`;
    }
    return `💻 Laptop Kasir (${hostname || 'Windows'})`;
  }
  if (isAndroid) {
    try {
      const { execSync } = require('child_process');
      const model = execSync('getprop ro.product.model', { encoding: 'utf8', timeout: 500 }).trim();
      const brand = execSync('getprop ro.product.brand', { encoding: 'utf8', timeout: 500 }).trim();
      if (model || brand) {
        let name = brand ? brand.toUpperCase() : 'ANDROID';
        if (model && !name.includes(model.toUpperCase())) name += ` ${model}`;
        return `📱 HP ${name}`;
      }
    } catch (_) {}

    if (hostname && hostname !== 'localhost') {
      return `📱 HP Android (${hostname})`;
    }
    return '📱 HP Android (Termux)';
  }
  return `🖥️ Server (${hostname || process.platform})`;
}
const DEVICE_NAME = detectDeviceName();
let isStandby = false;
let heartbeatTimer = null;

function getDeviceDetails() {
  const isAndroid = process.platform === 'android' || !!process.env.TERMUX_VERSION || fs.existsSync('/data/data/com.termux');
  const isWindows = process.platform === 'win32';

  let brand = '';
  let model = '';
  let androidVer = '';
  let battery = '';
  let batteryStatus = '';

  if (isAndroid) {
    try {
      const { execSync } = require('child_process');
      brand = execSync('getprop ro.product.brand', { encoding: 'utf8', timeout: 500 }).trim();
      model = execSync('getprop ro.product.model', { encoding: 'utf8', timeout: 500 }).trim();
      androidVer = execSync('getprop ro.build.version.release', { encoding: 'utf8', timeout: 500 }).trim();
    } catch (_) {}

    try {
      if (fs.existsSync('/sys/class/power_supply/battery/capacity')) {
        battery = fs.readFileSync('/sys/class/power_supply/battery/capacity', 'utf8').trim() + '%';
      }
      if (fs.existsSync('/sys/class/power_supply/battery/status')) {
        batteryStatus = fs.readFileSync('/sys/class/power_supply/battery/status', 'utf8').trim();
      }
    } catch (_) {}
  }

  const totalRamGb = (os.totalmem() / (1024 * 1024 * 1024)).toFixed(1);
  const freeRamGb = (os.freemem() / (1024 * 1024 * 1024)).toFixed(1);

  let fullModelName = '';
  if (isAndroid) {
    const b = (brand || '').toUpperCase();
    const m = model || '';
    if (b && m) {
      fullModelName = b === m.split(' ')[0].toUpperCase() ? m : `${b} ${m}`;
    } else {
      fullModelName = b || m || 'Android Device';
    }
  } else if (isWindows) {
    fullModelName = `Laptop (${os.hostname() || 'Windows PC'})`;
  } else {
    fullModelName = os.hostname() || process.platform;
  }

  return {
    brand: brand ? brand.toUpperCase() : (isWindows ? 'PC/Laptop' : 'Android'),
    model: model || (isWindows ? os.hostname() : 'Termux'),
    fullModelName: fullModelName.trim(),
    osVersion: isAndroid ? (androidVer ? `Android ${androidVer}` : 'Android (Termux)') : `${os.type()} ${os.release()}`,
    ramInfo: `${freeRamGb} GB free / ${totalRamGb} GB`,
    batteryInfo: battery ? `${battery}${batteryStatus ? ` (${batteryStatus})` : ''}` : null,
    hostname: os.hostname() || '',
    platform: process.platform,
    nodeVersion: process.version
  };
}

console.log(`[DEVICE IDENTIFIER] Perangkat: ${DEVICE_NAME} (ID: ${INSTANCE_ID})`);

// Claim master upfront so any older running device on another phone yields immediately
firebaseAdapter.claimMaster(INSTANCE_ID, DEVICE_NAME, process.platform).catch(() => {});

// Global process error handlers to prevent unexpected crashes
process.on('uncaughtException', (err) => {
  console.error('[GATEWAY PROCESS EXCEPTION]', err?.message || err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[GATEWAY UNHANDLED REJECTION]', reason?.message || reason);
});

// Singleton State Management
let currentSock = null;
let currentQrDataUrl = null;
let gatewayStatus = 'DISCONNECTED'; // 'CONNECTING', 'QR_READY', 'CONNECTED', 'DISCONNECTED'
let connectedUser = null;
let recentChats = [];
let isConnecting = false;
let reconnectTimer = null;

// Continuous Cluster Node Heartbeat (runs every 50s to optimize Firestore writes & stay within free tier)
setInterval(async () => {
  try {
    const curStatus = isStandby ? 'STANDBY' : gatewayStatus;
    const curDetails = getDeviceDetails();
    await firebaseAdapter.sendHeartbeat(
      INSTANCE_ID,
      curDetails.fullModelName || DEVICE_NAME,
      process.platform,
      curDetails,
      curStatus
    );
  } catch (_) {}
}, 50000);

// Dynamic Whitelist Settings & WhatsApp LID Resolution
let strictWhitelistOnly = true;
let whitelistNumbers = new Set(
  (process.env.TARGET_PHONE_NUMBERS || '')
    .split(',')
    .map(s => s.trim().replace(/\D/g, ''))
    .filter(Boolean)
);
let whitelistContactsList = []; // [{ name: 'ROGUE', phone: '6287789733632' }]
let whitelistLids = new Set(); // Set of LID digits e.g. '33668835856433'
let lidToPhoneMap = new Map(); // '33668835856433' -> '6287789733632'
let phoneToLidMap = new Map(); // '6287789733632' -> '33668835856433'
let autoPoEnabled = false;
let autoSettleTransferSlips = true; // Opsi B (100% Otomatis Penuh) default true

// Processed message IDs to prevent duplicates across restarts and history sync
const processedMessageIds = new Set();

// Seed recent message IDs from Firestore on startup
if (firebaseAdapter && typeof firebaseAdapter.loadRecentMessageIds === 'function') {
  firebaseAdapter.loadRecentMessageIds().then(ids => {
    ids.forEach(id => processedMessageIds.add(id));
    if (ids.size > 0) {
      console.log(`[CACHE INIT] Memuat ${ids.size} ID pesan terakhir untuk mencegah duplikasi.`);
    }
  }).catch(() => {});
}

// Dynamic Message Buffering / Debounce per Sender (Tahap 1: Gabung Chat Otomatis)
// Combines separate bubble messages from the same sender within 20 seconds into 1 full order
const pendingMessageBuffers = new Map();
const DEBOUNCE_WAIT_MS = 20000; // 20 detik jeda tunggu pesan lanjutan
const MAX_BUFFER_HOLD_MS = 60000; // 60 detik batas maksimal tunggu

// In-memory cache for recent raw messages to support Baileys getMessage / retry requests
const rawMessageCache = new Map();
const MAX_RAW_CACHE_SIZE = 1000;

function storeRawMessage(jid, id, message) {
  if (!id || !message) return;
  const key = `${jid}_${id}`;
  if (rawMessageCache.size >= MAX_RAW_CACHE_SIZE) {
    const firstKey = rawMessageCache.keys().next().value;
    rawMessageCache.delete(firstKey);
  }
  rawMessageCache.set(key, message);
}

async function flushMessageBuffer(bufferKey) {
  const buf = pendingMessageBuffers.get(bufferKey);
  if (!buf) return;
  pendingMessageBuffers.delete(bufferKey);

  if (buf.timer) {
    clearTimeout(buf.timer);
    buf.timer = null;
  }

  const combinedText = buf.texts.join('\n');
  console.log(`[BUFFER WA FLUSH] 🚀 Mengirim gabungan ${buf.texts.length} pesan dari ${buf.senderName} (+${buf.senderPhone}) ke Firestore.`);

  const isTransfer = buf.messageType === 'TRANSFER_SLIP';
  const chatPayload = {
    senderJid: buf.senderJid,
    senderPhone: buf.senderPhone,
    senderName: buf.senderName,
    messageText: combinedText,
    isOrderDetected: isTransfer ? false : buf.isOrderDetected,
    messageType: buf.messageType || (buf.isOrderDetected ? 'ORDER_PO' : 'CASUAL_CHAT'),
    hasImage: !!buf.hasImage,
    imageUrl: buf.imageUrl || null,
    transferInfo: buf.transferInfo || null,
    matchedInvoiceNo: buf.matchedInvoiceNo || (buf.transferInfo?.invoiceNo || null),
    caption: buf.caption || '',
    rawOcrText: buf.rawOcrText || '',
    messageCount: buf.texts.length,
    messageId: buf.messageIds?.[0] || '',
    messageIds: buf.messageIds || [],
    receivedAt: buf.receivedAt || new Date()
  };

  recentChats.unshift({
    ...chatPayload,
    receivedAt: new Date()
  });
  if (recentChats.length > 20) recentChats.pop();

  await firebaseAdapter.saveIncomingChat(chatPayload);
}

async function flushAllBuffers() {
  for (const key of Array.from(pendingMessageBuffers.keys())) {
    await flushMessageBuffer(key);
  }
}

function cleanPhone(p) {
  if (!p) return '';
  let s = p.toString().replace(/\D/g, '');
  if (s.startsWith('08')) s = '628' + s.slice(2);
  return s;
}

// Function to resolve WhatsApp LIDs for all whitelisted phone numbers
async function resolveWhitelistLids() {
  if (!currentSock || gatewayStatus !== 'CONNECTED') return;
  try {
    const phones = Array.from(whitelistNumbers);
    for (const phone of phones) {
      if (phoneToLidMap.has(phone)) continue;
      try {
        const jid = `${phone}@s.whatsapp.net`;
        const res = await currentSock.onWhatsApp(jid);
        if (Array.isArray(res) && res.length > 0) {
          const match = res[0];
          if (match.lid) {
            const lidClean = match.lid.split('@')[0].split(':')[0].replace(/\D/g, '');
            if (lidClean) {
              whitelistLids.add(lidClean);
              lidToPhoneMap.set(lidClean, phone);
              phoneToLidMap.set(phone, lidClean);
              console.log(`[LID RESOLVED] Phone +${phone} terdaftar dengan WhatsApp LID ${lidClean}`);
            }
          }
        }
      } catch (_) {
        // Individual phone lookup failure ignored
      }
    }
  } catch (err) {
    console.error('[LID RESOLVE ERROR]', err?.message || err);
  }
}

// Listen to Firestore dynamic settings
firebaseAdapter.listenToSettings((settings) => {
  if (!settings) return;
  if (settings.strictWhitelistOnly !== undefined) {
    strictWhitelistOnly = settings.strictWhitelistOnly;
  }
  if (settings.autoPoEnabled !== undefined) {
    autoPoEnabled = settings.autoPoEnabled;
  }
  if (settings.autoSettleTransferSlips !== undefined) {
    autoSettleTransferSlips = settings.autoSettleTransferSlips;
  }

  if (Array.isArray(settings.whitelistContacts)) {
    whitelistContactsList = [];
    const newNumbers = new Set(
      (process.env.TARGET_PHONE_NUMBERS || '')
        .split(',')
        .map(s => cleanPhone(s))
        .filter(Boolean)
    );

    settings.whitelistContacts.forEach(it => {
      const c = cleanPhone(it.phone || it.number);
      const name = (it.name || '').trim();
      if (c) {
        newNumbers.add(c);
        whitelistContactsList.push({ name, phone: c });
      }
    });

    whitelistNumbers = newNumbers;
  } else if (Array.isArray(settings.whitelistNumbers) && !settings.additionalWhitelist) {
    whitelistContactsList = [];
    const newNumbers = new Set(
      (process.env.TARGET_PHONE_NUMBERS || '')
        .split(',')
        .map(s => cleanPhone(s))
        .filter(Boolean)
    );

    settings.whitelistNumbers.forEach(n => {
      const c = cleanPhone(n);
      if (c) {
        newNumbers.add(c);
        whitelistContactsList.push({ name: 'Kontak WA', phone: c });
      }
    });

    whitelistNumbers = newNumbers;
  }

  if (Array.isArray(settings.additionalWhitelist)) {
    settings.additionalWhitelist.forEach(n => {
      const c = cleanPhone(n);
      if (c) whitelistNumbers.add(c);
    });
  }

  console.log(`[SETTINGS SYNC] Strict Whitelist: ${strictWhitelistOnly}, Auto-PO: ${autoPoEnabled}, Total Terdaftar: ${whitelistNumbers.size} nomor.`);

  // Resolve WhatsApp LIDs with active socket if connected
  resolveWhitelistLids();
});

function cleanupSocket() {
  if (heartbeatTimer) {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }
  flushAllBuffers().catch(() => {});
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (currentSock) {
    try {
      currentSock.ev.removeAllListeners();
      currentSock.end?.();
    } catch (_) {}
    currentSock = null;
  }
}

async function startBaileys() {
  if (isStandby) {
    console.log(`[BAILEYS] Perangkat "${DEVICE_NAME}" dalam mode STANDBY. Menunggu giliran atau aksi manual...`);
    return;
  }
  if (isConnecting) {
    console.log('[BAILEYS] Proses koneksi sedang berjalan, abaikan panggilan ganda...');
    return;
  }
  isConnecting = true;

  try {
    cleanupSocket();

    gatewayStatus = 'CONNECTING';
    currentQrDataUrl = null;
    await firebaseAdapter.updateGatewayStatus({
      status: 'CONNECTING',
      qrCode: null,
      phone: null,
      pushName: null,
      deviceName: DEVICE_NAME,
      devicePlatform: process.platform,
      instanceId: INSTANCE_ID
    });

    const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
    const { version, isLatest } = await fetchLatestBaileysVersion();
    console.log(`[BAILEYS] Versi WhatsApp Web v${version.join('.')}, isLatest: ${isLatest}`);

    const sock = makeWASocket({
      version,
      auth: state,
      logger: pino({ level: 'silent' }),
      browser: ['Lucifax-PFS AI Scanner', 'Chrome', '1.0.0'],
      connectTimeoutMs: 60000,
      defaultQueryTimeoutMs: 0,
      keepAliveIntervalMs: 25000,
      getMessage: async (key) => {
        if (!key) return undefined;
        const lookupKey = `${key.remoteJid}_${key.id}`;
        return rawMessageCache.get(lookupKey) || undefined;
      }
    });

    currentSock = sock;

    // Credentials update handler
    sock.ev.on('creds.update', saveCreds);

    // Connection update handler
    sock.ev.on('connection.update', async (update) => {
      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        gatewayStatus = 'QR_READY';
        try {
          currentQrDataUrl = await qrcode.toDataURL(qr, { width: 320, margin: 2 });
          console.log('[BAILEYS] QR Code baru siap di-scan (bisa via web dashboard atau terminal di bawah):');
          qrcode.toString(qr, { type: 'terminal', small: true }, (err, terminalQr) => {
            if (!err && terminalQr) console.log(terminalQr);
          });
          await firebaseAdapter.updateGatewayStatus({
            status: 'QR_READY',
            qrCode: currentQrDataUrl,
            phone: null,
            pushName: null
          });
        } catch (e) {
          console.error('[BAILEYS] Gagal membuat QR data URL:', e);
        }
      }

      if (connection === 'close') {
        const statusCode = (lastDisconnect?.error)?.output?.statusCode;
        console.warn(`[BAILEYS] Koneksi terputus. Status code: ${statusCode}`);

        currentQrDataUrl = null;
        connectedUser = null;
        isConnecting = false;

        if (statusCode === DisconnectReason.loggedOut) {
          // Logged out
          gatewayStatus = 'DISCONNECTED';
          console.log('[BAILEYS] Sesi di-logout dari WhatsApp (401). Menghapus data sesi lama...');
          try {
            fs.rmSync(AUTH_DIR, { recursive: true, force: true });
          } catch (_) {}
          await firebaseAdapter.updateGatewayStatus({
            status: 'DISCONNECTED',
            qrCode: null,
            phone: null,
            pushName: null,
            lastDisconnectReason: 'LOGGED_OUT'
          });
          console.log('[BAILEYS] 🔄 Menyiapkan QR Code baru dalam 2 detik...');
          cleanupSocket();
          reconnectTimer = setTimeout(() => {
            isConnecting = false;
            startBaileys();
          }, 2000);
        } else if (statusCode === DisconnectReason.connectionReplaced) {
          // Connection replaced by another session
          gatewayStatus = 'DISCONNECTED';
          console.warn('[BAILEYS] Sesi ditimpa perangkat lain (440). Menunggu aksi manual.');
          await firebaseAdapter.updateGatewayStatus({
            status: 'DISCONNECTED',
            qrCode: null,
            lastDisconnectReason: 'CONNECTION_REPLACED'
          });
        } else if (statusCode === DisconnectReason.restartRequired) {
          // 515 = standard restart required after fresh pairing
          console.log('[BAILEYS] WhatsApp meminta restart sesi (515) setelah pairing. Menghubungkan ulang...');
          cleanupSocket();
          reconnectTimer = setTimeout(() => {
            isConnecting = false;
            startBaileys();
          }, 2000);
        } else {
          // Temporary network error
          gatewayStatus = 'DISCONNECTED';
          await firebaseAdapter.updateGatewayStatus({
            status: 'DISCONNECTED',
            qrCode: null,
            lastDisconnectReason: lastDisconnect?.error?.message || 'TEMPORARY_DISCONNECT'
          });
          cleanupSocket();
          console.log('[BAILEYS] Mencoba menghubungkan kembali dalam 6 detik...');
          reconnectTimer = setTimeout(() => {
            isConnecting = false;
            startBaileys();
          }, 6000);
        }
      } else if (connection === 'open') {
        gatewayStatus = 'CONNECTED';
        currentQrDataUrl = null;
        isConnecting = false;
        if (reconnectTimer) {
          clearTimeout(reconnectTimer);
          reconnectTimer = null;
        }

        const userJid = sock.user?.id || '';
        const phone = userJid.split(':')[0].split('@')[0];
        const pushName = sock.user?.name || 'Admin Lucifax';
        connectedUser = { phone, pushName };

        // Claim master and notify Firestore of active device
        await firebaseAdapter.claimMaster(INSTANCE_ID, DEVICE_NAME, process.platform);

        console.log(`[BAILEYS] 🎉 BERHASIL TERHUBUNG & STABIL! Akun: ${pushName} (${phone}) [Perangkat: ${DEVICE_NAME}]`);
        const devDetails = getDeviceDetails();
        await firebaseAdapter.updateGatewayStatus({
          status: 'CONNECTED',
          qrCode: null,
          phone,
          pushName,
          deviceName: devDetails.fullModelName || DEVICE_NAME,
          devicePlatform: process.platform,
          deviceDetails: devDetails,
          instanceId: INSTANCE_ID,
          lastConnectedAt: new Date(),
          lastHeartbeat: new Date()
        });

        // Kirim 1x status aktif saat koneksi terhubung; interval detak berkala ditangani oleh timer 50s
        await firebaseAdapter.sendHeartbeat(INSTANCE_ID, devDetails.fullModelName || DEVICE_NAME, process.platform, getDeviceDetails(), 'CONNECTED');

        // Resolve Whitelist WhatsApp LIDs
        resolveWhitelistLids();
      }
    });

    // Helper to unwrap nested messages (ephemeral, viewOnce, etc.)
    function unwrapMessage(msg) {
      if (!msg) return {};
      let m = msg;
      if (m.ephemeralMessage?.message) m = m.ephemeralMessage.message;
      if (m.viewOnceMessage?.message) m = m.viewOnceMessage.message;
      if (m.viewOnceMessageV2?.message) m = m.viewOnceMessageV2.message;
      if (m.documentWithCaptionMessage?.message) m = m.documentWithCaptionMessage.message;
      return m;
    }

    function extractText(rawMsg) {
      if (!rawMsg) return '';
      const m = unwrapMessage(rawMsg);
      return (
        m.conversation ||
        m.extendedTextMessage?.text ||
        m.imageMessage?.caption ||
        m.videoMessage?.caption ||
        m.documentMessage?.caption ||
        rawMsg.conversation ||
        rawMsg.extendedTextMessage?.text ||
        ''
      ).trim();
    }

    // Process a single incoming or history sync message
    async function processSingleMessage(m, isHistorySync = false) {
      if (!m || !m.message) return;
      if (m.key?.fromMe) return;

      const msgId = m.key?.id;
      if (msgId && processedMessageIds.has(msgId)) {
        return; // Sudah pernah diproses, lewati
      }

      // Parse timestamp pesan
      const rawTs = m.messageTimestamp;
      const tsSec = typeof rawTs === 'number'
        ? rawTs
        : (rawTs?.low || (typeof rawTs?.toNumber === 'function' ? rawTs.toNumber() : 0));
      const msgTimeMs = tsSec > 0 ? tsSec * 1000 : Date.now();

      // Jika sinkronisasi riwayat, batasi pesan maksimal 12 jam terakhir
      const MAX_HISTORY_AGE_MS = 12 * 60 * 60 * 1000;
      if (isHistorySync && (Date.now() - msgTimeMs > MAX_HISTORY_AGE_MS)) {
        return; // Terlalu lama, lewati
      }

      // Deteksi & download foto media jika ada
      const unwrap = unwrapMessage(m.message);
      const isImageMessage = !!(unwrap.imageMessage || m.message?.imageMessage);
      let imageBuffer = null;
      let ocrText = '';
      let bankResult = { isBankSlip: false };
      let imageUrl = null;

      if (isImageMessage) {
        try {
          console.log(`[MEDIA] 📸 Mendeteksi foto masuk dari ${m.pushName || 'pengirim'}. Mengunduh media...`);
          imageBuffer = await downloadMediaMessage(
            m,
            'buffer',
            {},
            {
              logger: pino({ level: 'silent' }),
              reuploadRequest: currentSock?.updateMediaMessage
            }
          );

          if (imageBuffer && imageBuffer.length > 0) {
            console.log(`[MEDIA] 🔍 Menjalankan OCR lokal pada foto (${Math.round(imageBuffer.length / 1024)} KB)...`);
            const ocrRes = await ocrEngine.recognizeImage(imageBuffer);
            ocrText = (ocrRes?.text || '').trim();

            if (ocrText.length > 0) {
              console.log(`[LOCAL OCR] 📝 Hasil scan: "${ocrText.substring(0, 80).replace(/\n/g, ' ')}..."`);
              bankResult = bankSlipParser.parseBankReceipt(ocrText);
              if (bankResult.isBankSlip) {
                console.log(`[BANK SLIP DETECTED] 💳 Terdeteksi Bukti Transfer ${bankResult.bank}! Nominal: Rp ${bankResult.amount.toLocaleString('id-ID')} | Berita: "${bankResult.berita}" | Faktur: #${bankResult.invoiceNo || '-'}`);

                // JIKA BELUM ADA NOMOR FAKTUR DI BERITA: COCOKKAN KE KARTU PIUTANG SECARA OTOMATIS
                if (!bankResult.invoiceNo && bankResult.amount > 0) {
                  try {
                    const matchRec = await firebaseAdapter.findMatchingReceivable(bankResult.customerHint, bankResult.amount);
                    if (matchRec) {
                      bankResult.invoiceNo = matchRec.noInvoice;
                      bankResult.isAutoMatched = true;
                      bankResult.matchedToko = matchRec.toko;
                      bankResult.alreadyPaid = matchRec.isLunas;
                      console.log(`[AUTO-MATCH PIUTANG] 🎯 Berhasil dicocokkan ke Faktur #${matchRec.noInvoice} (${matchRec.toko}) - Nominal: Rp ${bankResult.amount.toLocaleString('id-ID')} (Lunas: ${matchRec.isLunas})`);
                    }
                  } catch (recErr) {
                    console.warn('[MATCH PIUTANG NOTICE]:', recErr.message);
                  }
                }

                // Upload foto struk ke Firebase Storage
                try {
                  const filename = `receipt_${Date.now()}_${msgId || 'img'}.jpg`;
                  imageUrl = await firebaseAdapter.uploadReceiptImage(imageBuffer, filename);
                  console.log(`[STORAGE UPLOAD] ✅ Foto struk diunggah: ${imageUrl}`);
                } catch (upErr) {
                  console.warn('[STORAGE UPLOAD NOTICE]:', upErr.message);
                }
              }
            }
          }
        } catch (mediaErr) {
          console.warn('[MEDIA DOWNLOAD/OCR ERROR]:', mediaErr.message);
        }
      }

      const rawCaption = extractText(m.message);
      let cleanText = rawCaption;

      if (bankResult.isBankSlip) {
        const invTag = bankResult.invoiceNo ? ` (Faktur #${bankResult.invoiceNo})` : '';
        const capTag = rawCaption ? ` - "${rawCaption}"` : '';
        cleanText = `[BUKTI TRANSFER ${bankResult.bank}] Rp ${bankResult.amount.toLocaleString('id-ID')}${invTag}${capTag}`;
      }

      if (!cleanText || cleanText.length === 0) {
        if (isImageMessage && !bankResult.isBankSlip) {
          cleanText = '[FOTO NON-STRUK]';
        } else {
          return;
        }
      }

      const remoteJid = m.key.remoteJid || '';
      const isLid = remoteJid.endsWith('@lid');
      const rawJidDigits = remoteJid.split('@')[0].split(':')[0].replace(/\D/g, '');

      // Extract sender phone
      let senderPhone = '';
      if (m.key.senderPn) {
        senderPhone = cleanPhone(m.key.senderPn);
      } else if (m.key.participantPn) {
        senderPhone = cleanPhone(m.key.participantPn);
      }

      if (!senderPhone && !isLid) {
        senderPhone = cleanPhone(rawJidDigits);
      }

      if (!senderPhone && isLid && lidToPhoneMap.has(rawJidDigits)) {
        senderPhone = lidToPhoneMap.get(rawJidDigits);
      }

      let senderName = m.pushName || 'Kontak WhatsApp';

      // Name matching fallback against whitelistContactsList
      const cleanPushName = (m.pushName || '').trim().toLowerCase();
      let matchedContact = null;
      if (cleanPushName) {
        matchedContact = whitelistContactsList.find(c => {
          const cn = c.name.toLowerCase().trim();
          return cn.length >= 3 && (cleanPushName.includes(cn) || cn.includes(cleanPushName));
        });
      }

      if (matchedContact) {
        if (!senderPhone || isLid) {
          senderPhone = matchedContact.phone;
        }
        if (isLid && rawJidDigits) {
          whitelistLids.add(rawJidDigits);
          lidToPhoneMap.set(rawJidDigits, matchedContact.phone);
          phoneToLidMap.set(matchedContact.phone, rawJidDigits);
          console.log(`[AUTO-LEARN LID] Memetakan WhatsApp LID ${rawJidDigits} ke ${matchedContact.name} (+${matchedContact.phone})`);
        }
        if (!m.pushName || m.pushName === 'Kontak WhatsApp') {
          senderName = matchedContact.name;
        }
      }

      if (!senderPhone) {
        senderPhone = rawJidDigits;
      }

      // STRICT WHITELIST CHECK
      if (strictWhitelistOnly && whitelistNumbers.size > 0) {
        let isAllowed = false;

        if (senderPhone) {
          isAllowed = Array.from(whitelistNumbers).some(wn => {
            const cleanWn = cleanPhone(wn);
            return cleanWn.length >= 7 && (senderPhone.endsWith(cleanWn) || cleanWn.endsWith(senderPhone) || senderPhone === cleanWn);
          });
        }

        if (!isAllowed && rawJidDigits && whitelistLids.has(rawJidDigits)) {
          isAllowed = true;
          if (lidToPhoneMap.has(rawJidDigits)) {
            senderPhone = lidToPhoneMap.get(rawJidDigits);
          }
        }

        if (!isAllowed && matchedContact) {
          isAllowed = true;
        }

        if (!isAllowed) {
          if (!isHistorySync) {
            console.log(`[STRICT FILTER BLOCKED] Pesan dari ${senderName} (+${senderPhone}) diblokir karena nomor tidak terdaftar.`);
          }
          return;
        }
      }

      // Catat msgId ke cache memory agar tidak ganda
      if (msgId) {
        processedMessageIds.add(msgId);
        if (processedMessageIds.size > 5000) {
          const firstEntry = processedMessageIds.values().next().value;
          processedMessageIds.delete(firstEntry);
        }
      }

      const tag = isHistorySync ? '[CHAT TERTUNDA / HISTORY]' : '[CHAT MASUK]';
      console.log(`${tag} Dari ${senderName} (+${senderPhone}): "${cleanText.substring(0, 50)}..."`);

      // =========================================================================
      // KHUSUS BUKTI TRANSFER BANK: BYPASS BUFFER & KIRIM LANGSUNG (1 STRUK = 1 KARTU)
      // Bukti transfer TIDAK BOLEH digabung atau saling menimpa dalam buffer pesanan!
      // =========================================================================
      if (bankResult.isBankSlip) {
        let isAutoSettled = false;
        let isPartial = false;
        let remainingAmount = 0;
        // OPSI B: Jika autoSettle aktif dan nomor faktur teridentifikasi -> LUNASI / CICIL SEKETIKA!
        if (autoSettleTransferSlips && bankResult.invoiceNo) {
          try {
            const settleRes = await firebaseAdapter.settleInvoicePayment(bankResult.invoiceNo, {
              amount: bankResult.amount,
              bank: bankResult.bank,
              imageUrl: imageUrl,
              berita: bankResult.berita,
              refNo: bankResult.refNo,
              senderName: bankResult.matchedToko || senderName
            });
            if (settleRes) {
              isAutoSettled = (settleRes.success === true || settleRes === true);
              isPartial = (settleRes.isLunas === false);
              remainingAmount = settleRes.remaining || 0;
            }
          } catch (setErr) {
            console.warn('[AUTO-SETTLE CALL ERROR]', setErr.message);
          }
        }

        const settleStatus = isAutoSettled ? 'processed' : 'pending';
        const typeLog = isPartial ? `CICILAN (Sisa: Rp ${remainingAmount.toLocaleString('id-ID')})` : 'LUNAS';
        console.log(`[TRANSFER SLIP DISPATCH] 🚀 Bukti transfer ${bankResult.bank} Rp ${bankResult.amount.toLocaleString('id-ID')} dikirim ke Firestore (Status: ${settleStatus}, AutoSettled: ${isAutoSettled}, Tipe: ${typeLog})!`);

        const slipPayload = {
          senderJid: remoteJid,
          senderPhone,
          senderName,
          messageText: cleanText,
          isOrderDetected: false,
          messageType: 'TRANSFER_SLIP',
          hasImage: true,
          imageUrl: imageUrl || null,
          transferInfo: {
            ...bankResult,
            isPartial,
            remainingAmount
          },
          matchedInvoiceNo: bankResult.invoiceNo || null,
          status: settleStatus,
          isPaymentApplied: isAutoSettled,
          isPartialPayment: isPartial,
          remainingAmount: remainingAmount,
          caption: rawCaption || '',
          rawOcrText: ocrText || '',
          messageCount: 1,
          messageId: msgId || '',
          messageIds: msgId ? [msgId] : [],
          receivedAt: new Date(msgTimeMs),
          processedAt: isAutoSettled ? new Date() : null
        };

        recentChats.unshift({
          ...slipPayload,
          receivedAt: new Date()
        });
        if (recentChats.length > 20) recentChats.pop();

        await firebaseAdapter.saveIncomingChat(slipPayload);
        return; // Selesai! Langsung keluar agar tidak masuk buffer chat teks pesanan
      }

      // =========================================================================
      // ALUR PESANAN TEKS BIASA: Tetap menggunakan Debounce Buffer (Jeda 8 detik)
      // =========================================================================
      const lower = cleanText.toLowerCase();
      const isOrderDetected =
        lower.includes('karton') ||
        lower.includes('ktn') ||
        lower.includes('dus') ||
        lower.includes('box') ||
        lower.includes('roll') ||
        lower.includes('pack') ||
        lower.includes('pcs') ||
        lower.includes('beres') ||
        lower.includes('rolade') ||
        lower.includes('kornet') ||
        lower.includes('fiva') ||
        lower.includes('order') ||
        lower.includes('po') ||
        lower.includes('kirim');
      const messageType = isOrderDetected ? 'ORDER_PO' : 'CASUAL_CHAT';

      const bufferKey = senderPhone || rawJidDigits || remoteJid;
      const now = Date.now();
      const waitMs = isHistorySync ? 2000 : DEBOUNCE_WAIT_MS;

      if (pendingMessageBuffers.has(bufferKey)) {
        const buf = pendingMessageBuffers.get(bufferKey);
        buf.texts.push(cleanText);
        if (msgId) buf.messageIds.push(msgId);
        buf.isOrderDetected = buf.isOrderDetected || isOrderDetected;
        buf.lastReceivedAt = now;
        if (senderName && senderName !== 'Kontak WhatsApp') {
          buf.senderName = senderName;
        }

        console.log(`[BUFFER WA] 📥 Chat lanjutan dari ${senderName} (+${senderPhone}) diterima. Pesan ke-${buf.texts.length} digabungkan.`);

        if (buf.timer) clearTimeout(buf.timer);

        const totalHold = now - buf.firstReceivedAt;
        const finalWait = totalHold >= MAX_BUFFER_HOLD_MS ? 100 : waitMs;

        buf.timer = setTimeout(async () => {
          await flushMessageBuffer(bufferKey);
        }, finalWait);
      } else {
        console.log(`[BUFFER WA] ⏳ Chat baru dari ${senderName} (+${senderPhone}) [${messageType}]. Menunggu buffer...`);
        const buf = {
          senderJid: remoteJid,
          senderPhone,
          senderName,
          texts: [cleanText],
          messageIds: msgId ? [msgId] : [],
          isOrderDetected,
          messageType,
          hasImage: isImageMessage,
          imageUrl,
          transferInfo: null,
          matchedInvoiceNo: null,
          caption: rawCaption,
          rawOcrText: ocrText,
          firstReceivedAt: now,
          lastReceivedAt: now,
          receivedAt: new Date(msgTimeMs),
          timer: null,
        };

        buf.timer = setTimeout(async () => {
          await flushMessageBuffer(bufferKey);
        }, waitMs);

        pendingMessageBuffers.set(bufferKey, buf);
      }
    }

    // 1. Tangkap pesan tertunda saat server offline / restart via history sync
    sock.ev.on('messaging-history.set', async ({ messages }) => {
      if (!Array.isArray(messages) || messages.length === 0) return;
      console.log(`[HISTORY SYNC] 📦 WhatsApp mengirim ${messages.length} riwayat pesan. Memeriksa pesan tertunda saat server offline...`);
      const sorted = [...messages].sort((a, b) => {
        const tA = Number(a.messageTimestamp) || 0;
        const tB = Number(b.messageTimestamp) || 0;
        return tA - tB;
      });
      for (const m of sorted) {
        if (m.key && m.message) {
          storeRawMessage(m.key.remoteJid, m.key.id, m.message);
        }
        try {
          await processSingleMessage(m, true);
        } catch (e) {
          console.warn('[HISTORY SYNC ITEM ERROR]', e.message);
        }
      }
    });

    // 2. Tangkap pesan masuk real-time
    sock.ev.on('messages.upsert', async ({ messages, type }) => {
      if (!Array.isArray(messages)) return;
      for (const m of messages) {
        if (m.key && m.message) {
          storeRawMessage(m.key.remoteJid, m.key.id, m.message);
        }
        try {
          await processSingleMessage(m, false);
        } catch (e) {
          console.error('[UPSERT ERROR]', e.message);
        }
      }
    });
  } catch (err) {
    console.error('[BAILEYS ERROR]', err?.message || err);
    gatewayStatus = 'ERROR';
    isConnecting = false;
    await firebaseAdapter.updateGatewayStatus({
      status: 'ERROR',
      lastDisconnectReason: err.message
    });
    cleanupSocket();
    reconnectTimer = setTimeout(() => {
      startBaileys();
    }, 8000);
  }
}

// Switch & Take-over mechanism: activate Gateway on this device cleanly
async function activateGatewayThisDevice(reason = 'MANUAL') {
  if (!isStandby && gatewayStatus === 'CONNECTED') {
    console.log(`\n[INFO] Perangkat "${DEVICE_NAME}" saat ini SUDAH AKTIF dan terhubung ke WhatsApp.`);
    return;
  }

  console.log(`\n======================================================`);
  console.log(`[TAKE-OVER] 🚀 Mengambil alih Gateway untuk "${DEVICE_NAME}" (${reason})...`);
  console.log(`[TAKE-OVER] 📡 Mengirim sinyal kepemilikan Gateway ke server...`);
  console.log(`======================================================\n`);

  isStandby = false;
  lastClaimTime = Date.now();

  try {
    await firebaseAdapter.claimMaster(INSTANCE_ID, DEVICE_NAME, process.platform);
  } catch (e) {
    console.error('[TAKE-OVER ERROR]', e.message);
  }

  cleanupSocket();
  isConnecting = false;
  setTimeout(startBaileys, 1000);
}

// Setup interactive stdin listener for instant takeover via Enter key in Termux
try {
  if (process.stdin.setEncoding) {
    process.stdin.setEncoding('utf8');
  }
  if (typeof process.stdin.resume === 'function') {
    process.stdin.resume();
  }
  process.stdin.on('data', async (chunk) => {
    if (isStandby) {
      await activateGatewayThisDevice('TOMBOL ENTER DI TERMINAL');
    } else {
      console.log(`\n[INFO] Perangkat "${DEVICE_NAME}" saat ini sedang AKTIF.`);
      console.log(`👉 Untuk beralih ke HP lain: Buka Termux di HP tersebut lalu tekan [ENTER].\n`);
    }
  });
} catch (e) {
  console.warn('[STDIN WARNING] Tidak dapat mendengarkan input keyboard:', e.message);
}

// Preemption Listener: If another device starts node server.js and claims master, yield immediately
firebaseAdapter.listenToMaster(INSTANCE_ID, async (masterData) => {
  if (!masterData || !masterData.activeInstanceId || masterData.activeInstanceId === INSTANCE_ID) return;

  const claimedTimeMs = masterData.claimedAt?.toDate?.()?.getTime() || 
    (typeof masterData.claimedAt === 'string' ? new Date(masterData.claimedAt).getTime() : 0);
  
  // Abaikan klaim lama sebelum proses ini dinyalakan / diaktifkan ulang
  if (claimedTimeMs <= lastClaimTime) {
    return;
  }

  // Abaikan jika master lain sudah mati/tidak ada detak sinyal (> 35 detik)
  const lastHeartbeatMs = masterData.lastHeartbeat?.toDate?.()?.getTime() || 0;
  if (lastHeartbeatMs > 0 && (Date.now() - lastHeartbeatMs > 35000)) {
    return;
  }

  if (!isStandby) {
    console.log(`\n======================================================`);
    console.log(`[AUTO-YIELD] ⚠️ Terdeteksi "${masterData.activeDeviceName || 'Perangkat Lain'}" baru saja mengambil alih Gateway!`);
    console.log(`[AUTO-YIELD] 💤 Menutup koneksi WhatsApp dan masuk ke mode STANDBY agar tidak terjadi bentrok.`);
    console.log(`👉 Ingin beralih ke HP ini lagi? Cukup tekan [ENTER] di layar ini kapan saja!`);
    console.log(`======================================================\x07\n`);
    isStandby = true;
    cleanupSocket();
    gatewayStatus = 'STANDBY';
    isConnecting = false;
    await firebaseAdapter.updateGatewayStatus({
      status: 'STANDBY',
      standbyDevice: DEVICE_NAME
    });
  }
});

// Listen to commands from Flutter via Firestore
let restartDebounceTimer = null;
firebaseAdapter.listenToCommands(async (cmd, data) => {
  console.log(`[COMMAND DITERIMA DARI FLUTTER]: ${cmd}`, data || '');
  if (cmd === 'SWITCH_TO') {
    const targetId = data?.targetInstanceId;
    const targetName = data?.targetDeviceName;
    const details = getDeviceDetails();
    const isTarget = (targetId && targetId === INSTANCE_ID) ||
                     (targetName && (targetName === DEVICE_NAME || targetName === details.fullModelName));

    if (isTarget) {
      console.log(`[COMMAND SWITCH_TO] 🎯 Perangkat ini dipilih secara spesifik dari Website untuk diaktifkan!`);
      await activateGatewayThisDevice('WEBSITE TARGETED SWITCH');
    } else {
      console.log(`[COMMAND SWITCH_TO] Instruksi ditujukan untuk perangkat lain (${targetName || targetId}), perangkat ini tetap STANDBY.`);
    }
  } else if (cmd === 'SWITCH_DEVICE' || cmd === 'SWITCH_GATEWAY') {
    if (isStandby) {
      console.log(`[COMMAND] Menerima instruksi alih perangkat dari Website/App untuk mengaktifkan "${DEVICE_NAME}"!`);
      await activateGatewayThisDevice('WEBSITE COMMAND');
    } else {
      console.log(`[COMMAND] Perangkat "${DEVICE_NAME}" sudah aktif, mengabaikan sinyal switch.`);
    }
  } else if (cmd === 'RESTART') {
    if (isStandby) {
      console.log('[COMMAND RESTART] Perangkat ini dalam mode STANDBY, abaikan restart agar tidak bentrok.');
      return;
    }
    if (restartDebounceTimer) {
      console.log('[COMMAND RESTART] Mengabaikan perintah restart ganda yang beruntun...');
      return;
    }
    restartDebounceTimer = setTimeout(() => {
      restartDebounceTimer = null;
    }, 5000);

    isStandby = false;
    lastClaimTime = Date.now();
    await firebaseAdapter.claimMaster(INSTANCE_ID, DEVICE_NAME, process.platform);
    cleanupSocket();
    isConnecting = false;
    setTimeout(startBaileys, 1500);
  } else if (cmd === 'LOGOUT') {
    cleanupSocket();
    try {
      fs.rmSync(AUTH_DIR, { recursive: true, force: true });
    } catch (_) {}
    gatewayStatus = 'DISCONNECTED';
    await firebaseAdapter.updateGatewayStatus({
      status: 'DISCONNECTED',
      qrCode: null,
      phone: null,
      pushName: null,
      lastDisconnectReason: 'MANUAL_LOGOUT'
    });
    isConnecting = false;
    setTimeout(startBaileys, 2000);
  }
});

// ==========================================
// REST API & WEB DASHBOARD ENDPOINTS
// ==========================================

app.get('/api/status', (req, res) => {
  res.json({
    status: gatewayStatus,
    phone: connectedUser?.phone || null,
    pushName: connectedUser?.pushName || null,
    hasQr: !!currentQrDataUrl,
    recentChatsCount: recentChats.length,
    timestamp: new Date()
  });
});

app.get('/api/qr', (req, res) => {
  res.json({
    status: gatewayStatus,
    qrCode: currentQrDataUrl
  });
});

app.post('/api/restart', (req, res) => {
  cleanupSocket();
  isConnecting = false;
  setTimeout(startBaileys, 1000);
  res.json({ success: true, message: 'Gateway direstart.' });
});

app.post('/api/logout', async (req, res) => {
  cleanupSocket();
  try { fs.rmSync(AUTH_DIR, { recursive: true, force: true }); } catch (_) {}
  isConnecting = false;
  setTimeout(startBaileys, 2000);
  res.json({ success: true, message: 'Sesi di-logout dan dihapus.' });
});

// Endpoint untuk simulasi pesan masuk saat dev / testing
app.post('/api/simulate-chat', async (req, res) => {
  const { senderName, senderPhone, text } = req.body;
  if (!text) return res.status(400).json({ error: 'Field "text" wajib diisi' });

  const payload = {
    senderJid: `${senderPhone || '6281234567890'}@s.whatsapp.net`,
    senderPhone: senderPhone || '6281234567890',
    senderName: senderName || 'Pak BC (Simulasi Dev)',
    messageText: text,
    isOrderDetected: true
  };

  const docId = await firebaseAdapter.saveIncomingChat(payload);
  recentChats.unshift({ ...payload, receivedAt: new Date() });
  res.json({ success: true, docId, message: 'Simulasi pesan berhasil disimpan ke Firestore!' });
});

// HTML Dashboard
app.get('/', (req, res) => {
  const html = `
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Lucifax-PFS WhatsApp Gateway</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 30px; }
    .card { background: #1e293b; border-radius: 12px; padding: 24px; max-width: 650px; margin: 0 auto; box-shadow: 0 10px 25px rgba(0,0,0,0.5); border: 1px solid #334155; }
    h1 { font-size: 20px; margin-top: 0; display: flex; align-items: center; gap: 10px; color: #38bdf8; }
    .badge { display: inline-block; padding: 6px 12px; border-radius: 20px; font-weight: bold; font-size: 13px; }
    .badge-connected { background: #065f46; color: #34d399; }
    .badge-qr { background: #78350f; color: #fbbf24; }
    .badge-disconnected { background: #7f1d1d; color: #f87171; }
    .qr-container { text-align: center; margin: 25px 0; background: #ffffff; padding: 15px; border-radius: 12px; display: inline-block; }
    .btn { background: #0284c7; color: white; border: none; padding: 10px 18px; border-radius: 8px; font-weight: bold; cursor: pointer; text-decoration: none; display: inline-block; margin-right: 8px; }
    .btn-danger { background: #dc2626; }
    .instructions { font-size: 13px; color: #94a3b8; line-height: 1.6; margin: 15px 0; }
  </style>
  <script>
    setTimeout(() => { if (document.getElementById('status-tag').dataset.status !== 'CONNECTED') location.reload(); }, 6000);
  </script>
</head>
<body>
  <div class="card">
    <h1>📱 Lucifax-PFS WhatsApp Gateway</h1>
    <p>Status Gateway: 
      <span id="status-tag" data-status="${gatewayStatus}" class="badge ${gatewayStatus === 'CONNECTED' ? 'badge-connected' : (gatewayStatus === 'QR_READY' ? 'badge-qr' : 'badge-disconnected')}">
        ${gatewayStatus}
      </span>
    </p>

    ${gatewayStatus === 'CONNECTED' ? `
      <div style="background: #064e3b; border: 1px solid #059669; padding: 16px; border-radius: 10px; margin: 20px 0;">
        <h3 style="margin: 0 0 6px 0; color: #6ee7b7;">✅ Perangkat Terhubung!</h3>
        <p style="margin: 0; color: #a7f3d0; font-size: 14px;">Nomor WA: <strong>+${connectedUser?.phone || ''}</strong> (${connectedUser?.pushName || ''})</p>
        <p style="margin: 6px 0 0 0; color: #6ee7b7; font-size: 12px;">Gateway aktif mendengarkan chat dari Pak BC dan otomatis menginput ke sistem sebagai antrean PO.</p>
      </div>
    ` : ''}

    ${gatewayStatus === 'QR_READY' && currentQrDataUrl ? `
      <div style="text-align: center;">
        <div class="qr-container">
          <img src="${currentQrDataUrl}" alt="Scan QR Code" style="width: 280px; height: 280px;" />
        </div>
        <div class="instructions">
          1. Buka WhatsApp di Ponsel Anda<br>
          2. Masuk ke <strong>Menu (titik 3) > Perangkat Tertaut</strong><br>
          3. Ketuk <strong>Tautkan Perangkat</strong> dan arahkan kamera ke QR di atas.
        </div>
      </div>
    ` : ''}

    <div style="margin-top: 25px;">
      <button class="btn" onclick="fetch('/api/restart', {method:'POST'}).then(() => location.reload())">🔄 Restart Gateway</button>
      <button class="btn btn-danger" onclick="if(confirm('Logout perangkat ini?')) fetch('/api/logout', {method:'POST'}).then(() => location.reload())">🚪 Putuskan Sesi / Logout</button>
    </div>
  </div>
</body>
</html>
  `;
  res.send(html);
});

// Start Express server & Baileys
app.listen(PORT, () => {
  console.log(`[WA GATEWAY SERVER] Berjalan di http://localhost:${PORT}`);
  startBaileys();
});
