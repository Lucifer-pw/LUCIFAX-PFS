import '../models/customer.dart';
import '../models/product.dart';
import '../models/ai_knowledge_rule.dart';
import '../models/chat_order_draft.dart';
import '../models/customer_product_history.dart';
import 'firebase_service.dart';

class AiChatParserService {
  final FirebaseService firebaseService;

  AiChatParserService(this.firebaseService);

  /// Main entry point to parse a raw WhatsApp chat text into a list of ChatOrderDraft
  Future<List<ChatOrderDraft>> parseChatOrders({
    required String rawChat,
    required List<Customer> customers,
    required List<Product> products,
    required List<AiKnowledgeRule> rules,
    String generalInstructions = '',
  }) async {
    final drafts = <ChatOrderDraft>[];
    if (rawChat.trim().isEmpty) return drafts;

    // 1. Separate rules by type
    final customerRules = rules.where((r) => r.type == 'customer_alias').toList();
    final productRules = rules.where((r) => r.type == 'product_alias').toList();
    final unitRules = rules.where((r) => r.type == 'unit').toList();
    final bonusRules = rules.where((r) => r.type == 'bonus_rule').toList();

    // 2. Multi-PO Splitting: Split chat into separate blocks per store/order
    final blocks = _splitChatIntoStoreBlocks(rawChat);

    for (var block in blocks) {
      final lines = block
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) continue;

      // Extract Customer from the header lines
      final customerInfo = _resolveCustomer(
        lines: lines,
        customers: customers,
        customerRules: customerRules,
      );

      final matchedCustomer = customerInfo.customer;
      final rawCustomerName = customerInfo.rawName;

      // Load Customer's Purchase History (AI learns from customer habit!)
      final customerHistory = await firebaseService.getCustomerProductHistory(
        customerName: matchedCustomer?.customerName ?? rawCustomerName,
        customerId: matchedCustomer?.id,
        aliasName: matchedCustomer?.aliasName,
      );

      // Extract Product Items from subsequent lines
      final draftItems = <ChatOrderItemDraft>[];

      for (int i = customerInfo.headerLineCount; i < lines.length; i++) {
        final line = lines[i];

        // Skip non-item lines (greetings, delivery instructions, chat timestamps)
        if (_isIgnoredLine(line)) continue;

        final itemDraft = await _parseItemLine(
          rawLine: line,
          products: products,
          productRules: productRules,
          unitRules: unitRules,
          customerHistory: customerHistory,
          customerName: matchedCustomer?.customerName ?? rawCustomerName,
          customerId: matchedCustomer?.id,
        );

        if (itemDraft != null) {
          draftItems.add(itemDraft);
        }
      }

      // Apply Bonus/Promo Rules (auto-append bonus items based on thresholds)
      _applyBonusRules(
        draftItems: draftItems,
        bonusRules: bonusRules,
        customerName: matchedCustomer?.customerName ?? rawCustomerName,
        products: products,
      );

      // If at least one item or valid customer found, add draft
      if (draftItems.isNotEmpty || matchedCustomer != null) {
        drafts.add(ChatOrderDraft(
          customerRawName: rawCustomerName,
          customerId: matchedCustomer?.id ?? '',
          customerName: matchedCustomer?.customerName ?? rawCustomerName,
          aliasName: matchedCustomer?.aliasName ?? '',
          city: (matchedCustomer != null && matchedCustomer.city.isNotEmpty)
              ? matchedCustomer.city
              : _detectCityFromText(block),
          province: matchedCustomer?.province ?? 'JAWA TENGAH',
          items: draftItems,
          rawChatBlock: block,
          note: 'PO via Chat Scanner',
        ));
      }
    }

