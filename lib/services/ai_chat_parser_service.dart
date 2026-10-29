import 'package:flutter/foundation.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/ai_knowledge_rule.dart';
import '../models/chat_order_draft.dart';
import '../models/customer_product_history.dart';
import 'firebase_service.dart';

class AiChatParserService {
  final FirebaseService? firebaseService;

  AiChatParserService([this.firebaseService]);

  /// Main entry point to parse a raw WhatsApp chat text into a list of ChatOrderDraft
  Future<List<ChatOrderDraft>> parseChatOrders({
    required String rawChat,
    required List<Customer> customers,
    required List<Product> products,
    required List<AiKnowledgeRule> rules,
    String generalInstructions = '',
    String? senderPhone,
    Map<String, List<CustomerProductHistory>>? mockCustomerHistory,
  }) async {
    final drafts = <ChatOrderDraft>[];
    if (rawChat.trim().isEmpty) return drafts;

    // 1. Separate rules by type
    final customerRules = rules.where((r) => r.type == 'customer_alias').toList();
    final productRules = rules.where((r) => r.type == 'product_alias').toList();
    final unitRules = rules.where((r) => r.type == 'unit').toList();
    final bonusRules = rules.where((r) => r.type == 'bonus_rule').toList();

    // 2. Multi-PO Splitting: Split chat into separate blocks per store/order
    final blocks = _splitChatIntoStoreBlocks(
      rawChat,
      customers: customers,
      customerRules: customerRules,
    );

    for (var block in blocks) {
      final lines = block
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) continue;

      // Extract Customer from header lines, bottom lines, or senderPhone
      final customerInfo = _resolveCustomer(
        lines: lines,
        customers: customers,
        customerRules: customerRules,
        senderPhone: senderPhone,
      );

      final matchedCustomer = customerInfo.customer;
      final rawCustomerName = customerInfo.rawName;

      // Load Customer's Purchase History (AI learns from customer habit!)
      List<CustomerProductHistory> customerHistory = [];
      if (mockCustomerHistory != null) {
        customerHistory = mockCustomerHistory[matchedCustomer?.id] ??
            mockCustomerHistory[matchedCustomer?.aliasName] ??
            mockCustomerHistory[matchedCustomer?.customerName] ??
            mockCustomerHistory[rawCustomerName] ??
            [];
      } else if (firebaseService != null) {
        customerHistory = await firebaseService!.getCustomerProductHistory(
          customerName: matchedCustomer?.customerName ?? rawCustomerName,
          customerId: matchedCustomer?.id,
          aliasName: matchedCustomer?.aliasName,
        );
      }

      // Extract Product Items and Chat Instructions/Notes from lines
      final draftItems = <ChatOrderItemDraft>[];
      final chatInstructionNotes = <String>[];

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        // Capture instructions / schedule notes from ANY line in the block (top, middle, bottom)
        if (_isInstructionOrScheduleLine(line)) {
          final trimmed = line.trim();
          if (!chatInstructionNotes.contains(trimmed)) {
            chatInstructionNotes.add(trimmed);
          }
          continue;
        }

        // Skip header lines if customer was at top
        if (i < customerInfo.headerLineCount) continue;
        // Skip customer line if customer was at bottom/middle
        if (customerInfo.customerLineIndex != null && i == customerInfo.customerLineIndex) continue;

        // Skip non-item lines (greetings, timestamps)
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
      final bonusNote = _applyBonusRules(
        draftItems: draftItems,
        bonusRules: bonusRules,
        customerName: matchedCustomer?.customerName ?? rawCustomerName,
        aliasName: matchedCustomer?.aliasName ?? '',
        rawCustomerName: rawCustomerName,
        products: products,
      );

      // Note is strictly empty by default so user doesn't have to erase it manually.
      // Only filled if a bonus rule applies (e.g. LG FF bonus note).
      final String finalNote = (bonusNote != null && bonusNote.isNotEmpty) ? bonusNote : '';

      // Only add draft if items exist (do NOT create phantom POs for non-order/admin messages!)
      if (draftItems.isNotEmpty) {
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
          note: finalNote,
        ));
      }
    }

    return drafts;
  }

  /// Splits multi-order chats into individual store blocks.
  /// Supports both store at TOP (header) and store at BOTTOM (footer / boundary between orders).
  List<String> _splitChatIntoStoreBlocks(
    String rawChat, {
    List<Customer> customers = const [],
    List<AiKnowledgeRule> customerRules = const [],
  }) {
    final rawLines = rawChat.split('\n');
    final blocks = <List<String>>[];
    List<String> currentBlock = [];

    // Regex to detect new store boundaries at header
    final newStoreRegex = RegExp(
      r'^(pak[.,\s]+mau\s+order\s+dari|po\s+|order\s+|toko\s+|[A-Z0-9\s]{3,30}\s+(ff|frozen|kendal|wonosobo|purwodadi|semarang|kudus|pati|demak))',
      caseSensitive: false,
    );

    // Helper: checks if ANY line after fromIndex contains an order item
    bool hasSubsequentOrderLines(int fromIndex) {
      for (int j = fromIndex + 1; j < rawLines.length; j++) {
        final nextTrimmed = rawLines[j].trim();
        if (nextTrimmed.isEmpty) continue;
        if (_looksLikeOrderLine(nextTrimmed)) return true;
      }
      return false;
    }

    // Helper: get next non-empty line
    String? getNextNonEmptyLine(int fromIndex) {
      for (int j = fromIndex + 1; j < rawLines.length; j++) {
        final t = rawLines[j].trim();
        if (t.isNotEmpty) return t;
      }
      return null;
    }

    // Helper: checks if currentBlock already has a customer identified (top, middle, or bottom)
    bool currentBlockHasCustomer() {
      for (var l in currentBlock) {
        final t = l.trim();
        if (t.isEmpty) continue;
        if (_isCandidateCustomerLine(t, customers: customers, customerRules: customerRules) ||
            newStoreRegex.hasMatch(t) ||
            _isStoreHeaderLine(t)) {
          return true;
        }
      }
      return false;
    }

    // Helper: checks if a line starts a new numbered list (e.g. "1. ", "1) ", "1- ")
    bool isNumberedListStart(String s) {
      return RegExp(r'^1[\.\)\-]\s+').hasMatch(s);
    }

    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final bool currentHasItems = currentBlock.any((l) => _looksLikeOrderLine(l));
      final bool remainingHasItems = hasSubsequentOrderLines(i);
      final bool isThisLineCust = _isCandidateCustomerLine(
        trimmed,
        customers: customers,
        customerRules: customerRules,
      );
      final bool isHeaderStore = newStoreRegex.hasMatch(trimmed) || _isStoreHeaderLine(trimmed);
      final String? nextLine = getNextNonEmptyLine(i);
      final bool isNextLineCust = nextLine != null && _isCandidateCustomerLine(
        nextLine,
        customers: customers,
        customerRules: customerRules,
      );
      final bool isNextLineOrder = nextLine != null && _looksLikeOrderLine(nextLine);

      // =========================================================================
      // 1. SPLIT BEFORE THIS LINE (Start of a New Order Block)
      // =========================================================================
      if (currentHasItems) {
        bool shouldSplitBefore = false;

        // Case 1A: This line starts a new numbered list ("1. "), and currentBlock
        // ALREADY has a customer specified (e.g. Paris FF completed, and now MMM's "1. Fiva bakso..." starts).
        if (isNumberedListStart(trimmed) && currentBlockHasCustomer()) {
          shouldSplitBefore = true;
        }

        // Case 1B: This line is a store header (Store at TOP) introducing upcoming items.
        // We split before this line if:
        // - There are items following in the chat (remainingHasItems is true)
        // - AND either:
        //   * currentBlock already has its own customer, OR
        //   * this line has an explicit header keyword ("po ", "order dari", "toko ", "pak mau order"), OR
        //   * the previous non-empty line in currentBlock was ALSO a customer line (adjacent customer transition)
        else if ((isHeaderStore || isThisLineCust) && remainingHasItems) {
          final bool hasExplicitHeaderPrefix = trimmed.toLowerCase().startsWith('po ') ||
              trimmed.toLowerCase().startsWith('order ') ||
              trimmed.toLowerCase().contains('order dari') ||
              trimmed.toLowerCase().startsWith('toko ') ||
              trimmed.toLowerCase().startsWith('pak mau order');

          final String lastInCurrent = currentBlock.reversed
              .map((l) => l.trim())
              .firstWhere((l) => l.isNotEmpty, orElse: () => '');
          final bool prevWasCust = lastInCurrent.isNotEmpty &&
              _isCandidateCustomerLine(lastInCurrent, customers: customers, customerRules: customerRules);

          if (currentBlockHasCustomer() || hasExplicitHeaderPrefix || prevWasCust) {
            shouldSplitBefore = true;
          }
        }

        if (shouldSplitBefore) {
          blocks.add(List.from(currentBlock));
          currentBlock.clear();
        }
      }

      // Add line to current block
      currentBlock.add(line);

      // =========================================================================
      // 2. SPLIT AFTER THIS LINE (Closing of Current Order Block / Store at Footer)
      // =========================================================================
      // Conditions:
      // - currentBlock ALREADY has order items
      // - this line is a customer line (closing/footer store for the items above)
      // - there ARE subsequent items in the remaining chat (remainingHasItems is true)
      // - AND:
      //   * The next non-empty line is the next order's item (isNextLineOrder), OR
      //   * The next non-empty line is ANOTHER store header (isNextLineCust)!
      if (currentHasItems && isThisLineCust && remainingHasItems) {
        if (isNextLineOrder || isNextLineCust) {
          blocks.add(List.from(currentBlock));
          currentBlock.clear();
        }
      }
    }

    if (currentBlock.isNotEmpty) {
      blocks.add(currentBlock);
    }

        // Post-process: Split blocks that contain BOTH a header store and a footer store
    final refinedBlocks = _splitMixedHeaderFooterBlocks(
      blocks,
      customers: customers,
      customerRules: customerRules,
    );

    return refinedBlocks.map((b) => b.join('\n').trim()).where((b) => b.isNotEmpty).toList();
  }

  /// If an order block contains both a header customer (at top) and a different footer customer (at bottom),
  /// split it into two separate blocks so each customer gets their own PO!
  List<List<String>> _splitMixedHeaderFooterBlocks(
    List<List<String>> inputBlocks, {
    List<Customer> customers = const [],
    List<AiKnowledgeRule> customerRules = const [],
  }) {
    final result = <List<String>>[];

    for (var block in inputBlocks) {
      final lines = block.map((l) => l.trim()).toList();
      if (lines.length < 4) {
        result.add(block);
        continue;
      }

      // Check order line indices
      final orderIndices = <int>[];
      for (int i = 0; i < lines.length; i++) {
        if (_looksLikeOrderLine(lines[i])) {
          orderIndices.add(i);
        }
      }

      // Need at least 2 order lines to split between two stores
      if (orderIndices.length < 2) {
        result.add(block);
        continue;
      }

      final firstOrderIdx = orderIndices.first;
      final lastOrderIdx = orderIndices.last;

      // 1. Detect Top Customer (lines before the first order line)
      Customer? topCust;
      for (int i = 0; i < firstOrderIdx; i++) {
        if (_isInstructionOrScheduleLine(lines[i]) || _isIgnoredLine(lines[i])) continue;
        final cust = _testMatchCustomer(lines[i], customers: customers, customerRules: customerRules);
        if (cust != null) {
          topCust = cust;
        }
      }

      // 2. Detect Bottom Customer (lines after the last order line)
      Customer? bottomCust;
      for (int i = lines.length - 1; i > lastOrderIdx; i--) {
        if (_isInstructionOrScheduleLine(lines[i]) || _isIgnoredLine(lines[i])) continue;
        final cust = _testMatchCustomer(lines[i], customers: customers, customerRules: customerRules);
        if (cust != null) {
          bottomCust = cust;
          break;
        }
      }

      // If we have a Top Customer AND a DIFFERENT Bottom Customer:
      // We must split this block into two!
      if (topCust != null &&
          bottomCust != null &&
          topCust.id != bottomCust.id &&
          topCust.customerName.toLowerCase() != bottomCust.customerName.toLowerCase()) {
        int splitIdx = -1;

        // Strategy A: Check for empty lines between firstOrderIdx and lastOrderIdx
        for (int i = firstOrderIdx + 1; i <= lastOrderIdx; i++) {
          if (block[i].trim().isEmpty) {
            splitIdx = i + 1;
            break;
          }
        }

        // Strategy B: Check for an instruction/schedule line between order items
        if (splitIdx == -1) {
          for (int i = firstOrderIdx + 1; i < lastOrderIdx; i++) {
            if (_isInstructionOrScheduleLine(lines[i])) {
              splitIdx = i;
              break;
            }
          }
        }

        // Strategy C: Check for prefix change across order items (e.g. lines starting with "Fv " vs without "Fv ")
        if (splitIdx == -1) {
          for (int i = firstOrderIdx + 1; i <= lastOrderIdx; i++) {
            final linePrev = lines[i - 1].toLowerCase();
            final lineCurr = lines[i].toLowerCase();

            final prevHasFv = linePrev.startsWith('fv ') || linePrev.startsWith('fiva ');
            final currHasFv = lineCurr.startsWith('fv ') || lineCurr.startsWith('fiva ');

            if (prevHasFv != currHasFv) {
              splitIdx = i;
              break;
            }
          }
        }

        // Strategy D: Fallback - split at the second order item if first was separate
        if (splitIdx == -1) {
          splitIdx = orderIndices[1];
        }

        if (splitIdx > 0 && splitIdx < lines.length) {
          final block1 = block.sublist(0, splitIdx);
          final block2 = block.sublist(splitIdx);
          result.add(block1);
          result.add(block2);
          continue;
        }
      }

      result.add(block);
    }

    return result;
  }

  bool _isCandidateCustomerLine(
    String line, {
    List<Customer> customers = const [],
    List<AiKnowledgeRule> customerRules = const [],
  }) {
    final lower = line.toLowerCase().trim();
    if (lower.isEmpty) return false;
    if (_looksLikeOrderLine(line)) return false;
    if (_isInstructionOrScheduleLine(line)) return false;
    if (_isIgnoredLine(line)) return false;

    // Direct check against known customers
    for (var cust in customers) {
      final cName = cust.customerName.toLowerCase().trim();
      final cAlias = cust.aliasName.toLowerCase().trim();
      if (cName.isNotEmpty && (lower == cName || lower.contains(cName))) return true;
      if (cAlias.isNotEmpty && (lower == cAlias || lower.contains(cAlias))) return true;
    }

    // Direct check against customer rules
    for (var rule in customerRules) {
      final rKw = rule.keyword.toLowerCase().trim();
      if (rKw.isNotEmpty && (lower == rKw || lower.contains(rKw))) return true;
    }

    // Common store prefixes/suffixes
    if (lower.contains('order dari') ||
        lower.startsWith('po ') ||
        lower.contains(' ff ') ||
        lower.endsWith(' ff') ||
        lower.contains(' frozen') ||
        lower.startsWith('toko ') ||
        RegExp(r'^(sjj|mmm|lg ff|kk ff|aniza ff|mister sosis)$', caseSensitive: false).hasMatch(lower)) {
      return true;
    }

    // Any short non-order line without digits between two order lists is a store name!
    if (!RegExp(r'\d').hasMatch(lower) && lower.length >= 2 && lower.length <= 40) {
      return true;
    }

    return false;
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
    final lower = line.toLowerCase().trim();
    if (lower.isEmpty) return false;

    // Instructions or schedule notes are NOT order lines
    if (_isInstructionOrScheduleLine(lower)) return false;

    // Clean leading list bullet/numbers like "1. ", "2) ", "- "
    final contentOnly = lower
        .replaceAll(RegExp(r'^\d+[\.\)]\s*'), '')
        .replaceAll(RegExp(r'^[-\*\•]\s*'), '')
        .trim();
    if (contentOnly.isEmpty) return false;

    final hasDigits = RegExp(r'\d').hasMatch(contentOnly);
    final hasQtyPattern = RegExp(
      r'(\d+\s*(k|ktn|karton|roll|pack|dus|box|bal|ball|pc|pcs|sak|kg|ons|bks|bungkus|biji))|([:=]\s*\d+)|(\.{2,}\s*\d+)',
      caseSensitive: false,
    ).hasMatch(contentOnly);

    if (!hasDigits && !hasQtyPattern) return false;

    final hasProductKeyword = contentOnly.contains('rolade') ||
        contentOnly.contains('beres') ||
        contentOnly.contains('kornet') ||
        contentOnly.contains('sosis') ||
        contentOnly.contains('bakso') ||
        contentOnly.contains('nugget') ||
        contentOnly.contains('siomay') ||
        contentOnly.contains('dimsum') ||
        contentOnly.contains('otak') ||
        contentOnly.contains('tempura');

    return hasProductKeyword || hasQtyPattern;
  }

  /// Normalizes phone number digits and checks if two phone numbers match
  bool _phonesMatch(String a, String b) {
    final da = a.replaceAll(RegExp(r'\D'), '');
    final db = b.replaceAll(RegExp(r'\D'), '');
    if (da.isEmpty || db.isEmpty) return false;
    if (da == db) return true;
    final normA = da.startsWith('62') ? da.substring(2) : (da.startsWith('0') ? da.substring(1) : da);
    final normB = db.startsWith('62') ? db.substring(2) : (db.startsWith('0') ? db.substring(1) : db);
    if (normA == normB) return true;
    if (normA.length >= 8 && normB.length >= 8) {
      return normA.endsWith(normB) || normB.endsWith(normA);
    }
    return false;
  }

  @visibleForTesting
  Customer? testMatchCustomerForDebug(
    String txt, {
    List<Customer> customers = const [],
    List<AiKnowledgeRule> customerRules = const [],
  }) => _testMatchCustomer(txt, customers: customers, customerRules: customerRules);

  /// Tests if a line matches a known master customer or customer alias rule
  Customer? _testMatchCustomer(
    String txt, {
    List<Customer> customers = const [],
    List<AiKnowledgeRule> customerRules = const [],
  }) {
    // Never match instructions, schedule lines, or ignored greetings as customers!
    if (_isInstructionOrScheduleLine(txt) || _isIgnoredLine(txt)) return null;

    String c = txt
        .replaceAll(RegExp(r'^(waalaikumsalam|assalamualaikum)[.,\s]*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^(pak[.,\s]+)?(mau\s+)?(orderan?|pesanan?|po)\s+(dari\s+)?', caseSensitive: false), '')
        .replaceAll(RegExp(r'^(orderan?|pesanan?|po)\s+', caseSensitive: false), '')
        .trim();
    // Strip leading list numbers like "1. ", "2. "
    c = c.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '').trim();
    final target = c.toLowerCase();
    if (target.isEmpty || target.length < 2) return null;

    // 1. Direct exact match on master customers FIRST (before checking order lines)
    for (var cust in customers) {
      if (cust.customerName.toLowerCase().trim() == target ||
          cust.aliasName.toLowerCase().trim() == target) {
        return cust;
      }
    }

    if (_looksLikeOrderLine(txt)) return null; // Never match order item line as customer!

    for (var rule in customerRules) {
      final rKw = rule.keyword.trim().toLowerCase();
      if (rKw.isNotEmpty && (target == rKw || target.contains(rKw) || (rKw.contains(target) && target.length >= 3))) {
        if (rule.targetId != null && rule.targetId!.isNotEmpty) {
          final cust = customers.firstWhere((item) => item.id == rule.targetId, orElse: () => Customer(id: '', customerName: '', aliasName: '', address: '', city: '', province: '', country: '', phone: '', ktpNumber: ''));
          if (cust.id.isNotEmpty) return cust;
        }
        final mapped = rule.mappedValue.trim().toLowerCase();
        final cust = customers.firstWhere((item) => item.customerName.toLowerCase() == mapped || item.aliasName.toLowerCase() == mapped || item.id.toLowerCase() == mapped, orElse: () => Customer(id: '', customerName: '', aliasName: '', address: '', city: '', province: '', country: '', phone: '', ktpNumber: ''));
        if (cust.id.isNotEmpty) return cust;
        final fuzzy = _findNearestMasterCustomer(rule.mappedValue, customers);
        if (fuzzy != null) return fuzzy;
      }
    }
    return _findNearestMasterCustomer(c, customers);
  }

  /// Resolve Customer by checking Rules, Master Customers, Sender Phone, or raw string
  _CustomerResolution _resolveCustomer({
    required List<String> lines,
    required List<Customer> customers,
    required List<AiKnowledgeRule> customerRules,
    String? senderPhone,
  }) {
    if (lines.isEmpty) {
      return _CustomerResolution(customer: null, rawName: '', headerLineCount: 0);
    }

    // Helper: test if a line is just a title/date/greeting without specific customer name
    bool isTitleOrGreetingOnly(String s) {
      final l = s.toLowerCase().trim();
      if (l == 'po' || l == 'po:' || l == 'po.' || l == 'po pesanan' || l == 'po orderan' || l == 'orderan' || l == 'pesanan') return true;
      return l.startsWith('orderan ') ||
          l.startsWith('pesanan ') ||
          l.startsWith('jadwal ') ||
          l.startsWith('assalamualaikum') ||
          l.startsWith('waalaikumsalam') ||
          l.startsWith('pak..') ||
          l.startsWith('msk erp') ||
          l.startsWith('masuk erp') ||
          l.startsWith('list erp') ||
          l.contains('2026') ||
          l.contains('2025') ||
          l.contains('juni') ||
          l.contains('juli') ||
          l.contains('agustus') ||
          l.contains('september') ||
          l.contains('oktober') ||
          l.contains('november') ||
          l.contains('desember');
    }

    // A. Check TOP lines (Line 0, Line 1, or Line 2)
    if (lines.isNotEmpty) {
      if (lines.length > 1 && isTitleOrGreetingOnly(lines[0])) {
        // Line 0 is a greeting/title like "Msk erp hari ini...."
        // Scan header lines (1, 2, 3) before order lines start.
        // If multiple customer matches exist (e.g. "1. Griya ff pekalongan" then "SJJ"),
        // the one directly preceding the order lines/schedule is the active customer!
        Customer? bestHeaderCust;
        String bestRawName = lines[1];
        int bestLineIdx = 1;

        for (int h = 1; h < lines.length && h <= 3; h++) {
          if (_looksLikeOrderLine(lines[h])) break;
          if (_isInstructionOrScheduleLine(lines[h]) || _isIgnoredLine(lines[h])) continue;
          final matchH = _testMatchCustomer(lines[h], customers: customers, customerRules: customerRules);
          if (matchH != null) {
            bestHeaderCust = matchH;
            bestRawName = lines[h];
            bestLineIdx = h;
          }
        }

        if (bestHeaderCust != null) {
          return _CustomerResolution(
            customer: bestHeaderCust,
            rawName: bestRawName,
            headerLineCount: bestLineIdx + 1,
            customerLineIndex: bestLineIdx,
          );
        } else if (!_looksLikeOrderLine(lines[1])) {
          return _CustomerResolution(
            customer: null,
            rawName: lines[1],
            headerLineCount: 2,
            customerLineIndex: 1,
          );
        }
      } else {
        final matchLine0 = _testMatchCustomer(lines[0], customers: customers, customerRules: customerRules);
        if (matchLine0 != null) {
          return _CustomerResolution(
            customer: matchLine0,
            rawName: lines[0],
            headerLineCount: 1,
            customerLineIndex: 0,
          );
        }
      }
    }

    // B. Check BOTTOM lines (scan non-order lines from bottom upwards, e.g. "Mister sosis", "Po aw")
    String? candidateBottomRawName;
    int? candidateBottomLineIdx;

    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];
      if (_looksLikeOrderLine(line) || _isIgnoredLine(line)) continue;

      final matchBottom = _testMatchCustomer(line, customers: customers, customerRules: customerRules);
      if (matchBottom != null) {
        return _CustomerResolution(
          customer: matchBottom,
          rawName: line,
          headerLineCount: 0,
          customerLineIndex: i,
        );
      } else if (candidateBottomRawName == null && _isCandidateCustomerLine(line, customers: customers, customerRules: customerRules)) {
        candidateBottomRawName = line;
        candidateBottomLineIdx = i;
      }
    }

    // C. Check Sender Phone (Tahap 2: match sender phone against customer database)
    if (senderPhone != null && senderPhone.trim().isNotEmpty) {
      for (var cust in customers) {
        if (cust.phone.isNotEmpty && _phonesMatch(cust.phone, senderPhone)) {
          return _CustomerResolution(
            customer: cust,
            rawName: cust.displayName,
            headerLineCount: 0,
            customerLineIndex: null,
          );
        }
      }
    }

    // D. If line 0 does not look like an order line, treat it as raw customer name
    if (lines.isNotEmpty && !_looksLikeOrderLine(lines[0]) && !_isIgnoredLine(lines[0])) {
      return _CustomerResolution(
        customer: null,
        rawName: lines[0],
        headerLineCount: 1,
        customerLineIndex: 0,
      );
    }

    // D2. If a candidate customer line was found at the bottom (even if unregistered in master), use it!
    if (candidateBottomRawName != null) {
      return _CustomerResolution(
        customer: null,
        rawName: candidateBottomRawName,
        headerLineCount: 0,
        customerLineIndex: candidateBottomLineIdx,
      );
    }

    // E. Line 0 is an order item line and no customer identified anywhere
    return _CustomerResolution(
      customer: null,
      rawName: 'Pelanggan WhatsApp',
      headerLineCount: 0,
      customerLineIndex: null,
    );
  }

  /// Searches and matches Master Customers using Acronyms (e.g. MMM -> Maju Market Mandiri), Stopwords, and Token Overlap
  Customer? _findNearestMasterCustomer(String text, List<Customer> customers) {
    if (customers.isEmpty) return null;

    final clean = text.toLowerCase().trim();
    if (clean.isEmpty) return null;

    // 1. Direct exact match check on master customers (customerName or aliasName) FIRST!
    for (var c in customers) {
      final cNameRaw = c.customerName.toLowerCase().trim();
      final cAliasRaw = c.aliasName.toLowerCase().trim();
      if (clean == cNameRaw || clean == cAliasRaw) {
        return c; // 100% exact match found!
      }
    }

    if (_looksLikeOrderLine(text)) return null; // Never match order item line as customer!

    // Known city names to strip from query (prevents city-as-name false matches)
    final knownCities = {
      'pekalongan', 'tegal', 'brebes', 'batang', 'pemalang',
      'semarang', 'demak', 'grobogan', 'salatiga', 'gubug', 'purwodadi', 'kendal',
      'wonosobo', 'magelang', 'purworejo', 'temanggung', 'kebumen',
      'banjarnegara', 'purbalingga', 'banyumas', 'cilacap',
      'kudus', 'jepara', 'pati', 'rembang', 'blora',
      'solo', 'surakarta', 'sragen', 'karanganyar', 'klaten', 'boyolali', 'colomadu', 'banjarsari',
      'yogyakarta', 'sleman', 'bantul', 'kulonprogo', 'gunungkidul', 'wates',
    };

    // Filter out generic stopwords AND city names
    String stripStopwords(String s) {
      return s
          .replaceAll(RegExp(r'\b(cv|pt|ud|tb|pd|toko|tk|ff|frozen|food)\b', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    final queryCleaned = stripStopwords(clean);
    // Remove city names from query tokens so they don't falsely match customer names
    final queryTokens = queryCleaned.split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !knownCities.contains(w))
        .toList();
    final queryAlphaNumOnly = clean.replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Helper: checks if phrase is found as a whole word/phrase within container (avoids false matches like "selasa" -> "ela")
    bool containsWordOrPhrase(String container, String phrase) {
      if (phrase.isEmpty || container.isEmpty) return false;
      if (container == phrase) return true;
      final pattern = r'(^|\s+)' + RegExp.escape(phrase) + r'($|\s+)';
      return RegExp(pattern).hasMatch(container);
    }

    Customer? bestMatch;
    int maxScore = 0;

    for (var c in customers) {
      final cNameRaw = c.customerName.toLowerCase().trim();
      final cAliasRaw = c.aliasName.toLowerCase().trim();
      final cCity = c.city.toLowerCase().trim();

      final cNameClean = stripStopwords(cNameRaw);
      final cAliasClean = stripStopwords(cAliasRaw);

      int score = 0;

      // Exact match after cleaning stopwords
      if (queryCleaned == cNameClean || (cAliasClean.isNotEmpty && queryCleaned == cAliasClean)) {
        return c; // 100% exact match
      }

      final cTokens = cNameClean.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
      final cAliasTokens = cAliasClean.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();

      // 2. Acronym / Initials Match (e.g. "MMM" -> M-aju M-arket M-andiri, "SJJ" -> S-umber J-adi J-aya)
      // Only for short acronym queries (length 2-5) and EXACT match (== initials)
      if (queryAlphaNumOnly.length >= 2 && queryAlphaNumOnly.length <= 5) {
        if (cTokens.length >= 2) {
          final initials = cTokens.map((w) => w[0]).join(); // e.g. "mmm", "sjj"
          if (queryAlphaNumOnly == initials) {
            score += 150; // Exact acronym match only!
          }
        }

        if (cAliasTokens.length >= 2) {
          final aliasInitials = cAliasTokens.map((w) => w[0]).join();
          if (queryAlphaNumOnly == aliasInitials) {
            score += 140;
          }
        }
      }

      // 3. Direct Substring / Whole Word Containment (whole words only to prevent e.g. "selasa" matching "ela")
      if (cNameClean.isNotEmpty && containsWordOrPhrase(queryCleaned, cNameClean)) {
        score += 80;
      }
      if (cAliasClean.isNotEmpty && containsWordOrPhrase(queryCleaned, cAliasClean)) {
        score += 70;
      }
      if (cNameClean.isNotEmpty && containsWordOrPhrase(cNameClean, queryCleaned)) {
        score += 60;
      }
      if (cAliasClean.isNotEmpty && containsWordOrPhrase(cAliasClean, queryCleaned)) {
        score += 60;
      }

      // 4. Token Overlap (city names already stripped from queryTokens)
      int matchedTokens = 0;
      for (var token in queryTokens) {
        if (cTokens.contains(token)) {
          score += 30;
          matchedTokens++;
        } else if (cAliasTokens.contains(token)) {
          score += 25;
          matchedTokens++;
        } else if (token.length >= 4) {
          // Substring token match ONLY for tokens >= 4 chars to avoid false syllable matches
          for (var ct in cTokens) {
            if (ct.length >= 4 && (ct.contains(token) || token.contains(ct))) {
              score += 15;
              break;
            }
          }
        }
      }

      if (matchedTokens >= 2) {
        score += 40;
      }

      // 5. City Match Bonus — ONLY a tie-breaker, never sufficient alone
      // City bonus only applies when there's already some name-based score
      if (score > 0 && cCity.isNotEmpty && clean.contains(cCity)) {
        score += 25;
      }

      if (score > maxScore) {
        maxScore = score;
        bestMatch = c;
      }
    }

    return maxScore >= 40 ? bestMatch : null;
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

    // Clean trailing dots, colons, dashes
    productText = productText.replaceAll(RegExp(r'[\.\:\=\,\-]+$'), '').trim();

    // Clean intermediate / trailing packaging notes like "= 2 ball", ": 2 bal", "= 2 dus", "100 ball", "35 ball", "300 pack"
    productText = productText.replaceAll(RegExp(r'[:=\-\s]*\b\d+[\s\.\-]*(bal|ball|dus|box|pack|pak|ktn|karton|roll|rol|pcs|pc)\b', caseSensitive: false), '').trim();
    productText = productText.replaceAll(RegExp(r'[\.\:\=\,\-]+$'), '').trim();

    // Remove brand "fiva " or "fv " if present at the start
    if (productText.toLowerCase().startsWith('fiva ')) {
      productText = productText.substring(5).trim();
    } else if (productText.toLowerCase().startsWith('fv ')) {
      productText = productText.substring(3).trim();
    }

    Product? matchedProduct;
    CustomerProductHistory? matchedHistory;

    // 1. PRIORITAS UTAMA: Cek Riwayat Pembelian Pelanggan Ini (AI Belajar dari Kebiasaan Customer)
    // Setiap toko punya kebiasaan varian dan tier harga tersendiri (misal 24 vs 24S, Tier 1 vs Tier 2).
    // Jika pelanggan ini pernah membeli barang yang cocok di invoice sebelumnya, utamakan riwayat toko tersebut!
    if (customerHistory.isNotEmpty && qtyInfo.hadExplicitQty) {
      matchedHistory = _matchProductFromCustomerHistory(productText, customerHistory);
      if (matchedHistory != null) {
        matchedProduct = products.firstWhere(
          (p) => (matchedHistory!.productId.isNotEmpty && p.id == matchedHistory.productId) ||
              p.name.toLowerCase() == matchedHistory.productName.toLowerCase(),
          orElse: () => products.firstWhere(
            (p) => p.name.toLowerCase().contains(matchedHistory!.productName.toLowerCase()),
            orElse: () => Product(
              id: matchedHistory!.productId,
              name: matchedHistory.productName,
              price: matchedHistory.price,
              stock: 0.0,
              isiKarton: 15,
              sizeGrams: 500.0,
            ),
          ),
        );
      }
    }

    // 2. PRIORITAS KEDUA: Aturan Kamus (AI Knowledge Rules - Singkatan Barang)
    // Jika belum ada di riwayat toko, gunakan aturan kamus singkatan barang
    if (matchedProduct == null) {
      final sortedRules = List<AiKnowledgeRule>.from(productRules)
        ..sort((a, b) => b.keyword.length.compareTo(a.keyword.length));

      for (var rule in sortedRules) {
        final rKw = rule.keyword.trim().toLowerCase();
        if (rKw.isEmpty) continue;
        final pTextLower = productText.toLowerCase();
        bool isMatch = pTextLower == rKw || pTextLower.contains(rKw) || rKw.contains(pTextLower);
        if (!isMatch) {
          final rTokens = rKw.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
          if (rTokens.length >= 2) {
            isMatch = rTokens.every((t) => pTextLower.contains(t));
          }
        }
        if (isMatch) {
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

    // Only accept if it matched an explicit AI Knowledge product rule OR exact master product name!
    // Never allow fuzzy or customer history matching without explicit quantity (avoids phantom items from store names or notes)
    if (!qtyInfo.hadExplicitQty) {
      if (matchedProduct == null) {
        for (var p in products) {
          if (p.name.toLowerCase().trim() == productText.toLowerCase().trim()) {
            matchedProduct = p;
            break;
          }
        }
      }
      if (matchedProduct == null) return null;
    }

    // 3. PRIORITAS KETIGA: Fallback Fuzzy / Keyword Match ke seluruh Master Barang
    if (matchedProduct == null || matchedProduct.id.isEmpty) {
      matchedProduct = _fuzzyMatchProduct(productText, products);
    }

    if (matchedProduct == null) return null;

    // 4. Historical Pricing: Tarik harga & diskon dari riwayat transaksi pelanggan
    double price = matchedProduct.price;
    double discountPercent = 0.0;
    double discountAmount = 0.0;
    String invoiceNo = '';
    bool isNewItemForCustomer = true;

    if (matchedHistory != null) {
      price = matchedHistory.price;
      discountPercent = matchedHistory.discountPercent;
      discountAmount = matchedHistory.discountAmount;
      invoiceNo = matchedHistory.invoiceNo;
      isNewItemForCustomer = false;
    } else {
      CustomerProductHistory? hist = customerHistory.firstWhere(
        (h) => (h.productId.isNotEmpty && h.productId == matchedProduct!.id) ||
            h.productName.toLowerCase() == matchedProduct!.name.toLowerCase(),
        orElse: () => CustomerProductHistory(productId: '', productName: '', price: 0, discountPercent: 0, discountAmount: 0, invoiceNo: ''),
      );

      // Pencocokan Varian Serumpun Cerdas (misal: "24" vs "24S", "Tier 2", dsb)
      if (hist.invoiceNo.isEmpty || hist.price <= 0) {
        final familyMatch = _findFamilyVariantInHistory(matchedProduct, customerHistory);
        if (familyMatch != null) {
          hist = familyMatch;
          final variantProd = products.firstWhere(
            (p) => (hist!.productId.isNotEmpty && p.id == hist.productId) ||
                p.name.toLowerCase() == hist.productName.toLowerCase(),
            orElse: () => products.firstWhere(
              (p) => p.name.toLowerCase().contains(hist!.productName.toLowerCase()),
              orElse: () => Product(
                id: hist!.productId,
                name: hist.productName,
                price: hist.price,
                stock: 0.0,
                isiKarton: matchedProduct?.isiKarton ?? 20,
                sizeGrams: matchedProduct?.sizeGrams ?? 500.0,
              ),
            ),
          );
          matchedProduct = variantProd;
        }
      }

      if (hist.invoiceNo.isNotEmpty && hist.price > 0) {
        price = hist.price;
        discountPercent = hist.discountPercent;
        discountAmount = hist.discountAmount;
        invoiceNo = hist.invoiceNo;
        isNewItemForCustomer = false;
      } else {
        // Fallback: Scan Firestore jika belum masuk di map
        final historyPricing = firebaseService != null
            ? await firebaseService!.getLastCustomerProductPricing(
                customerName,
                matchedProduct.id,
                customerId: customerId,
                productName: matchedProduct.name,
              )
            : null;
        if (historyPricing != null) {
          price = (historyPricing['price'] ?? matchedProduct.price).toDouble();
          discountPercent = (historyPricing['discountPercent'] ?? 0.0).toDouble();
          discountAmount = (historyPricing['discountAmount'] ?? 0.0).toDouble();
          invoiceNo = (historyPricing['invoiceNo'] ?? '').toString();
          isNewItemForCustomer = false;

          final histPName = (historyPricing['productName'] ?? '').toString().trim();
          if (histPName.isNotEmpty && histPName.toLowerCase() != matchedProduct.name.toLowerCase()) {
            final variantProd = products.firstWhere(
              (p) => p.name.toLowerCase() == histPName.toLowerCase(),
              orElse: () => matchedProduct!,
            );
            matchedProduct = variantProd;
          }
        }
      }
    }

    // Calculate qtyPcs (converting karton to pcs based on final matchedProduct's isiKarton)
    double qtyPcs = qtyInfo.qty;
    if (qtyInfo.unit == 'karton') {
      final isiKarton = matchedProduct.isiKarton > 0 ? matchedProduct.isiKarton : 10;
      qtyPcs = qtyInfo.qty * isiKarton;
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
      invoiceNo: invoiceNo,
    );
  }

  /// Parses number string respecting Indonesian formatting (dots as thousands separators, comma as decimal)
  /// e.g. "2.500" -> 2500.0, "15" -> 15.0, "2,5" -> 2.5, "2.5" -> 2.5 (unless 3 digits after dot like .000)
  double _parseIndonesianNumber(String str) {
    String s = str.trim();
    if (s.isEmpty) return 1.0;

    // Indonesian thousand dot with comma decimal: e.g. "2.500,5" -> "2500.5"
    if (RegExp(r'^\d{1,3}(\.\d{3})+,\d+$').hasMatch(s)) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(s) ?? 1.0;
    }

    // Indonesian thousand dot: e.g. "2.500", "10.000", "1.500.000"
    if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
      s = s.replaceAll('.', '');
      return double.tryParse(s) ?? 1.0;
    }

    // Comma decimal: e.g. "2,5" -> "2.5"
    if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    }

    return double.tryParse(s) ?? 1.0;
  }

  /// Extracts quantity and unit from line, returning cleaned product text
  _QtyUnitResolution _extractQuantityAndUnit(String line, List<AiKnowledgeRule> unitRules) {
    double qty = 1.0;
    String unit = 'pack';
    String cleaned = line;

    // Pattern 1: Colon format with optional explicit unit:
    // e.g. ": 35 karton", ": 200 pc", ": 200 pcs", ": 10 roll", or ratio ": 1", ": 2"
    final colonMatch = RegExp(
      r':\s*(\d+([.,]\d+)*)\s*(karton|ktn|k\b|dus|box|roll|rol|pack|pak|pcs|pc\b|bks|biji)?',
      caseSensitive: false,
    ).firstMatch(line);

    if (colonMatch != null) {
      qty = _parseIndonesianNumber(colonMatch.group(1) ?? '1');
      final matchedUnitStr = (colonMatch.group(3) ?? '').toLowerCase();

      if (matchedUnitStr.contains('roll') || matchedUnitStr.contains('rol')) {
        unit = 'roll';
      } else if (matchedUnitStr.contains('pack') ||
          matchedUnitStr.contains('pak') ||
          matchedUnitStr.contains('pcs') ||
          matchedUnitStr == 'pc' ||
          matchedUnitStr.contains('bks') ||
          matchedUnitStr.contains('biji')) {
        unit = 'pack';
      } else {
        // Defaults to karton if unit is karton/ktn/k/dus/box OR no unit was specified (ratio : 1, : 2)
        unit = 'karton';
      }

      cleaned = line.replaceAll(colonMatch.group(0)!, '').trim();
      // Strip any residual unit words if left over at the end
      cleaned = cleaned.replaceAll(RegExp(r'\b(karton|ktn|k|pack|pak|pcs|pc|roll|rol)\b', caseSensitive: false), '').trim();
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned, hadExplicitQty: true);
    }

    // Pattern 2: "35 k" / "40 K..." / "40 ktn" / "10 karton" / "5 dus"
    final kartonMatch = RegExp(r'(\d+([.,]\d+)*)\s*(k\b|k\.+|ktn|karton|dus|box)', caseSensitive: false).firstMatch(line);
    if (kartonMatch != null) {
      qty = _parseIndonesianNumber(kartonMatch.group(1) ?? '1');
      unit = 'karton';
      cleaned = line.replaceAll(kartonMatch.group(0)!, '').trim();
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned, hadExplicitQty: true);
    }

    // Pattern 3: "11 ROLL" / "325 roll" / "2.500 roll"
    final rollMatch = RegExp(r'(\d+([.,]\d+)*)\s*(roll|rol)', caseSensitive: false).firstMatch(line);
    if (rollMatch != null) {
      qty = _parseIndonesianNumber(rollMatch.group(1) ?? '1');
      unit = 'roll';
      cleaned = line.replaceAll(rollMatch.group(0)!, '').trim();
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned, hadExplicitQty: true);
    }

    // Pattern 4: "121 pack" / "45 pack" / "10 pcs" / "200 pc" / "10 bks"
    final packMatch = RegExp(r'(\d+([.,]\d+)*)\s*(pack|pak|pcs|pc\b|bks|biji)', caseSensitive: false).firstMatch(line);
    if (packMatch != null) {
      qty = _parseIndonesianNumber(packMatch.group(1) ?? '1');
      unit = 'pack';
      cleaned = line.replaceAll(packMatch.group(0)!, '').trim();
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned, hadExplicitQty: true);
    }

    // Pattern 5: Number at the end of line like "Rolade sapi 1000g 35"
    final endNumberMatch = RegExp(r'\b(\d+([.,]\d+)*)$').firstMatch(line);
    if (endNumberMatch != null) {
      qty = _parseIndonesianNumber(endNumberMatch.group(1) ?? '1');
      cleaned = line.substring(0, endNumberMatch.start).trim();
      final lowerCleaned = cleaned.toLowerCase();
      if (lowerCleaned.endsWith('roll') || lowerCleaned.endsWith('rol')) {
        unit = 'roll';
      } else if (lowerCleaned.endsWith('pack') ||
          lowerCleaned.endsWith('pak') ||
          lowerCleaned.endsWith('pcs') ||
          lowerCleaned.endsWith('pc') ||
          lowerCleaned.endsWith('bks') ||
          lowerCleaned.endsWith('biji')) {
        unit = 'pack';
      } else {
        // Sanity Check: If bulk number > 50 without explicit unit word ("karton/ktn/dus"),
        // it is almost certainly pack/pcs (e.g. 150 pack), NOT 150 karton (which would be 1.5 tons!).
        if (qty > 50) {
          unit = 'pack';
        } else {
          unit = 'karton'; // Default to karton for reasonable bulk order numbers (1..50)
        }
      }
      return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned, hadExplicitQty: true);
    }

    return _QtyUnitResolution(qty: qty, unit: unit, cleanedText: cleaned, hadExplicitQty: false);
  }

  @visibleForTesting
  CustomerProductHistory? testMatchCustomerHistory(String query, List<CustomerProductHistory> historyList) =>
      _matchProductFromCustomerHistory(query, historyList);

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
    final bool queryHas1000 = qTokens.contains('1000') ||
        qTokens.contains('1kg') ||
        cleanQ.contains('1 kg') ||
        cleanQ.contains('1kg') ||
        cleanQ.contains('1000g') ||
        cleanQ.contains('1000 g') ||
        cleanQ.contains('1000gr') ||
        cleanQ.contains('1000 gr');
    final bool queryHasPolos = qTokens.contains('polos');
    final bool queryHasBeres = qTokens.contains('beres') || qTokens.contains('beras') || qTokens.contains('brs');
    final bool queryHasMerah = qTokens.contains('merah');
    final bool queryHasCoklat = qTokens.contains('coklat') || qTokens.contains('cklt');
    final bool queryHasSapi = qTokens.contains('sapi') || qTokens.contains('sp');
    final bool queryHasAyam = qTokens.contains('ayam') || qTokens.contains('ay');
    final bool queryHas13 = qTokens.contains('13') || qTokens.contains('13s');
    final bool queryHas24 = qTokens.contains('24') || qTokens.contains('24s');
    final bool queryHas7 = qTokens.contains('7') || qTokens.contains('7s');
    final bool queryHas215 = qTokens.contains('215') || qTokens.contains('215g') || qTokens.contains('215gr');

    final bool queryHasMbg = cleanQ.contains('mbg') || qTokens.contains('mbg');

    CustomerProductHistory? bestMatch;
    int maxScore = 0;

    for (var h in historyList) {
      final hName = h.productName.toLowerCase();
      final bool hIsMbg = hName.contains('mbg') || h.productId.toLowerCase().contains('mbg');
      // STRICT GUARD: If customer did not type "mbg", never match MBG variants!
      if (!queryHasMbg && hIsMbg) continue;
      if (queryHasMbg && !hIsMbg) continue;
      final hTokens = hName.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').split(RegExp(r'\s+')).toSet();
      int score = 0;

      for (var qw in qTokens) {
        if (hTokens.contains(qw)) {
          score += 10;
        } else {
          final normQ = qw
              .replaceAll('ll', 'l')
              .replaceAll('bratwust', 'bratwurst')
              .replaceAll('coctail', 'cocktail')
              .replaceAll('koktail', 'cocktail');
          bool normMatched = false;
          for (var hw in hTokens) {
            final normH = hw
                .replaceAll('ll', 'l')
                .replaceAll('bratwust', 'bratwurst')
                .replaceAll('coctail', 'cocktail')
                .replaceAll('koktail', 'cocktail');
            if (normQ == normH) {
              score += 8;
              normMatched = true;
              break;
            }
          }
          if (!normMatched) {
            if ((qw == '24' && hTokens.contains('24s')) ||
                (qw == '13' && hTokens.contains('13s')) ||
                (qw == '7' && hTokens.contains('7s')) ||
                (qw == '24s' && hTokens.contains('24')) ||
                (qw == '13s' && hTokens.contains('13')) ||
                (qw == '7s' && hTokens.contains('7'))) {
              score += 10;
              normMatched = true;
            }
          }
          if (!normMatched && hName.contains(qw)) {
            // Do not give substring bonus if qw is 'roll'/'rol' inside 'rollade'/'rolade'
            if (!((qw == 'roll' || qw == 'rol') && (hName.contains('rollade') || hName.contains('rolade')) && !hTokens.contains(qw))) {
              score += 2;
            }
          }
        }
      }

      // Domain Bonuses:
      // A. "Beres" / "Beras" matches "BRS"
      if (queryHasBeres && (hTokens.contains('brs') || hName.contains('brs'))) {
        score += 20;
      }

      // B. "Merah" vs "Coklat" vs "Sapi" vs "Ayam"
      if (queryHasMerah) {
        if (hTokens.contains('merah') || hName.contains('merah')) {
          score += 25;
        } else if (hTokens.contains('coklat') || hName.contains('coklat')) {
          score -= 25;
        }
      }
      if (queryHasCoklat) {
        if (hTokens.contains('coklat') || hName.contains('coklat')) {
          score += 25;
        } else if (hTokens.contains('merah') || hName.contains('merah')) {
          score -= 25;
        }
      }
      if (queryHasSapi) {
        if (hTokens.contains('sapi') || hName.contains('sapi')) {
          score += 35;
        } else if (hTokens.contains('coklat') || hName.contains('coklat')) {
          // In Fiva Beres, "sapi" is "BRS COKLAT"
          score += 40;
        } else if (hTokens.contains('merah') || hName.contains('merah')) {
          // "sapi" must never match BRS MERAH
          score -= 40;
        }
        if (hTokens.contains('ayam') || hName.contains('ayam')) {
          score -= 30;
        }
      }
      if (queryHasAyam) {
        if (hTokens.contains('ayam') || hName.contains('ayam')) {
          score += 35;
        }
        if (hTokens.contains('sapi') || hName.contains('sapi')) {
          score -= 30;
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

      // D. "ROLL" variant vs 1000g / Non-Roll
      // Crucial: check isolated word tokens / boundaries, NEVER hName.contains('roll') because "rollade" contains "roll"!
      final bool hIsRoll = hTokens.contains('roll') ||
          hTokens.contains('rol') ||
          RegExp(r'\b(roll|rol)s?\b', caseSensitive: false).hasMatch(hName);
      final bool hIs1000 = hName.contains('1000') ||
          hName.contains('1kg') ||
          hTokens.contains('1000') ||
          hTokens.contains('1kg') ||
          hName.contains('1 kg');

      if (queryHasRoll) {
        if (hIsRoll) {
          score += 50; // Decisive bonus for true ROLL variant
        } else {
          score -= 50; // Severe penalty for non-roll when ROLL was requested
        }
        if (hIs1000) {
          score -= 80; // Heavy penalty for picking 1000g block when ROLL was requested
        }
      } else {
        // Query did NOT specify roll: penalize roll variants
        if (hIsRoll) {
          score -= 50;
        }
      }

      // E. "POLOS" variant (polos is NEVER roll)
      if (queryHasPolos) {
        if (hIsRoll) {
          score -= 60;
        }
      }

      // F. "LOYANG" variant
      if (queryHasLoyang) {
        if (hTokens.contains('loyang') || hTokens.contains('lyg') || hName.contains('loyang')) {
          score += 25;
        }
      }

      // G. 1000g vs smaller (250g, 400g, 500g, roll)
      if (queryHas1000) {
        if (hIs1000) {
          score += 40;
        } else {
          score -= 60; // Strongly avoid matching 250g/400g/500g/roll when customer explicitly asked for 1 kg / 1000g
        }
      }

      // Prefer Induk 24 over 24S when 's' was not explicitly typed in chat (only for variants like BRS MERAH that have both)
      // Never penalize BRS COKLAT 24S because 24S is its only 24 variant!
      if (queryHas24 && !cleanQ.contains('24s') && hName.contains('24s') && !hName.contains('coklat')) {
        score -= 10;
      }

      // G. Preference for order frequency & H. Recency preference:
      // ONLY reward frequency and recency IF there was an actual positive text match!
      // If there is zero text match (score <= 0), this product is unrelated to the query.
      if (score > 0) {
        score += (h.purchaseCount.clamp(1, 5) * 2);

        if (h.date != null) {
          final daysAgo = DateTime.now().difference(h.date!).inDays;
          if (daysAgo <= 30) {
            score += 6;
          } else if (daysAgo <= 90) {
            score += 3;
          }
        }
      }

      if (score > maxScore) {
        maxScore = score;
        bestMatch = h;
      } else if (score == maxScore && bestMatch != null && h.date != null) {
        // Tie-breaker: prefer the more recent invoice
        if (bestMatch.date == null || h.date!.isAfter(bestMatch.date!)) {
          bestMatch = h;
        }
      }
    }

    return maxScore >= 12 ? bestMatch : null;
  }

  /// Finds a product variant in customer history that belongs to the same product family
  /// (e.g. "BRS MERAH 24 500G" <-> "BRS MERAH 24S 500G", or "BRS COKLAT 24S 500 G" <-> "BRS COKLAT 24S 2 500G")
  CustomerProductHistory? _findFamilyVariantInHistory(
    Product targetProd,
    List<CustomerProductHistory> historyList,
  ) {
    if (historyList.isEmpty) return null;

    final targetName = targetProd.name.toLowerCase();
    final targetClean = targetName.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    final targetWords = targetClean.split(RegExp(r'\s+')).where((w) => w.length >= 2).toSet();

    final bool isBeres = targetWords.contains('brs') || targetWords.contains('beres');
    final bool isMerah = targetWords.contains('merah');
    final bool isCoklat = targetWords.contains('coklat');
    final bool isSapi = targetWords.contains('sapi') || targetWords.contains('sp');
    final bool isAyam = targetWords.contains('ayam') || targetWords.contains('ay');
    final bool isRoll = targetWords.contains('roll') || targetWords.contains('rol');
    final bool is1000 = targetWords.contains('1000') || targetWords.contains('1kg');

    CustomerProductHistory? bestMatch;
    int maxScore = 0;

    for (var h in historyList) {
      final hName = h.productName.toLowerCase();
      final hClean = hName.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
      final hWords = hClean.split(RegExp(r'\s+')).where((w) => w.length >= 2).toSet();

      // Guard 1: Beres must match Beres
      final bool hIsBeres = hWords.contains('brs') || hWords.contains('beres');
      if (isBeres != hIsBeres) continue;

      // Guard 2: Merah vs Coklat must never mix
      final bool hIsMerah = hWords.contains('merah');
      final bool hIsCoklat = hWords.contains('coklat');
      if (isMerah && !hIsMerah) continue;
      if (isCoklat && !hIsCoklat) continue;

      // Guard 3: Sapi vs Ayam must never mix
      final bool hIsSapi = hWords.contains('sapi') || hWords.contains('sp');
      final bool hIsAyam = hWords.contains('ayam') || hWords.contains('ay');
      if (isSapi && !hIsSapi) continue;
      if (isAyam && !hIsAyam) continue;

      // Guard 4: Roll vs 1000g must never mix
      final bool hIsRoll = hWords.contains('roll') || hWords.contains('rol');
      final bool hIs1000 = hWords.contains('1000') || hWords.contains('1kg');
      if (isRoll != hIsRoll) continue;
      if (is1000 != hIs1000) continue;

      // Guard 5: Count/pack sizes (24/24s, 13/13s, 7/7s)
      final bool targetHas24 = targetWords.contains('24') || targetWords.contains('24s');
      final bool hHas24 = hWords.contains('24') || hWords.contains('24s');
      if (targetHas24 != hHas24) continue;

      final bool targetHas13 = targetWords.contains('13') || targetWords.contains('13s');
      final bool hHas13 = hWords.contains('13') || hWords.contains('13s');
      if (targetHas13 != hHas13) continue;

      final bool targetHas7 = targetWords.contains('7') || targetWords.contains('7s');
      final bool hHas7 = hWords.contains('7') || hWords.contains('7s');
      if (targetHas7 != hHas7) continue;

      // Calculate similarity score
      int score = 0;
      for (var tw in targetWords) {
        if (hWords.contains(tw)) {
          score += 10;
        } else if ((tw == '24' && hWords.contains('24s')) ||
            (tw == '24s' && hWords.contains('24')) ||
            (tw == '13' && hWords.contains('13s')) ||
            (tw == '13s' && hWords.contains('13')) ||
            (tw == '7' && hWords.contains('7s')) ||
            (tw == '7s' && hWords.contains('7'))) {
          score += 15;
        }
      }

      // Bonus for recent invoice
      if (h.date != null) {
        final days = DateTime.now().difference(h.date!).inDays;
        if (days <= 30) score += 5;
      }

      if (score > maxScore) {
        maxScore = score;
        bestMatch = h;
      }
    }

    return maxScore >= 20 ? bestMatch : null;
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
    final bool queryHas1000 = qWords.contains('1000') ||
        qWords.contains('1kg') ||
        cleanQ.contains('1 kg') ||
        cleanQ.contains('1kg') ||
        cleanQ.contains('1000g') ||
        cleanQ.contains('1000 g') ||
        cleanQ.contains('1000gr') ||
        cleanQ.contains('1000 gr');
    final bool queryHasPolos = qWords.contains('polos');
    final bool queryHasBeres = qWords.contains('beres') || qWords.contains('beras') || qWords.contains('brs');
    final bool queryHasMerah = qWords.contains('merah');
    final bool queryHasCoklat = qWords.contains('coklat') || qWords.contains('cklt');
    final bool queryHasSapi = qWords.contains('sapi') || qWords.contains('sp');
    final bool queryHasAyam = qWords.contains('ayam') || qWords.contains('ay');
    final bool queryHas13 = qWords.contains('13') || qWords.contains('13s');
    final bool queryHas24 = qWords.contains('24') || qWords.contains('24s');
    final bool queryHas7 = qWords.contains('7') || qWords.contains('7s');
    final bool queryHas215 = qWords.contains('215') || qWords.contains('215g') || qWords.contains('215gr');

    final bool queryHasMbg = cleanQ.contains('mbg') || qWords.contains('mbg');

    Product? bestProduct;
    int maxScore = 0;

    for (var p in products) {
      final pName = p.name.toLowerCase();
      final bool pIsMbg = pName.contains('mbg') || p.kodeInduk.toLowerCase().contains('mbg');
      // STRICT GUARD: If customer did not type "mbg", never match MBG variants!
      if (!queryHasMbg && pIsMbg) continue;
      if (queryHasMbg && !pIsMbg) continue;
      final pWords = pName.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').split(RegExp(r'\s+')).toSet();
      int score = 0;

      for (var qw in qWords) {
        // Whole-word match
        if (pWords.contains(qw)) {
          score += 10;
        } else {
          // Normalize spelling (e.g. rolade == rollade, bratwust == bratwurst, coctail == cocktail)
          final normQ = qw
              .replaceAll('ll', 'l')
              .replaceAll('bratwust', 'bratwurst')
              .replaceAll('coctail', 'cocktail')
              .replaceAll('koktail', 'cocktail');
          bool normMatched = false;
          for (var pw in pWords) {
            final normP = pw
                .replaceAll('ll', 'l')
                .replaceAll('bratwust', 'bratwurst')
                .replaceAll('coctail', 'cocktail')
                .replaceAll('koktail', 'cocktail');
            if (normQ == normP) {
              score += 8;
              normMatched = true;
              break;
            }
          }
          if (!normMatched) {
            if ((qw == '24' && pWords.contains('24s')) ||
                (qw == '13' && pWords.contains('13s')) ||
                (qw == '7' && pWords.contains('7s')) ||
                (qw == '24s' && pWords.contains('24')) ||
                (qw == '13s' && pWords.contains('13')) ||
                (qw == '7s' && pWords.contains('7'))) {
              score += 10;
              normMatched = true;
            }
          }
          // Substring match only if no whole word matched
          if (!normMatched && pName.contains(qw)) {
            // Do not give substring bonus if qw is 'roll'/'rol' inside 'rollade'/'rolade'
            if (!((qw == 'roll' || qw == 'rol') && (pName.contains('rollade') || pName.contains('rolade')) && !pWords.contains(qw))) {
              score += 2;
            }
          }
        }
      }

      // Keyword differentiators:
      // A. "Beres" / "Beras" matches "BRS"
      if (queryHasBeres && (pWords.contains('brs') || pName.contains('brs'))) {
        score += 20;
      }

      // B. "Merah" vs "Coklat" vs "Sapi" vs "Ayam"
      if (queryHasMerah) {
        if (pWords.contains('merah') || pName.contains('merah')) {
          score += 25;
        } else if (pWords.contains('coklat') || pName.contains('coklat')) {
          score -= 25;
        }
      }
      if (queryHasCoklat) {
        if (pWords.contains('coklat') || pName.contains('coklat')) {
          score += 25;
        } else if (pWords.contains('merah') || pName.contains('merah')) {
          score -= 25;
        }
      }
      if (queryHasSapi) {
        if (pWords.contains('sapi') || pName.contains('sapi')) {
          score += 35;
        } else if (pWords.contains('coklat') || pName.contains('coklat')) {
          // In Fiva Beres, "sapi" is "BRS COKLAT"
          score += 40;
        } else if (pWords.contains('merah') || pName.contains('merah')) {
          // "sapi" must never match BRS MERAH
          score -= 40;
        }
        if (pWords.contains('ayam') || pName.contains('ayam')) {
          score -= 30;
        }
      }
      if (queryHasAyam) {
        if (pWords.contains('ayam') || pName.contains('ayam')) {
          score += 35;
        }
        if (pWords.contains('sapi') || pName.contains('sapi')) {
          score -= 30;
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

      // D. "ROLL" variant vs 1000g / Non-Roll
      // Crucial: check isolated word tokens / boundaries, NEVER pName.contains('roll') because "rollade" contains "roll"!
      final bool pIsRoll = pWords.contains('roll') ||
          pWords.contains('rol') ||
          RegExp(r'\b(roll|rol)s?\b', caseSensitive: false).hasMatch(pName);
      final bool pIs1000 = pName.contains('1000') ||
          pName.contains('1kg') ||
          pWords.contains('1000') ||
          pWords.contains('1kg') ||
          pName.contains('1 kg');

      if (queryHasRoll) {
        if (pIsRoll) {
          score += 50; // Decisive bonus for true ROLL variant
        } else {
          score -= 50; // Penalty for non-roll when ROLL was requested
        }
        if (pIs1000) {
          score -= 80; // Heavy penalty for picking 1000g when ROLL is requested
        }
      } else {
        if (pIsRoll) {
          score -= 50; // Penalty for roll variant when ROLL was not requested
        }
      }

      // E. "POLOS" variant (polos is NEVER roll)
      if (queryHasPolos) {
        if (pIsRoll) {
          score -= 60;
        }
      }

      // F. "LOYANG" variant
      if (queryHasLoyang) {
        if (pWords.contains('loyang') || pWords.contains('lyg') || pName.contains('loyang')) {
          score += 25;
        }
      }

      // G. 1000g vs smaller (250g, 400g, 500g, roll)
      if (queryHas1000) {
        if (pIs1000) {
          score += 40;
        } else {
          score -= 60;
        }
      }

      // Prefer Induk 24 over 24S when 's' was not explicitly typed in chat (only for variants like BRS MERAH that have both)
      // Never penalize BRS COKLAT 24S because 24S is its only 24 variant!
      if (queryHas24 && !cleanQ.contains('24s') && pName.contains('24s') && !pName.contains('coklat')) {
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
  String? _applyBonusRules({
    required List<ChatOrderItemDraft> draftItems,
    required List<AiKnowledgeRule> bonusRules,
    required String customerName,
    String aliasName = '',
    String rawCustomerName = '',
    required List<Product> products,
  }) {
    if (bonusRules.isEmpty || draftItems.isEmpty) return null;

    final cleanCust = customerName.trim().toLowerCase();
    final cleanAlias = aliasName.trim().toLowerCase();
    final cleanRaw = rawCustomerName.trim().toLowerCase();
    final combinedCust = '$cleanCust $cleanAlias $cleanRaw'.trim();
    final bonusItemsToAdd = <ChatOrderItemDraft>[];
    String? bonusNote;

    for (var rule in bonusRules) {
      // Parse rule keyword: "CUSTOMER|PRODUCT|MIN_QTY"
      final keyParts = rule.keyword.split('|');
      if (keyParts.length < 3) continue;

      final ruleCust = keyParts[0].trim().toLowerCase();
      final ruleProd = keyParts[1].trim().toLowerCase();
      final ruleMinQty = double.tryParse(keyParts[2].trim()) ?? 0;

      // Check if customer matches (either via customerName, aliasName, or rawCustomerName)
      final bool custMatches = combinedCust.contains(ruleCust) ||
          (cleanCust.isNotEmpty && ruleCust.contains(cleanCust)) ||
          (cleanAlias.isNotEmpty && ruleCust.contains(cleanAlias)) ||
          (cleanRaw.isNotEmpty && ruleCust.contains(cleanRaw));

      if (!custMatches) continue;

      // Parse rule mappedValue: "BONUS_PRODUCT|BONUS_QTY|BONUS_UNIT"
      final valParts = rule.mappedValue.split('|');
      if (valParts.length < 3) continue;

      final bonusProdName = valParts[0].trim();
      final bonusQty = double.tryParse(valParts[1].trim()) ?? 1;
      final bonusUnit = valParts[2].trim().toLowerCase();

      // Sum karton qty for the matching product in draftItems
      double totalKartonForProduct = 0;
      ChatOrderItemDraft? matchedItem;
      final ruleProdClean = ruleProd.replaceAll(RegExp(r'\s+'), '').toLowerCase();

      for (var item in draftItems) {
        final itemProdClean = item.productName.replaceAll(RegExp(r'\s+'), '').toLowerCase();
        final bool isProdMatch = itemProdClean.contains(ruleProdClean) ||
            ruleProdClean.contains(itemProdClean) ||
            (ruleProdClean.contains('kornet') && ruleProdClean.contains('loyang') && itemProdClean.contains('kornet') && itemProdClean.contains('loyang'));

        if (isProdMatch) {
          final unitLower = item.qtyUnit.toLowerCase().trim();
          if (unitLower == 'karton' || unitLower == 'ktn' || unitLower == 'k') {
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
          productName: bonusProduct.name,
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

        // Format specific note if LG FF
        if (combinedCust.contains('lg ff') || combinedCust.contains('wimbo')) {
          final qtyKtnStr = calculatedBonusQty % 1 == 0 ? calculatedBonusQty.toInt().toString() : calculatedBonusQty.toString();
          bonusNote = 'NOTE : BONUS $qtyKtnStr KARTON KORNET AYAM @400 G';
        }
      }
    }

    draftItems.addAll(bonusItemsToAdd);
    return bonusNote;
  }

  bool _isInstructionOrScheduleLine(String line) {
    final lower = line.toLowerCase().trim();
    if (lower.isEmpty) return false;

    return lower.startsWith('masuk erp') ||
        lower.startsWith('erp ') ||
        lower.contains('masuk erp') ||
        lower.startsWith('krm ') ||
        lower.startsWith('kirim ') ||
        lower.startsWith('kirimkan ') ||
        lower.startsWith('pengiriman ') ||
        lower.startsWith('jadwal ') ||
        lower.startsWith('catatan') ||
        lower.startsWith('nb:') ||
        lower.startsWith('note') ||
        lower.startsWith('ket:') ||
        lower.startsWith('keterangan') ||
        lower.contains('bsk pagi') ||
        lower.contains('besok pagi') ||
        lower.contains('bsk pg') ||
        lower.startsWith('titip ') ||
        lower.startsWith('faktur ') ||
        lower.startsWith('nota ');
  }

  bool _isIgnoredLine(String line) {
    final lower = line.toLowerCase().trim();
    if (_isInstructionOrScheduleLine(line)) return true;
    return lower.startsWith('waalaikumsalam') ||
        lower.startsWith('assalamualaikum') ||
        lower.startsWith('pagi ') ||
        lower.startsWith('siang ') ||
        lower.startsWith('sore ') ||
        lower.startsWith('senin') ||
        lower.startsWith('selasa') ||
        lower.startsWith('rabu') ||
        lower.startsWith('kamis') ||
        lower.startsWith('jumat') ||
        lower.startsWith('sabtu') ||
        lower.startsWith('minggu') ||
        lower.startsWith('diteruskan') ||
        RegExp(r'^\[?\d{1,2}[\.:]\d{2}\]?$').hasMatch(lower); // timestamp e.g. 17.04 or 07.30
  }

  String _detectCityFromText(String text) {
    final lower = text.toLowerCase();

    // Plat K (Kudus, Jepara, Pati, Rembang, Blora)
    if (lower.contains('blora')) return 'BLORA';
    if (lower.contains('rembang')) return 'REMBANG';
    if (lower.contains('jepara')) return 'JEPARA';
    if (lower.contains('kudus')) return 'KUDUS';
    if (lower.contains('pati')) return 'PATI';

    // Plat AD (Solo / Surakarta, Sragen, Karanganyar, Klaten, Boyolali, Colomadu, Banjarsari)
    if (lower.contains('surakarta') || lower.contains('solo')) return 'SURAKARTA';
    if (lower.contains('sragen')) return 'SRAGEN';
    if (lower.contains('karanganyar')) return 'KARANGANYAR';
    if (lower.contains('klaten')) return 'KLATEN';
    if (lower.contains('boyolali')) return 'BOYOLALI';
    if (lower.contains('colomadu')) return 'COLOMADU';
    if (lower.contains('banjarsari')) return 'BANJARSARI';

    // Plat H (Semarang, Demak, Kendal, Salatiga, Grobogan, Purwodadi, Gubug)
    if (lower.contains('purwodadi')) return 'PURWODADI';
    if (lower.contains('grobogan')) return 'GROBOGAN';
    if (lower.contains('gubug')) return 'GUBUG';
    if (lower.contains('salatiga')) return 'SALATIGA';
    if (lower.contains('kendal')) return 'KENDAL';
    if (lower.contains('demak')) return 'DEMAK';
    if (lower.contains('semarang')) return 'SEMARANG';

    // Plat AA (Wonosobo, Magelang, Temanggung, Purworejo, Kebumen)
    if (lower.contains('wonosobo')) return 'WONOSOBO';
    if (lower.contains('temanggung')) return 'TEMANGGUNG';
    if (lower.contains('purworejo')) return 'PURWOREJO';
    if (lower.contains('kebumen')) return 'KEBUMEN';
    if (lower.contains('magelang')) return 'MAGELANG';

    // Plat G (Pekalongan, Batang, Pemalang, Tegal, Brebes)
    if (lower.contains('pekalongan')) return 'PEKALONGAN';
    if (lower.contains('batang')) return 'BATANG';
    if (lower.contains('pemalang')) return 'PEMALANG';
    if (lower.contains('tegal')) return 'TEGAL';
    if (lower.contains('brebes')) return 'BREBES';

    // Plat R (Banyumas, Purwokerto, Purbalingga, Banjarnegara, Cilacap)
    if (lower.contains('purwokerto') || lower.contains('banyumas')) return 'BANYUMAS';
    if (lower.contains('purbalingga')) return 'PURBALINGGA';
    if (lower.contains('banjarnegara')) return 'BANJARNEGARA';
    if (lower.contains('cilacap')) return 'CILACAP';

    // Plat AB (Yogyakarta, Sleman, Bantul, Kulonprogo, Gunungkidul, Wates)
    if (lower.contains('yogyakarta') || lower.contains('jogja')) return 'YOGYAKARTA';
    if (lower.contains('sleman')) return 'SLEMAN';
    if (lower.contains('bantul')) return 'BANTUL';
    if (lower.contains('kulonprogo') || lower.contains('kulon progo')) return 'KULONPROGO';
    if (lower.contains('gunungkidul') || lower.contains('gunung kidul')) return 'GUNUNGKIDUL';
    if (lower.contains('wates')) return 'WATES';

    return '';
  }
}

class _CustomerResolution {
  final Customer? customer;
  final String rawName;
  final int headerLineCount;
  final int? customerLineIndex;

  _CustomerResolution({
    required this.customer,
    required this.rawName,
    required this.headerLineCount,
    this.customerLineIndex,
  });
}

class _QtyUnitResolution {
  final double qty;
  final String unit;
  final String cleanedText;
  final bool hadExplicitQty;

  _QtyUnitResolution({
    required this.qty,
    required this.unit,
    required this.cleanedText,
    this.hadExplicitQty = false,
  });
}
