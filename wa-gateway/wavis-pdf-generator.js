/**
 * WAVIS NATIVE PDF GENERATOR
 * L-W.A.V.I.S: Lucifax-Whatsapp Assistant Vision Interactive System
 * 
 * Modul pembuat file dokumen PDF faktur resmi (100% Persis Format Cetakan Kasir Fiva Gambar 4)
 * dan kartu piutang murni native Node.js tanpa dependensi eksternal (Zero-Dependency).
 * Kompatibel 100% dengan Windows, Linux, dan Termux Android.
 */

const fs = require('fs');
const path = require('path');

function escapePdf(str) {
  return String(str || '')
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)')
    .replace(/[^\x20-\x7E]/g, ' '); // Standard ASCII safe
}

// Load official circular Fiva logo binary objects if available
let fivaLogoStream = null;
let fivaMaskStream = null;
try {
  const logoPath = path.join(__dirname, 'fiva-logo.bin');
  if (fs.existsSync(logoPath)) {
    const raw = fs.readFileSync(logoPath);
    if (raw.length > 8) {
      const len11 = raw.readUInt32BE(0);
      const len12 = raw.readUInt32BE(4);
      const o11 = raw.slice(8, 8 + len11);
      const o12 = raw.slice(8 + len11, 8 + len11 + len12);

      function extractPureStream(buf) {
        const str = buf.toString('latin1');
        const sIdx = str.indexOf('stream');
        const eIdx = str.lastIndexOf('endstream');
        if (sIdx === -1 || eIdx === -1) return null;
        let start = sIdx + 6;
        if (buf[start] === 13) start++;
        if (buf[start] === 10) start++;
        let end = eIdx;
        if (buf[end - 1] === 10) end--;
        if (buf[end - 1] === 13) end--;
        return buf.slice(start, end);
      }

      fivaLogoStream = extractPureStream(o11);
      fivaMaskStream = extractPureStream(o12);
    }
  }
} catch (_) {}

class WavisPdfGenerator {
  /**
   * Helper pembuat nama file PDF resmi sesuai standar kasir:
   * Pattern: {no_invoice}_{AliasToko}_{Kota}_{Diskon% if present}_{tanggalkirim YYYYMMDD}.pdf
   * Contoh: 700_AW_FF_SEMARANG_20261117.pdf
   */
  static generateInvoiceFilename(inv) {
    const invNo = String(inv.invoiceNo || inv.id || '000').replace(/\D/g, '') || '000';
    let alias = String(inv.aliasName || inv.customerName || 'PELANGGAN').trim();
    alias = alias.toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '') || 'PELANGGAN';

    let city = String(inv.city || 'SEMARANG').trim().toUpperCase().replace(/[^A-Z0-9]+/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '') || 'SEMARANG';

    // Cek diskon terbesar
    const items = Array.isArray(inv.items) ? inv.items : [];
    let maxDisc = 0;
    for (const it of items) {
      if (!it.isBonus && it.discountPercent > maxDisc) {
        maxDisc = it.discountPercent;
      }
    }
    let discPart = '';
    if (maxDisc > 0) {
      const formattedDisc = (maxDisc % 1 === 0 ? maxDisc.toFixed(0) : maxDisc.toFixed(2)).replace('.', ',');
      discPart = `_${formattedDisc}%`;
    }

    let dateStr = '20261117';
    try {
      const targetDate = inv.deliveryDate ? (inv.deliveryDate.toDate ? inv.deliveryDate.toDate() : new Date(inv.deliveryDate)) : (inv.date ? (inv.date.toDate ? inv.date.toDate() : new Date(inv.date)) : new Date());
      const yyyy = targetDate.getFullYear();
      const mm = String(targetDate.getMonth() + 1).padStart(2, '0');
      const dd = String(targetDate.getDate()).padStart(2, '0');
      dateStr = `${yyyy}${mm}${dd}`;
    } catch (_) {}

