/**
 * L-W.A.V.I.S Notification Dispatcher
 * Versi: v3.3.272
 * 
 * Bertanggung jawab mengirim Push Notification bertingkat (FCM & Termux Local)
 * ke aplikasi LUCIFAX PFS di HP:
 * 1. Notifikasi Pesan Masuk (Realtime saat chat/foto diterima)
 * 2. Notifikasi Hasil Eksekusi (PO Sukses dengan rincian barang, diskon per-item, subtotal & grand total)
 * 3. Notifikasi Pelunasan Piutang (Bukti transfer cocok dengan faktur)
 * 4. Notifikasi Perlu Review (Jika W.A.V.I.S ragu/customer ambigu)
 */

const { exec } = require('child_process');
const NOTIF_VERSION = '3.3.272';
const FCM_TOPIC = 'wavis_alerts';

class NotificationDispatcher {
  constructor(firebaseAdapter) {
    this.firebaseAdapter = firebaseAdapter;
    this.topic = FCM_TOPIC;
  }

  getAdmin() {
    if (this.firebaseAdapter && this.firebaseAdapter.admin) {
      return this.firebaseAdapter.admin;
    }
    try {
      const admin = require('firebase-admin');
      if (admin.apps && admin.apps.length > 0) return admin;
    } catch (_) {}
    return null;
  }

