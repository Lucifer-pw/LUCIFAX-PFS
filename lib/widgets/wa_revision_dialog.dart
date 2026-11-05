import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/incoming_po_chat.dart';
import '../models/customer.dart';
import '../models/transaction.dart' as model_tr;
import '../models/chat_order_draft.dart';
import '../models/ai_knowledge_rule.dart';
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/firebase_service.dart';
import '../services/ai_chat_parser_service.dart';
import '../services/ktp_cache_service.dart';

void showProcessRevisionDialog(
  BuildContext context, {
  required IncomingPoChat chat,
  required CustomerProvider customerProvider,
  required ProductProvider productProvider,
  required TransactionProvider txProvider,
  required FirebaseService firebaseService,
  required Function(String invoiceNo, String message) onSuccess,
  required VoidCallback onMakeNewPo,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _WaRevisionDialogContent(
      chat: chat,
      customerProvider: customerProvider,
      productProvider: productProvider,
      txProvider: txProvider,
      firebaseService: firebaseService,
      onSuccess: onSuccess,
      onMakeNewPo: onMakeNewPo,
    ),
  );
}

class _WaRevisionDialogContent extends StatefulWidget {
  final IncomingPoChat chat;
  final CustomerProvider customerProvider;
  final ProductProvider productProvider;
  final TransactionProvider txProvider;
  final FirebaseService firebaseService;
  final Function(String invoiceNo, String message) onSuccess;
  final VoidCallback onMakeNewPo;

  const _WaRevisionDialogContent({
    required this.chat,
    required this.customerProvider,
    required this.productProvider,
    required this.txProvider,
    required this.firebaseService,
    required this.onSuccess,
    required this.onMakeNewPo,
  });

  @override
  State<_WaRevisionDialogContent> createState() => _WaRevisionDialogContentState();
}

