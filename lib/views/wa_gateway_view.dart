import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/incoming_po_chat.dart';
import '../models/wa_gateway_session.dart';
import '../models/wa_auto_po_settings.dart';
import '../models/ai_knowledge_rule.dart';
import '../models/customer.dart';
import '../models/transaction.dart' as model_tr;
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../services/firebase_service.dart';
import '../services/ai_chat_parser_service.dart';
import '../widgets/ai_chat_order_dialog.dart';

class WaGatewayView extends StatefulWidget {
  const WaGatewayView({super.key});

  @override
  State<WaGatewayView> createState() => _WaGatewayViewState();
}

class _WaGatewayViewState extends State<WaGatewayView> {
  bool _hidePhoneNumbers = false;

  @override
  void initState() {
    super.initState();
    _loadHidePhonePreference();
  }

  Future<void> _loadHidePhonePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _hidePhoneNumbers = prefs.getBool('pref_hide_wa_phone_numbers') ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleHidePhoneNumbers() async {
    setState(() {
      _hidePhoneNumbers = !_hidePhoneNumbers;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_hide_wa_phone_numbers', _hidePhoneNumbers);
    } catch (_) {}
  }

  String _maskPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '-';
    if (!_hidePhoneNumbers) return phone;
    String clean = phone.trim();
    bool hasPlus = clean.startsWith('+');
    if (hasPlus) clean = clean.substring(1);
    if (clean.length <= 6) return (hasPlus ? '+' : '') + '••••••';
    final prefix = clean.substring(0, clean.length >= 5 ? 5 : 3);
    final suffix = clean.substring(clean.length - 3);
    return '${hasPlus ? "+" : ""}$prefix•••••$suffix';
  }
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatusFilter = 'all'; // 'all', 'pending', 'processed', 'dismissed'
  final Set<String> _processingChatIds = {};
  bool _isProcessingBatch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openInAiScanner(IncomingPoChat chat) {
    showAiChatOrderDialog(context, initialChatText: chat.messageText);
    if (chat.status == 'pending') {
      _firebaseService.updateIncomingPoChatStatus(chat.id, 'processed');
    }
  }

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

