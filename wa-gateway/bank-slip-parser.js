/**
 * Bank Receipt / Transfer Slip Parser
 * Detects whether OCR text represents a bank transfer slip or bank mutation line, and extracts structured details
 */

function parseBankReceipt(rawText) {
  if (!rawText || typeof rawText !== 'string') {
    return { isBankSlip: false };
  }

  const clean = rawText.replace(/\r\n/g, '\n');
  const upper = clean.toUpperCase();

  // Bank name indicators
  const isBca = upper.includes('BCA') || upper.includes('KLIKBCA') || upper.includes('TRSF E-BANKING') || upper.includes('FTSCY') || upper.includes('WS95051') || upper.includes('M-TRANSFER') || upper.includes('M-BCA') || upper.includes('M TRANSFER');
  const isMandiri = upper.includes('MANDIRI') || upper.includes('LIVIN');
  const isBri = upper.includes('BRI') || upper.includes('BRIMO');
  const isBni = upper.includes('BNI') || upper.includes('WONDR');

  // E-banking / mutasi indicators
  const isEBanking = upper.includes('E-BANKING') || upper.includes('TRSF') || upper.includes('MUTASI') || upper.includes('REKENING KORAN');
  const isFivaRelated = upper.includes('FIVA') || upper.includes('SEJAHTE') || upper.includes('TITIP INV');

  // Transfer receipt indicator keywords
  const receiptKeywords = [
    'TRANSFER DANA',
    'TRANSAKSI TRANSFER',
    'TRANSFER SEKARANG',
    'TRANSAKSI BERHASIL',
    'TRANSFER BERHASIL',
    'BERHASIL',
    'NOMOR REFERENSI',
    'NO. REFERENSI',
    'REKENING TUJUAN',
    'NAMA PENERIMA',
    'DETAIL TRANSAKSI',
    'FIVA SEJAHTERA',
    'FIVA SEJAHTE',
    'PUTRA FIVA',
    '2306039099', // Rekening BCA PT Putra Fiva Sejahtera
    'TRSF E-BANKING',
    'TITIP INV',
    'MUTASI',
    'M-TRANSFER',
    'M-BCA',
    'M TRANSFER',
    'BIAYA BONGKAR'
  ];

  let keywordHits = 0;
  for (const kw of receiptKeywords) {
    if (upper.includes(kw)) keywordHits++;
  }

  // Must hit at least 2 bank receipt indicators or 1 strong indicator with bank context
  const hasStrongIndicator =
    upper.includes('BUKTI TRANSAKSI') ||
    upper.includes('TRANSFER DANA') ||
    upper.includes('TRSF E-BANKING') ||
    upper.includes('M-TRANSFER') ||
    upper.includes('M-BCA') ||
    (isEBanking && isFivaRelated) ||
    (upper.includes('BERHASIL') && (isBca || isMandiri || isBri || isBni));

  if (keywordHits < 2 && !hasStrongIndicator) {
    return { isBankSlip: false };
  }

  let bankName = 'BANK LAIN';
  if (isBca) bankName = 'BCA';
  else if (isMandiri) bankName = 'MANDIRI';
  else if (isBri) bankName = 'BRI';
  else if (isBni) bankName = 'BNI';

  // Extract Amount (Nominal Uang)
  let amount = 0;
  const amountPatterns = [
    // Pattern for mutasi accounting line e.g. "22,000,000.00 DB" or "22.000.000,00 DB" or "22,000,000.00 CR"
    /([0-9]{1,3}(?:[.,][0-9]{3})+(?:[.,][0-9]{2})?)\s*(?:DB|CR)\b/i,
    // Standard format with Jumlah / Total / Nominal
    /(?:Jumlah|Total|Nominal)\s*[:=]?\s*(?:Rp\.?|IDR)?\s*([0-9]{1,3}(?:[.,][0-9]{3})*(?:[.,][0-9]{2})?)/i,
    /(?:IDR|Rp\.?)\s*([0-9]{1,3}(?:[.,][0-9]{3})+(?:[.,][0-9]{2})?)/i,
    /(?:IDR|Rp\.?)\s*([0-9]+(?:[.,][0-9]{2})?)/i,
    // Raw mutasi digits without comma e.g. "22000000.00"
    /\b([0-9]{5,10}\.[0-9]{2})\b/
  ];

  for (const pat of amountPatterns) {
    const match = clean.match(pat);
    if (match && match[1]) {
      let numStr = match[1].trim();
      // Handle Indonesian currency format "7.050.000,00" or standard "10,136,331.00"
      if (numStr.includes('.') && numStr.includes(',')) {
        if (numStr.lastIndexOf(',') > numStr.lastIndexOf('.')) {
          // Indonesian: 7.050.000,00 -> 7050000.00
          numStr = numStr.replace(/\./g, '').replace(',', '.');
        } else {
          // US: 10,136,331.00 -> 10136331.00
          numStr = numStr.replace(/,/g, '');
        }
      } else if (numStr.includes('.')) {
        const parts = numStr.split('.');
        if (parts.length > 2 || (parts.length === 2 && parts[1].length === 3)) {
          numStr = numStr.replace(/\./g, '');
        }
      } else if (numStr.includes(',')) {
        const parts = numStr.split(',');
        if (parts.length > 2 || (parts.length === 2 && parts[1].length === 3)) {
          numStr = numStr.replace(/,/g, '');
        }
      }
      const parsed = parseFloat(numStr);
      if (!isNaN(parsed) && parsed > 0) {
        amount = parsed;
        break;
      }
    }
  }

  // Extract Reference Number
  let refNumber = '';
  const refMatch = clean.match(/(?:Nomor Referensi|No\. Referensi|Ref\.? No\.?|No\. Transaksi)\s*[:=]?\s*([A-Za-z0-9]+)/i);
  if (refMatch) {
    refNumber = refMatch[1].trim();
  } else {
    const ftscyMatch = clean.match(/\b([0-9A-Z]{4,8}\/[A-Z0-9]+\/[A-Z0-9]+)\b/i);
    if (ftscyMatch) refNumber = ftscyMatch[1].trim();
  }

  // Extract Berita / Keterangan / Detail Transaksi
  let berita = '';
  const beritaMatch = clean.match(/(?:Berita|Detail Transaksi|Catatan|Keterangan)\s*[:=]?\s*([^\n\r]+)/i);
  if (beritaMatch) {
    berita = beritaMatch[1].trim();
  } else {
    const titipMatch = clean.match(/(titip\s+inv[^\n\r]*)/i);
    if (titipMatch) {
      berita = titipMatch[1].trim();
    } else if (upper.includes('TRSF E-BANKING')) {
      const lines = clean.split('\n').map(l => l.trim()).filter(Boolean);
      const lastLine = lines.find(l => l.toUpperCase().includes('FIVA') || l.toUpperCase().includes('SEJAHTE'));
      if (lastLine) berita = lastLine;
    } else {
      const lines = clean.split('\n').map(l => l.trim()).filter(Boolean);
      const amountIdx = lines.findIndex(l => /(?:Rp\.?|IDR)\s*[0-9]/i.test(l));
      if (amountIdx !== -1 && amountIdx + 1 < lines.length) {
        const candidate = lines[amountIdx + 1];
        if (!candidate.toUpperCase().includes('BERHASIL') && !candidate.toUpperCase().includes('M-TRANSFER')) {
          berita = candidate;
        }
      }
    }
  }

  // Extract Target Invoice Number
  let invoiceNo = null;
  const beritaClean = (berita || '').replace(/2306039099/g, '');
  const fullClean = clean.replace(/2306039099/g, '');

  const dateDashInvMatch = beritaClean.match(/\d{1,2}\/\d{1,2}\s*-\s*(\d{2,5})\b/);
  if (dateDashInvMatch) {
    invoiceNo = dateDashInvMatch[1];
  } else {
    const prefixMatch = beritaClean.match(/(?:#|INV|INVOICE|NOTA|FAKTUR|SJJ?|PO)\s*[:=.\-]?\s*(\d{2,5})\b/i);
    if (prefixMatch) {
      invoiceNo = prefixMatch[1];
    } else {
      const fullPrefixMatch = fullClean.match(/(?:#|INV|INVOICE|NOTA|FAKTUR)\s*[:=.\-]?\s*(\d{2,5})\b/i);
      if (fullPrefixMatch) invoiceNo = fullPrefixMatch[1];
    }
  }

  // Extract Customer Hint
  let customerHint = '';
  if (upper.includes('MAJU MARKET')) customerHint = 'MAJU MARKET MANDIRI';
  else if (upper.includes('SJJ')) customerHint = 'SJJ';
  else if (upper.includes('SUSILO') || upper.includes('MISTER')) customerHint = 'MISTER SOSIS';
  else if (upper.includes('ANNISA') || upper.includes('ANIZA')) customerHint = 'ANIZA FF';
  else if (upper.includes('PARIS')) customerHint = 'PARIS FOOD';
  else if (upper.includes('HANA MAKMUR')) customerHint = 'HANA MAKMUR';
  else if (upper.includes('AW FF') || upper.includes('AW')) customerHint = 'AW FF';

  // Extract Recipient if available (e.g. "Ke 8175683107\nARSANDY VIDYA GUPTA PRAD")
  let recipient = '';
  const keMatch = clean.match(/Ke\s+([0-9]+)\s*[\r\n]+([^\r\n]+)/i);
  if (keMatch) {
    recipient = keMatch[2].trim();
  }

  // Detect Operational Expense vs Invoice Payment
  const expenseKeywords = [
    'BIAYA BONGKAR',
    'BONGKAR MUAT',
    'UANG MAKAN',
    'BENSIN',
    'SOLAR',
    'PARKIR',
    'TOL',
    'ONGKIR',
    'KASBON',
    'RETRIBUSI',
    'BIAYA OPERASIONAL'
  ];

  let isExpense = false;
  let expenseCategory = '';
  for (const exp of expenseKeywords) {
    if (upper.includes(exp)) {
      isExpense = true;
      expenseCategory = exp.replace(/\s+/g, '_');
      break;
    }
  }

  // Extract Date
  let rawDate = '';
  const dateMatch =
    clean.match(/(?:Tanggal|Tanggal Efektif|Tgl)\s*[:=]?\s*([0-9]{1,2}[\/\-\s][0-9A-Za-z]{2,8}[\/\-\s][0-9]{2,4})/i) ||
    clean.match(/(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})/i) ||
    clean.match(/(\d{1,2}\/\d{1,2}\/\d{2,4})/);
  if (dateMatch) {
    rawDate = dateMatch[1].trim();
  }

  return {
    isBankSlip: true,
    bank: bankName,
    amount,
    refNumber,
    berita,
    recipient,
    isExpense,
    expenseCategory,
    invoiceNo: isExpense ? null : invoiceNo,
    customerHint: isExpense ? '' : customerHint,
    rawDate,
    keywordHits,
    rawOcrText: clean
  };
}

module.exports = {
  parseBankReceipt
};
