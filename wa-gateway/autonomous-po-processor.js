/**
 * Autonomous PO Processor for WhatsApp Gateway (Termux / Background Node.js)
 * Memungkinkan pembuatan PO / Faktur Penjualan secara mandiri dari HP (Termux)
 * saat laptop kasir mati / aplikasi Flutter belum dibuka.
 */
const APO_VERSION = '3.3.272'; // v3.3.272 - Notifikasi Tahap 2 PO Sukses & Review Needed via FCM

class AutonomousPoProcessor {
  constructor(firebaseAdapter, notificationDispatcher = null) {
    this.firebaseAdapter = firebaseAdapter;
    this.notificationDispatcher = notificationDispatcher;
    this.cachedCustomers = [];
    this.cachedProducts = [];
    this.cachedRules = [];
    this.lastCacheTime = 0;
    this.CACHE_TTL_MS = 10 * 60 * 1000; // 10 menit cache
  }

  cleanPhone(p) {
    if (!p) return '';
    let s = p.toString().replace(/\D/g, '');
    if (s.startsWith('08')) s = '628' + s.slice(2);
    return s;
  }

  async refreshCacheIfNeeded() {
    const now = Date.now();
    if (now - this.lastCacheTime < this.CACHE_TTL_MS && this.cachedCustomers.length > 0) {
      return;
    }

    try {
      console.log('[AUTONOMOUS PO] 🔄 Menyinkronkan cache Master Data (Customers, Products, Rules) dari Firestore...');
      const db = this.firebaseAdapter.db || this.firebaseAdapter.clientDb;
      const isClient = this.firebaseAdapter.mode === 'client';

      if (!isClient && this.firebaseAdapter.db) {
        // Mode Firebase Admin
        const custSnap = await db.collection('customers').get();
        this.cachedCustomers = custSnap.docs.map(d => ({ id: d.id, ...d.data() }));

        const prodSnap = await db.collection('products').get();
        this.cachedProducts = prodSnap.docs.map(d => ({ id: d.id, ...d.data() }));

        const rulesSnap = await db.collection('ai_knowledge_rules').get();
        this.cachedRules = rulesSnap.docs.map(d => ({ id: d.id, ...d.data() }));
      } else if (isClient && this.firebaseAdapter.clientSdk) {
        // Mode Client SDK
        const { collection, getDocs } = require('firebase/firestore');
        const custSnap = await getDocs(collection(db, 'customers'));
        this.cachedCustomers = custSnap.docs.map(d => ({ id: d.id, ...d.data() }));

        const prodSnap = await getDocs(collection(db, 'products'));
        this.cachedProducts = prodSnap.docs.map(d => ({ id: d.id, ...d.data() }));

        const rulesSnap = await getDocs(collection(db, 'ai_knowledge_rules'));
        this.cachedRules = rulesSnap.docs.map(d => ({ id: d.id, ...d.data() }));
      }

      this.lastCacheTime = now;
      console.log(`[AUTONOMOUS PO] ✅ Cache diperbarui: ${this.cachedCustomers.length} pelanggan, ${this.cachedProducts.length} produk, ${this.cachedRules.length} aturan.`);
    } catch (err) {
      console.warn('[AUTONOMOUS PO CACHE WARNING]', err.message);
    }
  }

  resolveCustomer(lines, senderPhone, pushName) {
    const cleanSender = this.cleanPhone(senderPhone);

    // 1. Cek dari nomor HP
    if (cleanSender) {
      const byPhone = this.cachedCustomers.find(c => {
        const cp = this.cleanPhone(c.phone);
        return cp && (cleanSender.endsWith(cp) || cp.endsWith(cleanSender) || cleanSender === cp);
      });
      if (byPhone) return byPhone;
    }

    // 2. Cek baris pertama / kedua apakah cocok dengan alias rule atau nama pelanggan
    const custRules = this.cachedRules.filter(r => r.type === 'customer_alias');
    for (let i = 0; i < Math.min(lines.length, 3); i++) {
      const lineClean = lines[i].replace(/[^a-zA-Z0-9\s]/g, ' ').trim().toLowerCase();
      if (!lineClean || lineClean.length < 2) continue;

      // Cek rule alias
      const ruleMatch = custRules.find(r => {
        const from = (r.keyword || r.from || '').toLowerCase().trim();
        return from && (lineClean === from || lineClean.startsWith(from + ' ') || lineClean.endsWith(' ' + from));
      });
      if (ruleMatch) {
        // Cek targetId dulu
        if (ruleMatch.targetId) {
          const byId = this.cachedCustomers.find(c => c.id === ruleMatch.targetId);
          if (byId) return byId;
        }
        const targetName = (ruleMatch.mappedValue || ruleMatch.to || '').toLowerCase().trim();
        const found = this.cachedCustomers.find(c =>
          (c.customerName || '').toLowerCase().includes(targetName) ||
          (c.aliasName || '').toLowerCase().includes(targetName)
        );
        if (found) return found;
      }

      // Cek nama customer / alias langsung
      const directMatch = this.cachedCustomers.find(c => {
        const cn = (c.customerName || '').toLowerCase().trim();
        const an = (c.aliasName || '').toLowerCase().trim();
        return (cn && (lineClean.includes(cn) || cn.includes(lineClean))) ||
               (an && (lineClean.includes(an) || an.includes(lineClean)));
      });
      if (directMatch) return directMatch;
    }

    // 3. Cek pushName WhatsApp
    if (pushName) {
      const pnClean = pushName.toLowerCase().trim();
      const byPush = this.cachedCustomers.find(c => {
        const cn = (c.customerName || '').toLowerCase().trim();
        const an = (c.aliasName || '').toLowerCase().trim();
        return (cn && (pnClean.includes(cn) || cn.includes(pnClean))) ||
               (an && (pnClean.includes(an) || an.includes(pnClean)));
      });
      if (byPush) return byPush;
    }

    return null;
  }

