import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/ai_knowledge_rule.dart';
import '../providers/product_provider.dart';
import '../providers/customer_provider.dart';
import '../services/firebase_service.dart';

class AiKnowledgeView extends StatefulWidget {
  const AiKnowledgeView({super.key});

  @override
  State<AiKnowledgeView> createState() => _AiKnowledgeViewState();
}

class _AiKnowledgeViewState extends State<AiKnowledgeView> {
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _generalInstructionsController = TextEditingController();

  String _selectedFilter = 'all'; // 'all', 'customer_alias', 'product_alias', 'unit', 'bonus_rule'
  bool _isLoadingInstructions = true;
  bool _isSavingInstructions = false;

  @override
  void initState() {
    super.initState();
    _loadGeneralInstructions();
  }

  Future<void> _loadGeneralInstructions() async {
    final text = await _firebaseService.getAiGeneralInstructions();
    if (mounted) {
      setState(() {
        _generalInstructionsController.text = text.isNotEmpty
            ? text
            : '1. Angka dengan titik di awal (seperti 4., 5.) adalah nomor urut pesan, bukan jumlah pesanan.\n'
              '2. Satuan "k" atau "ktn" berarti Karton.\n'
              '3. Tanda titik dua seperti ": 1" berarti jumlah 1 Karton.\n'
              '4. Nama "Fiva" di awal nama barang diabaikan karena merupakan merk produk.';
        _isLoadingInstructions = false;
      });
    }
  }