  /**
   * Kirim notifikasi lokal Termux jika package termux-api terpasang
   */
  _tryLocalTermuxNotification(title, content) {
    try {
      const cleanTitle = (title || 'L-W.A.V.I.S').replace(/["`$\\]/g, ' ');
      const cleanContent = (content || '').replace(/["`$\\]/g, ' ');
      exec(`termux-notification --title "${cleanTitle}" --content "${cleanContent}" --priority high --sound`, () => {});
    } catch (_) {}
  }

  /**
   * 1. NOTIFIKASI PESAN / FOTO MASUK (Tahap 1)
   */
  async sendIncomingMessageAlert({ senderName, senderPhone, messageText, hasImage, isTransfer }) {
    try {
      const admin = this.getAdmin();
      const displayName = senderName || senderPhone || 'Pengirim';
      let bodyText = '';

      if (isTransfer || hasImage) {
        bodyText = `📷 Foto Bukti Transfer dari ${displayName} (+${senderPhone})\nSedang dianalisis oleh W.A.V.I.S...`;
      } else {
        const shortChat = (messageText || '').replace(/\r?\n/g, ' ').trim();
        const snippet = shortChat.length > 90 ? shortChat.substring(0, 90) + '...' : shortChat;
        bodyText = `📩 Pesan Masuk dari ${displayName} (+${senderPhone}):\n"${snippet}"`;
      }

      console.log(`[NOTIF FCM] 🔔 Mengirim Notifikasi Pesan Masuk dari ${displayName}...`);

      if (admin) {
        await admin.messaging().send({
          topic: this.topic,
          notification: {
            title: 'L-W.A.V.I.S • Pesan Masuk',
            body: bodyText
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'wavis_channel',
              priority: 'high',
              defaultSound: true,
              defaultVibrateTimings: true,
              tag: `incoming_${senderPhone || 'unknown'}`
            }
          },
          data: {
            type: 'CHAT_INCOMING',
            senderName: String(displayName),
            senderPhone: String(senderPhone || ''),
            hasImage: String(!!hasImage),
            isTransfer: String(!!isTransfer),
            timestamp: Date.now().toString()
          }
        });
        console.log(`[NOTIF FCM] ✅ Notifikasi Pesan Masuk terkirim via FCM (Topik: ${this.topic})`);
      }

      this._tryLocalTermuxNotification('L-W.A.V.I.S • Pesan Masuk', bodyText);
    } catch (err) {
      console.warn('[NOTIF FCM WARNING] Gagal mengirim notifikasi pesan masuk:', err.message);
    }
  }

  /**
   * 2. NOTIFIKASI PO SUKSES DENGAN RINCIAN BARANG & DISKON PER-ITEM (Tahap 2)
   */
  async sendPoSuccessAlert({ invoiceNo, customerName, items = [], grandTotal = 0 }) {
    try {
      const admin = this.getAdmin();
      const lines = [];
      lines.push(`✅ PO #${invoiceNo} DIBUAT • ${customerName}`);

      let rawSubtotal = 0;
      let totalDiscountRp = 0;
      let totalKarton = 0;

      for (const it of items) {
        if (it.isBonus) {
          lines.push(`• 🎁 [BONUS] ${it.productName} (${it.qty} pcs)`);
          continue;
        }

        const ktn = (it.boxCount || Math.round((it.qty || 0) / (it.isiKarton || 20))) || 0;
        totalKarton += ktn;

        let discTag = ' [Net]';
        if (it.discountPercent && it.discountPercent > 0) {
          discTag = ` [-${it.discountPercent}%]`;
        } else if (it.discountAmount && it.discountAmount > 0) {
          discTag = ` [-Rp ${Number(it.discountAmount).toLocaleString('id-ID')}]`;
        }

        const ktnStr = ktn > 0 ? ` (${ktn} Ktn)` : ` (${it.qty || 0} pcs)`;
        const itemSubtotal = it.subtotal || ((it.price || 0) * (it.qty || 0));
        const itemRaw = (it.price || 0) * (it.qty || 1);
        rawSubtotal += itemRaw;
        totalDiscountRp += Math.max(0, itemRaw - itemSubtotal);

        lines.push(`• ${it.productName}${ktnStr}${discTag} = Rp ${Math.round(itemSubtotal).toLocaleString('id-ID')}`);
      }

      lines.push('─────────────────────────────');
      if (totalDiscountRp > 0) {
        lines.push(`Subtotal: Rp ${Math.round(rawSubtotal).toLocaleString('id-ID')} • Total Disc: -Rp ${Math.round(totalDiscountRp).toLocaleString('id-ID')}`);
      }
      const ktnSummary = totalKarton > 0 ? ` (${totalKarton} Ktn)` : '';
      lines.push(`💰 GRAND TOTAL: Rp ${Math.round(grandTotal).toLocaleString('id-ID')}${ktnSummary}`);

      const fullBody = lines.join('\n');
      console.log(`[NOTIF FCM] 🚀 Mengirim Notifikasi PO #${invoiceNo} Sukses (${items.length} item)...`);

      if (admin) {
        await admin.messaging().send({
          topic: this.topic,
          notification: {
            title: `L-W.A.V.I.S • PO #${invoiceNo} DIBUAT`,
            body: fullBody
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'wavis_channel',
              priority: 'high',
              defaultSound: true,
              defaultVibrateTimings: true,
              tag: `po_${invoiceNo}`
            }
          },
          data: {
            type: 'PO_CREATED',
            invoiceNo: String(invoiceNo),
            customerName: String(customerName || ''),
            grandTotal: String(grandTotal || 0),
            totalKarton: String(totalKarton || 0),
            itemCount: String(items.length),
            timestamp: Date.now().toString()
          }
        });
        console.log(`[NOTIF FCM] ✅ Notifikasi PO #${invoiceNo} terkirim via FCM (Topik: ${this.topic})`);
      }

      this._tryLocalTermuxNotification(`L-W.A.V.I.S • PO #${invoiceNo} DIBUAT`, fullBody);
    } catch (err) {
      console.warn('[NOTIF FCM WARNING] Gagal mengirim notifikasi PO sukses:', err.message);
    }
  }

  /**
   * 3. NOTIFIKASI PIUTANG LUNAS (Tahap 2 untuk Transfer Bank)
   */
  async sendReceivablePaidAlert({ bankName, amount, invoiceNo, customerName }) {
    try {
      const admin = this.getAdmin();
      const amountStr = Number(amount || 0).toLocaleString('id-ID');
      const bank = bankName || 'Transfer Bank';
      const bodyText = `💸 PIUTANG LUNAS (${bank})\nRp ${amountStr} otomatis dialokasikan ke Faktur #${invoiceNo} (${customerName || 'Customer'})`;

      console.log(`[NOTIF FCM] 💸 Mengirim Notifikasi Piutang Lunas Faktur #${invoiceNo}...`);

      if (admin) {
        await admin.messaging().send({
          topic: this.topic,
          notification: {
            title: 'L-W.A.V.I.S • Piutang Lunas',
            body: bodyText
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'wavis_channel',
              priority: 'high',
              defaultSound: true,
              defaultVibrateTimings: true,
              tag: `paid_${invoiceNo}`
            }
          },
          data: {
            type: 'RECEIVABLE_PAID',
            bankName: String(bank),
            amount: String(amount || 0),
            invoiceNo: String(invoiceNo || ''),
            customerName: String(customerName || ''),
            timestamp: Date.now().toString()
          }
        });
        console.log(`[NOTIF FCM] ✅ Notifikasi Piutang Lunas terkirim via FCM`);
      }

      this._tryLocalTermuxNotification('L-W.A.V.I.S • Piutang Lunas', bodyText);
    } catch (err) {
      console.warn('[NOTIF FCM WARNING] Gagal mengirim notifikasi piutang lunas:', err.message);
    }
  }

  /**
   * 4. NOTIFIKASI PERLU REVIEW (Jika W.A.V.I.S ragu / data ambigu)
   */
  async sendReviewNeededAlert({ senderName, reason, rawChat }) {
    try {
      const admin = this.getAdmin();
      const snippet = (rawChat || '').replace(/\r?\n/g, ' ').substring(0, 80);
      const bodyText = `⚠️ PERLU REVIEW KASIR\nPesan dari ${senderName || 'Pengirim'} ditahan (${reason || 'Format Ambigu'}):\n"${snippet}..."\nSilakan cek web/app jika ada waktu luang.`;

      console.log(`[NOTIF FCM] ⚠️ Mengirim Notifikasi Perlu Review...`);

      if (admin) {
        await admin.messaging().send({
          topic: this.topic,
          notification: {
            title: 'L-W.A.V.I.S • Perlu Review',
            body: bodyText
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'wavis_channel',
              priority: 'high',
              defaultSound: true,
              defaultVibrateTimings: true,
              tag: `review_${Date.now()}`
            }
          },
          data: {
            type: 'REVIEW_NEEDED',
            senderName: String(senderName || ''),
            reason: String(reason || ''),
            timestamp: Date.now().toString()
          }
        });
        console.log(`[NOTIF FCM] ✅ Notifikasi Perlu Review terkirim via FCM`);
      }

      this._tryLocalTermuxNotification('L-W.A.V.I.S • Perlu Review', bodyText);
    } catch (err) {
      console.warn('[NOTIF FCM WARNING] Gagal mengirim notifikasi perlu review:', err.message);
    }
  }
}

module.exports = {
  NotificationDispatcher,
  NOTIF_VERSION
};
