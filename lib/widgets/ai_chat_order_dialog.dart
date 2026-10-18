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

void showAiChatOrderDialog(BuildContext context, {String? initialChatText}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AiChatOrderDialogContent(initialChatText: initialChatText),
  );
}

class _AiChatOrderDialogContent extends StatefulWidget {
  final String? initialChatText;
  const _AiChatOrderDialogContent({this.initialChatText});

  @override
  State<_AiChatOrderDialogContent> createState() => _AiChatOrderDialogContentState();
}

class _AiChatOrderDialogContentState extends State<_AiChatOrderDialogContent> {
  final TextEditingController _chatInputController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();
  late final AiChatParserService _parserService;

  bool _isAnalyzing = false;
  bool _isSavingAll = false;
  bool _isSyncingMemory = false;
  List<ChatOrderDraft> _parsedDrafts = [];
  final NumberFormat _rupiahFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _parserService = AiChatParserService(_firebaseService);
    if (widget.initialChatText != null && widget.initialChatText!.trim().isNotEmpty) {
      _chatInputController.text = widget.initialChatText!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyzeChat();
      });
    }
  }

  Future<void> _syncMemory() async {
    setState(() => _isSyncingMemory = true);
    try {
      final res = await _firebaseService.syncCustomerProductMemory();
      final customersCount = res['customersCount'] ?? 0;
      final productsCount = res['productsCount'] ?? 0;
      if (mounted) {
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🧠 Memori pelanggan berhasil diperbarui ($customersCount toko, $productsCount barang)!'),
              backgroundColor: Colors.teal,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal sinkronkan memori: ${res['error']}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal sinkronkan memori: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingMemory = false);
    }
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

  Future<Customer?> _showAutoRegisterCustomerDialog(ChatOrderDraft draft) async {
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    // List of supported cities in Central Java & DIY
    final List<String> supportedCities = [
      'SURAKARTA',
      'SOLO',
      'SEMARANG',
      'WONOSOBO',
      'MAGELANG',
      'KUDUS',
      'JEPARA',
      'PATI',
      'PEKALONGAN',
      'TEGAL',
      'BREBES',
      'BATANG',
      'PEMALANG',
      'DEMAK',
      'GROBOGAN',
      'PURWODADI',
      'SALATIGA',
      'KENDAL',
      'PURWOREJO',
      'TEMANGGUNG',
      'KEBUMEN',
      'BANJARNEGARA',
      'PURBALINGGA',
      'BANYUMAS',
      'CILACAP',
      'REMBANG',
      'BLORA',
      'SRAGEN',
      'KARANGANYAR',
      'KLATEN',
      'BOYOLALI',
      'COLOMADU',
      'BANJARSARI',
      'GUBUG',
      'YOGYAKARTA',
      'SLEMAN',
      'BANTUL',
      'KULONPROGO',
      'GUNUNGKIDUL',
      'WATES',
    ];

    // Determine initial city
    String detectedCity = draft.city.trim().toUpperCase();
    if (!supportedCities.contains(detectedCity)) {
      final rawUpper = '${draft.rawChatBlock} ${draft.customerRawName}'.toUpperCase();
      for (var c in supportedCities) {
        if (rawUpper.contains(c)) {
          detectedCity = c;
          break;
        }
      }
      if (!supportedCities.contains(detectedCity)) {
        detectedCity = 'SURAKARTA';
      }
    }

    String initialStoreName = draft.aliasName.isNotEmpty ? draft.aliasName : draft.customerName;
    if (initialStoreName.isEmpty) initialStoreName = draft.customerRawName;

    String currentCity = detectedCity;
    final storeNameController = TextEditingController(text: initialStoreName);
    final ownerNameController = TextEditingController(text: initialStoreName);
    final phoneController = TextEditingController();
    final cityController = TextEditingController(text: currentCity);
    final cityFocusNode = FocusNode();

    String generatedId = '';
    bool isLoadingId = true;
    bool isSaving = false;

    return await showDialog<Customer>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void fetchId(String city) async {
              setDialogState(() => isLoadingId = true);
              try {
                final id = await _firebaseService.generateCustomerID(city);
                setDialogState(() {
                  generatedId = id;
                  isLoadingId = false;
                });
              } catch (e) {
                setDialogState(() {
                  generatedId = 'ERROR';
                  isLoadingId = false;
                });
              }
            }

            if (generatedId.isEmpty && isLoadingId) {
              fetchId(currentCity);
            }

            String platKode = _firebaseService.getPlatKode(currentCity);
            String platAreaName = '';
            switch (platKode) {
              case 'AD':
                platAreaName = 'Solo Raya / Surakarta';
                break;
              case 'AA':
                platAreaName = 'Kedu (Wonosobo, Magelang, dll)';
                break;
              case 'H':
                platAreaName = 'Semarang Raya';
                break;
              case 'G':
                platAreaName = 'Pekalongan / Pantura Barat';
                break;
              case 'K':
                platAreaName = 'Muria / Pati / Kudus';
                break;
              case 'R':
                platAreaName = 'Banyumas Raya';
                break;
              case 'AB':
                platAreaName = 'D.I. Yogyakarta';
                break;
              default:
                platAreaName = 'Jawa Tengah';
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.amberAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Toko Belum Terdaftar di Master',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Daftarkan otomatis agar riwayat & ID resmi tersimpan',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Generated ID Card (Highlight)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ID PELANGGAN RESMI (AUTO PLAT):',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (isLoadingId)
                                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
                                    else
                                      Text(
                                        generatedId,
                                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                      ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF38BDF8).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Plat $platKode ($platAreaName)',
                                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Icon(Icons.verified_rounded, color: Color(0xFF38BDF8), size: 30),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Nama Toko / Alias
                      const Text('Nama Toko / Panggilan (Alias):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: storeNameController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          hintText: 'Contoh: LUCIFAX FF',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Nama Pemilik (Opsional)
                      const Text('Nama Lengkap Pemilik (Opsional):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: ownerNameController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          hintText: 'Contoh: SUSILO HARYAWAN',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Kota Searchable Input (Can type or pick from suggestions, updates ID live)
                      const Text('Kota / Wilayah Toko (Bisa Diketik):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      RawAutocomplete<String>(
                        textEditingController: cityController,
                        focusNode: cityFocusNode,
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return supportedCities;
                          }
                          final q = textEditingValue.text.toLowerCase().trim();
                          return supportedCities.where((c) {
                            final pKode = _firebaseService.getPlatKode(c).toLowerCase();
                            return c.toLowerCase().contains(q) || pKode.contains(q);
                          });
                        },
                        displayStringForOption: (String option) => option,
                        onSelected: (String selection) {
                          setDialogState(() {
                            currentCity = selection;
                            cityController.text = selection;
                            fetchId(selection);
                          });
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              hintText: 'Ketik kota (e.g. Solo, Semarang, Kudus)...',
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                              prefixIcon: const Icon(Icons.location_city_rounded, color: Color(0xFF38BDF8), size: 18),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF94A3B8)),
                                onPressed: () {
                                  if (focusNode.hasFocus) {
                                    focusNode.unfocus();
                                  } else {
                                    focusNode.requestFocus();
                                  }
                                },
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onChanged: (val) {
                              final upper = val.trim().toUpperCase();
                              if (supportedCities.contains(upper) && upper != currentCity) {
                                setDialogState(() {
                                  currentCity = upper;
                                  fetchId(upper);
                                });
                              }
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8,
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 460, maxHeight: 200),
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: options.length,
                                  separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                                  itemBuilder: (context, index) {
                                    final c = options.elementAt(index);
                                    final pKode = _firebaseService.getPlatKode(c);
                                    final isSelected = c == currentCity;
                                    return ListTile(
                                      dense: true,
                                      selected: isSelected,
                                      selectedTileColor: const Color(0xFF0284C7).withOpacity(0.2),
                                      title: Text(
                                        '$c (Plat $pKode)',
                                        style: TextStyle(
                                          color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        ),
                                      ),
                                      trailing: Text('Plat $pKode', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                      onTap: () => onSelected(c),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      // Nomor Telepon (Opsional)
                      const Text('Nomor Telepon / WhatsApp (Opsional):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          hintText: 'Contoh: 08123456789',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx, null),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: (isSaving || isLoadingId || generatedId.isEmpty || generatedId == 'ERROR')
                      ? null
                      : () async {
                          final sName = storeNameController.text.trim();
                          final oName = ownerNameController.text.trim();
                          final phone = phoneController.text.trim();

                          if (sName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Nama Toko wajib diisi!'), backgroundColor: Colors.orange),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          try {
                            final finalCustomer = Customer(
                              id: generatedId,
                              customerName: oName.isNotEmpty ? oName : sName,
                              aliasName: sName,
                              address: '',
                              city: currentCity,
                              province: 'JAWA TENGAH',
                              country: 'INDONESIA',
                              phone: phone,
                              ktpNumber: '',
                            );

                            // 1. Save customer to master
                            await customerProvider.saveCustomer(finalCustomer);

                            // 2. Automatically register alias to AI Knowledge Rules
                            final aliasRule = AiKnowledgeRule(
                              id: '',
                              type: 'customer_alias',
                              keyword: sName,
                              mappedValue: finalCustomer.customerName,
                              targetId: finalCustomer.id,
                              createdAt: DateTime.now(),
                              updatedBy: 'AI Auto Register',
                            );
                            await _firebaseService.saveAiKnowledgeRule(aliasRule);

                            if (mounted) {
                              Navigator.pop(dialogCtx, finalCustomer);
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Gagal mendaftarkan toko: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                  label: Text(
                    isSaving ? 'Mendaftarkan...' : 'Ya, Daftarkan & Buat PO',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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
      // Find by name or alias
      targetCustomer = customerProvider.customers.firstWhere(
        (c) => c.customerName.toLowerCase() == draft.customerName.toLowerCase() ||
            (c.aliasName.isNotEmpty && c.aliasName.toLowerCase() == draft.customerName.toLowerCase()),
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

    // Auto-Register Confirmation if customer is not yet in Master
    if (targetCustomer.id.isEmpty) {
      final registeredCustomer = await _showAutoRegisterCustomerDialog(draft);
      if (registeredCustomer == null) {
        // User cancelled dialog
        return;
      }
      targetCustomer = registeredCustomer;
      setState(() {
        draft.customerId = registeredCustomer.id;
        draft.customerName = registeredCustomer.customerName;
        draft.aliasName = registeredCustomer.aliasName;
        draft.city = registeredCustomer.city;
        draft.province = registeredCustomer.province;
      });
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
        note: draft.note,
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

    // Check if any draft has unregistered customer
    final unregIndex = _parsedDrafts.indexWhere((d) => d.customerId.isEmpty);
    if (unregIndex != -1) {
      final unreg = _parsedDrafts[unregIndex];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Toko "${unreg.customerName}" belum terdaftar. Silakan buat PO satu per satu untuk mendaftarkannya terlebih dahulu!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 32, vertical: isMobile ? 12 : 24),
      child: Container(
        width: 1020,
        height: MediaQuery.of(context).size.height * (isMobile ? 0.94 : 0.88),
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scan Chat WhatsApp → Auto PO',
                              style: TextStyle(color: Colors.white, fontSize: isMobile ? 15 : 18, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Otomatis mengenali toko, kuantiti, dan histori nota',
                              style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isMobile ? 10 : 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
                  if (isMobile)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isAnalyzing ? null : _analyzeChat,
                          icon: _isAnalyzing
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                          label: Text(
                            _isAnalyzing ? 'Menganalisa...' : '⚡ Analisa & Pecah Chat Jadi PO',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: TextButton.icon(
                            onPressed: _isSyncingMemory ? null : _syncMemory,
                            icon: _isSyncingMemory
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
                                : const Icon(Icons.psychology_alt_rounded, color: Color(0xFF38BDF8), size: 16),
                            label: Text(
                              _isSyncingMemory ? 'Menyinkronkan...' : '🧠 Sinkronkan Memori Pelanggan',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _isSyncingMemory ? null : _syncMemory,
                          icon: _isSyncingMemory
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
                              : const Icon(Icons.psychology_alt_rounded, color: Color(0xFF38BDF8), size: 16),
                          label: Text(
                            _isSyncingMemory ? 'Menyinkronkan...' : '🧠 Sinkronkan Memori Pelanggan',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
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
            if (isMobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('Hasil Deteksi Draft PO:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
                  if (_parsedDrafts.length > 1) ...[
                    const SizedBox(height: 8),
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
                ],
              )
            else
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
              child: _isAnalyzing
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF38BDF8).withOpacity(0.08), blurRadius: 24, spreadRadius: 2),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF38BDF8).withOpacity(0.85)),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  '🔍 Menganalisa Chat...',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Mengenali toko, barang, kuantiti, dan menarik harga dari histori nota...',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : _parsedDrafts.isEmpty
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
    final isMobile = MediaQuery.of(context).size.width < 768;

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
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 8 : 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.7),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                            const SizedBox(width: 6),
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
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () async {
                                final registered = await _showAutoRegisterCustomerDialog(draft);
                                if (registered != null) {
                                  setState(() {
                                    draft.customerId = registered.id;
                                    draft.customerName = registered.customerName;
                                    draft.aliasName = registered.aliasName;
                                    draft.city = registered.city;
                                    draft.province = registered.province;
                                  });
                                }
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amberAccent),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('⚠️ Belum Terdaftar', style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                    SizedBox(width: 4),
                                    Text('(Daftar)', style: TextStyle(color: Colors.white70, fontSize: 9.5)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (draft.city.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(4)),
                              child: Text(draft.city, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                            )
                          else
                            const SizedBox(),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () => _createTransactionFromDraft(draft, draftIndex),
                            icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 14),
                            label: const Text('Buat PO Transaksi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
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
                              InkWell(
                                onTap: () async {
                                  final registered = await _showAutoRegisterCustomerDialog(draft);
                                  if (registered != null) {
                                    setState(() {
                                      draft.customerId = registered.id;
                                      draft.customerName = registered.customerName;
                                      draft.aliasName = registered.aliasName;
                                      draft.city = registered.city;
                                      draft.province = registered.province;
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amberAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amberAccent),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('⚠️ Belum Terdaftar', style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                      SizedBox(width: 4),
                                      Text('(Daftarkan)', style: TextStyle(color: Colors.white70, fontSize: 9.5)),
                                    ],
                                  ),
                                ),
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
            padding: EdgeInsets.all(isMobile ? 8 : 12),
            child: Column(
              children: [
                if (isMobile)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 520,
                      child: Table(
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
                                      if (item.invoiceNo.isNotEmpty)
                                        Text('[Ref: #${item.invoiceNo}]', style: TextStyle(color: const Color(0xFF38BDF8).withOpacity(0.7), fontSize: 9)),
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
                    ),
                  )
                else
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
                                  if (item.invoiceNo.isNotEmpty)
                                    Text('[Ref: #${item.invoiceNo}]', style: TextStyle(color: const Color(0xFF38BDF8).withOpacity(0.7), fontSize: 9)),
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