    return `${invNo}_${alias}_${city}${discPart}_${dateStr}.pdf`;
  }

  /**
   * Bangun File PDF Faktur Penjualan (100% Identik dengan Cetakan Kasir Fiva Gambar 4)
   * Menggunakan format Letter Portrait (612 x 792 pt, Margin 20 pt, Grid Tabel 14 Baris Kotak)
   * @param {Object} inv Data faktur dari database transaksi
   * @returns {Buffer} Buffer binary PDF 1.4
   */
  static generateInvoicePdf(inv) {
    const hasLogo = !!(fivaLogoStream && fivaMaskStream);
    const objects = [];
    function addObj(c) {
      objects.push(c);
      return objects.length;
    }

    // 1: Catalog
    addObj('<< /Type /Catalog /Pages 2 0 R >>');
    // 2: Pages
    addObj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');

    // 3: Page (Letter Size: 612 x 792 pt, Printable Width: 572 pt)
    const resourceDict = hasLogo
      ? '<< /Font << /F1 5 0 R /F2 6 0 R /F3 7 0 R >> /XObject << /I11 8 0 R >> >>'
      : '<< /Font << /F1 5 0 R /F2 6 0 R /F3 7 0 R >> >>';
    addObj(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources ${resourceDict} >>`);

    let stream = '';
    function drawRect(x, y, w, h, lw = 1, r = 0, g = 0, b = 0) {
      stream += `${lw} w ${r.toFixed(3)} ${g.toFixed(3)} ${b.toFixed(3)} RG ${x.toFixed(2)} ${y.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re S\n`;
    }
    function drawLine(x1, y1, x2, y2, lw = 0.5, r = 0, g = 0, b = 0) {
      stream += `${lw} w ${r.toFixed(3)} ${g.toFixed(3)} ${b.toFixed(3)} RG ${x1.toFixed(2)} ${y1.toFixed(2)} m ${x2.toFixed(2)} ${y2.toFixed(2)} l S\n`;
    }
    function drawText(font, size, x, y, text, r = 0, g = 0, b = 0) {
      stream += `BT /${font} ${size} Tf ${r.toFixed(3)} ${g.toFixed(3)} ${b.toFixed(3)} rg ${x.toFixed(2)} ${y.toFixed(2)} Td (${escapePdf(text)}) Tj ET\n`;
    }

    const invoiceNo = String(inv.invoiceNo || inv.id || '000').replace(/^#/, '').trim();
    // Helper estimasi lebar teks Helvetica (1000 units per em)
    const charWidths = {
      ' ': 278, '.': 278, ',': 278, '-': 333, ':': 278, '(': 333, ')': 333, '/': 278,
      'A': 667, 'B': 667, 'C': 722, 'D': 722, 'E': 667, 'F': 611, 'G': 778, 'H': 722,
      'I': 278, 'J': 500, 'K': 667, 'L': 556, 'M': 833, 'N': 722, 'O': 778, 'P': 667,
      'Q': 778, 'R': 722, 'S': 667, 'T': 611, 'U': 722, 'V': 667, 'W': 944, 'X': 667,
      'Y': 667, 'Z': 611, '0': 556, '1': 556, '2': 556, '3': 556, '4': 556, '5': 556,
      '6': 556, '7': 556, '8': 556, '9': 556
    };
    function getTextWidth(str, size = 10.5) {
      let total = 0;
      for (const c of String(str || '').toUpperCase()) {
        total += (charWidths[c] || 550);
      }
      return (total * size) / 1000;
    }

    // Helper wrap teks ke baris-baris jika melebihi batas lebar (maxWidthPt)
    function wrapText(text, maxWidthPt = 106, size = 10.5) {
      const words = String(text || '').trim().split(/\s+/);
      if (words.length === 0 || words[0] === '') return ['-'];
      const lines = [];
      let currentLine = '';
      for (const word of words) {
        const testLine = currentLine ? `${currentLine} ${word}` : word;
        if (getTextWidth(testLine, size) <= maxWidthPt) {
          currentLine = testLine;
        } else {
          if (currentLine) {
            lines.push(currentLine);
            currentLine = word;
          } else {
            lines.push(word);
            currentLine = '';
          }
        }
      }
      if (currentLine) lines.push(currentLine);
      return lines;
    }

    // Kepada: Hanya nama alias toko (atau customer name)
    const custAlias = String(inv.aliasName || inv.customerName || 'Pelanggan').trim();
    const cleanCity = inv.city || 'SEMARANG';
    const cleanProv = inv.province || 'JAWA TENGAH';
    const fullAddr = `${cleanCity}, ${cleanProv}`.trim();

    let delivDateStr = '-';
    if (inv.deliveryDate) {
      try {
        const d = inv.deliveryDate.toDate ? inv.deliveryDate.toDate() : new Date(inv.deliveryDate);
        delivDateStr = `${String(d.getDate()).padStart(2, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${d.getFullYear()}`;
      } catch (_) {}
    }

    // Wrap Kepada dan Alamat secara otomatis jika nama/alamat terlalu panjang
    const kepadaLines = wrapText(custAlias, 106, 10.5);
    const alamatLines = wrapText(fullAddr, 106, 10.5);

    // Hitung total baris metadata di kolom kanan (minimal 4 baris)
    const totalRightLines = 1 + kepadaLines.length + 1 + alamatLines.length;
    const lineStep = 13.5;

    // Tinggi kotak header dinamis menyesuaikan isi (minimal 82 pt)
    const headerBoxH = Math.max(82, 28 + (totalRightLines * lineStep));
    const boxTop = 775;
    const boxBottom = boxTop - headerBoxH;

    // 1. TOP HEADER BOX (Kotak Border Hitam Solid 2px: Lebar 572 pt, Tinggi dinamis)
    // x = 20, y = boxBottom, w = 572, h = headerBoxH
    drawRect(20, boxBottom, 572, headerBoxH, 2);

    // Kiri: Logo Bulat Fiva + Identitas Perusahaan
    const logoY = boxTop - 64;
    if (hasLogo) {
      // Gambar image object /I11 berukuran 54 x 54 pt pada koordinat x = 26
      stream += `q 54 0 0 54 26 ${logoY} cm /I11 Do Q\n`;
    } else {
      // Vector circle fallback
      drawRect(26, logoY, 54, 54, 1.5, 0.8, 0.1, 0.1);
      drawText('F2', 12, 36, logoY + 22, 'Fiva', 0.8, 0.1, 0.1);
    }

    // Teks Nama & Alamat Perusahaan di Kiri (Font 8.2pt agar ada margin aman dengan kolom kanan)
    drawText('F2', 12, 86, boxTop - 20, 'FIVA SOLO FOOD & MEAT SUPPLY', 0, 0, 0);
    drawText('F1', 8.2, 86, boxTop - 34, 'JL. Pembangunan II No. 27 Jatibening I, Pondok Gede, Bekasi 17412,', 0, 0, 0);
    drawText('F1', 8.2, 86, boxTop - 46, 'Tel: 021-8484308', 0, 0, 0);
    drawText('F1', 8.2, 86, boxTop - 58, 'Fax: 021-84972237', 0, 0, 0);

    // Kanan: Metadata Faktur (No Invoice, Kepada, Tanggal Pengiriman, Alamat)
    // labelX = 362 (ada jarak aman 24 pt dari Bekasi 17412 yang berakhir di x=338)
    const labelX = 362;
    const colonX = 468;
    const valX = 475;

    let rightY = boxTop - 20;

    // 1. No Invoice
    drawText('F2', 10.5, labelX, rightY, 'No Invoice');
    drawText('F2', 10.5, colonX, rightY, ':');
    drawText('F1', 10.5, valX, rightY, invoiceNo);
    rightY -= lineStep;

    // 2. Kepada (Wrap otomatis jika panjang)
    drawText('F2', 10.5, labelX, rightY, 'Kepada');
    drawText('F2', 10.5, colonX, rightY, ':');
    for (let i = 0; i < kepadaLines.length; i++) {
      drawText('F1', 10.5, valX, rightY, kepadaLines[i]);
      if (i < kepadaLines.length - 1) {
        rightY -= lineStep;
      }
    }
    rightY -= lineStep;

    // 3. Tanggal Pengiriman
    drawText('F2', 10.5, labelX, rightY, 'Tanggal Pengiriman');
    drawText('F2', 10.5, colonX, rightY, ':');
    drawText('F1', 10.5, valX, rightY, delivDateStr);
    rightY -= lineStep;

    // 4. Alamat (Wrap otomatis jika panjang)
    drawText('F2', 10.5, labelX, rightY, 'Alamat');
    drawText('F2', 10.5, colonX, rightY, ':');
    for (let i = 0; i < alamatLines.length; i++) {
      drawText('F1', 10.5, valX, rightY, alamatLines[i]);
      if (i < alamatLines.length - 1) {
        rightY -= lineStep;
      }
    }

    // 2. SECTION TITLE BAR: INVOICE (Kotak Border Hitam 2px, Teks Bold Tengah Kapital)
    const invoiceBarTop = boxBottom;
    const invoiceBarH = 24;
    const invoiceBarBottom = invoiceBarTop - invoiceBarH;
    drawRect(20, invoiceBarBottom, 572, invoiceBarH, 2);
    const titleText = String(invoiceNo).toUpperCase().startsWith('LA') ? 'INVOICE LAMPIRAN' : 'INVOICE';
    drawText('F2', 14, 268, invoiceBarBottom + 8, titleText, 0, 0, 0);

    // 3. TABLE GRID (FULL SOLID BLACK BORDER DENGAN 5 KOLOM PRESISI & 14 BARIS KOTAK)
    // x = 20, lebar total = 572 pt.
    // Kolom 0 (NAMA BARANG): 255 pt -> x: 20 s/d 275
    // Kolom 1 (QTY): 55 pt         -> x: 275 s/d 330
    // Kolom 2 (HARGA): 85 pt       -> x: 330 s/d 415
    // Kolom 3 (DISKON): 75 pt      -> x: 415 s/d 490
    // Kolom 4 (SUB TOTAL): 102 pt  -> x: 490 s/d 592
    const tableTop = invoiceBarBottom;
    const headerH = 18;
    const rowH = 17.5;
    const totalGridRows = 14;
    const tableH = headerH + (totalGridRows * rowH); // 18 + 245 = 263 pt
    const tableBottom = tableTop - tableH;

    // Border Luar Tabel 2px
    drawRect(20, tableBottom, 572, tableH, 2);

    // Garis Pemisah Vertikal Kolom (Garis Solid 0.5px tembus dari atas sampai bawah)
    drawLine(275, tableBottom, 275, tableTop, 0.5);
    drawLine(330, tableBottom, 330, tableTop, 0.5);
    drawLine(415, tableBottom, 415, tableTop, 0.5);
    drawLine(490, tableBottom, 490, tableTop, 0.5);

    // Garis Bawah Header Tabel (2px)
    const headerBottomY = tableTop - headerH;
    drawLine(20, headerBottomY, 592, headerBottomY, 2);

    // Teks Header Tabel (Bold Kapital di Tengah Kolom)
    drawText('F2', 9, 100, headerBottomY + 5.5, 'NAMA BARANG');
    drawText('F2', 9, 294, headerBottomY + 5.5, 'QTY');
    drawText('F2', 9, 356, headerBottomY + 5.5, 'HARGA');
    drawText('F2', 9, 434, headerBottomY + 5.5, 'DISKON');
    drawText('F2', 9, 520, headerBottomY + 5.5, 'SUB TOTAL');

    // Render Data Barang & Garis Baris
    const items = Array.isArray(inv.items) ? inv.items : [];
    let currentY = headerBottomY;

    for (let r = 0; r < totalGridRows; r++) {
      const nextY = currentY - rowH;
      // Gambar garis horizontal pemisah baris (kecuali baris terakhir yang sudah ada border tabel)
      if (r < totalGridRows - 1) {
        drawLine(20, nextY, 592, nextY, 0.5);
      }

      if (r < items.length) {
        const it = items[r];
        const pName = it.displayNameWithBonus || it.productName || 'PRODUK';
        const qtyPcs = it.qty || 0;
        const price = Math.round(it.price || 0);
        const subtotal = Math.round(it.subtotal || 0);

        let discStr = '0,00%';
        if (it.isBonus) {
          discStr = '-';
        } else if (it.discountPercent && it.discountPercent > 0) {
          discStr = `${it.discountPercent.toFixed(2).replace('.', ',')}%`;
        }

        const priceStr = it.isBonus ? 'Rp 0' : `Rp ${price.toLocaleString('id-ID')}`;
        const subtotalStr = it.isBonus ? 'Rp 0' : `Rp ${subtotal.toLocaleString('id-ID')}`;

        // Text Y baseline
        const textY = nextY + 5.5;

        // Col 0: Nama Barang (Left aligned)
        drawText('F1', 9, 24, textY, pName.substring(0, 38));

        // Col 1: Qty (Centered in 275..330)
        const qtyStr = String(qtyPcs);
        const qtyOffset = 302 - (qtyStr.length * 2.5);
        drawText('F1', 9, qtyOffset, textY, qtyStr);

        // Col 2: Harga (Right aligned at 410)
        const prOffset = 410 - (priceStr.length * 5.2);
        drawText('F1', 9, prOffset, textY, priceStr);

        // Col 3: Diskon (Centered in 415..490)
        const discOffset = 452 - (discStr.length * 2.6);
        drawText('F1', 9, discOffset, textY, discStr);

        // Col 4: Sub Total (Right aligned at 587)
        const subOffset = 587 - (subtotalStr.length * 5.2);
        drawText('F1', 9, subOffset, textY, subtotalStr);
      }

      currentY = nextY;
    }

    // 4. BOTTOM SECTION: Catatan Merah & Diterima Oleh (Kiri) | Box Grand Total & Tanda Tangan (Kanan)
    const bottomTop = tableBottom - 6;

    // Kiri: Catatan (HANYA catatan asli pelanggan, LOG REVISI BOT DIKOSONGKAN sesuai Gambar 2 & 3)
    if (inv.note && String(inv.note).trim().length > 0) {
      const fullNote = String(inv.note).trim();
      if (!fullNote.toLowerCase().includes('revisi wa l-w.a.v.i.s')) {
        const maxChars = 75;
        let noteY = bottomTop - 6;
        for (let i = 0; i < fullNote.length && i < 225; i += maxChars) {
          const line = fullNote.substring(i, i + maxChars);
          drawText('F3', 8.5, 20, noteY, line, 0.85, 0.1, 0.1);
          noteY -= 11;
        }
      }
    }

    // Tanda Tangan Kiri: Diterima Oleh,
    drawText('F2', 10.5, 20, bottomTop - 42, 'Diterima Oleh,', 0, 0, 0);

    // Kanan: Box GRAND TOTAL (Border 2px, Divided Column 110 pt | 102 pt)
    // x = 380, y = bottomTop - 24, w = 212, h = 24
    const totalBoxY = bottomTop - 24;
    drawRect(380, totalBoxY, 212, 24, 2);
    drawLine(490, totalBoxY, 490, totalBoxY + 24, 0.5);

    drawText('F2', 11, 396, totalBoxY + 7, 'GRAND TOTAL', 0, 0, 0);
    const grandStr = `Rp ${Math.round(inv.grandTotal || 0).toLocaleString('id-ID')}`;
    const grandOffset = 587 - (grandStr.length * 6);
    drawText('F2', 11, grandOffset, totalBoxY + 7, grandStr, 0, 0, 0);

    // Tanda Tangan Kanan: Pengirim & Hormat Kami, (dengan nama Setiawan di bawahnya)
    const sigY = totalBoxY - 18;
    drawText('F2', 10.5, 430, sigY, 'Pengirim', 0, 0, 0);
    drawText('F2', 10.5, 526, sigY, 'Hormat Kami,', 0, 0, 0);

    drawText('F2', 10.5, 430, sigY - 45, 'Setiawan', 0, 0, 0);
    drawText('F2', 10.5, 526, sigY - 45, 'Setiawan', 0, 0, 0);

    // 4: Content Stream Object
    addObj(`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`);

    // 5: Fonts
    addObj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
    addObj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>');
    addObj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-BoldOblique >>');

    // 8: XObject Images (Fiva Logo & SMask) jika file fiva-logo.bin ada
    if (hasLogo) {
      const obj8Body = Buffer.concat([
        Buffer.from(`<</Type/XObject/Subtype/Image/Width 300/Height 300/BitsPerComponent 8/Name/I11/ColorSpace/DeviceRGB/SMask 9 0 R/Filter/FlateDecode/Length ${fivaLogoStream.length}>>\nstream\n`),
        fivaLogoStream,
        Buffer.from('\nendstream')
      ]);
      const obj9Body = Buffer.concat([
        Buffer.from(`<</Type/XObject/Subtype/Image/Width 300/Height 300/BitsPerComponent 8/Name/I12/ColorSpace/DeviceGray/Filter/FlateDecode/Length ${fivaMaskStream.length}>>\nstream\n`),
        fivaMaskStream,
        Buffer.from('\nendstream')
      ]);
      addObj(obj8Body); // 8 0 R: Image /I11
      addObj(obj9Body); // 9 0 R: SMask
    }

    let header = Buffer.from('%PDF-1.4\n');
    const parts = [header];
    let currentOffset = header.length;
    const offsets = [];

    objects.forEach((obj, idx) => {
      offsets.push(currentOffset);
      const objHeader = Buffer.from(`${idx + 1} 0 obj\n`);
      const objBody = Buffer.isBuffer(obj) ? obj : Buffer.from(obj, 'utf8');
      const objTrailer = Buffer.from('\nendobj\n');
      parts.push(objHeader, objBody, objTrailer);
      currentOffset += objHeader.length + objBody.length + objTrailer.length;
    });

    const startxref = currentOffset;
    let xrefStr = `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
    offsets.forEach(off => {
      xrefStr += `${String(off).padStart(10, '0')} 00000 n \n`;
    });
    xrefStr += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${startxref}\n%%EOF\n`;
    parts.push(Buffer.from(xrefStr, 'utf8'));

    return Buffer.concat(parts);
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

    const cust = data.customer || {};
    const custName = cust.customerName || 'PELANGGAN';
    const alias = cust.aliasName ? ` (${cust.aliasName})` : '';
    const cleanCity = cust.city || 'SEMARANG';
    const cleanProv = cust.province || 'JAWA TENGAH';
    const totalDebt = Math.round(data.totalDebt || 0);

    let tglStr = 'Hari ini';
    try {
      const d = new Date();
      tglStr = `${String(d.getDate()).padStart(2, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${d.getFullYear()}`;
    } catch (_) {}

    // 1. Header Banner
    drawRect(40, 765, 515, 50, 0.008, 0.518, 0.780);
    drawText('F2', 13.5, 55, 796, 'PT PUTRA FIVA SEJAHTERA (CABANG JAWA TENGAH)', 1, 1, 1);
    drawText('F1', 8.2, 55, 782, 'JL. Pembangunan II No. 27 Jatibening I, Pondok Gede, Bekasi, Indonesia 17412, Tel: 021-8484308', 0.9, 0.95, 1);
    drawText('F3', 7.5, 55, 771, 'Sistem Penjualan & Distribusi Terpadu L-W.A.V.I.S (L-Whatsapp Assistant Vision Interactive System)', 0.85, 0.92, 0.98);

    // 2. Judul Dokumen
    drawText('F2', 13, 40, 742, 'KARTU PIUTANG PELANGGAN', 0.06, 0.09, 0.16);
    drawLine(40, 735, 555, 735, 0.008, 0.518, 0.780, 1.5);

    // 3. Info Box Pelanggan
    drawRect(40, 665, 515, 62, 0.96, 0.97, 0.98);
    drawLine(40, 665, 555, 665, 0.85, 0.9, 0.95, 1);
    drawLine(40, 727, 555, 727, 0.85, 0.9, 0.95, 1);
    drawLine(40, 665, 40, 727, 0.85, 0.9, 0.95, 1);
    drawLine(555, 665, 555, 727, 0.85, 0.9, 0.95, 1);

    drawText('F2', 9, 52, 708, 'Nama Pelanggan:', 0.3, 0.35, 0.4);
    drawText('F2', 9, 145, 708, `${custName}${alias}`, 0.06, 0.09, 0.16);
    drawText('F2', 9, 52, 690, 'Kota / Wilayah:', 0.3, 0.35, 0.4);
    drawText('F1', 9, 145, 690, `${cleanCity}, ${cleanProv}`, 0.06, 0.09, 0.16);
    drawText('F2', 9, 52, 672, 'Tanggal Cetak:', 0.3, 0.35, 0.4);
    drawText('F1', 9, 145, 672, tglStr, 0.06, 0.09, 0.16);

    drawText('F2', 10, 345, 695, 'TOTAL SISA PIUTANG:', 0.7, 0.1, 0.1);
    drawText('F2', 13, 345, 675, `Rp ${totalDebt.toLocaleString('id-ID')}`, 0.85, 0.1, 0.1);

    // 4. Tabel Faktur Belum Lunas
    let tableY = 635;
    drawRect(40, tableY, 515, 22, 0.12, 0.16, 0.23);
    drawText('F2', 8.5, 46, tableY + 7, 'No', 1, 1, 1);
    drawText('F2', 8.5, 80, tableY + 7, 'No. Invoice', 1, 1, 1);
    drawText('F2', 8.5, 175, tableY + 7, 'Tgl Transaksi', 1, 1, 1);
    drawText('F2', 8.5, 275, tableY + 7, 'Grand Total (Rp)', 1, 1, 1);
    drawText('F2', 8.5, 385, tableY + 7, 'Terbayar (Rp)', 1, 1, 1);
    drawText('F2', 8.5, 475, tableY + 7, 'Sisa Piutang (Rp)', 1, 1, 1);

    tableY -= 20;
    const unpaid = Array.isArray(data.unpaidInvoices) ? data.unpaidInvoices : [];

    if (unpaid.length === 0) {
      drawText('F2', 10, 180, tableY - 10, 'STATUS LUNAS: Tidak ada faktur tertunggak! ✅', 0.05, 0.5, 0.2);
      tableY -= 30;
    } else {
      unpaid.forEach((inv, idx) => {
        const isEven = (idx % 2 === 1);
        if (isEven) {
          drawRect(40, tableY - 2, 515, 20, 0.97, 0.98, 0.99);
        }
        drawLine(40, tableY - 2, 555, tableY - 2, 0.88, 0.9, 0.92, 0.5);

        let invDateStr = '-';
        if (inv.date) {
          try {
            const d = inv.date.toDate ? inv.date.toDate() : new Date(inv.date);
            invDateStr = `${String(d.getDate()).padStart(2, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${d.getFullYear()}`;
          } catch (_) {}
        }

        const grand = Number(inv.grandTotal) || 0;
        const paid = Number(inv.transferBankDetails?.totalPaid || inv.transferBankDetails?.amount || inv.paidAmount || 0);
        const rem = Math.max(0, grand - paid);

        drawText('F1', 8, 48, tableY + 4, String(idx + 1), 0.2, 0.2, 0.2);
        drawText('F2', 8, 80, tableY + 4, `#${inv.invoiceNo || inv.id}`, 0.06, 0.09, 0.16);
        drawText('F1', 8, 175, tableY + 4, invDateStr, 0.2, 0.2, 0.2);
        drawText('F1', 8, 275, tableY + 4, Math.round(grand).toLocaleString('id-ID'), 0.2, 0.2, 0.2);
        drawText('F1', 8, 385, tableY + 4, Math.round(paid).toLocaleString('id-ID'), 0.2, 0.2, 0.2);
        drawText('F2', 8, 475, tableY + 4, Math.round(rem).toLocaleString('id-ID'), 0.75, 0.15, 0.15);

        tableY -= 20;
      });
    }

    drawLine(40, tableY, 555, tableY, 0.12, 0.16, 0.23, 1.2);

    // 5. Info Pembayaran Terakhir
    if (data.lastPayment && data.lastPayment.amount > 0) {
      tableY -= 25;
      drawRect(40, tableY - 10, 515, 26, 0.94, 0.98, 0.94);
      drawLine(40, tableY - 10, 555, tableY - 10, 0.75, 0.88, 0.75, 1);
      drawLine(40, tableY + 16, 555, tableY + 16, 0.75, 0.88, 0.75, 1);
      drawText('F2', 8.5, 52, tableY, 'Pembayaran / Cicilan Terakhir:', 0.05, 0.45, 0.2);
      const bStr = data.lastPayment.bank ? ` via ${data.lastPayment.bank}` : '';
      drawText('F1', 8.5, 210, tableY, `Rp ${Math.round(data.lastPayment.amount).toLocaleString('id-ID')} (Tgl: ${data.lastPayment.date || '-'})${bStr}`, 0.06, 0.09, 0.16);
    }

    // 6. Footer Dokumen
    drawText('F3', 7.2, 40, 40, 'Dicetak otomatis oleh L-W.A.V.I.S (L-Whatsapp Assistant Vision Interactive System) - PT PUTRA FIVA SEJAHTERA (Jawa Tengah)', 0.5, 0.55, 0.6);
    drawText('F1', 7.2, 485, 40, `Tgl Cetak: ${tglStr}`, 0.5, 0.55, 0.6);

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
