require('dotenv').config();
const GATEWAY_VERSION = '3.3.272'; // v3.3.272 - 2 Notifikasi Bertahap L-W.A.V.I.S (Pesan Masuk & Hasil PO FCM)
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
const { NotificationDispatcher, NOTIF_VERSION } = require('./notification-dispatcher');
const notificationDispatcher = new NotificationDispatcher(firebaseAdapter);
const AutonomousPoProcessor = require('./autonomous-po-processor');
const autoPoProcessor = new AutonomousPoProcessor(firebaseAdapter, notificationDispatcher);
if (firebaseAdapter && typeof firebaseAdapter.setNotificationDispatcher === 'function') {
  firebaseAdapter.setNotificationDispatcher(notificationDispatcher);
}

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
    gatewayVersion: GATEWAY_VERSION,
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
let disabledNumbers = new Set(); // Set of numbers turned OFF in settings
let disabledLids = new Set(); // Set of WhatsApp LIDs belonging to OFF numbers
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

// Helper: Deteksi apakah teks OCR adalah screenshot terminal / log / kode program
// Mencegah foto screenshot terminal (yang mengandung kata produk di dalam log) diproses sebagai pesanan
function _looksLikeScreenshot(t) {
  const indicators = [
    '[autonomous po]', '[buffer wa', '[chat masuk]', '[firebase]',
    '[update check]', '[settings sync]', '[cache init]', '[baileys]',
    '[local ocr]', '[media]', '[lid resolved]', '[auto-learn lid]',
    '[gateway process', '[device identifier]', 'node server.js',
    'version.json', '~/wa-gateway', 'curl -o', 'curl -l',
    'npm install', 'pm2 restart', 'console.log', 'require(',
    'module.exports', 'async function', 'firebase admin sdk',
    'serviceaccountkey', 'berhasil dibuat dari termux',
    'l-w.a.v.i.s', 'lucifax-pfs gateway', 'gateway updater',
    'update tersedia', 'gateway berhasil diupdate',
    'faktur #', 'grand total: rp', 'history match:',
    'autonomous po success', 'menunggu 120 detik',
  ];
  const matchCount = indicators.filter(ind => t.includes(ind)).length;
  if (matchCount >= 2) {
    console.log(`[SCREENSHOT FILTER] 🖼️ Teks terdeteksi sebagai screenshot terminal/log (${matchCount} indikator). Diabaikan sebagai bukan pesanan.`);
    return true;
  }
  return false;
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
    quotedInvoiceNo: buf.quotedInvoiceNo || null,
    quotedOcrText: buf.quotedOcrText || '',
    quotedImageUrl: buf.quotedImageUrl || null,
    quotedMessageText: buf.quotedMessageText || '',
    quotedStanzaId: buf.quotedStanzaId || null,
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

  const savedId = await firebaseAdapter.saveIncomingChat(chatPayload);

  // NOTIFIKASI TAHAP 1: PESAN / FOTO MASUK (REAL-TIME FCM KE HP)
  notificationDispatcher.sendIncomingMessageAlert({
    senderName: buf.senderName,
    senderPhone: buf.senderPhone,
    messageText: combinedText,
    hasImage: !!buf.hasImage,
    isTransfer: isTransfer
  });

  // Autonomous Auto-PO execution (khusus Termux saat laptop kasir mati / background)
  // DELAY 2 MENIT: Beri kesempatan Flutter (web/mobile) untuk proses duluan.
  // Jika Flutter sudah handle (status = processed), Termux SKIP.
  // Jika setelah 2 menit masih pending, Termux buat PO sendiri (dengan customer history pricing).
  if (autoPoEnabled && chatPayload.messageType === 'ORDER_PO' && !chatPayload.isQuotedReply) {
    const DELAY_MS = 2 * 60 * 1000; // 2 menit
    console.log(`[AUTONOMOUS PO] ⏱️ Menunggu ${DELAY_MS / 1000} detik sebelum proses PO otonom (memberi prioritas Flutter)...`);
    setTimeout(async () => {
      try {
        // Cek apakah Flutter sudah proses chat ini
        const chatDoc = await firebaseAdapter.getChatDocument(savedId);
        if (chatDoc && chatDoc.status === 'processed') {
          console.log(`[AUTONOMOUS PO] ⏭️ Chat ${savedId} sudah diproses oleh Flutter (Invoice #${chatDoc.createdInvoiceNo || '?'}). SKIP.`);
          return;
        }
        // Masih pending → Termux handle
        console.log(`[AUTONOMOUS PO] 🤖 Chat ${savedId} masih pending setelah ${DELAY_MS / 1000}s. Termux ambil alih proses PO...`);
        await autoPoProcessor.processAutonomousPo(savedId, chatPayload);
      } catch (err) {
        console.warn('[AUTONOMOUS PO BG ERROR]', err.message);
      }
    }, DELAY_MS);
  }
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
    const newDisabledNumbers = new Set();
    const newDisabledLids = new Set();

    settings.whitelistContacts.forEach(it => {
      const isEnabled = it.enabled !== false && it.enabled !== 'false';
      const c = cleanPhone(it.phone || it.number);
      const name = (it.name || '').trim();
      if (!c) return;

      if (!isEnabled) {
        newDisabledNumbers.add(c);
        if (phoneToLidMap.has(c)) {
          const mappedLid = phoneToLidMap.get(c);
          whitelistLids.delete(mappedLid);
          newDisabledLids.add(mappedLid);
        }
        return;
      }

      newNumbers.add(c);
      whitelistContactsList.push({ name, phone: c });
      if (phoneToLidMap.has(c)) {
        const mappedLid = phoneToLidMap.get(c);
        whitelistLids.add(mappedLid);
      }
    });

    whitelistNumbers = newNumbers;
    disabledNumbers = newDisabledNumbers;
    disabledLids = newDisabledLids;
  } else if (Array.isArray(settings.whitelistNumbers)) {
    whitelistContactsList = [];
    const newNumbers = new Set(
      (process.env.TARGET_PHONE_NUMBERS || '')
        .split(',')
        .map(s => cleanPhone(s))
        .filter(Boolean)
    );
    disabledNumbers.clear();
    disabledLids.clear();

    settings.whitelistNumbers.forEach(n => {
      const c = cleanPhone(n);
      if (c) {
        newNumbers.add(c);
        whitelistContactsList.push({ name: 'Kontak WA', phone: c });
      }
    });

    whitelistNumbers = newNumbers;
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

      // =========================================================================
      // DETEKSI TIPE PESAN: Forwarded vs Quoted Reply vs Biasa
      // =========================================================================
      const allCtxInfo = unwrapMessage(m.message)?.extendedTextMessage?.contextInfo
        || m.message?.extendedTextMessage?.contextInfo
        || unwrapMessage(m.message)?.imageMessage?.contextInfo
        || m.message?.imageMessage?.contextInfo;

      const isForwardedMessage = !!(allCtxInfo?.isForwarded || allCtxInfo?.forwardingScore > 0);
      const isQuotedReply = !!(allCtxInfo?.quotedMessage);

      if (isForwardedMessage) {
        console.log(`[MSG TYPE] ↪️ Pesan FORWARDED (diteruskan) terdeteksi.`);
      }
      if (isQuotedReply) {
        console.log(`[MSG TYPE] 💬 Pesan REPLY/QUOTE terdeteksi.`);
      }

      // =========================================================================
      // TAHAP 2: QUOTED MESSAGE VISION - Tangkap foto yang di-reply/tag
      // =========================================================================
      let quotedInvoiceNo = null;
      let quotedOcrText = '';
      let quotedImageUrl = null;
      let quotedMessageText = '';
      let quotedStanzaId = null;
      let quotedBankResult = { isBankSlip: false };

      try {
        const ctxInfo = allCtxInfo;

        if (ctxInfo && ctxInfo.quotedMessage) {
          const quotedMsg = unwrapMessage(ctxInfo.quotedMessage);
          const hasQuotedImage = !!(quotedMsg.imageMessage);

          if (hasQuotedImage) {
            console.log(`[QUOTED VISION] 🔎 Terdeteksi reply/tag foto! Mencoba download gambar yang di-reply...`);

            try {
              // Reconstruct a minimal message object for downloadMediaMessage
              const quotedMediaMsg = {
                key: {
                  remoteJid: m.key.remoteJid,
                  id: ctxInfo.stanzaId || m.key.id,
                  fromMe: false,
                },
                message: ctxInfo.quotedMessage,
              };

              const quotedBuffer = await downloadMediaMessage(
                quotedMediaMsg,
                'buffer',
                {},
                {
                  logger: pino({ level: 'silent' }),
                  reuploadRequest: currentSock?.updateMediaMessage,
                }
              );

              if (quotedBuffer && quotedBuffer.length > 0) {
                console.log(`[QUOTED VISION] 📸 Berhasil download foto yang di-tag (${Math.round(quotedBuffer.length / 1024)} KB). Menjalankan OCR...`);
                const qOcr = await ocrEngine.recognizeImage(quotedBuffer);
                quotedOcrText = (qOcr?.text || '').trim();

                if (quotedOcrText.length > 0) {
                  console.log(`[QUOTED VISION OCR] 📝 Hasil scan foto yang di-tag: "${quotedOcrText.substring(0, 100).replace(/\n/g, ' ')}..."`);

                  // Cek apakah foto yang di-tag adalah BUKTI TRANSFER BANK
                  quotedBankResult = bankSlipParser.parseBankReceipt(quotedOcrText);
                  if (quotedBankResult.isBankSlip) {
                    console.log(`[QUOTED VISION BANK SLIP] 💳 Bukti Transfer ${quotedBankResult.bank} terdeteksi dari foto yang di-tag! Nominal: Rp ${quotedBankResult.amount.toLocaleString('id-ID')} | Berita: "${quotedBankResult.berita}"`);
                    if (quotedBankResult.invoiceNo) {
                      quotedInvoiceNo = quotedBankResult.invoiceNo;
                    }
                  }

                  // Ekstrak nomor invoice dari OCR teks jika belum ada
                  if (!quotedInvoiceNo) {
                    const invoiceMatch = quotedOcrText.match(/(?:Invoice|Faktur|INVOICE|FAKTUR)\s*#?\s*(\d{2,6})/i);
                    if (invoiceMatch) {
                      quotedInvoiceNo = invoiceMatch[1];
                      console.log(`[QUOTED VISION] 🎯 Nomor invoice terdeteksi dari foto yang di-tag: #${quotedInvoiceNo}`);
                    } else {
                      // Fallback: cari pattern "#123" standalone
                      const hashMatch = quotedOcrText.match(/#(\d{2,6})\b/);
                      if (hashMatch) {
                        quotedInvoiceNo = hashMatch[1];
                        console.log(`[QUOTED VISION] 🎯 Nomor invoice (fallback hash) dari foto yang di-tag: #${quotedInvoiceNo}`);
                      }
                    }
                  }
                }

                // Upload foto quoted ke Firebase Storage untuk ditampilkan di UI
                try {
                  const qFilename = `quoted_${Date.now()}_${msgId || 'img'}.jpg`;
                  quotedImageUrl = await firebaseAdapter.uploadReceiptImage(quotedBuffer, qFilename);
                  console.log(`[QUOTED VISION UPLOAD] ✅ Foto yang di-tag diunggah: ${quotedImageUrl}`);
                } catch (qUpErr) {
                  console.warn(`[QUOTED VISION UPLOAD ERROR] Gagal upload foto quoted: ${qUpErr.message}`);
                }
              }
            } catch (quotedDlErr) {
              console.warn(`[QUOTED VISION DOWNLOAD ERROR] Gagal download foto yang di-reply: ${quotedDlErr.message}`);
            }
          } else {
            // Quoted message is text — extract full text and check invoice / previous chat linkage
            const quotedText = ctxInfo.quotedMessage?.conversation
              || ctxInfo.quotedMessage?.extendedTextMessage?.text
              || unwrapMessage(ctxInfo.quotedMessage)?.conversation
              || unwrapMessage(ctxInfo.quotedMessage)?.extendedTextMessage?.text
              || '';
            if (quotedText) {
              quotedMessageText = quotedText.trim();
              quotedStanzaId = ctxInfo.stanzaId || null;
              quotedOcrText = quotedText.trim();
              console.log(`[QUOTED TEXT] 💬 Teks yang di-reply: "${quotedMessageText.substring(0, 100).replace(/\n/g, ' ')}"`);

              // Cek apakah teks yang di-tag adalah BUKTI TRANSFER
              quotedBankResult = bankSlipParser.parseBankReceipt(quotedText);
              if (quotedBankResult.isBankSlip) {
                console.log(`[QUOTED TEXT BANK SLIP] 💳 Bukti Transfer ${quotedBankResult.bank} terdeteksi dari teks yang di-tag! Nominal: Rp ${quotedBankResult.amount.toLocaleString('id-ID')}`);
                if (quotedBankResult.invoiceNo) {
                  quotedInvoiceNo = quotedBankResult.invoiceNo;
                }
              }

              const textInvMatch = quotedText.match(/(?:Invoice|Faktur|INVOICE|FAKTUR)\s*#?\s*(\d{2,6})/i)
                || quotedText.match(/#(\d{2,6})\b/);
              if (textInvMatch) {
                quotedInvoiceNo = textInvMatch[1];
                console.log(`[QUOTED TEXT] 🎯 Nomor invoice dari teks yang di-reply: #${quotedInvoiceNo}`);
              } else if (quotedStanzaId) {
                // Check if stanzaId matches an earlier order chat in Firestore
                try {
                  const prevChat = await firebaseAdapter.findChatByMessageId(quotedStanzaId);
                  if (prevChat && prevChat.createdInvoiceNo) {
                    quotedInvoiceNo = prevChat.createdInvoiceNo.replace(/[^0-9]/g, '');
                    console.log(`[QUOTED STANZA MATCH] 🎯 Menemukan Invoice #${quotedInvoiceNo} dari pesan order sebelumnya!`);
                  }
                } catch (_) {}
              }
            }
          }
        }
      } catch (quotedErr) {
        console.warn('[QUOTED VISION ERROR]:', quotedErr.message);
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
                    const combinedHint = [bankResult.customerHint, bankResult.senderNameFromSlip, bankResult.berita, senderName].filter(Boolean).join(' ');
                    const matchRec = await firebaseAdapter.findMatchingReceivable(combinedHint, bankResult.amount, ocrText);
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
          if (ocrText && ocrText.length > 0) {
            cleanText = ocrText;
          } else {
            cleanText = '[FOTO NON-STRUK]';
          }
        } else {
          return;
        }
      } else if (isImageMessage && !bankResult.isBankSlip && ocrText && ocrText.length > 0) {
        cleanText = `${rawCaption}\n${ocrText}`;
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

      // 1. CEK KHUSUS STATUS OFF: Jika nomor atau WhatsApp LID ini dimatikan (OFF), LANGSUNG BLOKIR!
      const isSenderDisabled =
        (senderPhone && Array.from(disabledNumbers).some(dn => senderPhone.endsWith(dn) || dn.endsWith(senderPhone) || senderPhone === dn)) ||
        (rawJidDigits && disabledLids.has(rawJidDigits)) ||
        (isLid && lidToPhoneMap.has(rawJidDigits) && Array.from(disabledNumbers).some(dn => lidToPhoneMap.get(rawJidDigits).endsWith(dn) || dn.endsWith(lidToPhoneMap.get(rawJidDigits))));

      if (isSenderDisabled) {
        if (!isHistorySync) {
          console.log(`[STRICT FILTER BLOCKED] ⛔ Pesan dari ${senderName} (+${senderPhone || rawJidDigits}) diblokir seketika karena status kontak sedang DIMATIKAN (OFF).`);
        }
        return;
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
          if (lidToPhoneMap.has(rawJidDigits)) {
            const mappedPhone = cleanPhone(lidToPhoneMap.get(rawJidDigits));
            if (Array.from(whitelistNumbers).some(wn => cleanPhone(wn) === mappedPhone || mappedPhone.endsWith(cleanPhone(wn)))) {
              isAllowed = true;
              senderPhone = mappedPhone;
            } else {
              isAllowed = false;
            }
          }
        }

        if (!isAllowed && matchedContact) {
          const mcPhone = cleanPhone(matchedContact.phone);
          if (Array.from(whitelistNumbers).some(wn => cleanPhone(wn) === mcPhone || mcPhone.endsWith(cleanPhone(wn)))) {
            isAllowed = true;
          }
        }

        if (!isAllowed) {
          if (!isHistorySync) {
            console.log(`[STRICT FILTER BLOCKED] Pesan dari ${senderName} (+${senderPhone || rawJidDigits}) diblokir karena nomor tidak terdaftar.`);
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
              rawDate: bankResult.rawDate,
              rawOcrText: ocrText,
              receivedAt: new Date(msgTimeMs),
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

        // NOTIFIKASI TAHAP 1: BUKTI TRANSFER MASUK (REAL-TIME FCM KE HP)
        notificationDispatcher.sendIncomingMessageAlert({
          senderName: senderName,
          senderPhone: senderPhone,
          messageText: cleanText,
          hasImage: true,
          isTransfer: true
        });

        // NOTIFIKASI TAHAP 2: JIKA SUDAH AUTO-SETTLED (LUNAS)
        if (isAutoSettled && bankResult.invoiceNo) {
          notificationDispatcher.sendReceivablePaidAlert({
            bankName: bankResult.bank,
            amount: bankResult.amount,
            invoiceNo: bankResult.invoiceNo,
            customerName: bankResult.matchedToko || senderName
          });
        }

        return; // Selesai! Langsung keluar agar tidak masuk buffer chat teks pesanan
      }

      // =========================================================================
      // KHUSUS DOKUMEN BARANG DATANG / SURAT JALAN PABRIK KE FIVA:
      // Penerima adalah PT Putra Fiva Sejahtera (Gudang Solo).
      // Ini adalah STOK MASUK / PENERIMAAN BARANG, BUKAN PO PENJUALAN KE PELANGGAN!
      // JANGAN PERNAH dibuatkan Faktur Penjualan otomatis oleh Auto-PO!
      // =========================================================================
      const upperOcr = (ocrText || '').toUpperCase();
      const isBarangDatang =
        (upperOcr.includes('SHIPPING ADDRESS') || upperOcr.includes('CUSTOMER ADDRESS') || upperOcr.includes('DELIVERY ORDER') || upperOcr.includes('SURAT JALAN') || upperOcr.includes('ORDER#')) &&
        (upperOcr.includes('PUTRA FIVA') || upperOcr.includes('FIVA SEJAHTERA') || upperOcr.includes('JOKO SETIAWAN'));

      if (isBarangDatang) {
        console.log(`[BARANG DATANG] 📦 Terdeteksi Dokumen Penerimaan Barang Datang / Surat Jalan Pabrik ke Fiva! (Bukan PO Penjualan)`);
        if (imageBuffer && !imageUrl) {
          try {
            const filename = `surat_jalan_${Date.now()}_${msgId || 'img'}.jpg`;
            imageUrl = await firebaseAdapter.uploadReceiptImage(imageBuffer, filename);
          } catch (_) {}
        }

        const bdPayload = {
          senderJid: remoteJid,
          senderPhone,
          senderName,
          messageText: `[FOTO DOKUMEN PABRIK / SURAT JALAN]${rawCaption ? ' ' + rawCaption : ''}`.trim(),
          isOrderDetected: false,
          messageType: 'CASUAL_CHAT',
          hasImage: true,
          imageUrl: imageUrl || null,
          transferInfo: null,
          matchedInvoiceNo: null,
          status: 'dismissed', // Otomatis masuk tab Diabaikan / Bukan Order (Opsi B)
          dismissReason: 'BUKAN_ORDER',
          caption: rawCaption || '',
          rawOcrText: ocrText || '',
          messageCount: 1,
          messageId: msgId || '',
          messageIds: msgId ? [msgId] : [],
          receivedAt: new Date(msgTimeMs)
        };

        recentChats.unshift({
          ...bdPayload,
          receivedAt: new Date()
        });
        if (recentChats.length > 20) recentChats.pop();

        await firebaseAdapter.saveIncomingChat(bdPayload);
        return; // Selesai!
      }

      // =========================================================================
      // KHUSUS FORWARDED & QUOTED REPLY: BYPASS BUFFER & KIRIM TERPISAH
      // Forwarded message = 1 PO dari 1 toko (sudah lengkap dalam 1 bubble)
      // Quoted reply = revisi/balasan ke invoice foto (harus jadi dokumen sendiri)
      // TIDAK BOLEH digabung dengan pesan lain dalam buffer!
      // =========================================================================
      if (isForwardedMessage || isQuotedReply) {
        // =========================================================================
        // KHUSUS BALASAN / QUOTED KE BUKTI TRANSFER (TRANSFER SLIP REPLY):
        // Pengguna membalas struk transfer dengan teks (misal nama toko "mister sosis"
        // atau nomor invoice "#649"). Ini BUKAN PO baru!
        // WAVIS mencocokkan nominal struk + petunjuk toko ke piutang/faktur,
        // lalu melunasi faktur secara otomatis jika cocok.
        // =========================================================================
        let isReplyToTransfer = isQuotedReply && (quotedBankResult.isBankSlip || (quotedOcrText && quotedOcrText.includes('BUKTI TRANSFER')));

        if (!isReplyToTransfer && isQuotedReply && quotedStanzaId) {
          try {
            const prevChat = await firebaseAdapter.findChatByMessageId(quotedStanzaId);
            if (prevChat && (prevChat.messageType === 'TRANSFER_SLIP' || prevChat.transferInfo?.isBankSlip)) {
              isReplyToTransfer = true;
              if (!quotedBankResult.isBankSlip && prevChat.transferInfo) {
                quotedBankResult = { ...prevChat.transferInfo };
              }
            }
          } catch (_) {}
        }

        if (isReplyToTransfer) {
          console.log(`[TRANSFER SLIP REPLY] 🔗 Balasan ke Bukti Transfer ${quotedBankResult.bank || ''} Rp ${quotedBankResult.amount?.toLocaleString('id-ID') || 0} dari ${senderName}: "${cleanText}"`);

          let targetInvoiceNo = quotedInvoiceNo || quotedBankResult.invoiceNo || null;
          let matchedReceivable = null;

          // 1. Cek nomor invoice di teks balasan
          const directInvMatch = cleanText.match(/(?:Invoice|Faktur|INVOICE|FAKTUR)\s*#?\s*(\d{2,6})/i) || cleanText.match(/#(\d{2,6})\b/);
          if (directInvMatch) {
            targetInvoiceNo = directInvMatch[1];
          }

          // 2. Jika belum ada nomor invoice, cocokkan teks balasan (nama toko) + nominal struk ke piutang / faktur
          const slipAmount = quotedBankResult.amount || 0;
          if (!targetInvoiceNo && slipAmount > 0) {
            try {
              const combinedHint = [cleanText, quotedBankResult.customerHint, quotedBankResult.senderNameFromSlip, quotedBankResult.berita].filter(Boolean).join(' ');
              matchedReceivable = await firebaseAdapter.findMatchingReceivable(combinedHint, slipAmount, quotedOcrText);
              if (matchedReceivable) {
                targetInvoiceNo = matchedReceivable.noInvoice;
                quotedBankResult.invoiceNo = matchedReceivable.noInvoice;
                quotedBankResult.matchedToko = matchedReceivable.toko;
                quotedBankResult.isAutoMatched = true;
                console.log(`[TRANSFER SLIP REPLY MATCH] 🎯 Balasan "${cleanText}" berhasil mencocokkan Faktur #${targetInvoiceNo} (${matchedReceivable.toko})!`);
              }
            } catch (mErr) {
              console.warn('[TRANSFER SLIP REPLY MATCH ERROR]', mErr.message);
            }
          }

          // 3. Jika nomor faktur teridentifikasi -> LUNASI / CICIL OTOMATIS
          let isAutoSettled = false;
          let isPartial = false;
          let remainingAmount = 0;

          if (autoSettleTransferSlips && targetInvoiceNo) {
            try {
              const settleRes = await firebaseAdapter.settleInvoicePayment(targetInvoiceNo, {
                amount: slipAmount,
                bank: quotedBankResult.bank || 'TRANSFER',
                imageUrl: quotedImageUrl || '',
                berita: quotedBankResult.berita || cleanText,
                refNo: quotedBankResult.refNo || '',
                rawDate: quotedBankResult.rawDate || '',
                rawOcrText: quotedOcrText,
                receivedAt: new Date(msgTimeMs),
                senderName: matchedReceivable?.toko || cleanText || senderName
              });
              if (settleRes) {
                isAutoSettled = (settleRes.success === true || settleRes === true);
                isPartial = (settleRes.isLunas === false);
                remainingAmount = settleRes.remaining || 0;
              }
            } catch (setErr) {
              console.warn('[TRANSFER SLIP REPLY SETTLE ERROR]', setErr.message);
            }

            // Simpan memori aturan ke ai_knowledge_rules (Engine Self-Learning)
            if (matchedReceivable?.toko && cleanText) {
              await firebaseAdapter.saveAiKnowledgeRule({
                type: 'customer_alias',
                keyword: cleanText,
                mappedValue: matchedReceivable.toko,
                source: 'WA_GATEWAY_TRANSFER_REPLY'
              });
            }

            // Perbarui dokumen chat struk transfer aslinya agar statusnya 'processed'
            try {
              let origChat = quotedStanzaId ? await firebaseAdapter.findChatByMessageId(quotedStanzaId) : null;
              if (!origChat) {
                origChat = await firebaseAdapter.findRecentPendingTransferSlip(senderPhone, remoteJid, slipAmount);
              }
              if (origChat) {
                await firebaseAdapter.updateChatDocument(origChat.id, {
                  status: 'processed',
                  isPaymentApplied: true,
                  matchedInvoiceNo: targetInvoiceNo,
                  processedAt: new Date(),
                  'transferInfo.invoiceNo': targetInvoiceNo,
                  'transferInfo.matchedToko': matchedReceivable?.toko || cleanText,
                  'transferInfo.isAutoMatched': true,
                  'transferInfo.customerHint': cleanText
                });
                console.log(`[TRANSFER SLIP ORIGINAL UPDATED] ✅ Dokumen struk ${origChat.id} diperbarui ke PROCESSED (#${targetInvoiceNo})!`);
              }
            } catch (upOrigErr) {
              console.warn('[UPDATE ORIGINAL SLIP ERROR]', upOrigErr.message);
            }
          }

          const replyStatus = (isAutoSettled || targetInvoiceNo) ? 'processed' : 'pending';
          const replyPayload = {
            senderJid: remoteJid,
            senderPhone,
            senderName,
            messageText: cleanText,
            isOrderDetected: false,
            messageType: 'TRANSFER_SLIP_REPLY',
            hasImage: false,
            imageUrl: null,
            transferInfo: {
              ...quotedBankResult,
              invoiceNo: targetInvoiceNo,
              matchedToko: matchedReceivable?.toko || cleanText,
              isAutoMatched: !!matchedReceivable,
              customerHint: cleanText,
              isPartial,
              remainingAmount
            },
            matchedInvoiceNo: targetInvoiceNo || null,
            quotedInvoiceNo: targetInvoiceNo || null,
            quotedOcrText: quotedOcrText || '',
            quotedImageUrl: quotedImageUrl || null,
            quotedMessageText: quotedMessageText || '',
            quotedStanzaId: quotedStanzaId || null,
            isForwarded: false,
            isQuotedReply: true,
            caption: cleanText,
            rawOcrText: '',
            status: replyStatus,
            isPaymentApplied: isAutoSettled,
            isPartialPayment: isPartial,
            remainingAmount: remainingAmount,
            dismissReason: replyStatus === 'processed' ? 'TRANSFER_REPLY_RESOLVED' : null,
            messageCount: 1,
            messageId: msgId || '',
            messageIds: msgId ? [msgId] : [],
            receivedAt: new Date(msgTimeMs),
            processedAt: replyStatus === 'processed' ? new Date() : null
          };

          recentChats.unshift({
            ...replyPayload,
            receivedAt: new Date()
          });
          if (recentChats.length > 20) recentChats.pop();

          await firebaseAdapter.saveIncomingChat(replyPayload);
          return; // Selesai!
        }

        // Flush buffer lama dari sender ini dulu (kalau ada pesan biasa sebelumnya)
        const existingBufKey = senderPhone || rawJidDigits || remoteJid;
        if (pendingMessageBuffers.has(existingBufKey)) {
          console.log(`[BUFFER FLUSH BEFORE BYPASS] 🔄 Flush buffer lama dari ${senderName} sebelum simpan pesan forwarded/quoted terpisah.`);
          await flushMessageBuffer(existingBufKey);
        }

        // Helper: Deteksi apakah teks adalah screenshot terminal / log / kode program
        // → Fungsi _looksLikeScreenshot() sudah didefinisikan di level global

        const detectOrder = (text, isImg, bRes) => {
          if (bRes && bRes.isOrderDocument) return true;
          const t = (text || '').toLowerCase();

          // FILTER: Abaikan screenshot terminal / log / kode program
          if (_looksLikeScreenshot(t)) return false;

          const hasOrderWord = /\b(po|order|pesanan|pesan|nota|invoice|krm|kirim|antar|muat)\b/i.test(t);
          const hasUnitWord = /\b(k|ktn|karton|dus|box|roll|rol|pack|pak|pcs|bal|ball|bks|bungkus|ikat)\b/i.test(t);
          const hasProductWord = /\b(rolade|rollade|kornet|fiva|sosis|baso|bakso|beres|brs|nugget|tempura|siomay|otak|kaki naga|scallop|miniku)\b/i.test(t);
          const hasQtyPattern = /(?:^|\s|\.\.\.)\d+(?:[.,]\d+)?\s*(k|ktn|karton|dus|box|pack|pak|pcs|bal|ball|roll|rol|bks|bungkus)\b/i.test(t);

          if (isImg) {
            if (hasOrderWord && (hasProductWord || hasUnitWord)) return true;
            if (hasQtyPattern && (hasProductWord || hasOrderWord)) return true;
            return false;
          }

          if (hasOrderWord) return true;
          if (hasUnitWord && (hasQtyPattern || hasProductWord || t.includes('kirim') || t.includes('krm'))) return true;
          if (hasProductWord && (hasQtyPattern || t.includes('kirim') || t.includes('krm') || hasOrderWord || hasUnitWord)) return true;
          if (hasProductWord && /\d+/.test(t)) return true;
          return false;
        };

        const isOrderDetected = detectOrder(cleanText, !!isImageMessage, bankResult);

        const bypassType = isQuotedReply ? 'QUOTED_REPLY' : 'FORWARDED';
        const msgType = isQuotedReply ? 'QUOTED_REPLY' : (isOrderDetected ? 'ORDER_PO' : 'CASUAL_CHAT');

        console.log(`[${bypassType} BYPASS] 🚀 Pesan ${bypassType} dari ${senderName} (+${senderPhone}) dikirim langsung ke Firestore (bypass buffer). Teks: "${cleanText.substring(0, 60)}..."`);

        const bypassPayload = {
          senderJid: remoteJid,
          senderPhone,
          senderName,
          messageText: cleanText,
          isOrderDetected: isQuotedReply ? false : isOrderDetected,
          messageType: msgType,
          hasImage: !!isImageMessage,
          imageUrl: imageUrl || null,
          transferInfo: null,
          matchedInvoiceNo: null,
          quotedInvoiceNo: quotedInvoiceNo || null,
          quotedOcrText: quotedOcrText || '',
          quotedImageUrl: quotedImageUrl || null,
          quotedMessageText: quotedMessageText || '',
          quotedStanzaId: quotedStanzaId || null,
          isForwarded: isForwardedMessage,
          isQuotedReply: isQuotedReply,
          caption: rawCaption || '',
          rawOcrText: ocrText || '',
          messageCount: 1,
          messageId: msgId || '',
          messageIds: msgId ? [msgId] : [],
          receivedAt: new Date(msgTimeMs)
        };

        recentChats.unshift({
          ...bypassPayload,
          receivedAt: new Date()
        });
        if (recentChats.length > 20) recentChats.pop();

        const savedBypassId = await firebaseAdapter.saveIncomingChat(bypassPayload);

        // Autonomous Auto-PO execution untuk pesan forwarded pesanan (khusus Termux saat laptop kasir mati)
        // DELAY 2 MENIT: Sama seperti pesan biasa, beri prioritas Flutter dulu.
        if (autoPoEnabled && bypassPayload.messageType === 'ORDER_PO' && !bypassPayload.isQuotedReply) {
          const DELAY_MS = 2 * 60 * 1000;
          console.log(`[AUTONOMOUS PO] ⏱️ Forwarded order: Menunggu ${DELAY_MS / 1000}s sebelum proses PO otonom...`);
          setTimeout(async () => {
            try {
              const chatDoc = await firebaseAdapter.getChatDocument(savedBypassId);
              if (chatDoc && chatDoc.status === 'processed') {
                console.log(`[AUTONOMOUS PO] ⏭️ Forwarded chat ${savedBypassId} sudah diproses Flutter. SKIP.`);
                return;
              }
              console.log(`[AUTONOMOUS PO] 🤖 Forwarded chat ${savedBypassId} masih pending. Termux proses PO...`);
              await autoPoProcessor.processAutonomousPo(savedBypassId, bypassPayload);
            } catch (err) {
              console.warn('[AUTONOMOUS PO BG ERROR]', err.message);
            }
          }, DELAY_MS);
        }
        return; // Selesai! Langsung keluar agar tidak masuk buffer
      }

      // =========================================================================
      // ALUR PESANAN TEKS BIASA: Tetap menggunakan Debounce Buffer (Jeda 8 detik)
      // =========================================================================
      // CATATAN: Block "CEK SUSULAN TEKS BIASA KE BUKTI TRANSFER PENDING" sudah
      // dihapus permanen karena menyebabkan bug kritis:
      // 1. Teks "p" (atau teks pendek apapun) bisa hijack bukti transfer lama
      // 2. Membuat rule sampah di ai_knowledge_rules yang meracuni customer resolver
      // Transfer slip WAJIB dilunasi hanya via QUOTED REPLY yang eksplisit.
      // =========================================================================
      const detectOrderRegular = (text, isImg, bRes) => {
        if (bRes && bRes.isOrderDocument) return true;
        const t = (text || '').toLowerCase();

        // FILTER: Abaikan screenshot terminal / log / kode program
        if (_looksLikeScreenshot(t)) return false;

        const hasOrderWord = /\b(po|order|pesanan|pesan|nota|invoice)\b/i.test(t);
        const hasUnitWord = /\b(k|ktn|karton|dus|box|roll|rol|pack|pak|pcs|bal|ball|bks|bungkus|ikat)\b/i.test(t);
        const hasProductWord = /\b(rolade|kornet|fiva|sosis|baso|bakso|beres|brs|nugget|tempura|siomay|otak|kaki naga|scallop|miniku)\b/i.test(t);
        const hasQtyPattern = /(?:^|\s|\.\.\.)\d+(?:[.,]\d+)?\s*(k|ktn|karton|dus|box|pack|pak|pcs|bal|ball|roll|rol|bks|bungkus|ikat)\b/i.test(t);
        const hasVerb = /\b(krm|kirim|antar|muat)\b/i.test(t);

        if (isImg) {
          if (hasOrderWord && (hasProductWord || hasUnitWord)) return true;
          if (hasQtyPattern && (hasProductWord || hasOrderWord)) return true;
          return false;
        }

        if (hasOrderWord) return true;
        if (hasUnitWord && (hasQtyPattern || hasProductWord || hasVerb)) return true;
        if (hasProductWord && (hasQtyPattern || hasVerb || hasOrderWord)) return true;
        return false;
      };

      const isOrderDetected = detectOrderRegular(cleanText, !!isImageMessage, bankResult);
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
        // Preserve quotedInvoiceNo from first message that has it
        if (!buf.quotedInvoiceNo && quotedInvoiceNo) {
          buf.quotedInvoiceNo = quotedInvoiceNo;
          buf.quotedOcrText = quotedOcrText;
        }
        if (!buf.quotedMessageText && quotedMessageText) {
          buf.quotedMessageText = quotedMessageText;
          buf.quotedStanzaId = quotedStanzaId;
        }
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
          quotedInvoiceNo: quotedInvoiceNo || null,
          quotedOcrText: quotedOcrText || '',
          quotedImageUrl: quotedImageUrl || null,
          quotedMessageText: quotedMessageText || '',
          quotedStanzaId: quotedStanzaId || null,
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
  console.log(`[WA GATEWAY SERVER] 🚀 v${GATEWAY_VERSION} | Berjalan di http://localhost:${PORT}`);
  printAllVersions();
  startBaileys();
  // Auto-update checker: cek setiap 30 menit apakah ada versi baru di GitHub
  checkForUpdates();
  setInterval(checkForUpdates, 30 * 60 * 1000);
});

// ============================================================
// VERSION DISPLAY & AUTO-UPDATE CHECKER
// ============================================================

function printAllVersions() {
  try {
    const versionFile = path.join(__dirname, 'version.json');
    if (fs.existsSync(versionFile)) {
      const vInfo = JSON.parse(fs.readFileSync(versionFile, 'utf8'));
      console.log(`\n╔══════════════════════════════════════════════════╗`);
      console.log(`║  L-W.A.V.I.S • Lucifax-PFS Gateway v${vInfo.gateway || GATEWAY_VERSION}     ║`);
      console.log(`╠══════════════════════════════════════════════════╣`);
      if (vInfo.files) {
        for (const [file, ver] of Object.entries(vInfo.files)) {
          const padFile = file.padEnd(32);
          console.log(`║  ${padFile} v${ver}       ║`);
        }
      }
      console.log(`╠══════════════════════════════════════════════════╣`);
      console.log(`║  Updated: ${(vInfo.updatedAt || '-').padEnd(38)}║`);
      console.log(`╚══════════════════════════════════════════════════╝\n`);
    } else {
      console.log(`[VERSION] ⚠️ version.json tidak ditemukan. Jalankan update untuk mendapatkannya.`);
    }
  } catch (e) {
    console.warn('[VERSION] Gagal membaca version.json:', e.message);
  }
}

async function checkForUpdates() {
  try {
    const https = require('https');
    const remoteUrl = 'https://raw.githubusercontent.com/Lucifer-pw/LUCIFAX-PFS/main/wa-gateway/version.json';

    const remoteData = await new Promise((resolve, reject) => {
      https.get(remoteUrl, { headers: { 'User-Agent': 'Lucifax-Gateway' } }, (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          https.get(res.headers.location, { headers: { 'User-Agent': 'Lucifax-Gateway' } }, (res2) => {
            let data = '';
            res2.on('data', chunk => data += chunk);
            res2.on('end', () => resolve(data));
          }).on('error', reject);
          return;
        }
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve(data));
      }).on('error', reject);
    });

    const remote = JSON.parse(remoteData);
    const localVersionFile = path.join(__dirname, 'version.json');
    let local = { gateway: '0.0.0', files: {} };
    if (fs.existsSync(localVersionFile)) {
      local = JSON.parse(fs.readFileSync(localVersionFile, 'utf8'));
    }

    if (remote.gateway !== local.gateway) {
      console.log(`\n╔══════════════════════════════════════════════════╗`);
      console.log(`║  🔔 UPDATE TERSEDIA!                             ║`);
      console.log(`║  Lokal : v${(local.gateway || '?').padEnd(38)}║`);
      console.log(`║  Remote: v${(remote.gateway || '?').padEnd(38)}║`);
      console.log(`║  ${(remote.changelog || '').substring(0, 48).padEnd(48)}║`);
      console.log(`╠══════════════════════════════════════════════════╣`);
      console.log(`║  Jalankan perintah berikut untuk update:         ║`);
      console.log(`║  cd ~/wa-gateway && ./update.sh                  ║`);
      console.log(`╚══════════════════════════════════════════════════╝\n`);

      // Simpan info update ke Firestore agar bisa dibaca oleh app Flutter
      try {
        await firebaseAdapter.updateGatewaySession({
          updateAvailable: true,
          currentVersion: local.gateway,
          latestVersion: remote.gateway,
          updateChangelog: remote.changelog || '',
          updateCheckedAt: new Date()
        });
      } catch (_) {}
    } else {
      console.log(`[UPDATE CHECK] ✅ Gateway sudah versi terbaru (v${local.gateway})`);
    }
  } catch (e) {
    // Silent fail - jangan ganggu operasi gateway kalau check gagal
    console.log(`[UPDATE CHECK] ⚠️ Gagal cek update: ${e.message}`);
  }
}