  Future<void> _processSingleChatToPo(IncomingPoChat chat, {bool isAuto = false}) async {
    if (_isProcessingBatch && !isAuto) return;
    if (!isAuto) setState(() => _isProcessingBatch = true);

    try {
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      final parserService = AiChatParserService(_firebaseService);

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

      final drafts = await parserService.parseChatOrders(
        rawChat: chat.messageText,
        customers: customerProvider.customers,
        products: productProvider.products,
        rules: rulesSnap,
        generalInstructions: generalInstructions,
        senderPhone: chat.senderPhone,
      );

      // Validate: Must have at least 1 item with qty > 0
      if (drafts.isEmpty || drafts.first.items.isEmpty) {
        // Casual chat / non-order
        await _firebaseService.updateIncomingPoChatStatus(chat.id, 'dismissed');
        await FirebaseFirestore.instance.collection('incoming_po_chats').doc(chat.id).update({
          'dismissReason': 'BUKAN_ORDER',
        }).catchError((_) {});

        if (!isAuto && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pesan ini terdeteksi bukan format pesanan (status: DIABAIKAN).'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final List<String> createdInvoiceNos = [];
      final List<String> createdStoreNames = [];

      for (int dIdx = 0; dIdx < drafts.length; dIdx++) {
        final draft = drafts[dIdx];
        if (draft.items.isEmpty) continue;

        // Resolve or Auto-Register Customer for THIS draft
        Customer targetCustomer;
        if (draft.customerId.isNotEmpty) {
          targetCustomer = customerProvider.customers.firstWhere(
            (c) => c.id == draft.customerId,
            orElse: () => Customer(
              id: draft.customerId,
              customerName: draft.customerName,
              aliasName: draft.aliasName,
              address: '',
              city: draft.city,
              province: draft.province,
              country: 'INDONESIA',
              phone: chat.senderPhone,
              ktpNumber: '',
            ),
          );
        } else {
          // Fallback: Check if senderPhone matches any registered customer
          Customer? matchedByPhone;
          if (chat.senderPhone.isNotEmpty) {
            for (var c in customerProvider.customers) {
              if (c.phone.isNotEmpty && _phonesMatch(c.phone, chat.senderPhone)) {
                matchedByPhone = c;
                break;
              }
            }
          }

          if (matchedByPhone != null) {
            targetCustomer = matchedByPhone;
          } else {
            targetCustomer = customerProvider.customers.firstWhere(
              (c) => c.customerName.toLowerCase() == draft.customerName.toLowerCase() ||
                  (c.aliasName.isNotEmpty && c.aliasName.toLowerCase() == draft.customerName.toLowerCase()),
              orElse: () => Customer(
                id: '',
                customerName: draft.customerName,
                aliasName: draft.aliasName,
                address: '',
                city: draft.city.isNotEmpty ? draft.city : 'SEMARANG',
                province: draft.province.isNotEmpty ? draft.province : 'JAWA TENGAH',
                country: 'INDONESIA',
                phone: chat.senderPhone,
                ktpNumber: '',
              ),
            );
          }

          if (targetCustomer.id.isEmpty) {
            try {
              await customerProvider.saveCustomer(targetCustomer);
            } catch (_) {}
          }
        }

        // Convert items to TransactionItem
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

        // Create Transaction with user specified revised defaults:
        // statusDikirim: 'PENDING', statusTransfer: 'UNPAID', statusERP: ''
        final createdTr = await _firebaseService.createTransaction(
          customerId: targetCustomer.id,
          customerName: targetCustomer.customerName,
          aliasName: targetCustomer.aliasName,
          deliveryDate: DateTime.now(),
          city: targetCustomer.city.isNotEmpty ? targetCustomer.city : 'SEMARANG',
          province: targetCustomer.province.isNotEmpty ? targetCustomer.province : 'JAWA TENGAH',
          country: 'INDONESIA',
          items: trItems,
          grandTotal: draft.grandTotal,
          note: draft.note, // Kept empty unless bonus rule applies (e.g. NOTE : BONUS 1 KARTON...)
          createdBy: 'AI Auto-PO Gateway',
          idempotencyKey: 'wa_${chat.id}_$dIdx',
        );

        createdInvoiceNos.add(createdTr.invoiceNo);
        final displayName = targetCustomer.aliasName.isNotEmpty ? targetCustomer.aliasName : targetCustomer.customerName;
        createdStoreNames.add(displayName);
      }

      if (createdInvoiceNos.isEmpty) {
        return;
      }

      final allInvoicesStr = createdInvoiceNos.join(', ');

      // Update incoming_po_chats document
      await FirebaseFirestore.instance.collection('incoming_po_chats').doc(chat.id).update({
        'status': 'processed',
        'createdInvoiceNo': allInvoicesStr,
        'createdTransactionId': allInvoicesStr,
        'processedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${createdInvoiceNos.length} PO Berhasil Dibuat: ${createdStoreNames.join(' & ')} (Invoice #$allInvoicesStr)'),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing auto-PO: $e');
      if (!isAuto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat PO: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (!isAuto && mounted) setState(() => _isProcessingBatch = false);
    }
  }

  void _checkAndAutoProcess(List<IncomingPoChat> chats, bool autoPoEnabled) {
    if (!autoPoEnabled) return;
    for (var chat in chats) {
      if (chat.status == 'pending' && !_processingChatIds.contains(chat.id)) {
        _processingChatIds.add(chat.id);
        _processSingleChatToPo(chat, isAuto: true);
      }
    }
  }

  Future<void> _showManageWhitelistDialog(BuildContext context, WaAutoPoSettings settings) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    WaAutoPoSettings localSettings = settings;
    int? editingIndex;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final contacts = List<Map<String, String>>.from(localSettings.whitelistContacts);
          final isEditing = editingIndex != null && editingIndex! < contacts.length;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF0284C7).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.security_rounded, color: Color(0xFF38BDF8), size: 22),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kelola Nomor Whitelist', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Hanya chat dari nomor ini yang akan ditangkap ke database', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: 580,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Strict Mode Toggle inside Dialog
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: localSettings.strictWhitelistOnly ? Colors.teal.withOpacity(0.4) : const Color(0xFF334155)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          localSettings.strictWhitelistOnly ? Icons.verified_user_rounded : Icons.shield_outlined,
                          color: localSettings.strictWhitelistOnly ? Colors.tealAccent : const Color(0xFF64748B),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Aktifkan Filter Ketat (Strict Whitelist)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                              Text(
                                localSettings.strictWhitelistOnly
                                    ? 'Aktif: Chat dari nomor luar langsung dibuang di memori (tidak disimpan).'
                                    : 'Nonaktif: Semua nomor WhatsApp yang masuk diterima.',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: localSettings.strictWhitelistOnly,
                          activeColor: Colors.tealAccent,
                          onChanged: (val) async {
                            try {
                              final updated = localSettings.copyWith(strictWhitelistOnly: val);
                              await _firebaseService.saveWaAutoPoSettings(updated);
                              setDialogState(() {
                                localSettings = updated;
                              });
                            } catch (e) {
                              debugPrint('Gagal update strict whitelist: $e');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Add / Edit Whitelist Contact Form
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isEditing ? const Color(0xFF0284C7).withOpacity(0.12) : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isEditing ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isEditing)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.edit_rounded, color: Color(0xFF38BDF8), size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'Mode Edit Kontak: "${contacts[editingIndex!]['name']}"',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: TextField(
                                controller: nameController,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: 'Nama Kontak (e.g. Pak BC)',
                                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 5,
                              child: TextField(
                                controller: phoneController,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: 'Nomor WA (e.g. 081234567890)',
                                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isEditing ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () async {
                                final name = nameController.text.trim();
                                final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
                                if (phone.isEmpty) return;

                                try {
                                  final updatedContacts = List<Map<String, String>>.from(localSettings.whitelistContacts);
                                  if (isEditing) {
                                    updatedContacts[editingIndex!] = {
                                      'name': name.isNotEmpty ? name : 'Kontak WA',
                                      'phone': phone,
                                    };
                                  } else {
                                    updatedContacts.add({
                                      'name': name.isNotEmpty ? name : 'Kontak WA',
                                      'phone': phone,
                                    });
                                  }

                                  final updated = localSettings.copyWith(whitelistContacts: updatedContacts);
                                  await _firebaseService.saveWaAutoPoSettings(updated);

                                  nameController.clear();
                                  phoneController.clear();
                                  setDialogState(() {
                                    localSettings = updated;
                                    editingIndex = null;
                                  });
                                } catch (e) {
                                  debugPrint('Gagal simpan kontak whitelist: $e');
                                }
                              },
                              child: Text(
                                isEditing ? 'Simpan' : '+ Tambah',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            if (isEditing) ...[
                              const SizedBox(width: 6),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF94A3B8),
                                  side: const BorderSide(color: Color(0xFF475569)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  nameController.clear();
                                  phoneController.clear();
                                  setDialogState(() {
                                    editingIndex = null;
                                  });
                                },
                                child: const Text('Batal', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Daftar Nomor Terdaftar (${contacts.length}):',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      if (contacts.isNotEmpty)
                        const Text(
                          'Klik ✏️ untuk edit, 🗑️ untuk hapus',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Contacts List
                  Expanded(
                    child: contacts.isEmpty
                        ? const Center(
                            child: Text('Belum ada nomor yang didaftarkan ke whitelist.', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                          )
                        : ListView.separated(
                            itemCount: contacts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (cCtx, idx) {
                              final item = contacts[idx];
                              final isCurrentEdit = editingIndex == idx;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isCurrentEdit ? const Color(0xFF0284C7).withOpacity(0.15) : const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isCurrentEdit ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          const Icon(Icons.phone_android_rounded, color: Color(0xFF38BDF8), size: 18),
                                          const SizedBox(width: 10),
                                          Flexible(
                                            child: Text(
                                              item['name'] ?? '',
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '(+${_maskPhone(item['phone'])})',
                                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Edit Button
                                        IconButton(
                                          icon: const Icon(Icons.edit_rounded, color: Color(0xFF38BDF8), size: 18),
                                          tooltip: 'Edit Kontak',
                                          onPressed: () {
                                            setDialogState(() {
                                              editingIndex = idx;
                                              nameController.text = item['name'] ?? '';
                                              phoneController.text = item['phone'] ?? '';
                                            });
                                          },
                                        ),
                                        // Delete Button
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                          tooltip: 'Hapus Kontak',
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: dialogCtx,
                                              builder: (confCtx) => AlertDialog(
                                                backgroundColor: const Color(0xFF1E293B),
                                                title: const Text('Hapus Kontak Whitelist?', style: TextStyle(color: Colors.white, fontSize: 15)),
                                                content: Text(
                                                  'Hapus ${item['name']} (+${item['phone']}) dari daftar whitelist?',
                                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(confCtx, false),
                                                    child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
                                                  ),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                    onPressed: () => Navigator.pop(confCtx, true),
                                                    child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm == true) {
                                              try {
                                                final updatedContacts = List<Map<String, String>>.from(localSettings.whitelistContacts);
                                                updatedContacts.removeAt(idx);

                                                final updated = localSettings.copyWith(whitelistContacts: updatedContacts);
                                                await _firebaseService.saveWaAutoPoSettings(updated);

                                                setDialogState(() {
                                                  localSettings = updated;
                                                  if (editingIndex == idx) {
                                                    editingIndex = null;
                                                    nameController.clear();
                                                    phoneController.clear();
                                                  } else if (editingIndex != null && editingIndex! > idx) {
                                                    editingIndex = editingIndex! - 1;
                                                  }
                                                });
                                              } catch (e) {
                                                debugPrint('Gagal hapus kontak whitelist: $e');
                                              }
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup', style: TextStyle(color: Color(0xFF38BDF8))),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _simulateIncomingChat() async {
    const sampleChat = '''Orderan Lucifax FF Blora
1. Beres sapi 13 : 20 ktn
2. Rolade sp roll : 25 ktn
3. Kornet ayam loyang : 40 ktn
Kirim besok pagi ya pak bc''';

    final textController = TextEditingController(text: sampleChat);
    final senderController = TextEditingController(text: 'Pak BC (Simulasi WhatsApp)');
    final phoneController = TextEditingController(text: '6281234567890');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.science_rounded, color: Color(0xFF38BDF8), size: 22),
            SizedBox(width: 8),
            Text('Simulasi Chat WA Masuk (Dev)', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nama Pengirim:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: senderController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Nomor WA Pengirim:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: phoneController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Teks Pesanan WhatsApp:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: textController,
                maxLines: 5,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () async {
              Navigator.pop(ctx);
              final chat = IncomingPoChat(
                id: '',
                senderJid: '${phoneController.text.trim()}@s.whatsapp.net',
                senderPhone: phoneController.text.trim(),
                senderName: senderController.text.trim(),
                messageText: textController.text.trim(),
                receivedAt: DateTime.now(),
                isOrderDetected: true,
              );
              await _firebaseService.addIncomingPoChat(chat);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✨ Simulasi chat pesanan berhasil masuk ke antrean!'),
                    backgroundColor: Colors.teal,
                  ),
                );
              }
            },
            child: const Text('Kirim Simulasi', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: StreamBuilder<WaAutoPoSettings>(
        stream: _firebaseService.streamWaAutoPoSettings(),
        builder: (context, settingsSnap) {
          final settings = settingsSnap.data ?? WaAutoPoSettings(strictWhitelistOnly: true, autoPoEnabled: false);

          return Padding(
            padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Bar
                if (isMobile)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.mark_chat_unread_rounded, color: Color(0xFF10B981), size: 24),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('WhatsApp Auto-Sync Gateway', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                SizedBox(height: 2),
                                Text('Tangkap otomatis PO WhatsApp (Khusus Developer)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF38BDF8),
                                side: const BorderSide(color: Color(0xFF38BDF8)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _showManageWhitelistDialog(context, settings),
                              icon: const Icon(Icons.contacts_rounded, size: 14),
                              label: Text('📋 Whitelist (${settings.whitelistContacts.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.tealAccent,
                                side: const BorderSide(color: Colors.teal),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _simulateIncomingChat,
                              icon: const Icon(Icons.science_outlined, size: 14),
                              label: const Text('🧪 Tes Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => showAiChatOrderDialog(context),
                              icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                              label: const Text('Buka AI Scanner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.mark_chat_unread_rounded, color: Color(0xFF10B981), size: 28),
                          ),
                          const SizedBox(width: 14),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('WhatsApp Auto-Sync Gateway', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                              SizedBox(height: 3),
                              Text('Tangkap otomatis pesanan WhatsApp dari Pak BC tanpa perlu copy-paste manual (Khusus Developer)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _showManageWhitelistDialog(context, settings),
                            icon: const Icon(Icons.contacts_rounded, size: 16),
                            label: Text('📋 Kelola Whitelist (${settings.whitelistContacts.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.tealAccent,
                              side: const BorderSide(color: Colors.teal),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _simulateIncomingChat,
                            icon: const Icon(Icons.science_outlined, size: 16),
                            label: const Text('🧪 Tes Simulasi Chat', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => showAiChatOrderDialog(context),
                            icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                            label: const Text('Buka AI Scanner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 12),

                // Control Toggles Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: settings.autoPoEnabled ? Colors.teal.withOpacity(0.4) : const Color(0xFF334155)),
                  ),
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  settings.autoPoEnabled ? Icons.bolt_rounded : Icons.flash_off_rounded,
                                  color: settings.autoPoEnabled ? Colors.tealAccent : const Color(0xFF64748B),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text('Auto-PO: ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                          Text(
                                            settings.autoPoEnabled ? 'AKTIF (PO instan)' : 'NONAKTIF',
                                            style: TextStyle(
                                              color: settings.autoPoEnabled ? Colors.tealAccent : const Color(0xFF94A3B8),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: 28,
                                  child: Switch(
                                    value: settings.autoPoEnabled,
                                    activeColor: Colors.tealAccent,
                                    onChanged: (val) async {
                                      final updated = settings.copyWith(autoPoEnabled: val);
                                      await _firebaseService.saveWaAutoPoSettings(updated);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: settings.strictWhitelistOnly ? const Color(0xFF065F46).withOpacity(0.4) : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: settings.strictWhitelistOnly ? const Color(0xFF059669) : const Color(0xFF334155)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_rounded, color: settings.strictWhitelistOnly ? const Color(0xFF34D399) : const Color(0xFF64748B), size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    settings.strictWhitelistOnly ? 'Strict Filter: ON (Whitelist saja)' : 'Strict Filter: OFF',
                                    style: TextStyle(
                                      color: settings.strictWhitelistOnly ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            // Auto-PO Zero Click Toggle
                            Icon(
                              settings.autoPoEnabled ? Icons.bolt_rounded : Icons.flash_off_rounded,
                              color: settings.autoPoEnabled ? Colors.tealAccent : const Color(0xFF64748B),
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Otomatis Buat PO (Zero-Click): ', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    Text(
                                      settings.autoPoEnabled ? 'AKTIF (PO dibuat seketika)' : 'NONAKTIF (Perlu persetujuan)',
                                      style: TextStyle(
                                        color: settings.autoPoEnabled ? Colors.tealAccent : const Color(0xFF94A3B8),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'PO default: statusDikirim = PENDING, statusTransfer = UNPAID, statusERP = kosong',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Switch(
                              value: settings.autoPoEnabled,
                              activeColor: Colors.tealAccent,
                              onChanged: (val) async {
                                final updated = settings.copyWith(autoPoEnabled: val);
                                await _firebaseService.saveWaAutoPoSettings(updated);
                              },
                            ),
                            const Spacer(),

                            // Strict Filter Badge/Button
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: settings.strictWhitelistOnly ? const Color(0xFF065F46).withOpacity(0.4) : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: settings.strictWhitelistOnly ? const Color(0xFF059669) : const Color(0xFF334155)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.shield_rounded, color: settings.strictWhitelistOnly ? const Color(0xFF34D399) : const Color(0xFF64748B), size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    settings.strictWhitelistOnly ? 'Strict Filter: ON (Hanya nomor whitelist)' : 'Strict Filter: OFF',
                                    style: TextStyle(
                                      color: settings.strictWhitelistOnly ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 14),

                // Main Content
                Expanded(
                  child: isMobile
                      ? DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              Container(
                                height: 40,
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                                ),
                                child: const TabBar(
                                  indicator: BoxDecoration(
                                    color: Color(0xFF0284C7),
                                    borderRadius: BorderRadius.all(Radius.circular(8)),
                                  ),
                                  labelColor: Colors.white,
                                  unselectedLabelColor: Color(0xFF94A3B8),
                                  labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  tabs: [
                                    Tab(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.inbox_rounded, size: 15),
                                          SizedBox(width: 6),
                                          Text('Kotak Masuk PO'),
                                        ],
                                      ),
                                    ),
                                    Tab(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.phonelink_ring_rounded, size: 15),
                                          SizedBox(width: 6),
                                          Text('Status Perangkat WA'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _buildIncomingOrdersPanel(settings, isMobile: true),
                                    _buildGatewayStatusCard(isMobile: true),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Gateway Session Card (Flex 4)
                            Expanded(
                              flex: 4,
                              child: _buildGatewayStatusCard(isMobile: false),
                            ),
                            const SizedBox(width: 18),

                            // Incoming Orders Stream (Flex 7)
                            Expanded(
                              flex: 7,
                              child: _buildIncomingOrdersPanel(settings, isMobile: false),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGatewayStatusCard({bool isMobile = false}) {
    return StreamBuilder<WaGatewaySession>(
      stream: _firebaseService.streamWaGatewaySession(),
      builder: (context, snapshot) {
        final session = snapshot.data ?? WaGatewaySession(status: 'DISCONNECTED');
        final isConnected = session.isConnected;
        final isQrReady = session.isQrReady;

        Widget content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phonelink_ring_rounded, color: Color(0xFF38BDF8), size: 20),
                    const SizedBox(width: 8),
                    const Text('Status Perangkat WA', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    if (session.deviceName != null && session.deviceName!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                        ),
                        child: Text(
                          session.formattedDeviceName,
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                _buildStatusBadge(session),
              ],
            ),
            const SizedBox(height: 16),

            if (isConnected) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF059669)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 22),
                        SizedBox(width: 8),
                        Text('WhatsApp Web Aktif', style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Nomor Terhubung: +${_maskPhone(session.phone)}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: _hidePhoneNumbers ? 'Tampilkan Nomor HP' : 'Sembunyikan Nomor HP',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _toggleHidePhoneNumbers,
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                _hidePhoneNumbers ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: _hidePhoneNumbers ? const Color(0xFF94A3B8) : const Color(0xFF34D399),
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Nama Akun: ${session.pushName ?? 'Admin Lucifax'}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    const SizedBox(height: 10),
                    const Divider(color: Color(0xFF059669), height: 1),
                    const SizedBox(height: 10),
                    // MONITORING PERANGKAT AKTIF & SPESIFIKASI HP LENGKAP
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.75),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                session.devicePlatform == 'win32'
                                    ? Icons.laptop_mac_rounded
                                    : (session.devicePlatform == 'android' ? Icons.smartphone_rounded : Icons.dns_rounded),
                                size: 18,
                                color: const Color(0xFF38BDF8),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Spesifikasi Mesin Gateway Aktif:',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(color: Color(0xFF1E293B), height: 1),
                          const SizedBox(height: 8),

                          // 1. Model & Nama Device
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(
                                width: 85,
                                child: Text('Model HP/PC', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                              ),
                              const Text(': ', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                              Expanded(
                                child: Text(
                                  session.formattedDeviceName,
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),

                          // 2. Sistem Operasi (Android / Windows)
                          if (session.osVersion != null && session.osVersion!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const SizedBox(
                                  width: 85,
                                  child: Text('OS / Versi', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                ),
                                const Text(': ', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                Expanded(
                                  child: Text(
                                    session.osVersion!,
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // 3. Status Baterai HP
                          if (session.batteryInfo != null && session.batteryInfo!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const SizedBox(
                                  width: 85,
                                  child: Text('Baterai HP', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                ),
                                const Text(': ', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                Row(
                                  children: [
                                    const Icon(Icons.battery_charging_full_rounded, size: 14, color: Color(0xFF34D399)),
                                    const SizedBox(width: 4),
                                    Text(
                                      session.batteryInfo!,
                                      style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],

                          // 4. Memori RAM
                          if (session.ramInfo != null && session.ramInfo!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const SizedBox(
                                  width: 85,
                                  child: Text('Memori RAM', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                ),
                                const Text(': ', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                Text(
                                  session.ramInfo!,
                                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                                ),
                              ],
                            ),
                          ],

                          // 5. Sinyal Heartbeat
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const SizedBox(
                                width: 85,
                                child: Text('Detak Sinyal', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                              ),
                              const Text(': ', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                              Icon(
                                Icons.wifi_tethering_rounded,
                                size: 13,
                                color: session.isHeartbeatAlive ? const Color(0xFF34D399) : const Color(0xFFF87171),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                session.heartbeatAgo,
                                style: TextStyle(
                                  color: session.isHeartbeatAlive ? const Color(0xFF34D399) : const Color(0xFFF87171),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Gateway aktif mendengarkan chat dari Pak BC dan otomatis menginput ke sistem sebagai antrean PO.',
                      style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isMobile) const SizedBox(height: 20) else const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _firebaseService.sendWaGatewayCommand('RESTART'),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Restart'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF1E293B),
                            title: const Text('Putuskan Sesi WhatsApp?', style: TextStyle(color: Colors.white)),
                            content: const Text('Perangkat akan di-logout dan perlu scan QR ulang untuk menghubungkan kembali.', style: TextStyle(color: Color(0xFF94A3B8))),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Putuskan'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _firebaseService.sendWaGatewayCommand('LOGOUT');
                        }
                      },
                      icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 16),
                      label: const Text('Logout WA', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ] else if (isQrReady) ...[
              if (isMobile)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2),
                          ],
                        ),
                        child: _buildQrImage(session.qrCode!),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.withOpacity(0.3)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('📱 Petunjuk Scan QR:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                            SizedBox(height: 6),
                            Text('1. Buka WhatsApp di HP Anda', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                            Text('2. Tekan menu (⋮) > Perangkat Tertaut', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                            Text('3. Pilih "Tautkan Perangkat" dan arahkan kamera ke QR ini.', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          side: const BorderSide(color: Color(0xFF38BDF8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _firebaseService.sendWaGatewayCommand('RESTART'),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Muat Ulang QR', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2),
                              ],
                            ),
                            child: _buildQrImage(session.qrCode!),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.withOpacity(0.3)),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('📱 Petunjuk Scan QR:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                                SizedBox(height: 6),
                                Text('1. Buka WhatsApp di HP Anda', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                                Text('2. Tekan menu (⋮) > Perangkat Tertaut', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                                Text('3. Pilih "Tautkan Perangkat" dan arahkan kamera ke QR ini.', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _firebaseService.sendWaGatewayCommand('RESTART'),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Muat Ulang QR', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ] else ...[
              if (isMobile)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      Icon(Icons.wifi_off_rounded, color: const Color(0xFF64748B).withOpacity(0.6), size: 48),
                      const SizedBox(height: 12),
                      const Text('Gateway Offline / Belum Berjalan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Jalankan microservice gateway di server atau lokal dengan perintah:\ncd wa-gateway; node server.js',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _firebaseService.sendWaGatewayCommand('RESTART'),
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                        label: const Text('Coba Sambungkan', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded, color: const Color(0xFF64748B).withOpacity(0.6), size: 54),
                        const SizedBox(height: 14),
                        const Text('Gateway Offline / Belum Berjalan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'Jalankan microservice gateway di server atau lokal dengan perintah:\ncd wa-gateway; node server.js',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
                          ),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _firebaseService.sendWaGatewayCommand('RESTART'),
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                          label: const Text('Coba Sambungkan', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        );

        if (isMobile) {
          content = SingleChildScrollView(
            child: content,
          );
        }

        return Container(
          padding: EdgeInsets.all(isMobile ? 14 : 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isConnected
                  ? Colors.teal.withOpacity(0.4)
                  : (isQrReady ? Colors.amber.withOpacity(0.4) : Colors.white.withOpacity(0.08)),
            ),
          ),
          child: content,
        );
      },
    );
  }

  Widget _buildQrImage(String qrDataUrl) {
    try {
      final base64String = qrDataUrl.contains(',') ? qrDataUrl.split(',')[1] : qrDataUrl;
      final bytes = base64Decode(base64String);
      return Image.memory(bytes, width: 220, height: 220, fit: BoxFit.contain);
    } catch (e) {
      return const SizedBox(
        width: 220,
        height: 220,
        child: Center(child: Text('Gagal memuat QR', style: TextStyle(color: Colors.redAccent))),
      );
    }
  }

  Widget _buildStatusBadge(WaGatewaySession session) {
    Color bg;
    Color fg;
    String label;
    IconData? icon;

    final status = session.status;
    final isAlive = session.isHeartbeatAlive;

    switch (status) {
      case 'CONNECTED':
        if (isAlive) {
          bg = const Color(0xFF065F46);
          fg = const Color(0xFF34D399);
          label = 'TERHUBUNG';
          icon = Icons.check_circle_rounded;
        } else {
          bg = const Color(0xFF78350F);
          fg = const Color(0xFFFBBF24);
          label = 'TIDAK MERESPONS';
          icon = Icons.warning_amber_rounded;
        }
        break;
      case 'STANDBY':
        bg = const Color(0xFF334155);
        fg = const Color(0xFF94A3B8);
        label = 'STANDBY (SIAGA)';
        icon = Icons.pause_circle_outline_rounded;
        break;
      case 'QR_READY':
        bg = const Color(0xFF78350F);
        fg = const Color(0xFFFBBF24);
        label = 'SCAN QR';
        icon = Icons.qr_code_scanner_rounded;
        break;
      case 'CONNECTING':
        bg = const Color(0xFF1E3A8A);
        fg = const Color(0xFF60A5FA);
        label = 'MENGHUBUNGKAN';
        icon = Icons.sync_rounded;
        break;
      default:
        bg = const Color(0xFF7F1D1D);
        fg = const Color(0xFFF87171);
        label = 'OFFLINE';
        icon = Icons.wifi_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 12),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildIncomingOrdersPanel(WaAutoPoSettings settings, {bool isMobile = false}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Row(
              children: [
                const Icon(Icons.inbox_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                const Text('Kotak Masuk Pesanan WA', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                Tooltip(
                  message: _hidePhoneNumbers ? 'Tampilkan Nomor HP' : 'Sembunyikan Nomor HP',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _toggleHidePhoneNumbers,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        _hidePhoneNumbers ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: _hidePhoneNumbers ? const Color(0xFF94A3B8) : const Color(0xFF38BDF8),
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Cari pesan / pengirim...',
                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 16),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.inbox_rounded, color: Color(0xFF38BDF8), size: 20),
                const SizedBox(width: 8),
                const Text('Kotak Masuk Pesanan WhatsApp', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                Tooltip(
                  message: _hidePhoneNumbers ? 'Tampilkan Nomor HP' : 'Sembunyikan Nomor HP',
                  child: IconButton(
                    icon: Icon(
                      _hidePhoneNumbers ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: _hidePhoneNumbers ? const Color(0xFF94A3B8) : const Color(0xFF38BDF8),
                      size: 20,
                    ),
                    tooltip: _hidePhoneNumbers ? 'Tampilkan Nomor HP' : 'Sembunyikan Nomor HP',
                    onPressed: _toggleHidePhoneNumbers,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 220,
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Cari pesan / pengirim...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 16),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),

          // Filter chips wrapped in SingleChildScrollView for mobile responsiveness
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('all', 'Semua'),
                const SizedBox(width: 8),
                _buildFilterChip('pending', 'Menunggu Diproses'),
                const SizedBox(width: 8),
                _buildFilterChip('processed', 'Sudah Jadi PO'),
                const SizedBox(width: 8),
                _buildFilterChip('dismissed', 'Diabaikan / Bukan Order'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // List of incoming chats
          Expanded(
            child: StreamBuilder<List<IncomingPoChat>>(
              stream: _firebaseService.streamIncomingPoChats(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                }

                final allChats = snapshot.data ?? [];

                // Trigger Auto-PO processing if toggle is ON
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _checkAndAutoProcess(allChats, settings.autoPoEnabled);
                });

                final query = _searchController.text.trim().toLowerCase();
                final filteredChats = allChats.where((chat) {
                  if (_selectedStatusFilter != 'all' && chat.status != _selectedStatusFilter) return false;
                  if (query.isNotEmpty) {
                    return chat.senderName.toLowerCase().contains(query) ||
                        chat.senderPhone.contains(query) ||
                        chat.messageText.toLowerCase().contains(query);
                  }
                  return true;
                }).toList();

                if (filteredChats.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, color: const Color(0xFF64748B).withOpacity(0.5), size: 48),
                        const SizedBox(height: 12),
                        const Text('Belum ada chat pesanan masuk.', style: TextStyle(color: Color(0xFF94A3B8))),
                        const SizedBox(height: 6),
                        const Text('Chat WhatsApp yang masuk dari nomor terdaftar akan tampil di sini secara real-time.', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            side: const BorderSide(color: Color(0xFF38BDF8)),
                          ),
                          onPressed: _simulateIncomingChat,
                          icon: const Icon(Icons.science_outlined, size: 16),
                          label: const Text('Buat Simulasi Pesanan', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filteredChats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final chat = filteredChats[idx];
                    return _buildChatItemCard(chat, isMobile: isMobile);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedStatusFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedStatusFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(20),
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

  Widget _buildChatItemCard(IncomingPoChat chat, {bool isMobile = false}) {
    final isPending = chat.status == 'pending';
    final isProcessed = chat.status == 'processed';
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(chat.receivedAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending ? Colors.amber.withOpacity(0.3) : (isProcessed ? Colors.teal.withOpacity(0.4) : const Color(0xFF334155)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF0284C7).withOpacity(0.2),
                      child: const Icon(Icons.person, color: Color(0xFF38BDF8), size: 16),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        chat.senderName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('(+${_maskPhone(chat.senderPhone)})', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dateStr, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                  const SizedBox(width: 6),
                  _buildChatStatusBadge(chat),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Message snippet
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: Text(
              chat.messageText,
              style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12, height: 1.4, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 10),

          // Action Row / Wrap
          if (isMobile) ...[
            if (isProcessed && chat.createdInvoiceNo != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF059669)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Invoice #${chat.createdInvoiceNo} (PENDING, UNPAID)',
                        style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ] else if (chat.status == 'dismissed') ...[
              Text(
                chat.dismissReason == 'BUKAN_ORDER' ? '⚠️ Bukan format pesanan barang' : 'Diabaikan secara manual',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (isPending) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      side: const BorderSide(color: Color(0xFF334155)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: () => _firebaseService.updateIncomingPoChatStatus(chat.id, 'dismissed'),
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text('Abaikan', style: TextStyle(fontSize: 11)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _processSingleChatToPo(chat, isAuto: false),
                    icon: const Icon(Icons.bolt_rounded, color: Colors.white, size: 15),
                    label: const Text('⚡ Buat PO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
                if (chat.status == 'dismissed') ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: () => _firebaseService.updateIncomingPoChatStatus(chat.id, 'pending'),
                    icon: const Icon(Icons.undo_rounded, size: 14),
                    label: const Text('Ke Pending', style: TextStyle(fontSize: 11)),
                  ),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _openInAiScanner(chat),
                  icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                  label: const Text('AI Scanner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 18),
                  tooltip: 'Hapus Pesan',
                  onPressed: () => _firebaseService.deleteIncomingPoChat(chat.id),
                ),
              ],
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isProcessed && chat.createdInvoiceNo != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B).withOpacity(0.4),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF059669)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 15),
                        const SizedBox(width: 6),
                        Text(
                          'Invoice #${chat.createdInvoiceNo} (statusDikirim: PENDING, statusTransfer: UNPAID, ERP: kosong)',
                          style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ] else if (chat.status == 'dismissed') ...[
                  Text(
                    chat.dismissReason == 'BUKAN_ORDER' ? '⚠️ Bukan format pesanan barang' : 'Diabaikan secara manual',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ] else ...[
                  const SizedBox(),
                ],

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPending) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          side: const BorderSide(color: Color(0xFF334155)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onPressed: () => _firebaseService.updateIncomingPoChatStatus(chat.id, 'dismissed'),
                        icon: const Icon(Icons.close_rounded, size: 14),
                        label: const Text('Abaikan', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _processSingleChatToPo(chat, isAuto: false),
                        icon: const Icon(Icons.bolt_rounded, color: Colors.white, size: 15),
                        label: const Text('⚡ Langsung Buat PO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (chat.status == 'dismissed') ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          side: const BorderSide(color: Color(0xFF38BDF8)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onPressed: () => _firebaseService.updateIncomingPoChatStatus(chat.id, 'pending'),
                        icon: const Icon(Icons.undo_rounded, size: 14),
                        label: const Text('Kembalikan ke Pending', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openInAiScanner(chat),
                      icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                      label: const Text('Buka di AI Scanner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 18),
                      tooltip: 'Hapus Pesan',
                      onPressed: () => _firebaseService.deleteIncomingPoChat(chat.id),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatStatusBadge(IncomingPoChat chat) {
    Color bg;
    Color fg;
    String label;

    switch (chat.status) {
      case 'processed':
        bg = const Color(0xFF065F46);
        fg = const Color(0xFF34D399);
        label = chat.createdInvoiceNo != null ? 'PO #${chat.createdInvoiceNo} SELESAI' : 'SELESAI PO';
        break;
      case 'dismissed':
        bg = const Color(0xFF334155);
        fg = const Color(0xFF94A3B8);
        label = chat.dismissReason == 'BUKAN_ORDER' ? 'BUKAN ORDER' : 'DIABAIKAN';
        break;
      default:
        bg = const Color(0xFF78350F);
        fg = const Color(0xFFFBBF24);
        label = 'PENDING';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
