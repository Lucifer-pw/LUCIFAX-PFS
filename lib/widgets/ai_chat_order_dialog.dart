import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../models/transaction.dart' as model_tr;
import '../models/chat_order_draft.dart';
import '../models/ai_knowledge_rule.dart';
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../services/firebase_service.dart';
import '../services/ai_chat_parser_service.dart';

void showAiChatOrderDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _AiChatOrderDialogContent(),
  );
}

class _AiChatOrderDialogContent extends StatefulWidget {
  const _AiChatOrderDialogContent();

  @override
  State<_AiChatOrderDialogContent> createState() => _AiChatOrderDialogContentState();
}

class _AiChatOrderDialogContentState extends State<_AiChatOrderDialogContent> {
  final TextEditingController _chatInputController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();
  late final AiChatParserService _parserService;

  bool _isAnalyzing = false;
  bool _isSavingAll = false;
  List<ChatOrderDraft> _parsedDrafts = [];
  final NumberFormat _rupiahFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _parserService = AiChatParserService(_firebaseService);
  }

  @override
  void dispose() {
    _chatInputController.dispose();
    super.dispose();
  }

  Future<void> _analyzeChat() async {
    final text = _chatInputController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harap tempelkan teks chat WhatsApp terlebih dahulu!'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      final productProvider = Provider.of<ProductProvider>(context, listen: false);

      // Fetch knowledge rules & instructions (with resilient fallbacks)
      List<AiKnowledgeRule> rulesSnap = [];
      String generalInstructions = '';
      try {
        rulesSnap = await _firebaseService.streamAiKnowledgeRules().first.timeout(const Duration(seconds: 4));
      } catch (_) {
        rulesSnap = [];
      }

      try {
        generalInstructions = await _firebaseService.getAiGeneralInstructions().timeout(const Duration(seconds: 4));
      } catch (_) {
        generalInstructions = '';
      }

      final results = await _parserService.parseChatOrders(
        rawChat: text,
        customers: customerProvider.customers,
        products: productProvider.products,
        rules: rulesSnap,
        generalInstructions: generalInstructions,
      );

      setState(() {
        _parsedDrafts = results;
        _isAnalyzing = false;
      });

      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak ditemukan format pesanan dalam chat. Silakan periksa atau sesuaikan Kamus AI.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menganalisa chat: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _createTransactionFromDraft(ChatOrderDraft draft, int draftIndex) async {
        final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    // Validate customer
    Customer? targetCustomer;
    if (draft.customerId.isNotEmpty) {
      targetCustomer = customerProvider.customers.firstWhere(
        (c) => c.id == draft.customerId,
        orElse: () => Customer(
          id: '',
          customerName: draft.customerName,
          aliasName: draft.aliasName,
          address: '',
          city: draft.city,
          province: draft.province,
          country: 'INDONESIA',
          phone: '',
          ktpNumber: '',
        ),
      );
    } else {
      // Find by name
      targetCustomer = customerProvider.customers.firstWhere(
        (c) => c.customerName.toLowerCase() == draft.customerName.toLowerCase(),
        orElse: () => Customer(
          id: '',
          customerName: draft.customerName,
          aliasName: draft.aliasName,
          address: '',
          city: draft.city,
          province: draft.province,
          country: 'INDONESIA',
          phone: '',
          ktpNumber: '',
        ),
      );
    }

    if (draft.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daftar barang masih kosong untuk toko ini!'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      // Convert draft items to TransactionItem
      final trItems = draft.items.map((it) {
        return model_tr.TransactionItem(
          productId: it.productId,
          productName: it.productName,
          price: it.price,
          qty: it.qtyPcs,
          discountPercent: it.discountPercent,
          subtotal: it.subtotal,
          sizeGrams: it.sizeGrams,
          isBonus: it.isBonus,
        );
      }).toList();

      final grandTotal = draft.grandTotal;

      // Call createTransaction with named parameters (Status PENDING, UNPAID, stock NOT deducted)
      final createdTr = await _firebaseService.createTransaction(
        customerId: targetCustomer.id,
        customerName: targetCustomer.customerName,
        aliasName: targetCustomer.aliasName,
        deliveryDate: DateTime.now(),
        city: targetCustomer.city.isNotEmpty ? targetCustomer.city : 'SEMARANG',
        province: targetCustomer.province.isNotEmpty ? targetCustomer.province : 'JAWA TENGAH',
        country: 'INDONESIA',
        items: trItems,
        grandTotal: grandTotal,
        note: 'PO Otomatis dari Chat: ${draft.customerRawName}',
        createdBy: 'AI Chat Scanner',
      );
      final createdInvoiceNo = createdTr.invoiceNo;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ PO Toko ${draft.customerName} berhasil dibuat! (Invoice #$createdInvoiceNo - Status PENDING)'),
            backgroundColor: Colors.teal,
          ),
        );

        setState(() {
          _parsedDrafts.removeAt(draftIndex);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat transaksi: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _createAllTransactions() async {
    if (_parsedDrafts.isEmpty) return;
    setState(() => _isSavingAll = true);

    int successCount = 0;
    final List<ChatOrderDraft> copyDrafts = List.from(_parsedDrafts);

    for (int i = 0; i < copyDrafts.length; i++) {
      final draft = copyDrafts[i];
      try {
        await _createTransactionFromDraft(draft, 0);
        successCount++;
      } catch (e) {
        debugPrint('Error creating PO for ${draft.customerName}: $e');
      }
    }

    setState(() => _isSavingAll = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Berhasil membuat $successCount PO baru dengan status PENDING!'),
          backgroundColor: Colors.teal,
        ),
      );
      if (_parsedDrafts.isEmpty) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 32, vertical: 24),
      child: Container(
        width: 1020,
        height: MediaQuery.of(context).size.height * 0.88,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF38BDF8), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Scan Chat WhatsApp → Auto PO',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Otomatis mengenali toko, kuantiti (Karton/Pack/Roll), dan menarik harga nota terakhir',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Top Chat Input Box with Analyze Button
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tempel / Paste Chat WhatsApp Pak BC di Sini:',
                        style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      if (_chatInputController.text.isNotEmpty)
                        InkWell(
                          onTap: () => setState(() {
                            _chatInputController.clear();
                            _parsedDrafts.clear();
                          }),
                          child: const Text('Bersihkan Teks', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 86,
                    child: TextField(
                      controller: _chatInputController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
                      decoration: const InputDecoration(
                        hintText: 'Contoh:\nPak.. mau order dari MMM\n4. Fiva rolade sapi roll 400gr 11 ROLL\n5. Fiva beres sapi isi 13s 500gr 121 pack...',
                        hintStyle: TextStyle(color: Color(0xFF475569), fontSize: 11),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isAnalyzing ? null : _analyzeChat,
                        icon: _isAnalyzing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                        label: Text(
                          _isAnalyzing ? 'Menganalisa...' : 'Analisa & Pecah Chat Jadi PO',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Results Section Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Hasil Deteksi Draft PO:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_parsedDrafts.length} Toko Terdeteksi',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (_parsedDrafts.length > 1)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isSavingAll ? null : _createAllTransactions,
                    icon: _isSavingAll
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.done_all_rounded, color: Colors.white, size: 16),
                    label: const Text('Buat Semua PO Sekaligus (Status PENDING)', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Drafts List
            Expanded(
              child: _parsedDrafts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, color: const Color(0xFF64748B).withOpacity(0.5), size: 48),
                          const SizedBox(height: 8),
                          const Text(
                            'Belum ada draft PO.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tempelkan teks pesanan Pak BC pada kotak di atas, lalu klik "Analisa".',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _parsedDrafts.length,
                      itemBuilder: (context, index) {
                        final draft = _parsedDrafts[index];
                        return _buildDraftCard(draft, index);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftCard(ChatOrderDraft draft, int draftIndex) {
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card: Customer Selection & Quick Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.7),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.storefront_rounded, color: Color(0xFF38BDF8), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: draft.customerId.isNotEmpty ? draft.customerId : null,
                            hint: Text(
                              draft.customerName.isNotEmpty ? draft.customerName : draft.customerRawName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1E293B),
                              items: customerProvider.customers.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c.id,
                                  child: Text(
                                    '${c.customerName}${c.aliasName.isNotEmpty ? " (${c.aliasName})" : ""}${c.city.isNotEmpty ? " - ${c.city}" : ""} [${c.id}]',
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (newId) {
                                if (newId != null) {
                                  final selected = customerProvider.customers.firstWhere((item) => item.id == newId);
                                  setState(() {
                                    draft.customerId = selected.id;
                                    draft.customerName = selected.customerName;
                                    draft.aliasName = selected.aliasName;
                                    draft.city = selected.city;
                                    draft.province = selected.province;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        if (draft.customerId.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF38BDF8)),
                            ),
                            child: Text('ID: ${draft.customerId}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ] else ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amberAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amberAccent),
                            ),
                            child: const Text('⚠️ Belum Terdaftar', style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                        if (draft.city.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(4)),
                            child: Text(draft.city, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _createTransactionFromDraft(draft, draftIndex),
                  icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 16),
                  label: const Text('Buat PO Transaksi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
          ),

          // Items Table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.5), // Nama Barang
                    1: FlexColumnWidth(1.2), // Kuantiti Chat
                    2: FlexColumnWidth(1.2), // Total Pack
                    3: FlexColumnWidth(1.4), // Harga Unit (Histori)
                    4: FlexColumnWidth(1.4), // Subtotal
                  },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF334155)))),
                      children: const [
                        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('NAMA BARANG', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('QTY CHAT', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('TOTAL PACK', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('HARGA UNIT', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('SUBTOTAL', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                  ],
                ),
                ...draft.items.map((item) {
                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            if (item.isBonus)
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: Colors.pinkAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                child: const Text('🎁 BONUS OTOMATIS (Rp 0)', style: TextStyle(color: Colors.pinkAccent, fontSize: 9.5, fontWeight: FontWeight.bold)),
                              )
                            else if (item.isNewItemForCustomer)
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                child: const Text('⚠️ Barang Baru (Harga Master)', style: TextStyle(color: Colors.amberAccent, fontSize: 9.5)),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '${item.qtyInput % 1 == 0 ? item.qtyInput.toInt() : item.qtyInput} ${item.qtyUnit.toUpperCase()}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '${item.qtyPcs % 1 == 0 ? item.qtyPcs.toInt() : item.qtyPcs} Pack',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_rupiahFormatter.format(item.price), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            if (item.discountPercent > 0)
                              Text('Disc ${item.discountPercent}%', style: const TextStyle(color: Colors.greenAccent, fontSize: 10)),
                            if (item.discountAmount > 0)
                              Text('Pot. ${_rupiahFormatter.format(item.discountAmount)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 10)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          _rupiahFormatter.format(item.subtotal),
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ],
            ),
            const Divider(color: Color(0xFF334155)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${draft.items.length} Item Barang | Total: ${draft.totalKarton > 0 ? "${draft.totalKarton % 1 == 0 ? draft.totalKarton.toInt() : draft.totalKarton} Ktn" : "-"}',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                Text(
                  'Grand Total: ${_rupiahFormatter.format(draft.grandTotal)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  ),
);
}
}