  Future<void> _saveGeneralInstructions() async {
    setState(() => _isSavingInstructions = true);
    await _firebaseService.saveAiGeneralInstructions(_generalInstructionsController.text.trim());
    if (mounted) {
      setState(() => _isSavingInstructions = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Catatan aturan umum AI berhasil disimpan!'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  Future<void> _seedDefaultRules() async {
    final defaultRules = [
      AiKnowledgeRule(id: '', type: 'unit', keyword: 'k', mappedValue: '1 Karton', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'unit', keyword: 'ktn', mappedValue: '1 Karton', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'unit', keyword: 'dus', mappedValue: '1 Karton', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'unit', keyword: 'box', mappedValue: '1 Karton', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'unit', keyword: ': 1', mappedValue: '1 Karton', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'unit', keyword: ': 2', mappedValue: '2 Karton', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'unit', keyword: 'roll', mappedValue: '1 Pack', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'unit', keyword: 'pack', mappedValue: '1 Pack', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'unit', keyword: 'pcs', mappedValue: '1 Pack', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'customer_alias', keyword: 'LG FF', mappedValue: 'LG FF (WIMBO WIEK KUSTANTO)', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'customer_alias', keyword: 'LG FF WONOSOBO', mappedValue: 'LG FF (WIMBO WIEK KUSTANTO)', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'customer_alias', keyword: 'KK FF', mappedValue: 'KK FF WONOSOBO', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'customer_alias', keyword: 'KK FF WONOSOBO', mappedValue: 'KK FF WONOSOBO', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'customer_alias', keyword: 'MMM', mappedValue: 'MAJU MARKET MANDIRI', targetId: '0002', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'customer_alias', keyword: 'ANIZA FF', mappedValue: 'ANIZA FF KENDAL', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'customer_alias', keyword: 'ANIZA FF KENDAL', mappedValue: 'ANIZA FF KENDAL', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'customer_alias', keyword: 'Pak Nardi', mappedValue: 'NARDI FF (NARDI)', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'product_alias', keyword: 'ROLADE SAPI ROLL', mappedValue: 'ROLLADE SAPI ROLL 400 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'product_alias', keyword: 'KORNET AYAM LOYANG', mappedValue: 'KORNET AYAM LOYANG 400 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'product_alias', keyword: 'Beres merah 24', mappedValue: 'BRS MERAH 24 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'product_alias', keyword: 'Beres merah', mappedValue: 'BRS MERAH 24 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'product_alias', keyword: 'Beres sosis merah', mappedValue: 'BRS MERAH 24 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'product_alias', keyword: 'Beres sapi 13', mappedValue: 'BRS COKLAT 13S 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'product_alias', keyword: 'Beres sapi 24', mappedValue: 'BRS COKLAT 24S 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'product_alias', keyword: 'Beres coklat 24', mappedValue: 'BRS COKLAT 24S 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: '', type: 'product_alias', keyword: 'Rolade polos 1 kg', mappedValue: 'ROLLADE AYAM 1000 G ( MBG )', createdAt: DateTime.now()),
      // Bonus / Promo Rules
      AiKnowledgeRule(id: '', type: 'bonus_rule', keyword: 'LG FF|KORNET AYAM LOYANG 400 G|40', mappedValue: 'KORNET AYAM LOYANG 400 G|1|karton', createdAt: DateTime.now()),
    ];

    for (var r in defaultRules) {
      await _firebaseService.saveAiKnowledgeRule(r);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌱 Berhasil memuat 27 aturan kamus standar ke database!'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _generalInstructionsController.dispose();
    super.dispose();
  }

  void _showAddEditRuleDialog([AiKnowledgeRule? existingRule]) {
    final isEdit = existingRule != null;
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    String ruleType = existingRule?.type ?? 'product_alias';
    final keywordController = TextEditingController(text: existingRule?.keyword ?? '');
    final mappedValueController = TextEditingController(text: existingRule?.mappedValue ?? '');
    String? selectedTargetId = existingRule?.targetId;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(
                  isEdit ? Icons.edit_note_rounded : Icons.auto_awesome_rounded,
                  color: const Color(0xFF38BDF8),
                ),
                const SizedBox(width: 10),
                Text(
                  isEdit ? 'Edit Pengetahuan AI' : 'Tambah Pengetahuan Baru ke AI',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Kategori Ilmu:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ruleType,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF0F172A),
                          items: const [
                            DropdownMenuItem(value: 'product_alias', child: Text('Panggilan / Singkatan Barang', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'customer_alias', child: Text('Panggilan / Singkatan Toko', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'unit', child: Text('Aturan Satuan Kuantiti (Karton/Pack/Roll)', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'bonus_rule', child: Text('Aturan Bonus / Promo Otomatis', style: TextStyle(color: Colors.white))),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                ruleType = val;
                                selectedTargetId = null;
                                mappedValueController.clear();
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Keyword field
                    Text(
                      ruleType == 'bonus_rule'
                          ? 'Syarat Bonus (Format: Toko|Nama Barang|Min Karton):'
                          : ruleType == 'unit'
                              ? 'Istilah Satuan di Chat (e.g. "k", "roll", ": 1"):'
                              : 'Kata / Singkatan di Chat Pak BC:',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: keywordController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        hintText: ruleType == 'bonus_rule'
                            ? 'Contoh: LG FF|KORNET AYAM LOYANG 400 G|40'
                            : ruleType == 'customer_alias'
                                ? 'Contoh: MMM, LG FF'
                                : ruleType == 'product_alias'
                                    ? 'Contoh: Beres merah 24, Rolade polos 1 kg'
                                    : 'Contoh: k, ktn, roll, : 1',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Mapped Target Selection
                    if (ruleType == 'product_alias') ...[
                      const Text('Pilih Barang Asli di Master Barang:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedTargetId,
                            hint: const Text('Pilih Produk...', style: TextStyle(color: Color(0xFF64748B))),
                            isExpanded: true,
                            dropdownColor: const Color(0xFF0F172A),
                            items: productProvider.products.map((p) {
                              return DropdownMenuItem<String>(
                                value: p.id,
                                child: Text('${p.name} (${p.kodeInduk})', style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (pId) {
                              if (pId != null) {
                                final p = productProvider.products.firstWhere((item) => item.id == pId);
                                setDialogState(() {
                                  selectedTargetId = pId;
                                  mappedValueController.text = p.name;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ] else if (ruleType == 'customer_alias') ...[
                      const Text('Pilih Toko Asli di Master Pelanggan:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedTargetId,
                            hint: const Text('Pilih Pelanggan...', style: TextStyle(color: Color(0xFF64748B))),
                            isExpanded: true,
                            dropdownColor: const Color(0xFF0F172A),
                            items: customerProvider.customers.map((c) {
                              return DropdownMenuItem<String>(
                                value: c.id,
                                child: Text(c.aliasName.isNotEmpty ? '${c.customerName} (${c.aliasName})' : c.customerName, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (cId) {
                              if (cId != null) {
                                final c = customerProvider.customers.firstWhere((item) => item.id == cId);
                                setDialogState(() {
                                  selectedTargetId = cId;
                                  mappedValueController.text = c.customerName;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ] else if (ruleType == 'bonus_rule') ...[
                      const Text('Hadiah Bonus (Format: Barang Bonus|Jumlah|Satuan):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: mappedValueController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          hintText: 'Contoh: KORNET AYAM LOYANG 400 G|1|karton',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.pinkAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.pinkAccent.withOpacity(0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.pinkAccent, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Bonus otomatis berlaku KELIPATAN (misal beli 40 ktn dapat 1 ktn, 80 ktn dapat 2 ktn, 120 ktn dapat 3 ktn) dengan harga Rp 0.',
                                style: TextStyle(color: Colors.pinkAccent, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const Text('Artinya di Sistem (Karton / Pack):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: mappedValueController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          hintText: 'Contoh: Karton, 1 Pack',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final keyword = keywordController.text.trim();
                  final mappedVal = mappedValueController.text.trim();

                  if (keyword.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Harap masukkan kata kunci chat!'), backgroundColor: Colors.orange),
                    );
                    return;
                  }

                  if (mappedVal.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Harap tentukan target arti sistem!'), backgroundColor: Colors.orange),
                    );
                    return;
                  }

                  final newRule = AiKnowledgeRule(
                    id: existingRule?.id ?? '',
                    type: ruleType,
                    keyword: keyword,
                    mappedValue: mappedVal,
                    targetId: selectedTargetId,
                    createdAt: existingRule?.createdAt ?? DateTime.now(),
                    updatedBy: 'developer',
                  );

                  await _firebaseService.saveAiKnowledgeRule(newRule);
                  if (context.mounted) {
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isEdit ? 'Aturan berhasil diubah!' : 'Ilmu baru berhasil diajarkan ke AI!'),
                        backgroundColor: Colors.teal,
                      ),
                    );
                  }
                },
                child: Text(isEdit ? 'Simpan Perubahan' : 'Ajarkan ke AI', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteRule(AiKnowledgeRule rule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Aturan AI', style: TextStyle(color: Colors.white)),
        content: Text('Hapus aturan kata "${rule.keyword}"? AI tidak akan menggunakan aturan ini lagi.', style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await _firebaseService.deleteAiKnowledgeRule(rule.id);
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Aturan dihapus dari ingatan AI.'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.psychology_rounded, color: Color(0xFF38BDF8), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Pusat Pengetahuan & Kamus AI', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 3),
                        Text('Kelola kamus istilah, singkatan toko, dan aturan slang chat Pak BC (Khusus Developer)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.tealAccent,
                        side: const BorderSide(color: Colors.teal),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _seedDefaultRules,
                      icon: const Icon(Icons.grass_rounded, size: 16),
                      label: const Text('Muat Kamus Standar', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _showAddEditRuleDialog(),
                      icon: const Icon(Icons.add_rounded, color: Colors.white),
                      label: const Text('Tambah Ilmu Baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Top Quick Filter & Search Bar
            Row(
              children: [
                _buildFilterChip('all', 'Semua'),
                const SizedBox(width: 8),
                _buildFilterChip('customer_alias', 'Singkatan Toko'),
                const SizedBox(width: 8),
                _buildFilterChip('product_alias', 'Singkatan Barang'),
                const SizedBox(width: 8),
                _buildFilterChip('unit', 'Satuan Kuantiti'),
                const SizedBox(width: 8),
                _buildFilterChip('bonus_rule', 'Bonus / Promo'),
                const Spacer(),
                SizedBox(
                  width: 280,
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Cari kata atau arti...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    ),
                    onChanged: (val) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Main Content: Knowledge Rules Table & General Prompt Instructions Side-by-Side or Stacked
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Table Column (Flex 7)
                  Expanded(
                    flex: 7,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: StreamBuilder<List<AiKnowledgeRule>>(
                        stream: _firebaseService.streamAiKnowledgeRules(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                          }

                          final allRules = snapshot.data ?? [];
                          final query = _searchController.text.trim().toLowerCase();

                          final filteredRules = allRules.where((r) {
                            if (_selectedFilter != 'all' && r.type != _selectedFilter) return false;
                            if (query.isNotEmpty) {
                              return r.keyword.toLowerCase().contains(query) ||
                                  r.mappedValue.toLowerCase().contains(query);
                            }
                            return true;
                          }).toList();

                          if (filteredRules.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.auto_stories_outlined, color: const Color(0xFF64748B).withOpacity(0.6), size: 48),
                                  const SizedBox(height: 10),
                                  const Text('Belum ada aturan kamus yang sesuai.', style: TextStyle(color: Color(0xFF94A3B8))),
                                  const SizedBox(height: 6),
                                  const Text('Klik tombol "Tambah Ilmu Baru" atau muat kamus standar di bawah.', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: _seedDefaultRules,
                                    icon: const Icon(Icons.grass_rounded, color: Colors.white, size: 16),
                                    label: const Text('🌱 Muat Kamus Standar Sekarang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                ],
                              ),
                            );
                          }

                          return SingleChildScrollView(
                            child: SizedBox(
                              width: double.infinity,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12),
                                dataRowMinHeight: 48,
                                dataRowMaxHeight: 52,
                                columns: const [
                                  DataColumn(label: Text('KATA DI CHAT')),
                                  DataColumn(label: Text('KATEGORI')),
                                  DataColumn(label: Text('ARTINYA DI SISTEM')),
                                  DataColumn(label: Text('TANGGAL')),
                                  DataColumn(label: Text('AKSI')),
                                ],
                                rows: filteredRules.map((rule) {
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(
                                          rule.keyword,
                                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                      DataCell(_buildTypeBadge(rule.type)),
                                      DataCell(
                                        Text(
                                          rule.mappedValue,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          DateFormat('dd-MM-yyyy').format(rule.createdAt),
                                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                        ),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, color: Color(0xFF38BDF8), size: 18),
                                              tooltip: 'Edit Aturan',
                                              onPressed: () => _showAddEditRuleDialog(rule),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                              tooltip: 'Hapus Aturan',
                                              onPressed: () => _deleteRule(rule),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // General Rules Panel (Flex 4)
                  Expanded(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.notes_rounded, color: Colors.amberAccent, size: 20),
                              SizedBox(width: 8),
                              Text('Catatan Aturan Bebas AI', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Instruksi bahasa manusia yang dibaca AI setiap kali menganalisa chat:',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _isLoadingInstructions
                                ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                                : TextField(
                                    controller: _generalInstructionsController,
                                    maxLines: null,
                                    expands: true,
                                    textAlignVertical: TextAlignVertical.top,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.5),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFF0F172A),
                                      hintText: 'Tulis aturan bebas di sini...',
                                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _isSavingInstructions ? null : _saveGeneralInstructions,
                              icon: _isSavingInstructions
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save_rounded, color: Colors.white, size: 18),
                              label: const Text('Simpan Aturan Bebas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    Color bg;
    Color fg;
    String text;

    switch (type) {
      case 'customer_alias':
        bg = Colors.greenAccent.withOpacity(0.15);
        fg = Colors.greenAccent;
        text = 'Toko';
        break;
      case 'product_alias':
        bg = const Color(0xFF38BDF8).withOpacity(0.15);
        fg = const Color(0xFF38BDF8);
        text = 'Barang';
        break;
      case 'unit':
        bg = Colors.amberAccent.withOpacity(0.15);
        fg = Colors.amberAccent;
        text = 'Satuan';
        break;
      case 'bonus_rule':
        bg = Colors.pinkAccent.withOpacity(0.15);
        fg = Colors.pinkAccent;
        text = 'Bonus / Promo';
        break;
      default:
        bg = Colors.purpleAccent.withOpacity(0.15);
        fg = Colors.purpleAccent;
        text = 'Aturan';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