  resolveProduct(rawItemText) {
    const lower = rawItemText.toLowerCase();

    // 1. Ekstrak kuantiti & satuan
    const qtyMatch = lower.match(/(?:^|\s|\.\.\.)(\d+(?:[.,]\d+)?)\s*(k|ktn|karton|dus|box|pack|pcs|bal|ball|roll)\b/i);
    let qtyInput = 0;
    let qtyUnit = 'karton';
    if (qtyMatch) {
      qtyInput = parseFloat(qtyMatch[1].replace(',', '.'));
      const u = qtyMatch[2].toLowerCase();
      if (['k', 'ktn', 'karton', 'dus', 'box'].includes(u)) {
        qtyUnit = 'karton';
      } else if (['pack', 'pcs'].includes(u)) {
        qtyUnit = 'pcs';
      } else if (['bal', 'ball'].includes(u)) {
        qtyUnit = 'ball';
      } else if (['roll'].includes(u)) {
        qtyUnit = 'roll';
      }
    } else {
      // Fallback kuantiti di akhir baris: misal "...10"
      const endMatch = lower.match(/(?:\.\.\.|\s+)(\d+)\s*$/);
      if (endMatch) {
        qtyInput = parseFloat(endMatch[1]);
        qtyUnit = 'karton';
      }
    }

    if (qtyInput <= 0) return null;

    // Bersihkan teks barang dari kuantiti
    let cleanProd = lower
      .replace(/(?:^|\s|\.\.\.)(\d+(?:[.,]\d+)?)\s*(k|ktn|karton|dus|box|pack|pcs|bal|ball|roll)\b/gi, ' ')
      .replace(/^[0-9]+[.)]\s*/, '')
      .replace(/\.\.\..*$/, '')
      .replace(/[^a-zA-Z0-9\s]/g, ' ')
      .trim();

    // Normalisasi slang produk frozen food
    cleanProd = cleanProd
      .replace(/\bberes\b/g, 'brs')
      .replace(/\bberas\b/g, 'brs')
      .replace(/\bbratwust\b/g, 'bratwurst');

    // 2. Cocokkan dengan rules produk
    const prodRules = this.cachedRules.filter(r => r.type === 'product_alias');
    for (const r of prodRules) {
      let from = (r.keyword || r.from || '').toLowerCase().trim();
      from = from.replace(/\bberes\b/g, 'brs').replace(/\bberas\b/g, 'brs');
      if (from && cleanProd.includes(from)) {
        // Jika rule punya targetId, gunakan langsung
        if (r.targetId) {
          const p = this.cachedProducts.find(prod => prod.id === r.targetId);
          if (p) {
            return this.buildTransactionItem(p, qtyInput, qtyUnit);
          }
        }
        // Fallback ke nama produk (normalize spaces for matching)
        const to = (r.mappedValue || r.to || '').toLowerCase().trim().replace(/\s+/g, '');
        const p = this.cachedProducts.find(prod => {
          const pn = (prod.productName || prod.name || '').toLowerCase().replace(/\s+/g, '');
          return pn.includes(to) || to.includes(pn);
        });
        if (p) {
          return this.buildTransactionItem(p, qtyInput, qtyUnit);
        }
      }
    }

    // 3. Cocokkan dengan katalog produk langsung
    const words = cleanProd.split(/\s+/).filter(w => w.length >= 3);
    if (words.length > 0) {
      let bestProduct = null;
      let maxScore = 0;

      for (const p of this.cachedProducts) {
        const pName = (p.productName || p.name || '').toLowerCase();
        let score = 0;
        for (const w of words) {
          if (pName.includes(w)) score++;
        }
        if (score > maxScore) {
          maxScore = score;
          bestProduct = p;
        }
      }

      if (bestProduct && maxScore >= Math.min(2, words.length)) {
        return this.buildTransactionItem(bestProduct, qtyInput, qtyUnit);
      }
    }

