/**
 * WAVIS NATIVE PDF GENERATOR
 * L-W.A.V.I.S: Lucifax-Whatsapp Assistant Vision Interactive System
 * 
 * Modul pembuat file dokumen PDF resmi (Faktur Penjualan & Kartu Piutang)
 * murni native Node.js tanpa dependensi eksternal (Zero-Dependency).
 * Kompatibel 100% dengan Windows, Linux, dan Termux Android.
 */

function escapePdf(str) {
  return String(str || '')
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)')
    .replace(/[^\x20-\x7E]/g, ' '); // Standard ASCII safe
}

class WavisPdfGenerator {
  /**
   * Bangun File PDF Faktur Penjualan (Sales Invoice)
   * @param {Object} inv Data faktur dari database transaksi
   * @returns {Buffer} Buffer binary PDF 1.4
   */
  static generateInvoicePdf(inv) {
    const objects = [];
    function addObj(c) {
      objects.push(c);
      return objects.length;
    }

    // 1: Catalog
    addObj('<< /Type /Catalog /Pages 2 0 R >>');
    // 2: Pages
    addObj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    // 3: Page (A4 Size: 595.28 x 841.89 pt)
    addObj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R /F3 7 0 R >> >> >>');

    let stream = '';
    function drawRect(x, y, w, h, r, g, b) {
      stream += `${r.toFixed(3)} ${g.toFixed(3)} ${b.toFixed(3)} rg ${x.toFixed(2)} ${y.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re f\n`;
    }
    function drawLine(x1, y1, x2, y2, r, g, b, lw = 1) {
      stream += `${lw} w ${r.toFixed(3)} ${g.toFixed(3)} ${b.toFixed(3)} RG ${x1.toFixed(2)} ${y1.toFixed(2)} m ${x2.toFixed(2)} ${y2.toFixed(2)} l S\n`;
    }
    function drawText(font, size, x, y, text, r = 0, g = 0, b = 0) {
      stream += `BT /${font} ${size} Tf ${r.toFixed(3)} ${g.toFixed(3)} ${b.toFixed(3)} rg ${x.toFixed(2)} ${y.toFixed(2)} Td (${escapePdf(text)}) Tj ET\n`;
    }

    const invoiceNo = inv.invoiceNo || inv.id || '000';
    const displayCust = inv.aliasName ? `${inv.aliasName} (${inv.customerName})` : (inv.customerName || 'Pelanggan');
    const cleanCity = inv.city || 'SEMARANG';
    const cleanProv = inv.province || 'JAWA TENGAH';

    let tglStr = 'Hari ini';
    try {
      const d = inv.date ? (inv.date.toDate ? inv.date.toDate() : new Date(inv.date)) : new Date();
      const dd = String(d.getDate()).padStart(2, '0');
      const mm = String(d.getMonth() + 1).padStart(2, '0');
      const yyyy = d.getFullYear();
      tglStr = `${dd}-${mm}-${yyyy}`;
    } catch (_) {}

    // 1. Header Banner Kop Perusahaan
    drawRect(40, 765, 515, 50, 0.008, 0.518, 0.780); // #0284C7
    drawText('F2', 15, 55, 795, 'PT PANGAN PRIMA SUKSES (FIVA FROZEN FOOD)', 1, 1, 1);
    drawText('F1', 9, 55, 781, 'DISTRIBUTION CENTER - Gedung Pacific Century Place Lt. 45, Jakarta Selatan', 0.9, 0.95, 1);
    drawText('F3', 8, 55, 770, 'Sistem Penjualan & Distribusi Terpadu L-W.A.V.I.S', 0.85, 0.92, 0.98);

    // 2. Judul Dokumen
    drawText('F2', 13, 40, 742, `FAKTUR PENJUALAN #${invoiceNo}`, 0.06, 0.09, 0.16);
    drawLine(40, 735, 555, 735, 0.008, 0.518, 0.780, 1.5);

    // 3. Info Box Pelanggan & Transaksi
    drawRect(40, 655, 515, 72, 0.96, 0.97, 0.98); // Light Slate Box
    drawLine(40, 655, 555, 655, 0.85, 0.9, 0.95, 1);
    drawLine(40, 727, 555, 727, 0.85, 0.9, 0.95, 1);
    drawLine(40, 655, 40, 727, 0.85, 0.9, 0.95, 1);
    drawLine(555, 655, 555, 727, 0.85, 0.9, 0.95, 1);

    // Kolom Kiri
    drawText('F2', 9, 52, 708, 'Pelanggan:', 0.3, 0.35, 0.4);
    drawText('F1', 9, 125, 708, displayCust, 0.06, 0.09, 0.16);
    drawText('F2', 9, 52, 690, 'Kota/Provinsi:', 0.3, 0.35, 0.4);
    drawText('F1', 9, 125, 690, `${cleanCity}, ${cleanProv}`, 0.06, 0.09, 0.16);
    drawText('F2', 9, 52, 672, 'Status Kirim:', 0.3, 0.35, 0.4);
    const isDikirim = String(inv.status || '').toUpperCase() === 'DIKIRIM';
    drawText('F2', 9, 125, 672, inv.status || 'PENDING', isDikirim ? 0.05 : 0.85, isDikirim ? 0.55 : 0.45, 0.1);

    // Kolom Kanan
    drawText('F2', 9, 345, 708, 'No. Invoice:', 0.3, 0.35, 0.4);
    drawText('F2', 9, 420, 708, `#${invoiceNo}`, 0.06, 0.09, 0.16);
    drawText('F2', 9, 345, 690, 'Tgl Invoice:', 0.3, 0.35, 0.4);
    drawText('F1', 9, 420, 690, tglStr, 0.06, 0.09, 0.16);
    drawText('F2', 9, 345, 672, 'Status Bayar:', 0.3, 0.35, 0.4);
    const isPaid = String(inv.statusTransfer || '').toUpperCase() === 'PAID';
    drawText('F2', 9, 420, 672, inv.statusTransfer || 'UNPAID', isPaid ? 0.05 : 0.8, isPaid ? 0.55 : 0.1, 0.1);

    // 4. Tabel Rincian Barang
    let tableY = 625;
    // Header Tabel
    drawRect(40, tableY, 515, 22, 0.12, 0.16, 0.23); // Dark Slate #1E293B
    drawText('F2', 8.5, 46, tableY + 7, 'No', 1, 1, 1);
    drawText('F2', 8.5, 70, tableY + 7, 'Nama Barang', 1, 1, 1);
    drawText('F2', 8.5, 255, tableY + 7, 'Karton', 1, 1, 1);
    drawText('F2', 8.5, 305, tableY + 7, 'Qty (Pcs)', 1, 1, 1);
    drawText('F2', 8.5, 360, tableY + 7, 'Harga Unit', 1, 1, 1);
    drawText('F2', 8.5, 425, tableY + 7, 'Disc', 1, 1, 1);
    drawText('F2', 8.5, 475, tableY + 7, 'Subtotal (Rp)', 1, 1, 1);

    tableY -= 20;
    const items = Array.isArray(inv.items) ? inv.items : [];
    let totalKtnCount = 0;

    items.forEach((it, idx) => {
      const isEven = (idx % 2 === 1);
      if (isEven) {
        drawRect(40, tableY - 2, 515, 20, 0.97, 0.98, 0.99);
      }
      drawLine(40, tableY - 2, 555, tableY - 2, 0.88, 0.9, 0.92, 0.5);

      const ktn = it.cartonCount != null ? Number(it.cartonCount) : (it.isiKarton ? Math.round(Number(it.qty) / Number(it.isiKarton) * 10) / 10 : null);
      if (ktn) totalKtnCount += ktn;

      let discLabel = '-';
      if (it.discountPercent && it.discountPercent > 0) {
        discLabel = `${it.discountPercent}%`;
      } else if (it.discountAmount && it.discountAmount > 0) {
        discLabel = `-${Math.round(it.discountAmount).toLocaleString('id-ID')}`;
      }

      drawText('F1', 8, 48, tableY + 4, String(idx + 1), 0.2, 0.2, 0.2);
      drawText('F2', 8, 70, tableY + 4, (it.productName || 'PRODUK').substring(0, 32), 0.06, 0.09, 0.16);
      drawText('F1', 8, 258, tableY + 4, ktn ? `${ktn} Ktn` : '-', 0.2, 0.2, 0.2);
      drawText('F1', 8, 312, tableY + 4, `${it.qty || 0} pcs`, 0.2, 0.2, 0.2);
      drawText('F1', 8, 360, tableY + 4, Math.round(it.price || 0).toLocaleString('id-ID'), 0.2, 0.2, 0.2);
      drawText('F1', 8, 425, tableY + 4, discLabel, 0.2, 0.2, 0.2);
      drawText('F2', 8, 475, tableY + 4, Math.round(it.subtotal || 0).toLocaleString('id-ID'), 0.05, 0.45, 0.25);

      tableY -= 20;
    });

    drawLine(40, tableY, 555, tableY, 0.12, 0.16, 0.23, 1.2);

    // 5. Total & Summary Box
    tableY -= 15;
    drawRect(40, tableY - 24, 515, 34, 0.94, 0.98, 0.94); // Light Green
    drawLine(40, tableY - 24, 555, tableY - 24, 0.75, 0.88, 0.75, 1);
    drawLine(40, tableY + 10, 555, tableY + 10, 0.75, 0.88, 0.75, 1);
    drawLine(40, tableY - 24, 40, tableY + 10, 0.75, 0.88, 0.75, 1);
    drawLine(555, tableY - 24, 555, tableY + 10, 0.75, 0.88, 0.75, 1);

    const grandKtnStr = Math.round(totalKtnCount * 10) / 10;
    drawText('F2', 10, 52, tableY - 10, `Total Karton: ${grandKtnStr} Ktn (${items.length} Item Barang)`, 0.2, 0.3, 0.25);
    drawText('F2', 12, 340, tableY - 10, 'GRAND TOTAL:', 0.1, 0.4, 0.15);
    drawText('F2', 13, 440, tableY - 10, `Rp ${Math.round(inv.grandTotal || 0).toLocaleString('id-ID')}`, 0.05, 0.5, 0.2);

    // 6. Catatan Faktur
    if (inv.note && String(inv.note).trim().length > 0) {
      tableY -= 35;
      drawRect(40, tableY - 15, 515, 24, 0.98, 0.98, 0.98);
      drawLine(40, tableY - 15, 555, tableY - 15, 0.85, 0.9, 0.95, 0.8);
      drawLine(40, tableY + 9, 555, tableY + 9, 0.85, 0.9, 0.95, 0.8);
      drawText('F2', 8, 52, tableY - 5, 'Catatan:', 0.008, 0.518, 0.780);
      drawText('F1', 8, 100, tableY - 5, String(inv.note).substring(0, 85), 0.2, 0.25, 0.3);
    }

    // 7. Footer Dokumen Resmi
    drawText('F3', 7.5, 40, 40, 'Dicetak otomatis oleh L-W.A.V.I.S (Lucifax-Whatsapp Assistant Vision Interactive System) - PT Pangan Prima Sukses', 0.5, 0.55, 0.6);
    drawText('F1', 7.5, 470, 40, `Tgl Cetak: ${tglStr}`, 0.5, 0.55, 0.6);

    // 4: Content Stream Object
    addObj(`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`);
    // 5: Fonts
    addObj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
    addObj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>');
    addObj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique >>');

    let pdf = '%PDF-1.4\n';
    const offsets = [];
    objects.forEach((obj, idx) => {
      offsets.push(Buffer.byteLength(pdf));
      pdf += `${idx + 1} 0 obj\n${obj}\nendobj\n`;
    });

    const startxref = Buffer.byteLength(pdf);
    pdf += `xref\n0 ${objects.length + 1}\n`;
    pdf += '0000000000 65535 f \n';
    offsets.forEach(off => {
      pdf += `${String(off).padStart(10, '0')} 00000 n \n`;
    });
    pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n`;
    pdf += `startxref\n${startxref}\n%%EOF`;

    return Buffer.from(pdf, 'binary');
  }

  /**
   * Bangun File PDF Kartu Piutang (Receivables Summary)
   * @param {Object} data Rangkuman kartu piutang pelanggan
   * @returns {Buffer} Buffer binary PDF 1.4
   */
  static generateReceivablesPdf(data) {
    const objects = [];
    function addObj(c) {
      objects.push(c);
      return objects.length;
    }

    addObj('<< /Type /Catalog /Pages 2 0 R >>');
    addObj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
    addObj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R /F3 7 0 R >> >> >>');

    let stream = '';
    function drawRect(x, y, w, h, r, g, b) {
      stream += `${r.toFixed(3)} ${g.toFixed(3)} ${b.toFixed(3)} rg ${x.toFixed(2)} ${y.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re f\n`;
    }
    function drawLine(x1, y1, x2, y2, r, g, b, lw = 1) {
      stream += `${lw} w ${r.toFixed(3)} ${g.toFixed(3)} ${b.toFixed(3)} RG ${x1.toFixed(2)} ${y1.toFixed(2)} m ${x2.toFixed(2)} ${y2.toFixed(2)} l S\n`;
    }
    function drawText(font, size, x, y, text, r = 0, g = 0, b = 0) {
      stream += `BT /${font} ${size} Tf ${r.toFixed(3)} ${g.toFixed(3)} ${b.toFixed(3)} rg ${x.toFixed(2)} ${y.toFixed(2)} Td (${escapePdf(text)}) Tj ET\n`;
    }

    const custName = data.customerName || 'Toko Pelanggan';
    const alias = data.aliasName ? ` (${data.aliasName})` : '';
    const totalRemaining = Math.round(Number(data.totalRemaining) || 0);
    const unpaidInvoices = Array.isArray(data.unpaidInvoices) ? data.unpaidInvoices : [];

    const now = new Date();
    const dd = String(now.getDate()).padStart(2, '0');
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const yyyy = now.getFullYear();
    const tglStr = `${dd}-${mm}-${yyyy}`;

    // 1. Header Banner
    drawRect(40, 765, 515, 50, 0.08, 0.35, 0.2); // Green Banner #15803D
    drawText('F2', 15, 55, 795, 'PT PANGAN PRIMA SUKSES (FIVA FROZEN FOOD)', 1, 1, 1);
    drawText('F1', 9, 55, 781, 'LAPORAN REKAP KARTU PIUTANG PELANGGAN', 0.9, 0.98, 0.92);
    drawText('F3', 8, 55, 770, 'L-W.A.V.I.S Financial Assistant Module', 0.85, 0.95, 0.9);

    // 2. Info Toko
    drawText('F2', 13, 40, 742, `KARTU PIUTANG: ${custName}${alias}`, 0.06, 0.09, 0.16);
    drawLine(40, 735, 555, 735, 0.08, 0.35, 0.2, 1.5);

    drawRect(40, 670, 515, 55, 0.96, 0.98, 0.96);
    drawLine(40, 670, 555, 670, 0.85, 0.92, 0.85, 1);
    drawLine(40, 725, 555, 725, 0.85, 0.92, 0.85, 1);
    drawLine(40, 670, 40, 725, 0.85, 0.92, 0.85, 1);
    drawLine(555, 670, 555, 725, 0.85, 0.92, 0.85, 1);

    drawText('F2', 9, 52, 705, 'Pelanggan:', 0.3, 0.35, 0.4);
    drawText('F1', 9, 130, 705, `${custName}${alias}`, 0.06, 0.09, 0.16);
    drawText('F2', 9, 52, 685, 'Tgl Laporan:', 0.3, 0.35, 0.4);
    drawText('F1', 9, 130, 685, tglStr, 0.06, 0.09, 0.16);

    drawText('F2', 10, 330, 702, 'Total Sisa Piutang:', 0.8, 0.1, 0.1);
    drawText('F2', 13, 430, 700, `Rp ${totalRemaining.toLocaleString('id-ID')}`, 0.8, 0.1, 0.1);
    drawText('F1', 8.5, 330, 685, `Faktur Tertunggak: ${unpaidInvoices.length} Invoice`, 0.4, 0.45, 0.5);

    // 3. Tabel Faktur Belum Lunas
    let tableY = 640;
    drawRect(40, tableY, 515, 22, 0.15, 0.2, 0.25);
    drawText('F2', 8.5, 46, tableY + 7, 'No', 1, 1, 1);
    drawText('F2', 8.5, 75, tableY + 7, 'No. Faktur', 1, 1, 1);
    drawText('F2', 8.5, 150, tableY + 7, 'Tgl Faktur', 1, 1, 1);
    drawText('F2', 8.5, 230, tableY + 7, 'Total Tagihan (Rp)', 1, 1, 1);
    drawText('F2', 8.5, 340, tableY + 7, 'Terbayar (Rp)', 1, 1, 1);
    drawText('F2', 8.5, 445, tableY + 7, 'Sisa Saldo (Rp)', 1, 1, 1);

    tableY -= 20;
    if (unpaidInvoices.length === 0) {
      drawText('F2', 10, 180, tableY - 10, 'ALHAMDULILLAH, SEMUA TAGIHAN SUDAH LUNAS!', 0.05, 0.55, 0.2);
    } else {
      unpaidInvoices.forEach((inv, idx) => {
        if (idx % 2 === 1) {
          drawRect(40, tableY - 2, 515, 20, 0.98, 0.98, 0.98);
        }
        drawLine(40, tableY - 2, 555, tableY - 2, 0.9, 0.92, 0.94, 0.5);

        const gt = Math.round(Number(inv.grandTotal) || 0);
        const paid = Math.round(Number(inv.paidAmount) || 0);
        const rem = Math.round(gt - paid);

        let invDateStr = '-';
        try {
          const d = inv.date ? (inv.date.toDate ? inv.date.toDate() : new Date(inv.date)) : null;
          if (d) {
            invDateStr = `${String(d.getDate()).padStart(2, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${d.getFullYear()}`;
          }
        } catch (_) {}

        drawText('F1', 8, 48, tableY + 4, String(idx + 1), 0.2, 0.2, 0.2);
        drawText('F2', 8, 75, tableY + 4, `#${inv.invoiceNo || inv.id || '-'}`, 0.06, 0.09, 0.16);
        drawText('F1', 8, 150, tableY + 4, invDateStr, 0.2, 0.2, 0.2);
        drawText('F1', 8, 230, tableY + 4, gt.toLocaleString('id-ID'), 0.2, 0.2, 0.2);
        drawText('F1', 8, 340, tableY + 4, paid > 0 ? paid.toLocaleString('id-ID') : '-', 0.05, 0.45, 0.25);
        drawText('F2', 8, 445, tableY + 4, rem.toLocaleString('id-ID'), 0.8, 0.1, 0.1);

        tableY -= 20;
      });
    }

    drawLine(40, tableY, 555, tableY, 0.15, 0.2, 0.25, 1.2);

    // Footer
    drawText('F3', 7.5, 40, 40, 'Dicetak otomatis oleh L-W.A.V.I.S (Lucifax-Whatsapp Assistant Vision Interactive System) - PT Pangan Prima Sukses', 0.5, 0.55, 0.6);
    drawText('F1', 7.5, 470, 40, `Tgl Cetak: ${tglStr}`, 0.5, 0.55, 0.6);

    addObj(`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`);
    addObj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
    addObj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>');
    addObj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique >>');

    let pdf = '%PDF-1.4\n';
    const offsets = [];
    objects.forEach((obj, idx) => {
      offsets.push(Buffer.byteLength(pdf));
      pdf += `${idx + 1} 0 obj\n${obj}\nendobj\n`;
    });

    const startxref = Buffer.byteLength(pdf);
    pdf += `xref\n0 ${objects.length + 1}\n`;
    pdf += '0000000000 65535 f \n';
    offsets.forEach(off => {
      pdf += `${String(off).padStart(10, '0')} 00000 n \n`;
    });
    pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n`;
    pdf += `startxref\n${startxref}\n%%EOF`;

    return Buffer.from(pdf, 'binary');
  }
}

module.exports = WavisPdfGenerator;
