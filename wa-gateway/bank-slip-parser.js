/**
 * Bank Receipt / Transfer Slip Parser
 * Detects whether OCR text represents a bank transfer slip or bank mutation line, and extracts structured details
 */
const BSP_VERSION = '3.3.270'; // v3.3.270

function parseBankReceipt(rawText) {
  if (!rawText || typeof rawText !== 'string') {
    return { isBankSlip: false };
  }

  const clean = rawText.replace(/\r\n/g, '\n');
  const upper = clean.toUpperCase();

  // 1. Dokumen Pesanan / Order / Invoice / Surat Jalan / PO: JANGAN DIKIRA STRUK TRANSFER!
  const isOrderDocument =
    upper.includes('ORDER#') ||
    upper.includes('ORDER NUMBER') ||
    upper.includes('PURCHASE ORDER') ||
    upper.includes('DELIVERY ORDER') ||
    upper.includes('SALES ORDER') ||
    upper.includes('SURAT JALAN') ||
    upper.includes('SHIPPING ADDRESS') ||
    upper.includes('CUSTOMER ADDRESS') ||
    upper.includes('SALES PERSON') ||
    upper.includes('PAYMENT TERM') ||
    (upper.includes('DESCRIPTION') && upper.includes('QUANTITY')) ||
    (upper.includes('UNIT PRICE') && upper.includes('PRICE'));

  if (isOrderDocument) {
    return {
      isBankSlip: false,
      isOrderDocument: true,
      rawOcrText: clean
    };
  }

  // Bank name indicators
  const isBca = upper.includes('BCA') || upper.includes('KLIKBCA') || upper.includes('TRSF E-BANKING') || upper.includes('FTSCY') || upper.includes('WS95051') || upper.includes('M-TRANSFER') || upper.includes('M-BCA') || upper.includes('M TRANSFER') || upper.includes('2306039099') || upper.includes('23060') || upper.includes('5306039099') || upper.includes('PURBALINGGA');
  const isMandiri = upper.includes('MANDIRI') || upper.includes('LIVIN');
  const isBri = upper.includes('BRI') || upper.includes('BRIMO');
  const isBni = upper.includes('BNI') || upper.includes('WONDR');

  // E-banking / mutasi indicators
  const isEBanking = upper.includes('E-BANKING') || upper.includes('TRSF') || upper.includes('MUTASI') || upper.includes('REKENING KORAN');
  const isFivaRelated = upper.includes('FIVA') || upper.includes('SEJAHTE') || upper.includes('TITIP INV');

  // Teller / slip setoran fisik indicators
  const isTellerSlip = upper.includes('BUKTI SETORAN') || upper.includes('SETORAN TUNAI') || upper.includes('SETOR TUNAI') || upper.includes('PENYETOR') || upper.includes('NAMA PENYETOR') || upper.includes('NYETOR') || upper.includes('TELLER') || (upper.includes('SETOR') && (isBca || isFivaRelated));

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
    'OFARENSi',
    'REKENING TUJUAN',
    'NAMA PENERIMA',
    'DETAIL TRANSAKSI',
    '2306039099', // Rekening BCA PT Putra Fiva Sejahtera
    '5306039099', // Variasi OCR rekening
    'TRSF E-BANKING',
    'TITIP INV',
    'MUTASI',
    'M-TRANSFER',
    'M-BCA',
    'M TRANSFER',
    'BIAYA BONGKAR',
    'SETORAN TUNAI',
    'BUKTI SETORAN',
    'SETOR TUNAI',
    'PENYETOR',
    'TELLER',
    'BEBAS BIAYA ADM'
  ];

  let keywordHits = 0;
  for (const kw of receiptKeywords) {
    if (upper.includes(kw)) keywordHits++;
  }

  // PT Fiva identity counts at most 1 hit (prevent duplicate matching)
  if (upper.includes('PUTRA FIVA') || upper.includes('UTRA FIVA') || upper.includes('FIVA SEJAHTERA')) {
    keywordHits++;
  }

  // Must hit at least 2 bank receipt indicators or 1 strong indicator with bank context
  const hasStrongIndicator =
    upper.includes('BUKTI TRANSAKSI') ||
    upper.includes('BUKTI SETORAN') ||
    upper.includes('SETORAN TUNAI') ||
    upper.includes('SETOR TUNAI') ||
    upper.includes('PENYETOR') ||
    upper.includes('TRANSFER DANA') ||
    upper.includes('TRSF E-BANKING') ||
    upper.includes('M-TRANSFER') ||
    upper.includes('M-BCA') ||
    (isTellerSlip && (isBca || isFivaRelated)) ||
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
    // Formatted currency with thousand separators e.g. "874,574.00" or "102,874,574.00" or "24.784.640"
    /\b([0-9]{1,3}(?:[.,][0-9]{3})+(?:[.,][0-9]{2})?)\b/,
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
  if (upper.includes('WIMBO') || upper.includes('KUSTANTO') || upper.includes('LG FF')) customerHint = 'LG FF (WIMBO WIEK KUSTANTO)';
  else if (upper.includes('MAJU MARKET')) customerHint = 'MAJU MARKET MANDIRI';
  else if (upper.includes('SJJ')) customerHint = 'SJJ';
  else if (upper.includes('SUSILO') || upper.includes('MISTER')) customerHint = 'MISTER SOSIS';
  else if (upper.includes('ANNISA') || upper.includes('ANIZA')) customerHint = 'ANIZA FF';
  else if (upper.includes('PARIS')) customerHint = 'PARIS FOOD';
  else if (upper.includes('HANA MAKMUR')) customerHint = 'HANA MAKMUR';
  else if (upper.includes('AW FF') || /\bAW\b/.test(upper)) customerHint = 'AW FF';

  // Dynamic extraction from receipt lines (e.g. "Dari »— Wimbo Wiek Kustanto", "Pengirim: ...", "Dari: ...")
  let senderNameFromSlip = '';
  const senderMatch = clean.match(/(?:Dari|Pengirim|Nama Pengirim|Dari Rekening|Nama)\s*[:=»\-–—\s]+([^\r\n@]+)/i);
  if (senderMatch) {
    const rawSender = senderMatch[1].trim();
    if (!rawSender.toUpperCase().includes('REKENING') && !rawSender.toUpperCase().includes('BANK') && rawSender.length >= 3) {
      senderNameFromSlip = rawSender;
      if (!customerHint) {
        customerHint = rawSender;
      }
    }
  }

  // Extract Company Name if present in OCR (e.g. "CV HANA MAKMUR") - Prioritas karena lebih bersih
  const coMatches = Array.from(clean.matchAll(/\b(CV|PT|UD|TOKO)[ \t]+([A-Za-z0-9 ]{3,30})/gi));
  for (const m of coMatches) {
    const rawCo = m[0].trim();
    const upCo = rawCo.toUpperCase();
    if (!upCo.includes('FIVA') && !upCo.includes('SEJAHTERA') && !upCo.includes('PUTRA')) {
      customerHint = rawCo;
      senderNameFromSlip = rawCo;
      break;
    }
  }

  // Extract Penyetor from physical teller slip (e.g. "Nama Penyetor : CV HANA MAKMUR" / "Penyetor : ...")
  if (!senderNameFromSlip) {
    const penyetorMatch = clean.match(/(?:Nama\s*Penyetor|Penyetor|Rep\s*stor|Nyetor)\s*[:=»\-–—\s]+([^\r\n/]+)/i);
    if (penyetorMatch) {
      const rawP = penyetorMatch[1].replace(/[^a-zA-Z0-9\s]/g, ' ').trim();
      if (rawP.length >= 3) {
        senderNameFromSlip = rawP;
        if (!customerHint) customerHint = rawP;
      }
    }
  }

  // Extract ID / No Rek Penyetor (e.g. "0979022222")
  let penyetorId = '';
  const idMatch = clean.match(/(?:No\.?\s*ID|Rek|Nyetor)\s*[:=.\s]+([0-9]{5,15})/i);
  if (idMatch) {
    penyetorId = idMatch[1].trim();
  }

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

  // Validasi Mutlak: Jika indikator bank/teller sangat kuat, JANGAN DIBALIKKAN KE BUKAN STRUK!
  // Tetap tandai sebagai isBankSlip: true agar tidak pernah salah dibuatkan PO!
  if (amount <= 0 && !hasStrongIndicator && !isTellerSlip) {
    return {
      isBankSlip: false,
      rawOcrText: clean
    };
  }

  return {
    isBankSlip: true,
    slipType: isTellerSlip ? 'TELLER_DEPOSIT_SLIP' : 'TRANSFER_SLIP',
    bank: bankName,
    amount: amount || 0,
    isAmountUnclear: amount <= 0,
    refNumber,
    penyetorId,
    berita,
    recipient,
    senderNameFromSlip,
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
