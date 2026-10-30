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
    if (chat.isTransferSlip || chat.messageType == 'TRANSFER_SLIP') return;
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

  void _checkAndAutoProcess(List<IncomingPoChat> chats, WaAutoPoSettings settings) {
    // 1. Auto-PO untuk pesanan teks (hanya jika autoPoEnabled aktif)
    if (settings.autoPoEnabled) {
      for (var chat in chats) {
        if (chat.isTransferSlip || chat.messageType == 'TRANSFER_SLIP') continue;
        if (chat.status == 'pending' && !_processingChatIds.contains(chat.id)) {
          _processingChatIds.add(chat.id);
          _processSingleChatToPo(chat, isAuto: true);
        }
      }
    }

    // 2. Auto-Settle untuk bukti transfer (Opsi B: jika autoSettleTransferSlips aktif dan ada faktur target)
    if (settings.autoSettleTransferSlips) {
      for (var chat in chats) {
        if ((chat.isTransferSlip || chat.messageType == 'TRANSFER_SLIP') &&
            chat.status == 'pending' &&
            chat.matchedInvoiceNo != null &&
            chat.matchedInvoiceNo!.isNotEmpty &&
            !chat.isPaymentApplied &&
            !_processingChatIds.contains(chat.id)) {
          _processingChatIds.add(chat.id);
          _confirmTransferPayment(chat, chat.matchedInvoiceNo!);
        }
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
                            Row(
                              children: [
                                Icon(
                                  settings.autoSettleTransferSlips ? Icons.verified_rounded : Icons.pending_actions_rounded,
                                  color: settings.autoSettleTransferSlips ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    settings.autoSettleTransferSlips ? 'Pelunasan: Opsi B (Otomatis)' : 'Pelunasan: Opsi A (Konfirmasi)',
                                    style: TextStyle(
                                      color: settings.autoSettleTransferSlips ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: 28,
                                  child: Switch(
                                    value: settings.autoSettleTransferSlips,
                                    activeColor: const Color(0xFF34D399),
                                    onChanged: (val) async {
                                      final updated = settings.copyWith(autoSettleTransferSlips: val);
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
                            Container(
                              height: 32,
                              width: 1,
                              color: const Color(0xFF334155),
                              margin: const EdgeInsets.symmetric(horizontal: 14),
                            ),
                            // Auto-Settle Transfer Slips Toggle (Opsi B vs Opsi A)
                            Icon(
                              settings.autoSettleTransferSlips ? Icons.verified_rounded : Icons.pending_actions_rounded,
                              color: settings.autoSettleTransferSlips ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Pelunasan Struk: ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text(
                                      settings.autoSettleTransferSlips ? 'OPSI B (Otomatis Penuh)' : 'OPSI A (Konfirmasi Kasir)',
                                      style: TextStyle(
                                        color: settings.autoSettleTransferSlips ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  settings.autoSettleTransferSlips
                                      ? 'Struk cocok langsung lunas seketika di Piutang (Zero-Click)'
                                      : 'Struk menunggu klik konfirmasi tombol hijau kasir',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            Switch(
                              value: settings.autoSettleTransferSlips,
                              activeColor: const Color(0xFF34D399),
                              onChanged: (val) async {
                                final updated = settings.copyWith(autoSettleTransferSlips: val);
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _showSwitchDeviceDialog,
                      icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 16),
                      label: const Text('Alihkan HP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
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

  Future<void> _showSwitchDeviceDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.swap_horiz_rounded, color: Color(0xFF2DD4BF), size: 24),
            SizedBox(width: 10),
            Text(
              'Pilih Perangkat Gateway Pengganti',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih perangkat yang sedang siaga (STANDBY) untuk mengambil alih tugas Gateway WhatsApp:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<WaGatewayNode>>(
                stream: _firebaseService.streamWaGatewayNodes(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF0D9488), strokeWidth: 2),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                      ),
                      child: Text(
                        'Gagal memuat status cluster: ${snapshot.error}',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    );
                  }

                  final nodes = snapshot.data ?? [];
                  // Saring node yang sedang STANDBY / bukan yang sedang aktif CONNECTED
                  final standbyNodes = nodes.where((n) => n.status != 'CONNECTED' && n.status != 'DISCONNECTED').toList();

                  if (standbyNodes.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Belum Ada HP Siaga Terdeteksi',
                                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Pastikan Termux di HP Asus atau HP Redmi Anda sudah dibuka dan sedang menjalankan perintah:\nnode server.js',
                            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, height: 1.4),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(ctx);
                              await _firebaseService.sendWaGatewayCommand('SWITCH_DEVICE');
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Sinyal siaga umum terkirim ke seluruh perangkat!'),
                                  backgroundColor: Color(0xFF0D9488),
                                ),
                              );
                            },
                            icon: const Icon(Icons.broadcast_on_personal_rounded, size: 16),
                            label: const Text('Tetap Kirim Sinyal Siaga Umum', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: standbyNodes.map((node) {
                      final isAndroid = node.devicePlatform == 'android';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isAndroid ? Icons.smartphone_rounded : Icons.laptop_mac_rounded,
                                color: const Color(0xFF38BDF8),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    node.fullModelName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (node.batteryInfo != null && node.batteryInfo!.isNotEmpty) ...[
                                        const Icon(Icons.battery_charging_full_rounded, size: 13, color: Color(0xFF34D399)),
                                        const SizedBox(width: 3),
                                        Text(
                                          node.batteryInfo!,
                                          style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(
                                        'Detak: ${node.heartbeatAgo}',
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0D9488),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                Navigator.pop(ctx);
                                await _firebaseService.sendWaGatewaySwitchTarget(
                                  targetInstanceId: node.instanceId,
                                  targetDeviceName: node.deviceName,
                                );
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Mengalihkan Gateway ke ${node.fullModelName}...'),
                                    backgroundColor: const Color(0xFF0D9488),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.power_settings_new_rounded, size: 16, color: Colors.white),
                              label: const Text('Aktifkan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text(
                '💡 Tips: Anda juga bisa langsung membuka Termux di HP tujuan lalu menekan tombol [ENTER] untuk mengaktifkan.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
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
                _buildFilterChip('expense', 'Pengeluaran / Biaya'),
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
                  _checkAndAutoProcess(allChats, settings);
                });

                final query = _searchController.text.trim().toLowerCase();
                final filteredChats = allChats.where((chat) {
                  if (_selectedStatusFilter != 'all') {
                    if (_selectedStatusFilter == 'transfer') {
                      if (!chat.isTransferSlip && chat.messageType != 'TRANSFER_SLIP') return false;
                    } else if (_selectedStatusFilter == 'expense') {
                      if (!chat.isExpense) return false;
                    } else if (_selectedStatusFilter == 'processed') {
                      // Tab "Sudah Jadi PO" HANYA untuk pesanan order yang selesai diproses jadi Faktur
                      if (chat.isExpense) return false;
                      if (chat.isTransferSlip && !chat.isOrderDetected) return false;
                      if (chat.status != 'processed') return false;
                    } else if (_selectedStatusFilter == 'pending') {
                      // Tab "Menunggu Diproses" untuk order & transfer pending (bukan pengeluaran)
                      if (chat.isExpense) return false;
                      if (chat.status != 'pending') return false;
                    } else if (_selectedStatusFilter == 'dismissed') {
                      if (chat.isExpense) return false;
                      if (chat.status != 'dismissed') return false;
                    } else if (chat.status != _selectedStatusFilter) {
                      return false;
                    }
                  }
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
                        Icon(
                          _selectedStatusFilter == 'expense' ? Icons.outbox_rounded : Icons.chat_bubble_outline_rounded,
                          color: const Color(0xFF64748B).withOpacity(0.5),
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedStatusFilter == 'expense'
                              ? 'Belum ada bukti pengeluaran operasional.'
                              : 'Belum ada chat pesanan masuk.',
                          style: const TextStyle(color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedStatusFilter == 'expense'
                              ? 'Bukti transfer biaya operasional (bongkar muat, bensin, solar) akan tampil di sini.'
                              : 'Chat WhatsApp yang masuk dari nomor terdaftar akan tampil di sini secara real-time.',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                        ),
                        if (_selectedStatusFilter != 'expense') ...[
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

  Future<void> _confirmTransferPayment(IncomingPoChat chat, String invoiceNo) async {
    final invClean = invoiceNo.replaceAll('#', '').trim();
    if (invClean.isEmpty) return;

    try {
      final trDoc = await FirebaseFirestore.instance.collection('transactions').doc(invClean).get();
      if (!trDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Faktur #$invClean tidak ditemukan di database.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final trData = trDoc.data() ?? {};
      final String custName = (trData['aliasName'] != null && trData['aliasName'].toString().isNotEmpty)
          ? trData['aliasName'].toString()
          : (trData['customerName'] ?? 'Pelanggan').toString();

      // 1. Ambil data piutang untuk perhitungan cicilan vs lunas
      final recSnap = await FirebaseFirestore.instance.collection('receivables').where('noInvoice', isEqualTo: invClean).get();
      double effectiveNominal = ((trData['grandTotal'] ?? 0) as num).toDouble();
      double currentPaid = 0.0;
      DocumentReference? targetRecRef;

      if (recSnap.docs.isNotEmpty) {
        final recDoc = recSnap.docs.first;
        targetRecRef = recDoc.reference;
        final recData = recDoc.data();
        effectiveNominal = ((recData['nominal'] ?? recData['totalTagihan'] ?? effectiveNominal) as num).toDouble();
        if (recData['paidAmount'] != null) {
          currentPaid = ((recData['paidAmount']) as num).toDouble();
        } else if (recData['payments'] is List) {
          final list = recData['payments'] as List;
          currentPaid = list.fold<double>(0.0, (sum, p) => sum + (((p as Map)['amount'] as num?)?.toDouble() ?? 0.0));
        }
      }

      final double payAmount = ((chat.transferInfo?['amount'] as num?) ?? 0).toDouble();
      final double effectivePay = payAmount > 0 ? payAmount : (effectiveNominal - currentPaid);
      final double newPaidAmount = currentPaid + effectivePay;
      final bool willBeLunas = newPaidAmount >= (effectiveNominal - 1.0);
      final double remainingAfter = willBeLunas ? 0.0 : (effectiveNominal - newPaidAmount);

      final bankName = (chat.transferInfo?['bank'] ?? 'Transfer').toString();
      final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

      final paymentItem = {
        'id': 'pay_${DateTime.now().millisecondsSinceEpoch}',
        'amount': effectivePay,
        'date': Timestamp.now(),
        'note': willBeLunas
            ? 'Pelunasan manual via WA Gateway ($bankName)'
            : 'Cicilan manual via WA Gateway ($bankName) - Sisa ${currencyFormatter.format(remainingAfter)}',
        'paymentMethod': 'Transfer $bankName',
        'receiptUrl': chat.imageUrl ?? '',
        'createdAt': Timestamp.now(),
      };

      // 2. Sinkronisasi ke koleksi receivables
      if (targetRecRef != null) {
        await targetRecRef.update({
          'isLunas': willBeLunas,
          'paidAmount': newPaidAmount,
          'payments': FieldValue.arrayUnion([paymentItem]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 3. Update koleksi transactions
      await FirebaseFirestore.instance.collection('transactions').doc(invClean).update({
        'statusTransfer': willBeLunas ? 'PAID' : 'PARTIAL',
        if (willBeLunas) 'transferDate': Timestamp.now(),
        if (chat.imageUrl != null) 'transferReceiptUrl': chat.imageUrl,
        'transferBankDetails': {
          if (chat.transferInfo != null) ...chat.transferInfo!,
          'isPartial': !willBeLunas,
          'remaining': remainingAfter,
          'totalPaid': newPaidAmount,
          'totalTagihan': effectiveNominal,
          'settledAt': DateTime.now().toIso8601String(),
          'settleSource': 'WA_GATEWAY_MANUAL_LINK',
        },
      });

      // 4. Update koleksi incoming_po_chats
      await FirebaseFirestore.instance.collection('incoming_po_chats').doc(chat.id).update({
        'status': 'processed',
        'isPaymentApplied': true,
        'matchedInvoiceNo': invClean,
        'isPartialPayment': !willBeLunas,
        'remainingAmount': remainingAfter,
        'processedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        if (willBeLunas) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Pembayaran Faktur #$invClean ($custName) LUNAS PENUH! Bukti transfer tersimpan.'),
              backgroundColor: const Color(0xFF059669),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('💳 Pembayaran Cicilan ${currencyFormatter.format(effectivePay)} dicatat ke Faktur #$invClean ($custName). Sisa Tagihan: ${currencyFormatter.format(remainingAfter)}'),
              backgroundColor: const Color(0xFF0284C7),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal verifikasi pembayaran: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showReceiptImageDialog(BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 750),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('Gagal memuat gambar bukti transfer.', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLinkToInvoiceDialog(BuildContext context, IncomingPoChat chat) async {
    final initialQuery = (chat.matchedInvoiceNo != null && chat.matchedInvoiceNo!.isNotEmpty)
        ? chat.matchedInvoiceNo!
        : (chat.transferInfo?['customerHint'] ?? '').toString();
    final searchCtrl = TextEditingController(text: initialQuery);
    String selectedInv = chat.matchedInvoiceNo ?? '';

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 550, maxHeight: 600),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 22),
                          SizedBox(width: 8),
                          Text('Tautkan Bukti Transfer ke Faktur', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (chat.transferInfo != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF064E3B).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF059669)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_rounded, color: Color(0xFF34D399), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Bank: ${chat.transferInfo?['bank'] ?? '-'} | Nominal: Rp ${((chat.transferInfo?['amount'] as num?) ?? 0).toStringAsFixed(0)}',
                                  style: const TextStyle(color: Color(0xFF6EE7B7), fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                if ((chat.transferInfo?['berita'] ?? '').toString().isNotEmpty)
                                  Text(
                                    'Berita: "${chat.transferInfo?['berita']}"',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Cari Nomor Faktur / Nama Toko',
                      hintText: 'e.g. 683 atau Maju Market',
                      labelStyle: const TextStyle(color: Color(0xFF38BDF8)),
                      hintStyle: const TextStyle(color: Color(0xFF64748B)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8)),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  const Text('Pilih faktur tertunggak untuk dilunasi:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('transactions').orderBy('date', descending: true).limit(30).snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                        }
                        final docs = snap.data?.docs ?? [];
                        final q = searchCtrl.text.trim().toLowerCase();
                        final filteredDocs = docs.where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          final inv = (data['invoiceNo'] ?? d.id).toString().toLowerCase();
                          final cust = (data['customerName'] ?? '').toString().toLowerCase();
                          final alias = (data['aliasName'] ?? '').toString().toLowerCase();
                          if (q.isNotEmpty) {
                            return inv.contains(q) || cust.contains(q) || alias.contains(q);
                          }
                          return true;
                        }).toList();

                        // Utamakan faktur BELUM LUNAS (UNPAID) di urutan paling atas
                        filteredDocs.sort((a, b) {
                          final da = a.data() as Map<String, dynamic>;
                          final db = b.data() as Map<String, dynamic>;
                          final aUnpaid = (da['statusTransfer'] ?? 'UNPAID') == 'UNPAID' ? 0 : 1;
                          final bUnpaid = (db['statusTransfer'] ?? 'UNPAID') == 'UNPAID' ? 0 : 1;
                          return aUnpaid.compareTo(bUnpaid);
                        });

                        if (filteredDocs.isEmpty) {
                          return const Center(child: Text('Tidak ada faktur yang cocok.', style: TextStyle(color: Color(0xFF64748B))));
                        }

                        return ListView.separated(
                          itemCount: filteredDocs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (ctx, i) {
                            final doc = filteredDocs[i];
                            final data = doc.data() as Map<String, dynamic>;
                            final invNo = (data['invoiceNo'] ?? doc.id).toString();
                            final cust = (data['aliasName'] != null && data['aliasName'].toString().isNotEmpty)
                                ? data['aliasName'].toString()
                                : (data['customerName'] ?? 'Pelanggan').toString();
                            final total = (data['grandTotal'] as num?)?.toDouble() ?? 0.0;
                            final isUnpaid = (data['statusTransfer'] ?? 'UNPAID') == 'UNPAID';
                            final isSel = selectedInv == invNo;

                            return InkWell(
                              onTap: () => setDialogState(() => selectedInv = invNo),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFF0284C7).withOpacity(0.25) : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isSel ? const Color(0xFF38BDF8) : (isUnpaid ? Colors.amber.withOpacity(0.3) : const Color(0xFF334155))),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: isSel ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Faktur #$invNo - $cust', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                          Text('Total: Rp ${total.toStringAsFixed(0)} | Status: ${isUnpaid ? "Belum Lunas (UNPAID)" : "Lunas (PAID)"}', style: TextStyle(color: isUnpaid ? Colors.amber : const Color(0xFF34D399), fontSize: 11)),
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
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedInv.isNotEmpty ? const Color(0xFF10B981) : const Color(0xFF334155),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: selectedInv.isNotEmpty
                          ? () {
                              Navigator.pop(dialogCtx);
                              _confirmTransferPayment(chat, selectedInv);
                            }
                          : null,
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      label: Text(
                        selectedInv.isNotEmpty ? 'Konfirmasi Pembayaran Faktur #$selectedInv' : 'Pilih Faktur Dahulu',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedStatusFilter == key;
    Color activeBg = const Color(0xFF0284C7);
    Color activeBorder = const Color(0xFF38BDF8);
    if (key == 'expense') {
      activeBg = const Color(0xFFC2410C);
      activeBorder = const Color(0xFFFB923C);
    }
    return InkWell(
      onTap: () => setState(() => _selectedStatusFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? activeBorder : const Color(0xFF334155)),
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

  Widget _buildTransferSlipCard(IncomingPoChat chat, {bool isMobile = false}) {
    final isProcessed = chat.status == 'processed' || chat.isPaymentApplied;
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(chat.receivedAt);
    final bank = (chat.transferInfo?['bank'] ?? 'BANK').toString();
    final double amount = ((chat.transferInfo?['amount'] as num?) ?? 0).toDouble();
    final String berita = (chat.transferInfo?['berita'] ?? '').toString();
    final String customerHint = (chat.transferInfo?['customerHint'] ?? '').toString();
    final String refNumber = (chat.transferInfo?['refNumber'] ?? '').toString();
    final String recipient = (chat.recipientName ?? chat.transferInfo?['recipient'] ?? '').toString();
    final bool isExpense = chat.isExpense;

    final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final formattedAmount = currencyFormatter.format(amount);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isProcessed
              ? const Color(0xFF059669).withOpacity(0.5)
              : const Color(0xFF38BDF8).withOpacity(0.4),
          width: 1.5,
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
                      backgroundColor: const Color(0xFF059669).withOpacity(0.2),
                      child: const Icon(Icons.account_balance_rounded, color: Color(0xFF34D399), size: 16),
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
          const SizedBox(height: 12),

          // Transfer Slip Content Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF059669).withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail Image if available
                if (chat.hasImage && chat.imageUrl != null && chat.imageUrl!.isNotEmpty) ...[
                  InkWell(
                    onTap: () => _showReceiptImageDialog(context, chat.imageUrl!, 'Bukti Transfer $bank ($formattedAmount)'),
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            chat.imageUrl!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 80,
                              height: 80,
                              color: const Color(0xFF334155),
                              child: const Icon(Icons.broken_image_rounded, color: Color(0xFF64748B)),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Center(
                              child: Icon(Icons.zoom_in_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // Info details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
                            ),
                            child: Text(
                              bank,
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formattedAmount,
                            style: const TextStyle(
                              color: Color(0xFF34D399),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (isExpense) ...[
                        Row(
                          children: [
                            const Icon(Icons.outbox_rounded, color: Color(0xFFFB923C), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Pengeluaran Operasional (${chat.expenseCategory?.replaceAll('_', ' ') ?? 'BIAYA'})',
                              style: const TextStyle(color: Color(0xFFFB923C), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ] else if (chat.matchedInvoiceNo != null && chat.matchedInvoiceNo!.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.receipt_long_rounded, color: Color(0xFFF59E0B), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Target Faktur: #${chat.matchedInvoiceNo}',
                              style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            if (chat.transferInfo?['alreadyPaid'] == true) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.withOpacity(0.5)),
                                ),
                                child: const Text(
                                  'SUDAH PERNAH LUNAS',
                                  style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.help_outline_rounded, color: Color(0xFF38BDF8), size: 14),
                            const SizedBox(width: 4),
                            const Text(
                              'Target Belum Ditentukan (Perlu Tautkan Manual)',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (recipient.isNotEmpty) ...[
                        Text('Penerima: $recipient', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      ],
                      if (customerHint.isNotEmpty) ...[
                        Text('Pengirim/Toko: $customerHint', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      ],
                      if (berita.isNotEmpty) ...[
                        Text('Berita Transfer: "$berita"', style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                      ],
                      if (refNumber.isNotEmpty) ...[
                        Text('No. Ref: $refNumber', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                      ],
                      if (chat.caption != null && chat.caption!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Catatan Pengirim: "${chat.caption}"', style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action Row for Transfer Slip
          if (isProcessed) ...[
            if (isExpense) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFC2410C).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFB923C).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.outbox_rounded, color: Color(0xFFFB923C), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bukti Pengeluaran Diarsipkan (${chat.expenseCategory?.replaceAll('_', ' ') ?? 'BIAYA'} - $formattedAmount)',
                        style: const TextStyle(color: Color(0xFFFDBA74), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 18),
                      tooltip: 'Hapus Bukti',
                      onPressed: () => _firebaseService.deleteIncomingPoChat(chat.id),
                    ),
                  ],
                ),
              ),
            ] else if (chat.isPartialPayment) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0369A1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF0284C7)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pie_chart_outline_rounded, color: Color(0xFF38BDF8), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pembayaran Cicilan Diterapkan (Faktur #${chat.matchedInvoiceNo ?? '-'}) - Sisa Piutang: ${currencyFormatter.format(chat.remainingAmount)}',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 18),
                      tooltip: 'Hapus Bukti',
                      onPressed: () => _firebaseService.deleteIncomingPoChat(chat.id),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF059669)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pembayaran Telah Diterapkan (Faktur #${chat.matchedInvoiceNo ?? '-'}) - STATUS: LUNAS',
                        style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 18),
                      tooltip: 'Hapus Bukti',
                      onPressed: () => _firebaseService.deleteIncomingPoChat(chat.id),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isExpense) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC2410C),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => FirebaseFirestore.instance.collection('incoming_po_chats').doc(chat.id).update({
                          'status': 'processed',
                          'processedAt': FieldValue.serverTimestamp(),
                        }),
                        icon: const Icon(Icons.archive_outlined, color: Colors.white, size: 16),
                        label: const Text(
                          'Arsipkan Pengeluaran',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ] else if (chat.matchedInvoiceNo != null && chat.matchedInvoiceNo!.isNotEmpty && chat.transferInfo?['alreadyPaid'] != true) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _confirmTransferPayment(chat, chat.matchedInvoiceNo!),
                        icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                        label: Text(
                          'Tandai Faktur #${chat.matchedInvoiceNo} Lunas',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => _showLinkToInvoiceDialog(context, chat),
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: Text(
                        chat.matchedInvoiceNo != null ? 'Tautkan ke Faktur Lain' : 'Tautkan ke Faktur',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 18),
                  tooltip: 'Hapus Pesan',
                  onPressed: () => _firebaseService.deleteIncomingPoChat(chat.id),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildChatItemCard(IncomingPoChat chat, {bool isMobile = false}) {
    if (chat.isTransferSlip) {
      return _buildTransferSlipCard(chat, isMobile: isMobile);
    }

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

    if (chat.isTransferSlip || chat.messageType == 'TRANSFER_SLIP') {
      if (chat.isExpense) {
        if (chat.status == 'processed') {
          bg = const Color(0xFF78350F);
          fg = const Color(0xFFFBBF24);
          label = 'PENGELUARAN (DIARSIPKAN)';
        } else if (chat.status == 'dismissed') {
          bg = const Color(0xFF334155);
          fg = const Color(0xFF94A3B8);
          label = 'PENGELUARAN DIABAIKAN';
        } else {
          bg = const Color(0xFF7C2D12);
          fg = const Color(0xFFFB923C);
          final cat = chat.expenseCategory != null ? chat.expenseCategory!.replaceAll('_', ' ') : 'PENGELUARAN';
          label = 'BIAYA ($cat)';
        }
      } else if (chat.status == 'processed' || chat.isPaymentApplied) {
        if (chat.isPartialPayment) {
          bg = const Color(0xFF0C4A6E);
          fg = const Color(0xFF38BDF8);
          label = chat.matchedInvoiceNo != null
              ? 'CICILAN (Faktur #${chat.matchedInvoiceNo})'
              : 'CICILAN DITERAPKAN';
        } else {
          bg = const Color(0xFF065F46);
          fg = const Color(0xFF34D399);
          label = chat.matchedInvoiceNo != null
              ? 'LUNAS (Faktur #${chat.matchedInvoiceNo})'
              : 'LUNAS (TERVERIFIKASI)';
        }
      } else if (chat.status == 'dismissed') {
        bg = const Color(0xFF334155);
        fg = const Color(0xFF94A3B8);
        label = 'STRUK DIABAIKAN';
      } else {
        if (chat.matchedInvoiceNo != null && chat.matchedInvoiceNo!.isNotEmpty) {
          bg = const Color(0xFF78350F);
          fg = const Color(0xFFFBBF24);
          label = 'TARGET #${chat.matchedInvoiceNo}';
        } else {
          bg = const Color(0xFF075985);
          fg = const Color(0xFF38BDF8);
          label = 'PERLU TAUTKAN';
        }
      }
    } else {
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
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