    return null;
  }


  buildTransactionItem(prod, qtyInput, qtyUnit, historyPricing = null) {
    const sizeGrams = Number(prod.sizeGrams) || 500;
    let pcsPerKtn = Number(prod.isiKarton) || 0;

    // Fallback: Deteksi isi karton dari nama produk jika isiKarton tidak ada di DB
    if (pcsPerKtn <= 0) {
      const pname = prod.productName || prod.name || '';
      if (sizeGrams >= 1000) {
        pcsPerKtn = 10;
      } else if (/\b24S?\b/i.test(pname)) {
        pcsPerKtn = 24;
      } else if (/\b13S?\b/i.test(pname)) {
        pcsPerKtn = 13;
      } else if (/\b7S?\b/i.test(pname)) {
        pcsPerKtn = 7;
      } else {
        pcsPerKtn = 15;
      }
    }

    let qtyPcs = qtyInput;
    if (qtyUnit === 'karton') {
      qtyPcs = qtyInput * pcsPerKtn;
    } else if (qtyUnit === 'ball') {
      qtyPcs = qtyInput * 25; // 1 ball = 25 pcs
    }

    // UPGRADE: Gunakan harga dari customer history jika tersedia
    let price = Number(prod.price) || 0;
    let discountPercent = 0;
    let discountAmount = 0;
    let pricingSource = 'LIST';

    if (historyPricing && historyPricing.price > 0) {
      price = historyPricing.price;
      discountPercent = historyPricing.discountPercent || 0;
      discountAmount = historyPricing.discountAmount || 0;
      pricingSource = `HISTORY (Invoice #${historyPricing.invoiceNo || '?'})`;
    }

    const subtotal = Math.round(qtyPcs * price);
    const productName = prod.productName || prod.name || 'PRODUK';

    console.log(`[AUTONOMOUS PO]   📦 ${productName} | Qty: ${qtyPcs} pcs (${qtyInput} ${qtyUnit}) | Harga: Rp ${price.toLocaleString('id-ID')} [${pricingSource}] | Diskon: ${discountPercent}% | Subtotal: Rp ${subtotal.toLocaleString('id-ID')}`);

    return {
      productId: prod.id || '',
      productName: productName,
      price: price,
      qty: qtyPcs,
      discountPercent: discountPercent,
      discountAmount: discountAmount,
      subtotal: subtotal,
      sizeGrams: sizeGrams,
      weightKg: Math.round(qtyPcs * sizeGrams / 1000 * 100) / 100,
      isBonus: false
    };
  }

  // BARU: Cocokkan produk dari history pembelian customer (sama seperti Flutter _matchProductFromCustomerHistory)
  matchProductFromHistory(productText, customerHistory) {
    if (!customerHistory || customerHistory.length === 0) return null;

    const cleanQ = productText.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').trim();
    if (!cleanQ) return null;

    // 1. Direct name match
    for (const h of customerHistory) {
      const hName = (h.productName || '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').trim();
      if (hName === cleanQ || (h.productId || '').toLowerCase() === cleanQ) {
        return h;
      }
    }

    // 2. Tokenized scoring (domain-aware matching, mirip Flutter)
    const qTokens = cleanQ.split(/\s+/).filter(w => w.length >= 2 || /^\d+$/.test(w));
    const queryHasBeres = qTokens.includes('beres') || qTokens.includes('beras') || qTokens.includes('brs');
    const queryHasMerah = qTokens.includes('merah');
    const queryHasCoklat = qTokens.includes('coklat') || qTokens.includes('cklt');
    const queryHasSapi = qTokens.includes('sapi') || qTokens.includes('sp');
    const queryHasAyam = qTokens.includes('ayam') || qTokens.includes('ay');
    const queryHasRoll = qTokens.includes('roll') || qTokens.includes('rol');
    const queryHasLoyang = qTokens.includes('loyang') || qTokens.includes('lyg');
    const queryHas1000 = qTokens.includes('1000') || qTokens.includes('1kg') || cleanQ.includes('1 kg') || cleanQ.includes('1000g');
    const queryHasPolos = qTokens.includes('polos');
    const queryHas13 = qTokens.includes('13') || qTokens.includes('13s');
    const queryHas24 = qTokens.includes('24') || qTokens.includes('24s');
    const queryHas7 = qTokens.includes('7') || qTokens.includes('7s');

    let bestMatch = null;
    let maxScore = 0;

    for (const h of customerHistory) {
      const hName = (h.productName || '').toLowerCase();
      const hTokens = new Set(hName.replace(/[^a-z0-9\s]/g, ' ').split(/\s+/));
      let score = 0;

      for (const qw of qTokens) {
        if (hTokens.has(qw)) {
          score += 10;
        } else {
          // Normalisasi typo
          const normQ = qw.replace(/ll/g, 'l').replace('bratwust', 'bratwurst').replace('coctail', 'cocktail');
          let normMatched = false;
          for (const hw of hTokens) {
            const normH = hw.replace(/ll/g, 'l').replace('bratwust', 'bratwurst').replace('coctail', 'cocktail');
            if (normQ === normH) { score += 8; normMatched = true; break; }
          }
          if (!normMatched) {
            // 24 vs 24S, 13 vs 13S, 7 vs 7S
            if ((qw === '24' && hTokens.has('24s')) || (qw === '13' && hTokens.has('13s')) || (qw === '7' && hTokens.has('7s')) ||
                (qw === '24s' && hTokens.has('24')) || (qw === '13s' && hTokens.has('13')) || (qw === '7s' && hTokens.has('7'))) {
              score += 10; normMatched = true;
            }
          }
          if (!normMatched && hName.includes(qw)) {
            if (!((qw === 'roll' || qw === 'rol') && (hName.includes('rollade') || hName.includes('rolade')) && !hTokens.has(qw))) {
              score += 2;
            }
          }
        }
      }

      // Domain bonuses
      if (queryHasBeres && (hTokens.has('brs') || hName.includes('brs'))) score += 20;
      if (queryHasMerah) {
        if (hTokens.has('merah') || hName.includes('merah')) score += 25;
        else if (hTokens.has('coklat') || hName.includes('coklat')) score -= 25;
      }
      if (queryHasCoklat) {
        if (hTokens.has('coklat') || hName.includes('coklat')) score += 25;
        else if (hTokens.has('merah') || hName.includes('merah')) score -= 25;
      }
      if (queryHasSapi) {
        if (hTokens.has('sapi') || hName.includes('sapi')) score += 25;
        else if (hTokens.has('ayam') || hName.includes('ayam')) score -= 25;
      }
      if (queryHasAyam) {
        if (hTokens.has('ayam') || hName.includes('ayam')) score += 25;
        else if (hTokens.has('sapi') || hName.includes('sapi')) score -= 25;
      }
      if (queryHasRoll && (hTokens.has('roll') || hTokens.has('rol'))) score += 15;
      if (queryHasLoyang && (hTokens.has('loyang') || hTokens.has('lyg'))) score += 15;
      if (queryHas1000 && (hName.includes('1000') || hName.includes('1kg') || hName.includes('1 kg'))) score += 15;
      if (queryHasPolos && hTokens.has('polos')) score += 15;
      if (!queryHasRoll && !queryHasLoyang && (hTokens.has('roll') || hTokens.has('rol') || hTokens.has('loyang'))) score -= 10;
      if (!queryHas1000 && (hName.includes('1000') || hName.includes('1kg'))) score -= 10;
      if (!queryHasPolos && hTokens.has('polos')) score -= 10;

      // Size number disambiguation (13 vs 24 vs 7)
      if (queryHas13 && !queryHas24 && !queryHas7) {
        if (hTokens.has('13') || hTokens.has('13s')) score += 15;
        if (hTokens.has('24') || hTokens.has('24s')) score -= 20;
      }
      if (queryHas24 && !queryHas13 && !queryHas7) {
        if (hTokens.has('24') || hTokens.has('24s')) score += 15;
        if (hTokens.has('13') || hTokens.has('13s')) score -= 20;
      }
      if (queryHas7 && !queryHas13 && !queryHas24) {
        if (hTokens.has('7') || hTokens.has('7s')) score += 15;
        if (hTokens.has('24') || hTokens.has('24s')) score -= 20;
      }

      // Minimum threshold: at least 1 core product word matched
      const coreWords = qTokens.filter(w => w.length >= 3);
      const coreMatched = coreWords.filter(w => hTokens.has(w) || hName.includes(w)).length;
      if (coreMatched === 0 && score < 20) continue;

      if (score > maxScore) {
        maxScore = score;
        bestMatch = h;
      }
    }

    // Minimum score threshold to avoid false positives
    return maxScore >= 15 ? bestMatch : null;
  }

  // BARU: Cari varian serumpun di history (misal customer pernah beli 24S, chat tulis 24)
  findFamilyVariantInHistory(matchedProduct, customerHistory) {
    if (!matchedProduct || !customerHistory || customerHistory.length === 0) return null;
    const prodName = (matchedProduct.productName || matchedProduct.name || '').toLowerCase();
    // Normalisasi: hapus S dari angka size, hapus spasi
    const normalize = (s) => s.replace(/[^a-z0-9]/g, '').replace(/24s/g, '24').replace(/13s/g, '13').replace(/7s/g, '7').replace(/2500g/g, '500g');
    const prodNorm = normalize(prodName);
    if (!prodNorm) return null;

    for (const h of customerHistory) {
      const hNorm = normalize((h.productName || '').toLowerCase());
      if (hNorm && hNorm === prodNorm && h.price > 0) {
        return h;
      }
    }
    return null;
  }

  // BARU: Terapkan bonus rules (sama format seperti Flutter)
  applyBonusRules(items, customer) {
    const bonusRules = this.cachedRules.filter(r => r.type === 'bonus_rule');
    if (bonusRules.length === 0 || items.length === 0) return null;

    const cleanCust = (customer.customerName || '').toLowerCase().trim();
    const cleanAlias = (customer.aliasName || '').toLowerCase().trim();
    const combinedCust = `${cleanCust} ${cleanAlias}`.trim();
    const bonusItems = [];
    let bonusNote = null;

    for (const rule of bonusRules) {
      const keyParts = (rule.keyword || '').split('|');
      if (keyParts.length < 3) continue;

      const ruleCust = keyParts[0].trim().toLowerCase();
      const ruleProd = keyParts[1].trim().toLowerCase();
      const ruleMinQty = parseFloat(keyParts[2].trim()) || 0;

      // Cek customer match
      const custMatches = combinedCust.includes(ruleCust) ||
        (cleanCust && ruleCust.includes(cleanCust)) ||
        (cleanAlias && ruleCust.includes(cleanAlias));
      if (!custMatches) continue;

      // Parse mapped value: "BONUS_PRODUCT|BONUS_QTY|BONUS_UNIT"
      const valParts = (rule.mappedValue || '').split('|');
      if (valParts.length < 3) continue;

      const bonusProdName = valParts[0].trim();
      const bonusQty = parseFloat(valParts[1].trim()) || 1;
      const bonusUnit = valParts[2].trim().toLowerCase();

      // Sum karton qty untuk matching product
      let totalKartonForProduct = 0;
      const ruleProdClean = ruleProd.replace(/\s+/g, '').toLowerCase();

      for (const item of items) {
        const itemProdClean = (item.productName || '').replace(/\s+/g, '').toLowerCase();
        const isProdMatch = itemProdClean.includes(ruleProdClean) || ruleProdClean.includes(itemProdClean);
        if (isProdMatch) {
          // Item qty sudah dalam pcs, convert balik ke karton untuk threshold check
          // Kita simpan qtyInput di item sekarang
          totalKartonForProduct += item._qtyInputKarton || 0;
        }
      }

      // Cek threshold dan hitung kelipatan bonus
      if (ruleMinQty > 0 && totalKartonForProduct >= ruleMinQty) {
        const multiplier = Math.floor(totalKartonForProduct / ruleMinQty);
        if (multiplier <= 0) continue;

        const calculatedBonusQty = bonusQty * multiplier;

        // Resolve bonus product dari master
        let bonusProduct = this.cachedProducts.find(p =>
          (p.productName || p.name || '').toLowerCase() === bonusProdName.toLowerCase()
        );
        if (!bonusProduct) {
          bonusProduct = this.cachedProducts.find(p =>
            (p.productName || p.name || '').toLowerCase().includes(bonusProdName.toLowerCase())
          );
        }

        const bProdName = bonusProduct ? (bonusProduct.productName || bonusProduct.name) : bonusProdName;
        const bSizeGrams = bonusProduct ? (Number(bonusProduct.sizeGrams) || 500) : 500;
        const bIsiKarton = bonusProduct ? (Number(bonusProduct.isiKarton) || 20) : 20;

        let bonusQtyPcs = calculatedBonusQty;
        if (bonusUnit === 'karton') {
          bonusQtyPcs = calculatedBonusQty * bIsiKarton;
        }

        bonusItems.push({
          productId: bonusProduct ? bonusProduct.id : '',
          productName: bProdName,
          price: 0,
          qty: bonusQtyPcs,
          discountPercent: 0,
          discountAmount: 0,
          subtotal: 0,
          sizeGrams: bSizeGrams,
          weightKg: Math.round(bonusQtyPcs * bSizeGrams / 1000 * 100) / 100,
          isBonus: true
        });

        console.log(`[AUTONOMOUS PO]   🎁 BONUS: ${bProdName} x${calculatedBonusQty} ${bonusUnit} (Rule: ${rule.keyword})`);

        // Specific note for LG FF
        if (combinedCust.includes('lg ff') || combinedCust.includes('wimbo')) {
          const qtyStr = calculatedBonusQty % 1 === 0 ? calculatedBonusQty.toString() : calculatedBonusQty.toFixed(1);
          bonusNote = `NOTE : BONUS ${qtyStr} KARTON KORNET AYAM @400 G`;
        }
      }
    }

    // Append bonus items
    items.push(...bonusItems);
    return bonusNote;
  }

  async parseOrderChat(rawChat, senderPhone, pushName) {
    await this.refreshCacheIfNeeded();

    const lines = rawChat.split('\n').map(l => l.trim()).filter(l => l.length > 0);
    if (lines.length === 0) return null;

    const customer = this.resolveCustomer(lines, senderPhone, pushName);
    if (!customer) {
      console.log(`[AUTONOMOUS PO] ⚠️ Customer belum dapat dipastikan dari pengirim (+${senderPhone}). Menunggu konfirmasi kasir.`);
      return null;
    }

    // UPGRADE: Load Customer Product History dari Firestore
    console.log(`[AUTONOMOUS PO] 📋 Memuat history pembelian ${customer.customerName} (${customer.aliasName || '-'})...`);
    let customerHistory = [];
    try {
      customerHistory = await this.firebaseAdapter.getCustomerProductMemory(
        customer.id,
        customer.customerName,
        customer.aliasName
      );
      console.log(`[AUTONOMOUS PO] 📋 History ditemukan: ${customerHistory.length} produk untuk ${customer.customerName}`);
    } catch (err) {
      console.warn(`[AUTONOMOUS PO] ⚠️ Gagal memuat history: ${err.message}`);
    }

    const items = [];
    for (const line of lines) {
      const lower = line.toLowerCase();
      // Skip instruksi / sapaan / header toko
      if (lower.startsWith('krm') || lower.startsWith('kirim') || lower.startsWith('kirimkan') ||
          lower.startsWith('pengiriman') || lower.startsWith('salam') || lower.startsWith('pagi') ||
          lower.startsWith('siang') || lower.startsWith('catatan') || lower.startsWith('note') ||
          lower.startsWith('nb:') || lower.startsWith('jadwal') || lower.startsWith('titip') ||
          lower.startsWith('masuk erp') || lower.startsWith('faktur')) {
        continue;
      }
      if (customer.aliasName && lower.includes(customer.aliasName.toLowerCase())) continue;
      if (customer.customerName && lower.includes(customer.customerName.toLowerCase())) continue;

      const item = await this.resolveProductWithHistory(line, customerHistory, customer);
      if (item) {
        items.push(item);
      }
    }

    if (items.length === 0) {
      return null;
    }

    // Apply Bonus Rules
    const bonusNote = this.applyBonusRules(items, customer);

    const grandTotal = items.reduce((sum, it) => sum + (it.subtotal || 0), 0);

    // Clean up internal fields
    for (const item of items) {
      delete item._qtyInputKarton;
    }

    return {
      customer,
      items,
      grandTotal,
      bonusNote
    };
  }

  // UPGRADE: resolveProduct dengan customer history pricing
  async resolveProductWithHistory(rawItemText, customerHistory, customer) {
    const lower = rawItemText.toLowerCase();

    // 1. Ekstrak kuantiti & satuan (sama seperti sebelumnya)
    const qtyMatch = lower.match(/(?:^|\s|\.\.\.)\b(\d+(?:[.,]\d+)?)\s*(k|ktn|karton|dus|box|pack|pcs|bal|ball|roll)\b/i);
    let qtyInput = 0;
    let qtyUnit = 'karton';
    if (qtyMatch) {
      qtyInput = parseFloat(qtyMatch[1].replace(',', '.'));
      const u = qtyMatch[2].toLowerCase();
      if (['k', 'ktn', 'karton', 'dus', 'box'].includes(u)) qtyUnit = 'karton';
      else if (['pack', 'pcs'].includes(u)) qtyUnit = 'pcs';
      else if (['bal', 'ball'].includes(u)) qtyUnit = 'ball';
      else if (['roll'].includes(u)) qtyUnit = 'roll';
    } else {
      const endMatch = lower.match(/(?:\.\.\.|\s+)(\d+)\s*$/);
      if (endMatch) {
        qtyInput = parseFloat(endMatch[1]);
        qtyUnit = 'karton';
      }
    }
    if (qtyInput <= 0) return null;

    // Bersihkan teks barang
    let cleanProd = lower
      .replace(/(?:^|\s|\.\.\.)\b(\d+(?:[.,]\d+)?)\s*(k|ktn|karton|dus|box|pack|pcs|bal|ball|roll)\b/gi, ' ')
      .replace(/^[0-9]+[.)]\s*/, '')
      .replace(/\.\.\..*$/, '')
      .replace(/[^a-zA-Z0-9\s]/g, ' ')
      .trim();

    // Normalisasi slang
    cleanProd = cleanProd
      .replace(/\bberes\b/g, 'brs')
      .replace(/\bberas\b/g, 'brs')
      .replace(/\bbratwust\b/g, 'bratwurst');

    // Strip revision words
    cleanProd = cleanProd.replace(/^(tambah|tmbh|revisi)\s+/i, '').trim();
    // Strip brand prefix
    cleanProd = cleanProd.replace(/^(fiva|fv)\s+/i, '').trim();

    if (cleanProd.length < 2 || !/[a-zA-Z]/.test(cleanProd)) return null;

    let matchedProduct = null;
    let historyPricing = null;

    // PRIORITAS 1: Cek Customer History (AI belajar dari kebiasaan customer)
    if (customerHistory.length > 0) {
      const histMatch = this.matchProductFromHistory(cleanProd, customerHistory);
      if (histMatch) {
        // Cari product di master berdasarkan history match
        matchedProduct = this.cachedProducts.find(p =>
          (histMatch.productId && p.id === histMatch.productId) ||
          (p.productName || p.name || '').toLowerCase() === histMatch.productName.toLowerCase()
        );
        if (!matchedProduct) {
          matchedProduct = this.cachedProducts.find(p =>
            (p.productName || p.name || '').toLowerCase().includes(histMatch.productName.toLowerCase())
          );
        }
        if (!matchedProduct) {
          matchedProduct = { id: histMatch.productId, name: histMatch.productName, price: histMatch.price, isiKarton: 15, sizeGrams: 500 };
        }
        historyPricing = histMatch;
        console.log(`[AUTONOMOUS PO]   🎯 History match: "${cleanProd}" → ${histMatch.productName} (Harga: Rp ${histMatch.price.toLocaleString('id-ID')}, Invoice #${histMatch.invoiceNo})`);
      }
    }

    // PRIORITAS 2: Cocokkan dengan AI Knowledge Rules
    if (!matchedProduct) {
      const prodRules = this.cachedRules.filter(r => r.type === 'product_alias');
      for (const r of prodRules) {
        let from = (r.keyword || r.from || '').toLowerCase().trim();
        from = from.replace(/\bberes\b/g, 'brs').replace(/\bberas\b/g, 'brs');
        if (from && cleanProd.includes(from)) {
          if (r.targetId) {
            const p = this.cachedProducts.find(prod => prod.id === r.targetId);
            if (p) { matchedProduct = p; break; }
          }
          const to = (r.mappedValue || r.to || '').toLowerCase().trim().replace(/\s+/g, '');
          const p = this.cachedProducts.find(prod => {
            const pn = (prod.productName || prod.name || '').toLowerCase().replace(/\s+/g, '');
            return pn.includes(to) || to.includes(pn);
          });
          if (p) { matchedProduct = p; break; }
        }
      }
    }

    // PRIORITAS 3: Fuzzy match ke master produk
    if (!matchedProduct) {
      const words = cleanProd.split(/\s+/).filter(w => w.length >= 3);
      if (words.length > 0) {
        let bestProduct = null;
        let maxScore = 0;
        for (const p of this.cachedProducts) {
          const pName = (p.productName || p.name || '').toLowerCase();
          let score = 0;
          for (const w of words) { if (pName.includes(w)) score++; }
          if (score > maxScore) { maxScore = score; bestProduct = p; }
        }
        if (bestProduct && maxScore >= Math.min(2, words.length)) {
          matchedProduct = bestProduct;
        }
      }
    }

    if (!matchedProduct) return null;

    // UPGRADE: Jika belum ada history pricing, cek variant family + fallback scan transaksi
    if (!historyPricing && customerHistory.length > 0) {
      // Cek exact match di history by productId/name
      const directHist = customerHistory.find(h =>
        (h.productId && h.productId === matchedProduct.id) ||
        (h.productName || '').toLowerCase() === (matchedProduct.productName || matchedProduct.name || '').toLowerCase()
      );
      if (directHist && directHist.price > 0) {
        historyPricing = directHist;
      } else {
        // Cek variant family (24 vs 24S)
        const familyMatch = this.findFamilyVariantInHistory(matchedProduct, customerHistory);
        if (familyMatch) {
          historyPricing = familyMatch;
          // Switch ke product varian yang customer biasa beli
          const variantProd = this.cachedProducts.find(p =>
            (familyMatch.productId && p.id === familyMatch.productId) ||
            (p.productName || p.name || '').toLowerCase() === familyMatch.productName.toLowerCase()
          );
          if (variantProd) {
            matchedProduct = variantProd;
            console.log(`[AUTONOMOUS PO]   🔄 Variant switch: → ${familyMatch.productName} (sesuai kebiasaan customer)`);
          }
        }
      }
    }

    // UPGRADE: Fallback scan transaksi terakhir jika masih tidak ada history pricing
    if (!historyPricing) {
      try {
        const fallbackPricing = await this.firebaseAdapter.getLastCustomerProductPricing(
          customer.customerName,
          matchedProduct.id || '',
          customer.id,
          matchedProduct.productName || matchedProduct.name
        );
        if (fallbackPricing) {
          historyPricing = fallbackPricing;
          // Kalau product name berbeda (variant), switch
          const histPName = (fallbackPricing.productName || '').trim();
          if (histPName && histPName.toLowerCase() !== (matchedProduct.productName || matchedProduct.name || '').toLowerCase()) {
            const variantProd = this.cachedProducts.find(p =>
              (p.productName || p.name || '').toLowerCase() === histPName.toLowerCase()
            );
            if (variantProd) {
              matchedProduct = variantProd;
              console.log(`[AUTONOMOUS PO]   🔄 Fallback variant switch: → ${histPName}`);
            }
          }
          console.log(`[AUTONOMOUS PO]   💰 Fallback pricing: Rp ${fallbackPricing.price.toLocaleString('id-ID')} (Invoice #${fallbackPricing.invoiceNo})`);
        }
      } catch (err) {
        console.warn(`[AUTONOMOUS PO]   ⚠️ Fallback pricing error: ${err.message}`);
      }
    }

    const item = this.buildTransactionItem(matchedProduct, qtyInput, qtyUnit, historyPricing);
    // Simpan qtyInput karton untuk bonus calculation
    if (qtyUnit === 'karton') item._qtyInputKarton = qtyInput;
    return item;
  }

  async processAutonomousPo(chatDocId, chatPayload) {
    try {
      // 0. CEK ULANG status chat (anti duplikat dengan Flutter)
      const chatDoc = await this.firebaseAdapter.getChatDocument(chatDocId);
      if (chatDoc && chatDoc.status === 'processed') {
        console.log(`[AUTONOMOUS PO] ⏭️ Chat ${chatDocId} sudah diproses (Invoice #${chatDoc.createdInvoiceNo || '?'}). SKIP duplikat.`);
        return null;
      }

      // 1. Jangan proses jika quoted reply / revisi (harus melalui verifikasi kasir)
      if (chatPayload.isQuotedReply) {
        console.log(`[AUTONOMOUS PO] ℹ️ Chat adalah QUOTED_REPLY (Revisi/Balasan). Dibiarkan pending untuk review kasir.`);
        return null;
      }

      console.log(`[AUTONOMOUS PO] 🤖 Memulai analisis otonom pesanan dari ${chatPayload.senderName} (+${chatPayload.senderPhone})...`);
      const parsed = await this.parseOrderChat(
        chatPayload.messageText,
        chatPayload.senderPhone,
        chatPayload.senderName
      );

      if (!parsed || parsed.items.length === 0) {
        console.log(`[AUTONOMOUS PO] ⏳ Format pesanan belum lengkap atau butuh verifikasi manual. Chat disimpan sebagai pending.`);
        if (this.notificationDispatcher) {
          this.notificationDispatcher.sendReviewNeededAlert({
            senderName: chatPayload.senderName,
            reason: 'Format pesanan belum lengkap / produk tidak cocok',
            rawChat: chatPayload.messageText
          });
        }
        return null;
      }

      console.log(`[AUTONOMOUS PO] 🎯 Pelanggan: ${parsed.customer.customerName} (${parsed.customer.aliasName || '-'}), ${parsed.items.length} item barang, Grand Total: Rp ${parsed.grandTotal.toLocaleString('id-ID')}`);

      // 2. CEK LAGI sebelum create (double check anti race condition)
      const chatDocRecheck = await this.firebaseAdapter.getChatDocument(chatDocId);
      if (chatDocRecheck && chatDocRecheck.status === 'processed') {
        console.log(`[AUTONOMOUS PO] ⏭️ Chat ${chatDocId} sudah diproses saat parsing. SKIP.`);
        return null;
      }

      // 3. Generate Nomor Faktur resmi via transaction
      const invoiceNo = await this.firebaseAdapter.getNextInvoiceNo();
      if (!invoiceNo) {
        throw new Error('Gagal menghasilkan nomor faktur transaksi');
      }

      // 4. Simpan Transaksi baru ke Firestore (Status: PENDING)
      const now = new Date();
      const transactionDoc = {
        invoiceNo: String(invoiceNo),
        customerId: parsed.customer.id || '',
        customerName: parsed.customer.customerName || '',
        aliasName: parsed.customer.aliasName || '',
        date: now,
        deliveryDate: null,
        city: parsed.customer.city || 'SEMARANG',
        province: parsed.customer.province || 'JAWA TENGAH',
        country: 'INDONESIA',
        items: parsed.items,
        grandTotal: parsed.grandTotal,
        note: parsed.bonusNote || '',
        status: 'PENDING',
        statusTransfer: parsed.grandTotal <= 0 ? 'PAID' : 'UNPAID',
        transferDate: null,
        createdBy: 'AI Auto-PO Termux Gateway',
        createdAt: now,
        sourceInvoices: [],
        lampiranInvoiceNo: '',
        isLampiran: false
      };

      await this.firebaseAdapter.saveTransaction(invoiceNo, transactionDoc);

      // 5. Update dokumen incoming_po_chats menjadi processed
      if (chatDocId) {
        await this.firebaseAdapter.markChatAsProcessed(chatDocId, invoiceNo);
      }

      console.log(`[AUTONOMOUS PO SUCCESS] 🚀🎉 FAKTUR #${invoiceNo} (${parsed.customer.customerName}) BERHASIL DIBUAT DARI TERMUX! Grand Total: Rp ${parsed.grandTotal.toLocaleString('id-ID')}`);

      // NOTIFIKASI TAHAP 2: PO BERHASIL DIBUAT (RINCIAN LENGKAP VIA FCM KE HP)
      if (this.notificationDispatcher) {
        this.notificationDispatcher.sendPoSuccessAlert({
          invoiceNo: String(invoiceNo),
          customerName: parsed.customer.customerName,
          items: parsed.items,
          grandTotal: parsed.grandTotal
        });
      }
      return {
        success: true,
        invoiceNo: String(invoiceNo),
        customerName: parsed.customer.customerName,
        grandTotal: parsed.grandTotal
      };
    } catch (err) {
      console.error('[AUTONOMOUS PO ERROR]', err.message);
      return null;
    }
  }
}

module.exports = AutonomousPoProcessor;