    return drafts;
  }

  /// Splits multi-order chats into individual store blocks
  List<String> _splitChatIntoStoreBlocks(String rawChat) {
    final rawLines = rawChat.split('\n');
    final blocks = <List<String>>[];
    List<String> currentBlock = [];

    // Regex to detect new store boundaries
    final newStoreRegex = RegExp(
      r'^(pak[.,\s]+mau\s+order\s+dari|po\s+|order\s+|toko\s+|[A-Z0-9\s]{3,30}\s+(ff|frozen|kendal|wonosobo|purwodadi|semarang|kudus|pati|demak))',
      caseSensitive: false,
    );

    for (var line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Check if this line looks like a greeting with new PO, or a capitalized store title
      bool isNewStore = false;
      if (newStoreRegex.hasMatch(trimmed)) {
        isNewStore = true;
      } else if (trimmed.startsWith('Waalaikumsalam') && currentBlock.isNotEmpty) {
        isNewStore = true;
      } else if (_isStoreHeaderLine(trimmed) && currentBlock.isNotEmpty) {
        // If previous block already has items, start a new block
        bool prevHasItems = currentBlock.any((l) => _looksLikeOrderLine(l));
        if (prevHasItems) {
          isNewStore = true;
        }
      }

      if (isNewStore && currentBlock.isNotEmpty) {
        blocks.add(List.from(currentBlock));
        currentBlock.clear();
      }

      currentBlock.add(line);
    }

    if (currentBlock.isNotEmpty) {
      blocks.add(currentBlock);
    }

    return blocks.map((b) => b.join('\n').trim()).where((b) => b.isNotEmpty).toList();
  }

  bool _isStoreHeaderLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('order dari') ||
        lower.startsWith('po ') ||
        lower.contains(' ff ') ||
        lower.endsWith(' ff') ||
        lower.startsWith('pak nardi');
  }

  bool _looksLikeOrderLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('rolade') ||
        lower.contains('beres') ||
        lower.contains('kornet') ||
        lower.contains('sosis') ||
        lower.contains('bakso') ||
        lower.contains('roll') ||
        lower.contains('pack') ||
        RegExp(r'\d+\s*(k|ktn|roll|pack|:)', caseSensitive: false).hasMatch(line);
  }

  /// Resolve Customer by checking Rules, Master Customers, or raw string
  _CustomerResolution _resolveCustomer({
    required List<String> lines,
    required List<Customer> customers,
    required List<AiKnowledgeRule> customerRules,
  }) {
    String headerText = lines.first;
    int headerCount = 1;

    // Check first 2 lines for customer title
    if (lines.length > 1 && (lines[0].toLowerCase().startsWith('waalaikumsalam') || lines[0].toLowerCase().startsWith('pak..'))) {
      if (lines[0].toLowerCase().contains('order dari')) {
        headerText = lines[0];
      } else if (lines[1].toLowerCase().startsWith('po ') || lines[1].toLowerCase().contains(' ff')) {
        headerText = lines[1];
        headerCount = 2;
      }
    }

    // Clean prefix like "Pak.. mau order dari ", "Po ", "order dari "
    String cleanName = headerText;
    cleanName = cleanName.replaceAll(RegExp(r'^(waalaikumsalam|assalamualaikum)[.,\s]*', caseSensitive: false), '');
    cleanName = cleanName.replaceAll(RegExp(r'^(pak[.,\s]+)?mau\s+order\s+dari\s+', caseSensitive: false), '');
    cleanName = cleanName.replaceAll(RegExp(r'^po\s+', caseSensitive: false), '');
    cleanName = cleanName.replaceAll(RegExp(r'^order\s+', caseSensitive: false), '');
    cleanName = cleanName.trim();

    // 1. Check AI Knowledge Rules (Customer Alias)
    for (var rule in customerRules) {
      if (cleanName.toLowerCase().contains(rule.keyword.toLowerCase()) ||
          rule.keyword.toLowerCase().contains(cleanName.toLowerCase())) {
        // Find in master by mappedValue or targetId
        final match = customers.firstWhere(
          (c) => (rule.targetId != null && c.id == rule.targetId) ||
              c.customerName.toLowerCase() == rule.mappedValue.toLowerCase() ||
              c.aliasName.toLowerCase() == rule.mappedValue.toLowerCase(),
          orElse: () => Customer(id: '', customerName: rule.mappedValue, aliasName: '', address: '', city: 'SEMARANG', province: 'JAWA TENGAH', country: 'INDONESIA', phone: '', ktpNumber: ''),
        );
        return _CustomerResolution(
          customer: match.id.isNotEmpty ? match : null,
          rawName: rule.mappedValue.isNotEmpty ? rule.mappedValue : cleanName,
          headerLineCount: headerCount,
        );
      }
    }

    // 2. Direct Intelligent Matching against Master Customer
    Customer? bestMatch;
    int maxScore = 0;
    final target = cleanName.toLowerCase();
    final targetWords = target.split(RegExp(r'[\s\-_,.]+')).where((w) => w.length >= 2).toList();

    for (var c in customers) {
      final cName = c.customerName.toLowerCase();
      final cAlias = c.aliasName.toLowerCase();
      final cCity = c.city.toLowerCase();
      int score = 0;

      // Exact matches
      if (target == cName || target == cAlias) {
        bestMatch = c;
        maxScore = 200;
        break;
      }

      // Store name contained directly
      if (cName.isNotEmpty && target.contains(cName)) {
        score += 60;
      }
      if (cAlias.isNotEmpty && target.contains(cAlias)) {
        score += 50;
      }

      // City match bonus (e.g. chat says 'LG FF WONOSOBO' and customer's city is 'WONOSOBO')
      if (cCity.isNotEmpty && targetWords.contains(cCity)) {
        score += 35;
      }

      // Individual word overlaps
      for (var word in targetWords) {
        if (cName.split(RegExp(r'\s+')).contains(word)) score += 15;
        if (cAlias.split(RegExp(r'\s+')).contains(word)) score += 10;
      }

      if (score > maxScore) {
        maxScore = score;
        bestMatch = c;
      }
    }

    return _CustomerResolution(
      customer: (maxScore >= 25) ? bestMatch : null,
      rawName: bestMatch?.customerName ?? cleanName,
      headerLineCount: headerCount,
    );
  }

  /// Parses a single item line into ChatOrderItemDraft
  Future<ChatOrderItemDraft?> _parseItemLine({
    required String rawLine,
    required List<Product> products,
    required List<AiKnowledgeRule> productRules,
    required List<AiKnowledgeRule> unitRules,
    required List<CustomerProductHistory> customerHistory,
    required String customerName,
    String? customerId,
  }) async {
    String cleanLine = rawLine.trim();

    // Clean leading item numbers like "4. ", "5. ", "- "
    cleanLine = cleanLine.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '');
    cleanLine = cleanLine.replaceAll(RegExp(r'^[-\*\•]\s*'), '');

    // Extract quantity and unit
    _QtyUnitResolution qtyInfo = _extractQuantityAndUnit(cleanLine, unitRules);

    // Remove the extracted quantity part to get pure product name
    String productText = qtyInfo.cleanedText;

    // Remove brand "fiva " if present at the start
    if (productText.toLowerCase().startsWith('fiva ')) {
      productText = productText.substring(5).trim();
    }

    Product? matchedProduct;
    CustomerProductHistory? matchedHistory;

    // 1. PRIORITAS UTAMA: Cek Riwayat Pembelian Pelanggan Ini (AI Belajar dari Kebiasaan Customer!)
    // Jika pelanggan ini (misal MMM) pernah membeli barang yang cocok (misal "BRS MERAH 24 500G"),
    // utamakan barang dari riwayat pelanggan tersebut!
    if (customerHistory.isNotEmpty) {
      matchedHistory = _matchProductFromCustomerHistory(productText, customerHistory);
      if (matchedHistory != null) {
        matchedProduct = products.firstWhere(
          (p) => (matchedHistory!.productId.isNotEmpty && p.id == matchedHistory.productId) ||
              p.name.toLowerCase() == matchedHistory.productName.toLowerCase(),
          orElse: () => Product(
            id: matchedHistory!.productId,
            name: matchedHistory.productName,
            price: matchedHistory.price,
            stock: 0.0,
            isiKarton: 15,
            sizeGrams: 500.0,
          ),
        );
      }
    }

    // 2. Jika tidak ada di riwayat pelanggan, cocokkan dengan Aturan Kamus (AI Knowledge Rules)
    if (matchedProduct == null) {
      for (var rule in productRules) {
        if (productText.toLowerCase().contains(rule.keyword.toLowerCase()) ||
            rule.keyword.toLowerCase().contains(productText.toLowerCase())) {
          matchedProduct = products.firstWhere(
            (p) => (rule.targetId != null && p.id == rule.targetId) ||
                p.name.toLowerCase() == rule.mappedValue.toLowerCase() ||
                p.kodeInduk.toLowerCase() == rule.mappedValue.toLowerCase(),
            orElse: () => products.firstWhere(
              (p) => p.name.toLowerCase().contains(rule.mappedValue.toLowerCase()),
              orElse: () => Product(id: '', name: rule.mappedValue, price: 0.0, stock: 0.0, isiKarton: 10, sizeGrams: 500.0),
            ),
          );
          break;
        }
      }
    }

    // 3. Fallback terakhir: Fuzzy / Keyword Match ke seluruh Master Barang
    if (matchedProduct == null || matchedProduct.id.isEmpty) {
      matchedProduct = _fuzzyMatchProduct(productText, products);
    }

    if (matchedProduct == null) return null;

    // Calculate qtyPcs (converting karton to pcs based on isiKarton)
    double qtyPcs = qtyInfo.qty;
    if (qtyInfo.unit == 'karton') {
      final isiKarton = matchedProduct.isiKarton > 0 ? matchedProduct.isiKarton : 10;
      qtyPcs = qtyInfo.qty * isiKarton;
    }

    // 4. Historical Pricing: Tarik harga & diskon dari riwayat transaksi pelanggan
    double price = matchedProduct.price;
    double discountPercent = 0.0;
    double discountAmount = 0.0;
    bool isNewItemForCustomer = true;

    if (matchedHistory != null) {
      price = matchedHistory.price;
      discountPercent = matchedHistory.discountPercent;
      discountAmount = matchedHistory.discountAmount;
      isNewItemForCustomer = false;
    } else {
      final hist = customerHistory.firstWhere(
        (h) => (h.productId.isNotEmpty && h.productId == matchedProduct!.id) ||
            h.productName.toLowerCase() == matchedProduct!.name.toLowerCase(),
        orElse: () => CustomerProductHistory(productId: '', productName: '', price: 0, discountPercent: 0, discountAmount: 0, invoiceNo: ''),
      );
      if (hist.invoiceNo.isNotEmpty && hist.price > 0) {
        price = hist.price;
        discountPercent = hist.discountPercent;
        discountAmount = hist.discountAmount;
        isNewItemForCustomer = false;
      } else {
        // Fallback: Scan Firestore jika belum masuk di map
        final historyPricing = await firebaseService.getLastCustomerProductPricing(
          customerName,
          matchedProduct.id,
          customerId: customerId,
          productName: matchedProduct.name,
        );
        if (historyPricing != null) {
          price = (historyPricing['price'] ?? matchedProduct.price).toDouble();
          discountPercent = (historyPricing['discountPercent'] ?? 0.0).toDouble();
          discountAmount = (historyPricing['discountAmount'] ?? 0.0).toDouble();
          isNewItemForCustomer = false;
        }
      }
    }

    return ChatOrderItemDraft(
      productId: matchedProduct.id,
      productName: matchedProduct.name,
      rawText: rawLine,
      qtyUnit: qtyInfo.unit,
      qtyInput: qtyInfo.qty,
      qtyPcs: qtyPcs,
      price: price,
      discountPercent: discountPercent,
      discountAmount: discountAmount,
      sizeGrams: matchedProduct.sizeGrams,
      isNewItemForCustomer: isNewItemForCustomer,
    );
  }

  /// Extracts quantity and unit from line, returning cleaned product text
  _QtyUnitResolution _extractQuantityAndUnit(String line, List<AiKnowledgeRule> unitRules) {
    double qty = 1.0;
    String unit = 'pack';
    String cleaned = line;

    // Pattern 1: Ratio format like "Beres merah 24 : 1" or ": 2" (means Karton)
    final ratioMatch = RegExp(r':\s*(\d+(\.\d+)?)').firstMatch(line);
    if (ratioMatch != null) {
      qty = double.tryParse(ratioMatch.group(1) ?? '1') ?? 1.0;
      unit = 'karton';
      cleaned = line.replaceAll(ratioMatch.group(0)!, '').trim();
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned);
    }

    // Pattern 2: "35 k" / "40 K..." / "40 ktn" / "10 karton" / "5 dus"
    final kartonMatch = RegExp(r'(\d+(\.\d+)?)\s*(k\b|k\.+|ktn|karton|dus|box)', caseSensitive: false).firstMatch(line);
    if (kartonMatch != null) {
      qty = double.tryParse(kartonMatch.group(1) ?? '1') ?? 1.0;
      unit = 'karton';
      cleaned = line.replaceAll(kartonMatch.group(0)!, '').trim();
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned);
    }

    // Pattern 3: "11 ROLL" / "325 roll"
    final rollMatch = RegExp(r'(\d+(\.\d+)?)\s*(roll|rol)', caseSensitive: false).firstMatch(line);
    if (rollMatch != null) {
      qty = double.tryParse(rollMatch.group(1) ?? '1') ?? 1.0;
      unit = 'roll';
      cleaned = line.replaceAll(rollMatch.group(0)!, '').trim();
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned);
    }

    // Pattern 4: "121 pack" / "45 pack" / "10 pcs" / "10 bks"
    final packMatch = RegExp(r'(\d+(\.\d+)?)\s*(pack|pak|pcs|bks|biji)', caseSensitive: false).firstMatch(line);
    if (packMatch != null) {
      qty = double.tryParse(packMatch.group(1) ?? '1') ?? 1.0;
      unit = 'pack';
      cleaned = line.replaceAll(packMatch.group(0)!, '').trim();
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned);
    }

    // Pattern 5: Number at the end of line like "Rolade sapi 1000g 35"
    final endNumberMatch = RegExp(r'\b(\d+(\.\d+)?)$').firstMatch(line);
    if (endNumberMatch != null) {
      qty = double.tryParse(endNumberMatch.group(1) ?? '1') ?? 1.0;
      unit = 'karton'; // Default to karton for whole bulk numbers in warehouse
      cleaned = line.substring(0, endNumberMatch.start).trim();
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned);
    }

    return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned);
  }

  /// Matches product text against products that THIS customer has actually bought in their invoice history.
  /// Allows the AI to learn customer-specific purchasing patterns, exact variants (e.g. 24 vs 24S), and historical prices.
  CustomerProductHistory? _matchProductFromCustomerHistory(
    String query,
    List<CustomerProductHistory> historyList,
  ) {
    if (historyList.isEmpty) return null;

    final cleanQ = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
    if (cleanQ.isEmpty) return null;

    // 1. Direct name match
    for (var h in historyList) {
      final hNameClean = h.productName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
      if (hNameClean == cleanQ || h.productId.toLowerCase() == cleanQ) {
        return h;
      }
    }

    // 2. Tokenize with domain awareness
    final qTokens = cleanQ.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    final bool queryHasRoll = qTokens.contains('roll') || qTokens.contains('rol');
    final bool queryHasLoyang = qTokens.contains('loyang') || qTokens.contains('lyg');
    final bool queryHas1000 = qTokens.contains('1000') || qTokens.contains('1kg');
    final bool queryHasBeres = qTokens.contains('beres') || qTokens.contains('beras') || qTokens.contains('brs');
    final bool queryHasMerah = qTokens.contains('merah');
    final bool queryHasCoklat = qTokens.contains('coklat') || qTokens.contains('cklt');
    final bool queryHas13 = qTokens.contains('13') || qTokens.contains('13s');
    final bool queryHas24 = qTokens.contains('24') || qTokens.contains('24s');
    final bool queryHas7 = qTokens.contains('7') || qTokens.contains('7s');
    final bool queryHas215 = qTokens.contains('215') || qTokens.contains('215g') || qTokens.contains('215gr');

    CustomerProductHistory? bestMatch;
    int maxScore = 0;

    for (var h in historyList) {
      final hName = h.productName.toLowerCase();
      final hTokens = hName.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').split(RegExp(r'\s+')).toSet();
      int score = 0;

      for (var qw in qTokens) {
        if (hTokens.contains(qw)) {
          score += 10;
        } else {
          final normQ = qw.replaceAll('ll', 'l').replaceAll('bratwust', 'bratwurst');
          bool normMatched = false;
          for (var hw in hTokens) {
            final normH = hw.replaceAll('ll', 'l').replaceAll('bratwust', 'bratwurst');
            if (normQ == normH) {
              score += 8;
              normMatched = true;
              break;
            }
          }
          if (!normMatched && hName.contains(qw)) {
            score += 2;
          }
        }
      }

      // Domain Bonuses:
      // A. "Beres" / "Beras" matches "BRS"
      if (queryHasBeres && (hTokens.contains('brs') || hName.contains('brs'))) {
        score += 20;
      }

      // B. "Merah" vs "Coklat"
      if (queryHasMerah) {
        if (hTokens.contains('merah') || hName.contains('merah')) {
          score += 25;
        } else if (hTokens.contains('coklat') || hName.contains('coklat')) {
          score -= 20;
        }
      }
      if (queryHasCoklat) {
        if (hTokens.contains('coklat') || hName.contains('coklat')) {
          score += 25;
        } else if (hTokens.contains('merah') || hName.contains('merah')) {
          score -= 20;
        }
      }

      // C. Specific Sizes & Counts (13, 24, 7, 215)
      if (queryHas13 && (hName.contains('13') || hTokens.contains('13s') || hTokens.contains('13'))) {
        score += 25;
      }
      if (queryHas24 && (hName.contains('24') || hTokens.contains('24s') || hTokens.contains('24'))) {
        score += 25;
      }
      if (queryHas7 && (hName.contains('7') || hTokens.contains('7s') || hTokens.contains('7'))) {
        score += 25;
      }
      if (queryHas215 && (hName.contains('215') || hTokens.contains('215g') || hTokens.contains('215gr'))) {
        score += 30;
      }

      // D. "ROLL" variant
      if (queryHasRoll) {
        if (hTokens.contains('roll') || hTokens.contains('rol') || hName.contains('roll')) {
          score += 25;
        } else if (hName.contains('1000')) {
          score -= 15;
        }
      }

      // E. "LOYANG" variant
      if (queryHasLoyang) {
        if (hTokens.contains('loyang') || hTokens.contains('lyg') || hName.contains('loyang')) {
          score += 25;
        }
      }

      // F. 1000g vs smaller
      if (queryHas1000 && hName.contains('1000')) {
        score += 20;
      }

      // Prefer Induk 24 over 24S when 's' was not explicitly typed in chat
      if (queryHas24 && !cleanQ.contains('24s') && hName.contains('24s')) {
        score -= 10;
      }

      // G. Preference for higher order frequency
      score += (h.purchaseCount.clamp(1, 5) * 2);

      if (score > maxScore) {
        maxScore = score;
        bestMatch = h;
      }
    }

    return maxScore >= 12 ? bestMatch : null;
  }

  Product? _fuzzyMatchProduct(String query, List<Product> products) {
    if (products.isEmpty) return null;
    final cleanQ = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();

    // 1. Direct name or code match
    for (var p in products) {
      final pNameClean = p.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
      if (pNameClean == cleanQ || p.id.toLowerCase() == cleanQ || p.kodeInduk.toLowerCase() == cleanQ) {
        return p;
      }
    }

    // 2. Score based on whole-word matching and type bonuses
    final qWords = cleanQ.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    final bool queryHasRoll = qWords.contains('roll') || qWords.contains('rol');
    final bool queryHasLoyang = qWords.contains('loyang') || qWords.contains('lyg');
    final bool queryHas1000 = qWords.contains('1000') || qWords.contains('1kg');
    final bool queryHasBeres = qWords.contains('beres') || qWords.contains('beras') || qWords.contains('brs');
    final bool queryHasMerah = qWords.contains('merah');
    final bool queryHasCoklat = qWords.contains('coklat') || qWords.contains('cklt');
    final bool queryHas13 = qWords.contains('13') || qWords.contains('13s');
    final bool queryHas24 = qWords.contains('24') || qWords.contains('24s');
    final bool queryHas7 = qWords.contains('7') || qWords.contains('7s');
    final bool queryHas215 = qWords.contains('215') || qWords.contains('215g') || qWords.contains('215gr');

    Product? bestProduct;
    int maxScore = 0;

    for (var p in products) {
      final pName = p.name.toLowerCase();
      final pWords = pName.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').split(RegExp(r'\s+')).toSet();
      int score = 0;

      for (var qw in qWords) {
        // Whole-word match
        if (pWords.contains(qw)) {
          score += 10;
        } else {
          // Normalize spelling (e.g. rolade == rollade, bratwust == bratwurst)
          final normQ = qw.replaceAll('ll', 'l').replaceAll('bratwust', 'bratwurst');
          bool normMatched = false;
          for (var pw in pWords) {
            final normP = pw.replaceAll('ll', 'l').replaceAll('bratwust', 'bratwurst');
            if (normQ == normP) {
              score += 8;
              normMatched = true;
              break;
            }
          }
          // Substring match only if no whole word matched
          if (!normMatched && pName.contains(qw)) {
            score += 2;
          }
        }
      }

      // Keyword differentiators:
      // A. "Beres" / "Beras" matches "BRS"
      if (queryHasBeres && (pWords.contains('brs') || pName.contains('brs'))) {
        score += 20;
      }

      // B. "Merah" vs "Coklat"
      if (queryHasMerah) {
        if (pWords.contains('merah') || pName.contains('merah')) {
          score += 25;
        } else if (pWords.contains('coklat') || pName.contains('coklat')) {
          score -= 20;
        }
      }
      if (queryHasCoklat) {
        if (pWords.contains('coklat') || pName.contains('coklat')) {
          score += 25;
        } else if (pWords.contains('merah') || pName.contains('merah')) {
          score -= 20;
        }
      }

      // C. Specific Sizes & Counts (13, 24, 7, 215)
      if (queryHas13 && (pName.contains('13') || pWords.contains('13s') || pWords.contains('13'))) {
        score += 25;
      }
      if (queryHas24 && (pName.contains('24') || pWords.contains('24s') || pWords.contains('24'))) {
        score += 25;
      }
      if (queryHas7 && (pName.contains('7') || pWords.contains('7s') || pWords.contains('7'))) {
        score += 25;
      }
      if (queryHas215 && (pName.contains('215') || pWords.contains('215g') || pWords.contains('215gr'))) {
        score += 30;
      }

      // D. "ROLL" variant
      if (queryHasRoll) {
        if (pWords.contains('roll') || pWords.contains('rol') || pName.contains('roll')) {
          score += 25; // Massive bonus for true ROLL variant
        } else if (pName.contains('1000')) {
          score -= 15; // Penalty for picking 1000g when ROLL is requested
        }
      }

      // E. "LOYANG" variant
      if (queryHasLoyang) {
        if (pWords.contains('loyang') || pWords.contains('lyg') || pName.contains('loyang')) {
          score += 25;
        }
      }

      // F. 1000g vs 400g/500g
      if (queryHas1000 && pName.contains('1000')) {
        score += 20;
      }

      // Prefer Induk 24 over 24S when 's' was not explicitly typed in chat
      if (queryHas24 && !cleanQ.contains('24s') && pName.contains('24s')) {
        score -= 10;
      }

      if (score > maxScore) {
        maxScore = score;
        bestProduct = p;
      }
    }

    return maxScore >= 4 ? bestProduct : null;
  }

  /// Apply Bonus/Promo rules: auto-append bonus items based on customer & qty thresholds
  /// Rule keyword format: "CUSTOMER_NAME|PRODUCT_NAME|MIN_QTY_KARTON" (pipe-separated)
  /// Rule mappedValue format: "BONUS_PRODUCT_NAME|BONUS_QTY|BONUS_UNIT" (pipe-separated)
  void _applyBonusRules({
    required List<ChatOrderItemDraft> draftItems,
    required List<AiKnowledgeRule> bonusRules,
    required String customerName,
    required List<Product> products,
  }) {
    if (bonusRules.isEmpty || draftItems.isEmpty) return;

    final cleanCust = customerName.trim().toLowerCase();
    final bonusItemsToAdd = <ChatOrderItemDraft>[];

    for (var rule in bonusRules) {
      // Parse rule keyword: "CUSTOMER|PRODUCT|MIN_QTY"
      final keyParts = rule.keyword.split('|');
      if (keyParts.length < 3) continue;

      final ruleCust = keyParts[0].trim().toLowerCase();
      final ruleProd = keyParts[1].trim().toLowerCase();
      final ruleMinQty = double.tryParse(keyParts[2].trim()) ?? 0;

      // Check if customer matches
      if (!cleanCust.contains(ruleCust) && !ruleCust.contains(cleanCust)) continue;

      // Parse rule mappedValue: "BONUS_PRODUCT|BONUS_QTY|BONUS_UNIT"
      final valParts = rule.mappedValue.split('|');
      if (valParts.length < 3) continue;

      final bonusProdName = valParts[0].trim();
      final bonusQty = double.tryParse(valParts[1].trim()) ?? 1;
      final bonusUnit = valParts[2].trim().toLowerCase();

      // Sum karton qty for the matching product in draftItems
      double totalKartonForProduct = 0;
      ChatOrderItemDraft? matchedItem;
      for (var item in draftItems) {
        if (item.productName.toLowerCase().contains(ruleProd) ||
            ruleProd.contains(item.productName.toLowerCase())) {
          if (item.qtyUnit.toLowerCase() == 'karton') {
            totalKartonForProduct += item.qtyInput;
          }
          matchedItem = item;
        }
      }

      // Check if threshold is met and calculate multiples (kelipatan bonus)
      if (ruleMinQty > 0 && totalKartonForProduct >= ruleMinQty && matchedItem != null) {
        final multiplier = (totalKartonForProduct / ruleMinQty).floor();
        if (multiplier <= 0) continue;

        final calculatedBonusQty = bonusQty * multiplier;

        // Resolve bonus product from master
        Product? bonusProduct;
        for (var p in products) {
          if (p.name.toLowerCase() == bonusProdName.toLowerCase()) {
            bonusProduct = p;
            break;
          }
        }
        // Fallback: use matched item's product info
        bonusProduct ??= products.firstWhere(
          (p) => p.name.toLowerCase().contains(bonusProdName.toLowerCase()),
          orElse: () => Product(
            id: matchedItem!.productId,
            name: bonusProdName,
            price: 0.0,
            stock: 0.0,
            isiKarton: 20,
            sizeGrams: matchedItem.sizeGrams,
          ),
        );

        // Calculate bonus qty in pcs
        double bonusQtyPcs = calculatedBonusQty;
        if (bonusUnit == 'karton') {
          final isiKarton = bonusProduct.isiKarton > 0 ? bonusProduct.isiKarton : 20;
          bonusQtyPcs = calculatedBonusQty * isiKarton;
        }

        bonusItemsToAdd.add(ChatOrderItemDraft(
          productId: bonusProduct.id,
          productName: '${bonusProduct.name} (BONUS)',
          rawText: '[AUTO BONUS] ${rule.keyword} (Kelipatan x$multiplier)',
          qtyUnit: bonusUnit,
          qtyInput: calculatedBonusQty,
          qtyPcs: bonusQtyPcs,
          price: 0.0,
          discountPercent: 0.0,
          discountAmount: 0.0,
          sizeGrams: bonusProduct.sizeGrams,
          isNewItemForCustomer: false,
          isBonus: true,
        ));
      }
    }

    draftItems.addAll(bonusItemsToAdd);
  }

  bool _isIgnoredLine(String line) {
    final lower = line.toLowerCase();
    return lower.startsWith('krm ') ||
        lower.startsWith('kirim ') ||
        lower.startsWith('waalaikumsalam') ||
        lower.startsWith('assalamualaikum') ||
        lower.startsWith('pagi ') ||
        lower.startsWith('siang ') ||
        lower.startsWith('sore ') ||
        lower.startsWith('selasa') ||
        lower.startsWith('kamis') ||
        RegExp(r'^\d{1,2}[\.:]\d{2}$').hasMatch(lower); // timestamp e.g. 17.04
  }

  String _detectCityFromText(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('wonosobo')) return 'WONOSOBO';
    if (lower.contains('kendal')) return 'KENDAL';
    if (lower.contains('purwodadi')) return 'PURWODADI';
    if (lower.contains('kudus')) return 'KUDUS';
    if (lower.contains('pati')) return 'PATI';
    if (lower.contains('demak')) return 'DEMAK';
    if (lower.contains('solo') || lower.contains('surakarta')) return 'SURAKARTA';
    if (lower.contains('jogja') || lower.contains('yogyakarta')) return 'YOGYAKARTA';
    if (lower.contains('magelang')) return 'MAGELANG';
    if (lower.contains('temanggung')) return 'TEMANGGUNG';
    if (lower.contains('semarang')) return 'SEMARANG';
    return 'SEMARANG';
  }
}

class _CustomerResolution {
  final Customer? customer;
  final String rawName;
  final int headerLineCount;

  _CustomerResolution({
    required this.customer,
    required this.rawName,
    required this.headerLineCount,
  });
}

class _QtyUnitResolution {
  final double qty;
  final String unit;
  final String cleanedText;

  _QtyUnitResolution({
    required this.qty,
    required this.unit,
    required this.cleanedText,
  });
}
