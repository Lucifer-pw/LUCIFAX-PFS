import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/operational_invoice.dart';
import '../models/operational_category.dart';
import '../models/operational_payment_method.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../services/operational_invoice_pdf_service.dart';

class OperationalInvoiceView extends StatefulWidget {
  const OperationalInvoiceView({super.key});

  @override
  State<OperationalInvoiceView> createState() => _OperationalInvoiceViewState();
}

class _ItemRowData {
  final TextEditingController titleController;
  final TextEditingController amountController;
  final TextEditingController noteController;
  String category;

  _ItemRowData({
    String title = '',
    String amount = '',
    String note = '',
    this.category = 'Maintenance & Upgrade Server (Firebase / Cloud)',
  })  : titleController = TextEditingController(text: title),
        amountController = TextEditingController(text: amount),
        noteController = TextEditingController(text: note);

  void dispose() {
    titleController.dispose();
    amountController.dispose();
    noteController.dispose();
  }
}

class _OperationalInvoiceViewState extends State<OperationalInvoiceView> {
  final FirebaseService _firebaseService = FirebaseService();
  final currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  String _searchQuery = '';
  String _selectedCategoryFilter = 'SEMUA';

  final List<String> _defaultCategories = [
    'Maintenance & Upgrade Server (Firebase / Cloud)',
    'Pengembangan & Biaya Program (App Dev)',
    'Domain & Cloud Infrastructure',
    'Biaya Operasional Maintenance Rutin',
    'Lainnya',
  ];

  final List<String> _defaultPaymentMethods = [
    'DANA / E-Wallet',
    'Transfer Bank (BCA/Mandiri)',
    'Kas / Cash',
    'Lainnya',
  ];

  @override
  void initState() {
    super.initState();
    // Seed default categories & payment methods to Firestore if empty
    _firebaseService.seedDefaultOperationalCategoriesIfEmpty();
    _firebaseService.seedDefaultOperationalPaymentMethodsIfEmpty();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;

    // Security Gate: Developer Role Only
    if (user == null || !user.isDeveloper) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, color: Colors.redAccent, size: 48),
                SizedBox(height: 16),
                Text(
                  'Akses Terbatas (Developer Only)',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Halaman pembuat invoice tagihan operasional ini khusus untuk Role Developer.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header & Title
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'LUCIFAX Operational Billing',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Resi Klaim Operasional (Multi-Item)',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _showManageCategoriesDialog(context),
                            icon: const Icon(Icons.category_rounded, color: Color(0xFF38BDF8), size: 14),
                            label: const Text('Kategori', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _showManagePaymentMethodsDialog(context),
                            icon: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF38BDF8), size: 14),
                            label: const Text('Metode Bayar', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _showCreateInvoiceDialog(context, user.name.isNotEmpty ? user.name : user.username),
                            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                            label: const Text('Buat Invoice', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF118EEA),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'LUCIFAX Operational Billing',
                                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Sistem pencatatan & cetak resi klaim operasional resmi LUCIFAX PFS (Multi-Item & Dynamic Master)',
                                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),