class _WaRevisionDialogContentState extends State<_WaRevisionDialogContent> {
  late final AiChatParserService _parserService;
  final NumberFormat _rupiahFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _isLoading = true;
  String? _errorMessage;
  Customer? _targetCustomer;
  ChatOrderDraft? _draft;
  List<model_tr.Transaction> _customerInvoices = [];
  model_tr.Transaction? _selectedInvoice;
  bool _isMakeNewPo = false;
  String _mergeMode = 'ACCUMULATE'; // 'ACCUMULATE' or 'REPLACE'
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _parserService = AiChatParserService(widget.firebaseService);
    _initData();
  }

  Future<void> _initData() async {
    try {
      List<AiKnowledgeRule> rulesSnap = [];
      String generalInstructions = '';
      try {
        rulesSnap = await widget.firebaseService.streamAiKnowledgeRules().first.timeout(const Duration(seconds: 4));
      } catch (_) {}
      try {
        generalInstructions = await widget.firebaseService.getAiGeneralInstructions().timeout(const Duration(seconds: 4));
      } catch (_) {}

      final drafts = await _parserService.parseChatOrders(
        rawChat: widget.chat.messageText,
        customers: widget.customerProvider.customers,
        products: widget.productProvider.products,
        rules: rulesSnap,
        generalInstructions: generalInstructions,
        senderPhone: widget.chat.senderPhone,
      );

      if (drafts.isEmpty || drafts.first.items.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Tidak ditemukan format pesanan barang dalam teks chat ini.';
          });
        }
        return;
      }

      _draft = drafts.first;

      // 1. Resolve Target Customer
      if (_draft!.customerId.isNotEmpty) {
        _targetCustomer = widget.customerProvider.customers.firstWhere(
          (c) => c.id == _draft!.customerId,
          orElse: () => Customer(
            id: _draft!.customerId,
            customerName: _draft!.customerName,
            aliasName: _draft!.aliasName,
            address: '',
            city: _draft!.city,
            province: _draft!.province,
            country: 'INDONESIA',
            phone: widget.chat.senderPhone,
            ktpNumber: '',
          ),
        );
      } else {
        for (var c in widget.customerProvider.customers) {
          if (c.customerName.toLowerCase() == _draft!.customerName.toLowerCase() ||
              (c.aliasName.isNotEmpty && c.aliasName.toLowerCase() == _draft!.customerName.toLowerCase())) {
            _targetCustomer = c;
            break;
          }
        }
      }

      // 2. Fetch Customer's Invoices
      final allTxs = widget.txProvider.transactions;
      List<model_tr.Transaction> matches = [];

      if (_targetCustomer != null) {
        final cId = _targetCustomer!.id.toLowerCase();
        final cName = _targetCustomer!.customerName.toLowerCase().trim();
        final aName = _targetCustomer!.aliasName.toLowerCase().trim();

        matches = allTxs.where((t) {
          if (cId.isNotEmpty && t.customerId.toLowerCase() == cId) return true;
          final tName = t.customerName.toLowerCase().trim();
          final taName = t.aliasName.toLowerCase().trim();
          if (cName.isNotEmpty && (tName == cName || taName == cName)) return true;
          if (aName.isNotEmpty && (tName == aName || taName == aName)) return true;
          return false;
        }).toList();
      }

      // Fallback query directly to Firestore if provider is empty or no matches
      if (matches.isEmpty && _targetCustomer != null && _targetCustomer!.id.isNotEmpty) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('transactions')
              .where('customerId', isEqualTo: _targetCustomer!.id)
              .orderBy('createdAt', descending: true)
              .limit(15)
              .get();
          matches = snap.docs.map((d) => model_tr.Transaction.fromMap(d.data(), d.id)).toList();
        } catch (_) {}
      }

      matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _customerInvoices = matches;

      // 3. Pre-select invoice: PRIORITAS dari AI Vision (quotedInvoiceNo dari foto yang di-tag)
      if (widget.chat.quotedInvoiceNo != null && widget.chat.quotedInvoiceNo!.isNotEmpty) {
        final qInvNo = widget.chat.quotedInvoiceNo!;
        final found = _customerInvoices.where((t) => t.invoiceNo.toString() == qInvNo).toList();
        if (found.isNotEmpty) {
          _selectedInvoice = found.first;
          debugPrint('[REVISION DIALOG] Auto-selected Invoice #$qInvNo dari AI Vision (foto yang di-tag)');
        } else {
          // Invoice dari Vision mungkin milik customer lain atau sudah dihapus, cari di semua transaksi
          final allTxMatch = allTxs.where((t) => t.invoiceNo.toString() == qInvNo).toList();
          if (allTxMatch.isNotEmpty) {
            _customerInvoices.insert(0, allTxMatch.first);
            _selectedInvoice = allTxMatch.first;
            debugPrint('[REVISION DIALOG] Auto-selected Invoice #$qInvNo dari Vision (beda customer pool)');
          }
        }
      }

      // Fallback: check if invoice number is mentioned in chat text (e.g. #691)
      if (_selectedInvoice == null) {
        final invoiceMatch = RegExp(r'#?(\d{2,6})\b').firstMatch(widget.chat.messageText);
        if (invoiceMatch != null) {
          final numStr = invoiceMatch.group(1);
          final found = _customerInvoices.where((t) => t.invoiceNo.toString() == numStr).toList();
          if (found.isNotEmpty) {
            _selectedInvoice = found.first;
          }
        }
      }

      // If not selected yet, pick latest PENDING invoice
      if (_selectedInvoice == null) {
        final pending = _customerInvoices.where((t) => t.status == 'PENDING').toList();
        if (pending.isNotEmpty) {
          _selectedInvoice = pending.first;
        } else if (_customerInvoices.isNotEmpty) {
          _selectedInvoice = _customerInvoices.first;
        } else {
          _isMakeNewPo = true;
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Gagal memproses analisis chat: $e';
        });
      }
    }
  }

  void _showZoomImageDialog(BuildContext context, String imageUrl, String title) {
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
                    child: Builder(
                      builder: (context) {
                        final memBytes = KtpCacheManager.peekMemoryCache(imageUrl);
                        if (memBytes != null) {
                          return Image.memory(memBytes, fit: BoxFit.contain);
                        }
                        return FutureBuilder<KtpCacheResult?>(
                          future: KtpCacheManager.getOrFetchKtpImage(customerId: 'receipt', imageUrl: imageUrl),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return Image.memory(snapshot.data!.bytes, fit: BoxFit.contain);
                            }
                            return Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                              },
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text('Gagal memuat gambar.', style: TextStyle(color: Colors.redAccent)),
                              ),
                            );
                          },
                        );
                      },
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

  List<Map<String, dynamic>> _calculateDiff() {
    if (_selectedInvoice == null || _draft == null) return [];

    final List<Map<String, dynamic>> rows = [];

    if (_mergeMode == 'REPLACE') {
      for (var dItem in _draft!.items) {
        rows.add({
          'name': dItem.productName,
          'oldQtyStr': '-',
          'changeStr': '${dItem.qtyInput.toInt()} ${dItem.qtyUnit}',
          'newQtyStr': '${dItem.qtyInput.toInt()} ${dItem.qtyUnit}',
          'subtotalStr': _rupiahFormatter.format(dItem.subtotal),
          'isNew': true,
        });
      }
      return rows;
    }

    // ACCUMULATE mode
    final Set<String> handledDraftNames = {};

    for (var oldItem in _selectedInvoice!.items) {
      final cleanOld = oldItem.cleanProductName.toLowerCase();
      final matchDraft = _draft!.items.where((d) {
        final cleanD = d.productName.replaceAll(RegExp(r'\s*\(BONUS\)', caseSensitive: false), '').trim().toLowerCase();
        return cleanD == cleanOld;
      }).toList();

      if (matchDraft.isNotEmpty) {
        final dItem = matchDraft.first;
        handledDraftNames.add(dItem.productName.toLowerCase());

        final double addPcs = dItem.qtyPcs;
        final double finalPcs = oldItem.qty + addPcs;
        final double unitPrice = oldItem.price;
        final double disc = oldItem.discountPercent;
        final double gross = finalPcs * unitPrice;
        final double discAmt = gross * (disc / 100.0);
        final double finalSubtotal = (gross - discAmt).roundToDouble();

        final pcsPerKtn = (dItem.qtyPcs > 0 && dItem.qtyInput > 0) ? (dItem.qtyPcs / dItem.qtyInput) : 15.0;
        final oldKtn = (oldItem.qty / pcsPerKtn).round();
        final addKtn = dItem.qtyInput.toInt();
        final newKtn = oldKtn + addKtn;

        rows.add({
          'name': oldItem.displayNameWithBonus,
          'oldQtyStr': oldKtn > 0 ? '$oldKtn Ktn' : '${oldItem.qty.toInt()} pcs',
          'changeStr': '+${addKtn > 0 ? "$addKtn Ktn" : "${addPcs.toInt()} pcs"}',
          'newQtyStr': newKtn > 0 ? '$newKtn Ktn' : '${finalPcs.toInt()} pcs',
          'subtotalStr': _rupiahFormatter.format(finalSubtotal),
          'isNew': false,
        });
      } else {
        final oldKtn = (oldItem.qty / 15.0).round();
        rows.add({
          'name': oldItem.displayNameWithBonus,
          'oldQtyStr': oldKtn > 0 ? '$oldKtn Ktn' : '${oldItem.qty.toInt()} pcs',
          'changeStr': '(Tetap)',
          'newQtyStr': oldKtn > 0 ? '$oldKtn Ktn' : '${oldItem.qty.toInt()} pcs',
          'subtotalStr': _rupiahFormatter.format(oldItem.subtotal),
          'isNew': false,
        });
      }
    }

    // New items from draft not in old invoice
    for (var dItem in _draft!.items) {
      final cleanD = dItem.productName.replaceAll(RegExp(r'\s*\(BONUS\)', caseSensitive: false), '').trim().toLowerCase();
      if (!handledDraftNames.contains(dItem.productName.toLowerCase()) &&
          !_selectedInvoice!.items.any((it) => it.cleanProductName.toLowerCase() == cleanD)) {
        rows.add({
          'name': dItem.productName,
          'oldQtyStr': '-',
          'changeStr': '+${dItem.qtyInput.toInt()} ${dItem.qtyUnit}',
          'newQtyStr': '${dItem.qtyInput.toInt()} ${dItem.qtyUnit}',
          'subtotalStr': _rupiahFormatter.format(dItem.subtotal),
          'isNew': true,
        });
      }
    }

    return rows;
  }

  List<model_tr.TransactionItem> _buildFinalMergedItems() {
    if (_selectedInvoice == null || _draft == null) return [];

    if (_mergeMode == 'REPLACE') {
      return _draft!.items.map((it) {
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
    }

    final List<model_tr.TransactionItem> results = [];
    final Set<String> handledDraftNames = {};

    for (var oldItem in _selectedInvoice!.items) {
      final cleanOld = oldItem.cleanProductName.toLowerCase();
      final matchDraft = _draft!.items.where((d) {
        final cleanD = d.productName.replaceAll(RegExp(r'\s*\(BONUS\)', caseSensitive: false), '').trim().toLowerCase();
        return cleanD == cleanOld;
      }).toList();

      if (matchDraft.isNotEmpty) {
        final dItem = matchDraft.first;
        handledDraftNames.add(dItem.productName.toLowerCase());

        final double finalQty = oldItem.qty + dItem.qtyPcs;
        final double unitPrice = oldItem.price;
        final double disc = oldItem.discountPercent;
        final double gross = finalQty * unitPrice;
        final double discAmt = gross * (disc / 100.0);
        final double finalSubtotal = (gross - discAmt).roundToDouble();

        results.add(model_tr.TransactionItem(
          productId: oldItem.productId,
          productName: oldItem.productName,
          price: oldItem.price,
          qty: finalQty,
          discountPercent: oldItem.discountPercent,
          subtotal: finalSubtotal,
          sizeGrams: oldItem.sizeGrams,
          isBonus: oldItem.isBonus,
        ));
      } else {
        results.add(oldItem);
      }
    }

    for (var dItem in _draft!.items) {
      final cleanD = dItem.productName.replaceAll(RegExp(r'\s*\(BONUS\)', caseSensitive: false), '').trim().toLowerCase();
      if (!handledDraftNames.contains(dItem.productName.toLowerCase()) &&
          !_selectedInvoice!.items.any((it) => it.cleanProductName.toLowerCase() == cleanD)) {
        results.add(model_tr.TransactionItem(
          productId: dItem.productId,
          productName: dItem.productName,
          price: dItem.price,
          qty: dItem.qtyPcs,
          discountPercent: dItem.discountPercent,
          subtotal: dItem.subtotal,
          sizeGrams: dItem.sizeGrams,
          isBonus: dItem.isBonus,
        ));
      }
    }

    return results;
  }

  Future<void> _submitUpdate() async {
    if (_selectedInvoice == null) return;
    setState(() => _isSubmitting = true);

    try {
      final finalItems = _buildFinalMergedItems();
      final finalGrandTotal = finalItems.fold(0.0, (sum, it) => sum + (it.isBonus ? 0.0 : it.subtotal)).roundToDouble();

      final updatedTr = model_tr.Transaction(
        invoiceNo: _selectedInvoice!.invoiceNo,
        customerId: _selectedInvoice!.customerId,
        customerName: _selectedInvoice!.customerName,
        aliasName: _selectedInvoice!.aliasName,
        date: _selectedInvoice!.date,
        deliveryDate: _selectedInvoice!.deliveryDate,
        city: _selectedInvoice!.city,
        province: _selectedInvoice!.province,
        country: _selectedInvoice!.country,
        items: finalItems,
        grandTotal: finalGrandTotal,
        note: _selectedInvoice!.note,
        status: _selectedInvoice!.status,
        statusTransfer: _selectedInvoice!.statusTransfer,
        transferDate: _selectedInvoice!.transferDate,
        erpSyncDate: _selectedInvoice!.erpSyncDate,
        createdBy: _selectedInvoice!.createdBy,
        createdAt: _selectedInvoice!.createdAt,
        returnAmount: _selectedInvoice!.returnAmount,
        hasReturn: _selectedInvoice!.hasReturn,
        movedItems: _selectedInvoice!.movedItems,
        movedToInvoice: _selectedInvoice!.movedToInvoice,
        isLocked: _selectedInvoice!.isLocked,
        sourceInvoices: _selectedInvoice!.sourceInvoices,
        lampiranInvoiceNo: _selectedInvoice!.lampiranInvoiceNo,
        isLampiran: _selectedInvoice!.isLampiran,
      );

      await widget.firebaseService.updateTransaction(updatedTr);

      await FirebaseFirestore.instance.collection('incoming_po_chats').doc(widget.chat.id).update({
        'status': 'processed',
        'createdInvoiceNo': '${_selectedInvoice!.invoiceNo} (UPDATED)',
        'createdTransactionId': _selectedInvoice!.invoiceNo,
        'processedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.of(context).pop();
      }

      widget.onSuccess(
        _selectedInvoice!.invoiceNo,
        '🎉 Berhasil! Invoice #${_selectedInvoice!.invoiceNo} (${_targetCustomer?.customerName}) telah diperbarui dengan revisi order!',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui invoice: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFD97706).withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.edit_note_rounded, color: Color(0xFFFBBF24), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Proses Revisi / Update Pesanan', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  _targetCustomer != null ? 'Pelanggan: ${_targetCustomer!.customerName} (${_targetCustomer!.aliasName})' : 'Pengirim: ${widget.chat.senderName}',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: _isLoading
            ? const SizedBox(
                height: 250,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFBBF24)),
                      SizedBox(height: 12),
                      Text('Menganalisis chat dan mencocokkan nomor faktur...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                    ],
                  ),
                ),
              )
            : _errorMessage != null
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF7F1D1D).withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
                    child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Box Pesan WhatsApp Asli
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF38BDF8), size: 14),
                                  SizedBox(width: 6),
                                  Text('Teks Chat dari Pengirim:', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.chat.messageText,
                                style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12, fontFamily: 'monospace', height: 1.3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // AI Vision Detection Banner (jika foto yang di-tag berhasil di-scan)
                        if ((widget.chat.quotedInvoiceNo != null && widget.chat.quotedInvoiceNo!.isNotEmpty) ||
                            (widget.chat.quotedImageUrl != null && widget.chat.quotedImageUrl!.isNotEmpty) ||
                            (widget.chat.quotedOcrText != null && widget.chat.quotedOcrText!.trim().isNotEmpty)) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF10B981)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.chat.quotedImageUrl != null && widget.chat.quotedImageUrl!.isNotEmpty) ...[
                                      InkWell(
                                        onTap: () => _showZoomImageDialog(
                                          context,
                                          widget.chat.quotedImageUrl!,
                                          widget.chat.quotedInvoiceNo != null
                                              ? 'Foto yang Di-reply (Invoice #${widget.chat.quotedInvoiceNo})'
                                              : 'Foto yang Di-reply',
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: Builder(
                                                builder: (context) {
                                                  final qUrl = widget.chat.quotedImageUrl!;
                                                  final mem = KtpCacheManager.peekMemoryCache(qUrl);
                                                  if (mem != null) {
                                                    return Image.memory(mem, width: 70, height: 70, fit: BoxFit.cover);
                                                  }
                                                  return FutureBuilder<KtpCacheResult?>(
                                                    future: KtpCacheManager.getOrFetchKtpImage(customerId: 'receipt', imageUrl: qUrl),
                                                    builder: (context, snapshot) {
                                                      if (snapshot.hasData && snapshot.data != null) {
                                                        return Image.memory(snapshot.data!.bytes, width: 70, height: 70, fit: BoxFit.cover);
                                                      }
                                                      return Image.network(
                                                        qUrl,
                                                        width: 70,
                                                        height: 70,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (_, __, ___) => Container(
                                                          width: 70,
                                                          height: 70,
                                                          color: const Color(0xFF334155),
                                                          child: const Icon(Icons.broken_image, color: Color(0xFF64748B), size: 24),
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ),
                                            Positioned.fill(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.25),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Center(
                                                  child: Icon(Icons.zoom_in_rounded, color: Colors.white, size: 22),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.auto_awesome, color: Color(0xFF34D399), size: 16),
                                              const SizedBox(width: 6),
                                              const Text(
                                                'AI Vision: Foto yang Di-reply Berhasil Di-scan',
                                                style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                              const Spacer(),
                                              if (widget.chat.quotedImageUrl != null && widget.chat.quotedImageUrl!.isNotEmpty)
                                                const Text('🔍 Klik foto untuk zoom', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          if (widget.chat.quotedInvoiceNo != null) ...[
                                            Text(
                                              'Nomor Invoice terdeteksi dari screenshot: #${widget.chat.quotedInvoiceNo} (Otomatis terpilih di bawah)',
                                              style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ] else ...[
                                            const Text(
                                              'Foto terlampir pada balasan chat.',
                                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                // OCR Text Box if available
                                if (widget.chat.quotedOcrText != null && widget.chat.quotedOcrText!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A).withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.document_scanner_rounded, color: Color(0xFF38BDF8), size: 12),
                                            SizedBox(width: 4),
                                            Text(
                                              'Teks Terbaca dari Scan Foto (OCR):',
                                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          widget.chat.quotedOcrText!.trim(),
                                          style: const TextStyle(
                                            color: Color(0xFFE2E8F0),
                                            fontSize: 10.5,
                                            fontFamily: 'monospace',
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Section 1: Pemilihan Invoice Sasaran
                        const Text(
                          '1. Pilih Nomor Invoice yang Mau Di-update / Direvisi:',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),

                        if (_customerInvoices.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: !_isMakeNewPo ? const Color(0xFFD97706) : const Color(0xFF334155)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<model_tr.Transaction?>(
                                value: _isMakeNewPo ? null : _selectedInvoice,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1E293B),
                                hint: const Text('Pilih Invoice Terdaftar...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                items: _customerInvoices.map((tr) {
                                  final isPending = tr.status == 'PENDING';
                                  final totalKtn = tr.items.fold<double>(0.0, (sum, it) => sum + (it.qty / 15.0)).round();
                                  return DropdownMenuItem<model_tr.Transaction>(
                                    value: tr,
                                    child: Row(
                                      children: [
                                        Text('Invoice #${tr.invoiceNo}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isPending ? const Color(0xFF78350F) : const Color(0xFF065F46),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isPending ? 'PENDING' : 'DIKIRIM',
                                            style: TextStyle(color: isPending ? const Color(0xFFFBBF24) : const Color(0xFF34D399), fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(DateFormat('dd-MM-yyyy').format(tr.date), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                        const Spacer(),
                                        Text('$totalKtn Ktn • ${_rupiahFormatter.format(tr.grandTotal)}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedInvoice = val;
                                      _isMakeNewPo = false;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Radio: Opsi Buat PO Baru
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isMakeNewPo = true;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: _isMakeNewPo ? const Color(0xFF0284C7).withOpacity(0.15) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _isMakeNewPo ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
                            ),
                            child: Row(
                              children: [
                                Icon(_isMakeNewPo ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _isMakeNewPo ? const Color(0xFF38BDF8) : const Color(0xFF64748B), size: 18),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('+ Buat Sebagai PO Baru Terpisah (Nomor Baru)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                      Text('Tidak mengubah invoice lama, pesanan ini dibuatkan faktur baru tersendiri.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Warning jika Invoice Terpilih berstatus DIKIRIM
                        if (!_isMakeNewPo && _selectedInvoice != null && _selectedInvoice!.status == 'DIKIRIM') ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7F1D1D).withOpacity(0.4),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFEF4444)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFCA5A5), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '⚠️ Peringatan: Invoice #${_selectedInvoice!.invoiceNo} berstatus DIKIRIM (Tutup Buku). Mengubah invoice ini akan mempengaruhi laporan fisik stok gudang dan stok opname.',
                                    style: const TextStyle(color: Color(0xFFFEE2E2), fontSize: 11, height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Section 2: Mode Perubahan (Hanya jika update invoice)
                        if (!_isMakeNewPo && _selectedInvoice != null) ...[
                          Row(
                            children: [
                              const Text('2. Metode Penggabungan:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 12),
                              ChoiceChip(
                                label: const Text('➕ Tambah Qty (Akumulasi)', style: TextStyle(fontSize: 11)),
                                selected: _mergeMode == 'ACCUMULATE',
                                selectedColor: const Color(0xFFD97706),
                                backgroundColor: const Color(0xFF0F172A),
                                labelStyle: TextStyle(color: _mergeMode == 'ACCUMULATE' ? Colors.white : const Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                                onSelected: (sel) {
                                  if (sel) setState(() => _mergeMode = 'ACCUMULATE');
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('🔄 Ganti Total (Replace)', style: TextStyle(fontSize: 11)),
                                selected: _mergeMode == 'REPLACE',
                                selectedColor: const Color(0xFF0284C7),
                                backgroundColor: const Color(0xFF0F172A),
                                labelStyle: TextStyle(color: _mergeMode == 'REPLACE' ? Colors.white : const Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                                onSelected: (sel) {
                                  if (sel) setState(() => _mergeMode = 'REPLACE');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Section 3: Pratinjau Perubahan (Diff Preview Table)
                          const Text('3. Pratinjau Perubahan Barang:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),

                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Column(
                              children: [
                                // Table Header
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1E293B),
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                                  ),
                                  child: const Row(
                                    children: [
                                      Expanded(flex: 4, child: Text('Nama Produk', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                      Expanded(flex: 2, child: Text('Qty Lama', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                      Expanded(flex: 2, child: Text('Revisi Chat', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold))),
                                      Expanded(flex: 2, child: Text('Qty Akhir', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold))),
                                      Expanded(flex: 3, child: Text('Subtotal Akhir', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                ),
                                // Table Rows
                                ..._calculateDiff().map((row) {
                                  final isNew = row['isNew'] == true;
                                  final isChange = row['changeStr'] != '(Tetap)';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.04))),
                                      color: isChange ? const Color(0xFFD97706).withOpacity(0.06) : Colors.transparent,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 4,
                                          child: Row(
                                            children: [
                                              if (isNew) ...[
                                                Container(
                                                  margin: const EdgeInsets.only(right: 6),
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                  decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(4)),
                                                  child: const Text('BARU', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                              Expanded(
                                                child: Text(row['name'], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(flex: 2, child: Text(row['oldQtyStr'], textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11))),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            row['changeStr'],
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: isChange ? const Color(0xFFFBBF24) : const Color(0xFF64748B),
                                              fontSize: 11,
                                              fontWeight: isChange ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        Expanded(flex: 2, child: Text(row['newQtyStr'], textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold))),
                                        Expanded(flex: 3, child: Text(row['subtotalStr'], textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Total Comparison Summary Box
                          () {
                            final finalItems = _buildFinalMergedItems();
                            final finalTotal = finalItems.fold(0.0, (sum, it) => sum + (it.isBonus ? 0.0 : it.subtotal)).roundToDouble();
                            final finalKtn = finalItems.fold<double>(0.0, (sum, it) => sum + (it.qty / 15.0)).round();
                            final oldKtn = _selectedInvoice!.items.fold<double>(0.0, (sum, it) => sum + (it.qty / 15.0)).round();

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF064E3B).withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF059669)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Total Karton: $oldKtn Ktn ➔ $finalKtn Ktn', style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 12, fontWeight: FontWeight.bold)),
                                  Text(
                                    'Grand Total: ${_rupiahFormatter.format(_selectedInvoice!.grandTotal)} ➔ ${_rupiahFormatter.format(finalTotal)}',
                                    style: const TextStyle(color: Color(0xFF34D399), fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          }(),
                        ],
                      ],
                    ),
                  ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF94A3B8), side: const BorderSide(color: Color(0xFF334155))),
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        if (!_isMakeNewPo && _selectedInvoice != null) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isSubmitting ? null : _submitUpdate,
            icon: _isSubmitting
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            label: Text(
              _isSubmitting ? 'Memperbarui...' : 'Terapkan & Update Invoice #${_selectedInvoice!.invoiceNo}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ] else if (_isMakeNewPo) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onMakeNewPo();
            },
            icon: const Icon(Icons.add_task_rounded, color: Colors.white, size: 16),
            label: const Text('Buat Sebagai PO Baru Terpisah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ],
    );
  }
}