                      Row(
                        children: [
                          // Button Kelola Kategori
                          OutlinedButton.icon(
                            onPressed: () => _showManageCategoriesDialog(context),
                            icon: const Icon(Icons.category_rounded, color: Color(0xFF38BDF8), size: 16),
                            label: const Text('Kelola Kategori', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Button Kelola Metode Bayar
                          OutlinedButton.icon(
                            onPressed: () => _showManagePaymentMethodsDialog(context),
                            icon: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF38BDF8), size: 16),
                            label: const Text('Kelola Metode Bayar', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Button Buat Invoice Operasional
                          ElevatedButton.icon(
                            onPressed: () => _showCreateInvoiceDialog(context, user.name.isNotEmpty ? user.name : user.username),
                            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                            label: const Text('Buat Invoice Operasional', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF118EEA),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

            SizedBox(height: isMobile ? 10 : 20),

            // Search & Category Filter Bar
            StreamBuilder<List<OperationalCategory>>(
              stream: _firebaseService.streamOperationalCategories(),
              builder: (context, catSnap) {
                final customCats = (catSnap.data ?? []).map((c) => c.name).toList();
                final allCats = customCats.isNotEmpty ? customCats : _defaultCategories;

                return isMobile
                    ? Column(
                        children: [
                          TextField(
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Cari invoice, rincian item, atau nominal...',
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF118EEA), size: 16),
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF334155)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF334155)),
                              ),
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedCategoryFilter,
                                dropdownColor: const Color(0xFF1E293B),
                                isExpanded: true,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                items: ['SEMUA', ...allCats].map((cat) {
                                  return DropdownMenuItem<String>(
                                    value: cat,
                                    child: Text(cat == 'SEMUA' ? 'Semua Kategori' : cat),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedCategoryFilter = val);
                                },
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: TextField(
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Cari invoice, rincian item, atau nominal...',
                                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF118EEA), size: 18),
                                filled: true,
                                fillColor: const Color(0xFF1E293B),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF334155)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF334155)),
                                ),
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedCategoryFilter,
                                dropdownColor: const Color(0xFF1E293B),
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                items: ['SEMUA', ...allCats].map((cat) {
                                  return DropdownMenuItem<String>(
                                    value: cat,
                                    child: Text(cat == 'SEMUA' ? 'Semua Kategori' : cat),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedCategoryFilter = val);
                                },
                              ),
                            ),
                          ),
                        ],
                      );
              },
            ),

            SizedBox(height: isMobile ? 10 : 20),

            // Invoices List Stream
            Expanded(
              child: StreamBuilder<List<OperationalInvoice>>(
                stream: _firebaseService.streamOperationalInvoices(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                    );
                  }

                  final invoices = snapshot.data ?? [];

                  // Apply search & category filter
                  final filtered = invoices.where((inv) {
                    final matchesSearch = inv.invoiceNo.toLowerCase().contains(_searchQuery) ||
                        inv.amount.toString().contains(_searchQuery) ||
                        inv.items.any((item) =>
                            item.title.toLowerCase().contains(_searchQuery) ||
                            item.category.toLowerCase().contains(_searchQuery) ||
                            item.note.toLowerCase().contains(_searchQuery));

                    final matchesCat = _selectedCategoryFilter == 'SEMUA' ||
                        inv.items.any((item) => item.category == _selectedCategoryFilter);

                    return matchesSearch && matchesCat;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
                          const SizedBox(height: 12),
                          const Text(
                            'Belum ada invoice operasional.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Klik tombol "Buat Invoice Operasional" di atas untuk membuat resi tagihan baru.',
                            style: TextStyle(color: Color(0xFF475569), fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final inv = filtered[index];
                      return _buildInvoiceCard(context, inv, isMobile);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(BuildContext context, OperationalInvoice inv, bool isMobile) {
    if (isMobile) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Resi + Badges + Popup Menu
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF118EEA).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF118EEA), size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Resi: #${inv.invoiceNo}',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (inv.items.length > 1) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF0EA5E9), width: 0.8),
                    ),
                    child: Text(
                      '${inv.items.length} Item',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 9),
                    ),
                  ),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (inv.status == 'LUNAS' ? Colors.teal : Colors.amber).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: inv.status == 'LUNAS' ? Colors.teal : Colors.amber, width: 0.8),
                  ),
                  child: Text(
                    inv.status,
                    style: TextStyle(
                      color: inv.status == 'LUNAS' ? Colors.tealAccent : Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF38BDF8), size: 20),
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onSelected: (value) {
                    switch (value) {
                      case 'view':
                        _showLucifaxReceiptModal(context, inv);
                        break;
                      case 'edit':
                        _showCreateInvoiceDialog(context, inv.createdBy, inv);
                        break;
                      case 'delete':
                        _confirmDeleteInvoice(context, inv.id);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'view',
                      child: Row(
                        children: [
                          Icon(Icons.receipt_rounded, color: Color(0xFF38BDF8), size: 16),
                          SizedBox(width: 8),
                          Text('Lihat / Cetak Resi', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, color: Colors.amberAccent, size: 16),
                          SizedBox(width: 8),
                          Text('Edit Invoice', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                          SizedBox(width: 8),
                          Text('Hapus Invoice', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Title
            Text(
              inv.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Bottom Row: Date & Total Amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('dd MMM yyyy, HH:mm').format(inv.date),
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                ),
                Text(
                  currencyFormatter.format(inv.amount),
                  style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF118EEA).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF118EEA), size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                inv.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (inv.items.length > 1) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF0EA5E9), width: 0.8),
                ),
                child: Text(
                  '${inv.items.length} Item',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (inv.status == 'LUNAS' ? Colors.teal : Colors.amber).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: inv.status == 'LUNAS' ? Colors.teal : Colors.amber, width: 0.8),
              ),
              child: Text(
                inv.status,
                style: TextStyle(
                  color: inv.status == 'LUNAS' ? Colors.tealAccent : Colors.amberAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Text(
                'Resi: #${inv.invoiceNo}',
                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Text(
                DateFormat('dd MMM yyyy, HH:mm').format(inv.date),
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  inv.items.map((i) => i.category).toSet().join(', '),
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currencyFormatter.format(inv.amount),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF38BDF8)),
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                switch (value) {
                  case 'view':
                    _showLucifaxReceiptModal(context, inv);
                    break;
                  case 'edit':
                    _showCreateInvoiceDialog(context, inv.createdBy, inv);
                    break;
                  case 'delete':
                    _confirmDeleteInvoice(context, inv.id);
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility_rounded, color: Color(0xFF38BDF8), size: 18), SizedBox(width: 10), Text('Lihat Resi', style: TextStyle(color: Colors.white))])),
                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, color: Color(0xFF38BDF8), size: 18), SizedBox(width: 10), Text('Edit Invoice', style: TextStyle(color: Colors.white))])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18), SizedBox(width: 10), Text('Hapus Invoice', style: TextStyle(color: Colors.redAccent))])),
              ],
            ),
          ],
        ),
        onTap: () => _showLucifaxReceiptModal(context, inv),
      ),
    );
  }

  // ==========================================
  // CREATE INVOICE DIALOG (CLEAN VERTICAL FORM MATCHING GAMBAR 1)
  // ==========================================
  void _showCreateInvoiceDialog(BuildContext context, String currentUserName, [OperationalInvoice? existingInv]) {
    final String autoInvoiceNo = existingInv?.invoiceNo ?? 'DEV-OP-${DateFormat('yyyyMMdd').format(DateTime.now())}-${(DateTime.now().millisecondsSinceEpoch % 1000).toString().padLeft(3, '0')}';
    final invoiceNoController = TextEditingController(text: autoInvoiceNo);

    final List<_ItemRowData> itemRows = existingInv != null && existingInv.items.isNotEmpty
        ? existingInv.items.map((item) {
            final row = _ItemRowData(category: item.category.isNotEmpty ? item.category : _defaultCategories[0]);
            row.titleController.text = item.title;
            row.amountController.text = item.amount > 0 ? item.amount.toInt().toString() : '';
            row.noteController.text = item.note;
            return row;
          }).toList()
        : [_ItemRowData()];

    String selectedStatus = existingInv?.status ?? 'LUNAS';
    String selectedPaymentMethod = existingInv?.paymentMethod ?? _defaultPaymentMethods[0];
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StreamBuilder<List<OperationalCategory>>(
          stream: _firebaseService.streamOperationalCategories(),
          builder: (context, catSnap) {
            return StreamBuilder<List<OperationalPaymentMethod>>(
              stream: _firebaseService.streamOperationalPaymentMethods(),
              builder: (context, paySnap) {
                final categoryObjects = catSnap.data ?? [];
                final categoryMap = {for (var c in categoryObjects) c.name: c};

                final customCats = categoryObjects.map((c) => c.name).toList();
                final categoriesList = customCats.isNotEmpty ? customCats : _defaultCategories;

                final customPays = (paySnap.data ?? []).map((p) => p.name).toList();
                final paymentMethodsList = customPays.isNotEmpty ? customPays : _defaultPaymentMethods;

                if (!paymentMethodsList.contains(selectedPaymentMethod)) {
                  selectedPaymentMethod = paymentMethodsList.first;
                }

                for (var row in itemRows) {
                  if (row.category.isNotEmpty && !categoriesList.contains(row.category)) {
                    // Only reset if category is truly empty/invalid AND we have real Firestore data
                    // Don't reset categories loaded from existing invoice items
                    if (catSnap.hasData && catSnap.data!.isNotEmpty) {
                      // Category was deleted from master data, reset to first
                      row.category = categoriesList.first;
                    }
                    // If stream hasn't loaded yet (catSnap.data is null/empty), keep existing value
                  } else if (row.category.isEmpty) {
                    row.category = categoriesList.first;
                  }
                }

                return StatefulBuilder(
                  builder: (context, setDialogState) {
                    double calculateGrandTotal() {
                      double sum = 0.0;
                      for (var row in itemRows) {
                        final val = double.tryParse(row.amountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                        sum += val;
                      }
                      return sum;
                    }

                    return AlertDialog(
                      backgroundColor: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.receipt_long_rounded, color: Color(0xFF118EEA), size: 20),
                              const SizedBox(width: 10),
                              Text(existingInv == null ? 'Buat Invoice Tagihan Operasional (Dev)' : 'Edit Invoice Operasional #${existingInv.invoiceNo}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                            onPressed: () => Navigator.pop(dialogCtx),
                          ),
                        ],
                      ),
                      content: SizedBox(
                        width: 650,
                        height: 580,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. Nomor Invoice / Resi
                              const Text('Nomor Invoice / Resi', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: invoiceNoController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // 2. Row: Metode Pembayaran & Status Invoice
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Metode Pembayaran', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F172A),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              isExpanded: true,
                                              value: selectedPaymentMethod,
                                              dropdownColor: const Color(0xFF1E293B),
                                              style: const TextStyle(color: Colors.white, fontSize: 13),
                                              items: paymentMethodsList.map((method) {
                                                return DropdownMenuItem<String>(
                                                  value: method,
                                                  child: Text(method, overflow: TextOverflow.ellipsis),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                if (val != null) setDialogState(() => selectedPaymentMethod = val);
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Status Invoice', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F172A),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              isExpanded: true,
                                              value: selectedStatus,
                                              dropdownColor: const Color(0xFF1E293B),
                                              style: const TextStyle(color: Colors.white, fontSize: 13),
                                              items: const [
                                                DropdownMenuItem(value: 'LUNAS', child: Text('LUNAS')),
                                                DropdownMenuItem(value: 'PENDING', child: Text('PENDING')),
                                              ],
                                              onChanged: (val) {
                                                if (val != null) setDialogState(() => selectedStatus = val);
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),
                              const Divider(color: Color(0xFF334155), height: 1),
                              const SizedBox(height: 16),

                              // Header Section Rincian Item Tagihan
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'RINCIAN ITEM TAGIHAN:',
                                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      setDialogState(() {
                                        final firstCatName = categoriesList.first;
                                        final newRow = _ItemRowData(category: firstCatName);
                                        final firstCatObj = categoryMap[firstCatName];
                                        if (firstCatObj != null) {
                                          if (newRow.titleController.text.trim().isEmpty) {
                                            newRow.titleController.text = firstCatObj.name;
                                          }
                                          if (firstCatObj.defaultAmount > 0) {
                                            newRow.amountController.text = firstCatObj.defaultAmount.toInt().toString();
                                          }
                                        }
                                        itemRows.add(newRow);
                                      });
                                    },
                                    icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF38BDF8), size: 18),
                                    label: const Text('+ Tambah Item', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Item Rows
                              ...List.generate(itemRows.length, (idx) {
                                final row = itemRows[idx];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(16),
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
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF334155),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Rincian Item #${idx + 1}',
                                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          if (itemRows.length > 1)
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              tooltip: 'Hapus Item Ini',
                                              onPressed: () {
                                                setDialogState(() {
                                                  row.dispose();
                                                  itemRows.removeAt(idx);
                                                });
                                              },
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Keterangan / Judul Tagihan
                                      const Text('Keterangan / Judul Tagihan *', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: row.titleController,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'Contoh : Biaya Operasional Server & Hosting',
                                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                          filled: true,
                                          fillColor: const Color(0xFF1E293B),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Nominal Tagihan (Rp) *
                                      const Text('Nominal Tagihan (Rp) *', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: row.amountController,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 14, fontWeight: FontWeight.bold),
                                        onChanged: (_) => setDialogState(() {}),
                                        decoration: InputDecoration(
                                          prefixText: 'Rp ',
                                          prefixStyle: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                                          hintText: '200000',
                                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                          filled: true,
                                          fillColor: const Color(0xFF1E293B),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Kategori Dropdown
                                      const Text('Kategori', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            isExpanded: true,
                                            value: row.category,
                                            dropdownColor: const Color(0xFF1E293B),
                                            style: const TextStyle(color: Colors.white, fontSize: 13),
                                            items: categoriesList.map((cat) {
                                              return DropdownMenuItem<String>(
                                                value: cat,
                                                child: Text(cat, overflow: TextOverflow.ellipsis),
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) {
                                                setDialogState(() {
                                                  row.category = val;
                                                  final catObj = categoryMap[val];
                                                  if (catObj != null) {
                                                    if (row.titleController.text.trim().isEmpty) {
                                                      row.titleController.text = catObj.name;
                                                    }
                                                    if (catObj.defaultAmount > 0) {
                                                      row.amountController.text = catObj.defaultAmount.toInt().toString();
                                                    }
                                                  }
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Catatan / Rincian Tambahan
                                      const Text('Catatan / Rincian Tambahan (Opsional)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: row.noteController,
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                        decoration: InputDecoration(
                                          hintText: 'Misal : Pembayaran Langganan Maintenance (Pay as You go)',
                                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                          filled: true,
                                          fillColor: const Color(0xFF1E293B),
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),

                              const SizedBox(height: 10),

                              // Total Netto Display Box
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('TOTAL NETTO TAGIHAN:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text(
                                      currencyFormatter.format(calculateGrandTotal()),
                                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            for (var r in itemRows) {
                              r.dispose();
                            }
                            Navigator.pop(dialogCtx);
                          },
                          child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF118EEA),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final invNo = invoiceNoController.text.trim();

                                  List<OperationalInvoiceItem> parsedInvoiceItems = [];
                                  for (var row in itemRows) {
                                    final title = row.titleController.text.trim();
                                    final amt = double.tryParse(row.amountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                                    final note = row.noteController.text.trim();

                                    if (title.isNotEmpty && amt > 0) {
                                      parsedInvoiceItems.add(
                                        OperationalInvoiceItem(
                                          title: title,
                                          category: row.category,
                                          amount: amt,
                                          note: note,
                                        ),
                                      );
                                    }
                                  }

                                  if (invNo.isEmpty || parsedInvoiceItems.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Lengkapi minimal 1 item dengan Deskripsi dan Nominal yang valid!'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                    return;
                                  }

                                  setDialogState(() => isSaving = true);

                                  final newInvoice = OperationalInvoice(
                                    id: existingInv?.id ?? '',
                                    invoiceNo: invNo,
                                    items: parsedInvoiceItems,
                                    date: existingInv?.date ?? DateTime.now(),
                                    status: selectedStatus,
                                    paymentMethod: selectedPaymentMethod,
                                    createdBy: existingInv?.createdBy ?? currentUserName,
                                    createdAt: existingInv?.createdAt ?? DateTime.now(),
                                  );

                                  try {
                                    await _firebaseService.saveOperationalInvoice(newInvoice);
                                    if (mounted) {
                                      for (var r in itemRows) {
                                        r.dispose();
                                      }
                                      Navigator.pop(dialogCtx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(existingInv == null
                                              ? '🎉 Resi Invoice Operasional #${newInvoice.invoiceNo} berhasil disimpan!'
                                              : '🎉 Resi Invoice Operasional #${newInvoice.invoiceNo} berhasil diperbarui!'),
                                          backgroundColor: Colors.teal,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    setDialogState(() => isSaving = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Gagal menyimpan invoice: $e'), backgroundColor: Colors.redAccent),
                                      );
                                    }
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Simpan Invoice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================
  // MANAGE CATEGORIES DIALOG (DYNAMIC MASTER CRUD)
  // ==========================================
  void _showManageCategoriesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.category_rounded, color: Color(0xFF38BDF8), size: 22),
                SizedBox(width: 10),
                Text('Kelola Kategori Operasional', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF38BDF8)),
              tooltip: 'Tambah Kategori Baru',
              onPressed: () => _showAddEditCategoryModal(context),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 400,
          child: StreamBuilder<List<OperationalCategory>>(
            stream: _firebaseService.streamOperationalCategories(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)));
              }

              final categories = snapshot.data ?? [];

              if (categories.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.category_outlined, color: Color(0xFF475569), size: 48),
                      const SizedBox(height: 12),
                      const Text('Belum ada kategori', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                      const SizedBox(height: 8),
                      const Text('Tambah manual atau isi data default', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Text('Isi Kategori Default', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF38BDF8),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await _firebaseService.seedDefaultOperationalCategoriesIfEmpty();
                        },
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: categories.length,
                itemBuilder: (context, idx) {
                  final cat = categories[idx];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(cat.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (cat.description.isNotEmpty)
                            Text(cat.description, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                          if (cat.defaultAmount > 0)
                            Text('Nominal Default: ${currencyFormatter.format(cat.defaultAmount)}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8)),
                        color: const Color(0xFF1E293B),
                        onSelected: (val) {
                          if (val == 'edit') {
                            _showAddEditCategoryModal(context, cat);
                          } else if (val == 'delete') {
                            _firebaseService.deleteOperationalCategory(cat.id);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 18),
                                SizedBox(width: 10),
                                Text('Edit', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                SizedBox(width: 10),
                                Text('Hapus', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
        ],
      ),
    );
  }

  void _showAddEditCategoryModal(BuildContext context, [OperationalCategory? cat]) {
    final nameCtrl = TextEditingController(text: cat?.name ?? '');
    final descCtrl = TextEditingController(text: cat?.description ?? '');
    final amountCtrl = TextEditingController(
      text: cat != null && cat.defaultAmount > 0 
          ? cat.defaultAmount.toInt().toString() 
          : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(cat == null ? 'Tambah Kategori Baru' : 'Edit Kategori', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nama Kategori *', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            const SizedBox(height: 4),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Misal: Lisensi Software',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Nominal Default (Rp) (Opsional)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            const SizedBox(height: 4),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'Rp ',
                prefixStyle: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                hintText: 'Misal: 200000',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Deskripsi (Opsional)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            const SizedBox(height: 4),
            TextField(
              controller: descCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Catatan pengelompokan...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final parsedAmount = double.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
              final newCat = OperationalCategory(
                id: cat?.id ?? '',
                name: name,
                description: descCtrl.text.trim(),
                defaultAmount: parsedAmount,
              );
              await _firebaseService.saveOperationalCategory(newCat);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MANAGE PAYMENT METHODS DIALOG (DYNAMIC MASTER CRUD)
  // ==========================================
  void _showManagePaymentMethodsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF38BDF8), size: 22),
                SizedBox(width: 10),
                Text('Kelola Metode Pembayaran', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF38BDF8)),
              tooltip: 'Tambah Metode Bayar Baru',
              onPressed: () => _showAddEditPaymentMethodModal(context),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 400,
          child: StreamBuilder<List<OperationalPaymentMethod>>(
            stream: _firebaseService.streamOperationalPaymentMethods(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)));
              }

              final methods = snapshot.data ?? [];

              if (methods.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF475569), size: 48),
                      const SizedBox(height: 12),
                      const Text('Belum ada metode pembayaran', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                      const SizedBox(height: 8),
                      const Text('Tambah manual atau isi data default', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Text('Isi Metode Bayar Default', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF38BDF8),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await _firebaseService.seedDefaultOperationalPaymentMethodsIfEmpty();
                        },
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: methods.length,
                itemBuilder: (context, idx) {
                  final m = methods[idx];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: m.description.isNotEmpty ? Text(m.description, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)) : null,
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8)),
                        color: const Color(0xFF1E293B),
                        onSelected: (val) {
                          if (val == 'edit') {
                            _showAddEditPaymentMethodModal(context, m);
                          } else if (val == 'delete') {
                            _firebaseService.deleteOperationalPaymentMethod(m.id);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 18),
                                SizedBox(width: 10),
                                Text('Edit', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                SizedBox(width: 10),
                                Text('Hapus', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
        ],
      ),
    );
  }

  void _showAddEditPaymentMethodModal(BuildContext context, [OperationalPaymentMethod? method]) {
    final nameCtrl = TextEditingController(text: method?.name ?? '');
    final descCtrl = TextEditingController(text: method?.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(method == null ? 'Tambah Metode Pembayaran' : 'Edit Metode Pembayaran', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nama Metode Pembayaran *', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            const SizedBox(height: 4),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Misal: Kartu Kredit Corporate',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Deskripsi (Opsional)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            const SizedBox(height: 4),
            TextField(
              controller: descCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Misal: Rekening BCA 1234xxxx',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final newMethod = OperationalPaymentMethod(
                id: method?.id ?? '',
                name: name,
                description: descCtrl.text.trim(),
              );
              await _firebaseService.saveOperationalPaymentMethod(newMethod);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // RECEIPT MODAL & PRINT SELECTION
  // ==========================================
  void _showLucifaxReceiptModal(BuildContext context, OperationalInvoice inv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF38BDF8), size: 24),
                const SizedBox(width: 10),
                Text('Resi Invoice #${inv.invoiceNo}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('PT PUTRA FIVA SEJAHTERA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(inv.status, style: TextStyle(color: inv.status == 'LUNAS' ? Colors.tealAccent : Colors.amberAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Tanggal: ${DateFormat('dd MMMM yyyy, HH:mm').format(inv.date)}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                          Text('Metode: ${inv.paymentMethod}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Table of Multi-Items
                const Text('RINCIAN TAGIHAN OPERASIONAL:', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FixedColumnWidth(30),
                      1: FlexColumnWidth(3),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(2),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFF1E293B)),
                        children: [
                          _buildTableHead('NO'),
                          _buildTableHead('DESKRIPSI'),
                          _buildTableHead('KATEGORI'),
                          _buildTableHead('JUMLAH'),
                        ],
                      ),
                      ...List.generate(inv.items.length, (idx) {
                        final item = inv.items[idx];
                        return TableRow(
                          children: [
                            _buildTableCellText('${idx + 1}', align: TextAlign.center),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                  if (item.note.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(item.note, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                                  ],
                                ],
                              ),
                            ),
                            _buildTableCellText(item.category),
                            _buildTableCellText(currencyFormatter.format(item.amount), align: TextAlign.right, isBold: true, color: const Color(0xFF38BDF8)),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Total Netto Box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL NETTO INVOICE:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(
                        currencyFormatter.format(inv.amount),
                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // Edit Invoice Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () {
              Navigator.pop(ctx);
              _showCreateInvoiceDialog(context, inv.createdBy, inv);
            },
            icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 16),
            label: const Text('Edit Invoice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          // Cetak & Download Menu
          PopupMenuButton<String>(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) async {
              final dateStr = DateFormat('dd_MM_yyyy').format(inv.date);
              switch (value) {
                case 'download_pt':
                  final pdfBytes = await OperationalInvoicePdfService.generatePdf(inv);
                  final filename = 'Invoice_Operasional_$dateStr.pdf';
                  await Printing.sharePdf(bytes: pdfBytes, filename: filename);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('PDF $filename berhasil di-download!'), backgroundColor: Colors.teal),
                    );
                  }
                  break;
                case 'download_dana':
                  final pdfBytes2 = await OperationalInvoicePdfService.generateDanaStylePdf(inv);
                  final filename2 = 'Resi_Dana_$dateStr.pdf';
                  await Printing.sharePdf(bytes: pdfBytes2, filename: filename2);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('PDF $filename2 berhasil di-download!'), backgroundColor: Colors.teal),
                    );
                  }
                  break;
                case 'download_faktur':
                  final pdfBytes3 = await OperationalInvoicePdfService.generateFakturPajakStylePdf(inv);
                  final filename3 = 'Faktur_Pajak_$dateStr.pdf';
                  await Printing.sharePdf(bytes: pdfBytes3, filename: filename3);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('PDF $filename3 berhasil di-download!'), backgroundColor: Colors.teal),
                    );
                  }
                  break;
                case 'cetak_pt':
                  final pdfBytes = await OperationalInvoicePdfService.generatePdf(inv);
                  SystemChrome.setApplicationSwitcherDescription(
                    ApplicationSwitcherDescription(label: 'Invoice_Operasional_$dateStr'),
                  );
                  await Printing.layoutPdf(onLayout: (_) => pdfBytes, name: 'Invoice_Operasional_$dateStr.pdf');
                  break;
                case 'cetak_dana':
                  final pdfBytes2 = await OperationalInvoicePdfService.generateDanaStylePdf(inv);
                  SystemChrome.setApplicationSwitcherDescription(
                    ApplicationSwitcherDescription(label: 'Resi_Dana_$dateStr'),
                  );
                  await Printing.layoutPdf(onLayout: (_) => pdfBytes2, name: 'Resi_Dana_$dateStr.pdf');
                  break;
                case 'cetak_faktur':
                  final pdfBytes3 = await OperationalInvoicePdfService.generateFakturPajakStylePdf(inv);
                  SystemChrome.setApplicationSwitcherDescription(
                    ApplicationSwitcherDescription(label: 'Faktur_Pajak_$dateStr'),
                  );
                  await Printing.layoutPdf(onLayout: (_) => pdfBytes3, name: 'Faktur_Pajak_$dateStr.pdf');
                  break;
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF118EEA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text('Download / Cetak', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 18),
                ],
              ),
            ),
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'download_pt',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18),
                    SizedBox(width: 10),
                    Text('Download PDF (Format PT)', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'download_dana',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, color: Color(0xFF38BDF8), size: 18),
                    SizedBox(width: 10),
                    Text('Download PDF (Resi DANA)', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'download_faktur',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, color: Colors.amberAccent, size: 18),
                    SizedBox(width: 10),
                    Text('Download PDF (Faktur Pajak)', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'cetak_pt',
                child: Row(
                  children: [
                    Icon(Icons.print_rounded, color: Color(0xFF0284C7), size: 18),
                    SizedBox(width: 10),
                    Text('Cetak Format PT', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'cetak_dana',
                child: Row(
                  children: [
                    Icon(Icons.receipt_rounded, color: Color(0xFF118EEA), size: 18),
                    SizedBox(width: 10),
                    Text('Cetak Resi DANA', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'cetak_faktur',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF94A3B8), size: 18),
                    SizedBox(width: 10),
                    Text('Cetak Faktur Pajak', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableHead(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(text, style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _buildTableCellText(String text, {TextAlign align = TextAlign.left, bool isBold = false, Color color = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 11),
      ),
    );
  }

  void _confirmDeleteInvoice(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hapus Invoice Operasional', style: TextStyle(color: Colors.white)),
        content: const Text('Apakah Anda yakin ingin menghapus invoice operasional ini?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await _firebaseService.deleteOperationalInvoice(id);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
