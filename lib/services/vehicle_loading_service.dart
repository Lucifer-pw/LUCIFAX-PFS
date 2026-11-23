import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/product.dart';
import '../models/transaction.dart';

/// Allocation of an item to a specific invoice / customer
class VehicleLoadingAllocation {
  final String invoiceNo;
  final String customerName;
  final String city;
  final double qty; // pcs
  final double karton;
  final double weightKg;
  final String originalItemName;
  final double price;
  final bool isBonus;

  VehicleLoadingAllocation({
    required this.invoiceNo,
    required this.customerName,
    required this.city,
    required this.qty,
    required this.karton,
    required this.weightKg,
    required this.originalItemName,
    required this.price,
    this.isBonus = false,
  });

  String get kartonFormatted {
    if (karton <= 0) return '0 Ktn';
    if (karton % 1 == 0) return '${karton.toInt()} Ktn';
    return '${karton.toStringAsFixed(1)} Ktn';
  }
}

/// Aggregated item grouped by Kode Induk (physical product identity)
class VehicleLoadingItem {
  final String kodeInduk;
  final String canonicalProductName;
  final int isiKarton;
  final double sizeGrams;
  double totalQty; // total pcs
  double totalKarton;
  double totalWeightKg;
  double currentStockPcs; // Stok fisik saat ini di gudang (pcs) berdasarkan kodeInduk
  double currentStockKtn; // Stok fisik saat ini di gudang (karton)
  final List<VehicleLoadingAllocation> allocations;

  VehicleLoadingItem({
    required this.kodeInduk,
    required this.canonicalProductName,
    required this.isiKarton,
    required this.sizeGrams,
    required this.totalQty,
    required this.totalKarton,
    required this.totalWeightKg,
    this.currentStockPcs = 0.0,
    this.currentStockKtn = 0.0,
    List<VehicleLoadingAllocation>? allocations,
  }) : allocations = allocations ?? [];

  String get totalKartonFormatted {
    if (totalKarton <= 0) return '0 Ktn';
    if (totalKarton % 1 == 0) return '${totalKarton.toInt()} Ktn';
    return '${totalKarton.toStringAsFixed(1)} Ktn';
  }

  // Sisa stok fisik setelah dikurangi muatan skim ini
  double get remainingStockPcs => currentStockPcs - totalQty;
  double get remainingStockKtn => currentStockKtn - totalKarton;

  // Status apakah stok kurang / minus (butuh restock order pabrik)
  bool get isDeficit => remainingStockPcs < 0;

  // Berapa karton & pcs kekurangannya (untuk order pabrik)
  double get deficitPcs => isDeficit ? (totalQty - currentStockPcs) : 0.0;
  double get deficitKtn => isDeficit ? (totalKarton - currentStockKtn) : 0.0;

  String get currentStockKtnFormatted {
    if (currentStockKtn <= 0) return '0 Ktn';
    if (currentStockKtn % 1 == 0) return '${currentStockKtn.toInt()} Ktn';
    return '${currentStockKtn.toStringAsFixed(1)} Ktn';
  }

  String get remainingStockKtnFormatted {
    final r = remainingStockKtn;
    if (r == 0) return '0 Ktn';
    final sign = r > 0 ? '+' : '';
    if (r % 1 == 0) return '$sign${r.toInt()} Ktn';
    return '$sign${r.toStringAsFixed(1)} Ktn';
  }

  String get deficitKtnFormatted {
    final d = deficitKtn;
    if (d <= 0) return '0 Ktn';
    if (d % 1 == 0) return '${d.toInt()} Ktn';
    return '${d.toStringAsFixed(1)} Ktn';
  }
}

/// Summary per invoice included in the vehicle load
class VehicleLoadingInvoiceSummary {
  final String invoiceNo;
  final String customerName;
  final String city;
  final double totalKarton;
  final double totalQty;
  final double totalWeightKg;
  final int itemCount;
  final String statusKirim;
  final String statusBayar;

  VehicleLoadingInvoiceSummary({
    required this.invoiceNo,
    required this.customerName,
    required this.city,
    required this.totalKarton,
    required this.totalQty,
    required this.totalWeightKg,
    required this.itemCount,
    required this.statusKirim,
    required this.statusBayar,
  });

  String get totalKartonFormatted {
    if (totalKarton <= 0) return '0 Ktn';
    if (totalKarton % 1 == 0) return '${totalKarton.toInt()} Ktn';
    return '${totalKarton.toStringAsFixed(1)} Ktn';
  }
}

/// Full aggregated loading summary for a vehicle run
class VehicleLoadingSummary {
  final List<Transaction> selectedTransactions;
  final List<VehicleLoadingItem> items;
  final List<VehicleLoadingInvoiceSummary> invoiceSummaries;
  final double grandTotalKarton;
  final double grandTotalQty;
  final double grandTotalWeightKg;
  final List<String> distinctCustomers;
  final List<String> distinctCities;

  VehicleLoadingSummary({
    required this.selectedTransactions,
    required this.items,
    required this.invoiceSummaries,
    required this.grandTotalKarton,
    required this.grandTotalQty,
    required this.grandTotalWeightKg,
    required this.distinctCustomers,
    required this.distinctCities,
  });

  String get grandTotalKartonStr {
    if (grandTotalKarton <= 0) return '0 Ktn';
    if (grandTotalKarton % 1 == 0) return '${grandTotalKarton.toInt()} Ktn';
    return '${grandTotalKarton.toStringAsFixed(1)} Ktn';
  }

  // Defisit / Kebutuhan Restock Pabrik
  int get totalDeficitSkuCount => items.where((i) => i.isDeficit).length;
  double get totalDeficitKarton => items.where((i) => i.isDeficit).fold(0.0, (sum, i) => sum + i.deficitKtn);
  double get totalDeficitQty => items.where((i) => i.isDeficit).fold(0.0, (sum, i) => sum + i.deficitPcs);

  String get totalDeficitKartonStr {
    if (totalDeficitKarton <= 0) return '0 Ktn';
    if (totalDeficitKarton % 1 == 0) return '${totalDeficitKarton.toInt()} Ktn';
    return '${totalDeficitKarton.toStringAsFixed(1)} Ktn';
  }
}

class VehicleLoadingService {
  /// Aggregates items from selected transactions based on [Product.kodeInduk]
  static VehicleLoadingSummary calculateLoadingSummary({
    required List<Transaction> transactions,
    required List<Product> products,
  }) {
    if (transactions.isEmpty) {
      return VehicleLoadingSummary(
        selectedTransactions: [],
        items: [],
        invoiceSummaries: [],
        grandTotalKarton: 0.0,
        grandTotalQty: 0.0,
        grandTotalWeightKg: 0.0,
        distinctCustomers: [],
        distinctCities: [],
      );
    }

    // Fast lookup dictionaries
    final byId = {for (var p in products) p.id.toLowerCase().trim(): p};
    final byName = {for (var p in products) p.name.toLowerCase().trim(): p};
    final byKodeInduk = <String, List<Product>>{};
    final Map<String, double> stockByKodeInduk = {};
    final Map<String, int> isiKartonByKodeInduk = {};

    for (var p in products) {
      final k = p.kodeInduk.toLowerCase().trim();
      if (k.isNotEmpty) {
        byKodeInduk.putIfAbsent(k, () => []).add(p);
        // Track physical stock per kodeInduk (taking max across price variants/docs)
        if (!stockByKodeInduk.containsKey(k) || p.stock > stockByKodeInduk[k]!) {
          stockByKodeInduk[k] = p.stock;
        }
        if (p.isiKarton > 0 && !isiKartonByKodeInduk.containsKey(k)) {
          isiKartonByKodeInduk[k] = p.isiKarton;
        }
      }
      final idKey = p.id.toLowerCase().trim();
      if (idKey.isNotEmpty && !stockByKodeInduk.containsKey(idKey)) {
        stockByKodeInduk[idKey] = p.stock;
      }
    }

    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Product resolver helper
    Product? resolveProduct(TransactionItem item) {
      final idClean = item.productId.toLowerCase().trim();
      final nameClean = item.productName.toLowerCase().trim();
      final cleanName = item.cleanProductName.toLowerCase().trim();

      if (idClean.isNotEmpty && byId.containsKey(idClean)) return byId[idClean];
      if (nameClean.isNotEmpty && byName.containsKey(nameClean)) return byName[nameClean];
      if (cleanName.isNotEmpty && byName.containsKey(cleanName)) return byName[cleanName];

      if (idClean.isNotEmpty && byKodeInduk.containsKey(idClean)) {
        return byKodeInduk[idClean]!.first;
      }
      if (cleanName.isNotEmpty && byKodeInduk.containsKey(cleanName)) {
        return byKodeInduk[cleanName]!.first;
      }

      // Normalized fallback
      final normName = norm(cleanName);
      if (normName.isNotEmpty) {
        for (var p in products) {
          if (norm(p.name) == normName || norm(p.kodeInduk) == normName) {
            return p;
          }
        }
      }
      return null;
    }

    // Primary master product name for a kodeInduk
    String getCanonicalNameForKodeInduk(String kodeInduk, Product? matched, String fallbackName) {
      final kClean = kodeInduk.toLowerCase().trim();
      final siblings = byKodeInduk[kClean];
      if (siblings != null && siblings.isNotEmpty) {
        // Prefer sibling where name or id equals kodeInduk, or first non-empty name
        for (var s in siblings) {
          if (s.name.toUpperCase().trim() == kodeInduk.toUpperCase().trim()) return s.name.trim();
        }
        return siblings.first.name.trim();
      }
      if (matched != null && matched.name.trim().isNotEmpty) {
        return matched.name.trim();
      }
      return fallbackName;
    }

    final Map<String, VehicleLoadingItem> groupedItems = {};
    final List<VehicleLoadingInvoiceSummary> invoiceSummaries = [];

    double grandTotalKarton = 0.0;
    double grandTotalQty = 0.0;
    double grandTotalWeightKg = 0.0;

    final Set<String> customersSet = {};
    final Set<String> citiesSet = {};

    for (var tr in transactions) {
      final custName = tr.aliasName.isNotEmpty ? tr.aliasName : tr.customerName;
      if (custName.trim().isNotEmpty) customersSet.add(custName.trim());
      if (tr.city.trim().isNotEmpty) citiesSet.add(tr.city.trim());

      double invKarton = 0.0;
      double invQty = 0.0;
      double invWeight = 0.0;

      for (var item in tr.items) {
        final Product? matched = resolveProduct(item);

        // Determine effective kodeInduk
        String effectiveKodeInduk;
        if (matched != null && matched.kodeInduk.trim().isNotEmpty) {
          effectiveKodeInduk = matched.kodeInduk.trim().toUpperCase();
        } else if (item.productId.trim().isNotEmpty) {
          effectiveKodeInduk = item.productId.trim().toUpperCase();
        } else {
          effectiveKodeInduk = item.cleanProductName.trim().toUpperCase();
        }

        final canonicalName = getCanonicalNameForKodeInduk(effectiveKodeInduk, matched, item.cleanProductName);
        final kLookup = effectiveKodeInduk.toLowerCase().trim();
        final int isiKarton = (matched != null && matched.isiKarton > 0)
            ? matched.isiKarton
            : (isiKartonByKodeInduk[kLookup] ?? _inferIsiKartonFromName(canonicalName));

        final double itemKarton = (isiKarton > 0 && item.qty > 0) ? (item.qty / isiKarton) : 0.0;
        final double itemWeight = item.weightKg > 0 ? item.weightKg : (item.qty * item.sizeGrams / 1000.0);

        final double stockPcs = stockByKodeInduk[kLookup] ?? (matched?.stock ?? 0.0);
        final double stockKtn = (isiKarton > 0 && stockPcs > 0) ? (stockPcs / isiKarton) : 0.0;

        invKarton += itemKarton;
        invQty += item.qty;
        invWeight += itemWeight;

        grandTotalKarton += itemKarton;
        grandTotalQty += item.qty;
        grandTotalWeightKg += itemWeight;

        final allocation = VehicleLoadingAllocation(
          invoiceNo: tr.invoiceNo.toString().replaceAll('#', ''),
          customerName: custName,
          city: tr.city,
          qty: item.qty,
          karton: itemKarton,
          weightKg: itemWeight,
          originalItemName: item.displayNameWithBonus,
          price: item.price,
          isBonus: item.isBonus,
        );

        if (!groupedItems.containsKey(effectiveKodeInduk)) {
          groupedItems[effectiveKodeInduk] = VehicleLoadingItem(
            kodeInduk: effectiveKodeInduk,
            canonicalProductName: canonicalName,
            isiKarton: isiKarton,
            sizeGrams: matched?.sizeGrams ?? item.sizeGrams,
            totalQty: item.qty,
            totalKarton: itemKarton,
            totalWeightKg: itemWeight,
            currentStockPcs: stockPcs,
            currentStockKtn: stockKtn,
            allocations: [allocation],
          );
        } else {
          final existing = groupedItems[effectiveKodeInduk]!;
          existing.totalQty += item.qty;
          existing.totalKarton += itemKarton;
          existing.totalWeightKg += itemWeight;
          existing.allocations.add(allocation);
          if (existing.currentStockPcs == 0 && stockPcs > 0) {
            existing.currentStockPcs = stockPcs;
            existing.currentStockKtn = stockKtn;
          }
        }
      }

      invoiceSummaries.add(VehicleLoadingInvoiceSummary(
        invoiceNo: tr.invoiceNo.toString().replaceAll('#', ''),
        customerName: custName,
        city: tr.city,
        totalKarton: invKarton,
        totalQty: invQty,
        totalWeightKg: invWeight,
        itemCount: tr.items.length,
        statusKirim: tr.status,
        statusBayar: tr.statusTransfer,
      ));
    }

    // Sort items alphabetically by canonical product name
    final sortedItems = groupedItems.values.toList()
      ..sort((a, b) => a.canonicalProductName.toLowerCase().compareTo(b.canonicalProductName.toLowerCase()));

    // Sort allocations inside each item by invoiceNo numeric or string
    for (var item in sortedItems) {
      item.allocations.sort((a, b) {
        final aNum = int.tryParse(a.invoiceNo) ?? 0;
        final bNum = int.tryParse(b.invoiceNo) ?? 0;
        if (aNum > 0 && bNum > 0) return aNum.compareTo(bNum);
        return a.invoiceNo.compareTo(b.invoiceNo);
      });
    }

    return VehicleLoadingSummary(
      selectedTransactions: transactions,
      items: sortedItems,
      invoiceSummaries: invoiceSummaries,
      grandTotalKarton: grandTotalKarton,
      grandTotalQty: grandTotalQty,
      grandTotalWeightKg: grandTotalWeightKg,
      distinctCustomers: customersSet.toList()..sort(),
      distinctCities: citiesSet.toList()..sort(),
    );
  }

  /// Best-effort inference for isiKarton if master product is missing
  static int _inferIsiKartonFromName(String name) {
    final upper = name.toUpperCase();
    if (upper.contains('24S') || upper.contains('24 S') || upper.contains('24 ')) return 15;
    if (upper.contains('13S') || upper.contains('13 S') || upper.contains('13 ')) return 15;
    if (upper.contains('7S') || upper.contains('7 S') || upper.contains('7 ')) return 15;
    if (upper.contains('ROLLADE') || upper.contains('ROLADE')) return 30;
    if (upper.contains('BRATWURST')) return 15;
    if (upper.contains('SOSIS')) return 30;
    if (upper.contains('BAKSO')) return 20;
    if (upper.contains('MINI')) return 15;
    return 1;
  }

  /// Generates clean, formatted text ready to be sent to WhatsApp (driver/checker)
  static String generateWhatsAppText(VehicleLoadingSummary summary) {
    final now = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());
    final invList = summary.selectedTransactions.map((t) => '#${t.invoiceNo.toString().replaceAll('#', '')}').join(', ');
    final destinations = summary.distinctCustomers.join(', ');
    final cities = summary.distinctCities.join(', ');

    final buf = StringBuffer();
    buf.writeln('🚚 *SKIM MUATAN KENDARAAN (L-W.A.V.I.S)*');
    buf.writeln('📅 *Waktu Muat:* $now');
    buf.writeln('📋 *Daftar Faktur (${summary.selectedTransactions.length}):* $invList');
    buf.writeln('📍 *Toko Tujuan:* $destinations ($cities)');
    buf.writeln('');
    buf.writeln('═════════════════════════════');
    buf.writeln('📦 *TOTAL MUATAN KENDARAAN:*');
    buf.writeln('• *Total Karton:* *${summary.grandTotalKartonStr}*');
    buf.writeln('• *Total Qty:* ${NumberFormat('#,##0', 'id_ID').format(summary.grandTotalQty)} Pcs');
    buf.writeln('• *Total Berat:* ${summary.grandTotalWeightKg.toStringAsFixed(2)} Kg');
    buf.writeln('• *Jumlah SKU Induk:* ${summary.items.length} Macam Barang');
    buf.writeln('═════════════════════════════');
    buf.writeln('');
    buf.writeln('📋 *REKAP KARTON MASUK MOBIL (KODE INDUK):*');

    for (int i = 0; i < summary.items.length; i++) {
      final item = summary.items[i];
      buf.writeln('${i + 1}. *[${item.kodeInduk}] ${item.canonicalProductName}*');
      buf.writeln('   📦 *${item.totalKartonFormatted}* (${NumberFormat('#,##0', 'id_ID').format(item.totalQty)} pcs | ${item.totalWeightKg.toStringAsFixed(2)} kg) • Isi: ${item.isiKarton}/Ktn');
      for (var alloc in item.allocations) {
        buf.writeln('   ↳ #${alloc.invoiceNo} ${alloc.customerName}: ${alloc.kartonFormatted} (${alloc.qty.toInt()} pcs)');
      }
      buf.writeln('');
    }

    buf.writeln('═════════════════════════════');
    buf.writeln('🚚 *RINCIAN PER FAKTUR / DROP POINT:*');
    for (var inv in summary.invoiceSummaries) {
      buf.writeln('• *#${inv.invoiceNo} ${inv.customerName} (${inv.city.toUpperCase()}):* ${inv.totalKartonFormatted} (${inv.totalWeightKg.toStringAsFixed(2)} kg) • ${inv.itemCount} Item');
    }
    buf.writeln('═════════════════════════════');
    buf.writeln('✨ _Dicetak otomatis oleh L-W.A.V.I.S - PT PUTRA FIVA SEJAHTERA (Jawa Tengah)_');

    return buf.toString();
  }

  /// Generates clean WhatsApp text specifically for ordering deficit goods from the factory
  static String generateRestockFactoryOrderWhatsAppText(VehicleLoadingSummary summary) {
    final now = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());
    final deficitItems = summary.items.where((i) => i.isDeficit).toList();

    final buf = StringBuffer();
    buf.writeln('🏭 *LIST ORDER RESTOCK PABRIK (ANALISA SKIM MUATAN)*');
    buf.writeln('📅 *Waktu Analisa:* $now');
    buf.writeln('📋 *Status Muatan:* ${summary.selectedTransactions.length} Faktur terpilih (${summary.grandTotalKartonStr})');
    buf.writeln('═════════════════════════════');
    buf.writeln('🚨 *TOTAL KEKURANGAN STOK GUDANG:*');
    buf.writeln('• *Total Butuh Order Pabrik:* *${summary.totalDeficitKartonStr}* (${NumberFormat('#,##0', 'id_ID').format(summary.totalDeficitQty)} Pcs)');
    buf.writeln('• *Jumlah SKU yang Kurang:* *${summary.totalDeficitSkuCount} Macam Barang*');
    buf.writeln('═════════════════════════════');
    buf.writeln('');

    if (deficitItems.isEmpty) {
      buf.writeln('✅ *ALHAMDULILLAH, SEMUA STOK FISIK DI GUDANG MENCUKUPI.*');
      buf.writeln('Tidak ada barang yang defisit untuk muatan ini.');
    } else {
      buf.writeln('📦 *RINCIAN KEKURANGAN PER KODE INDUK:*');
      for (int i = 0; i < deficitItems.length; i++) {
        final item = deficitItems[i];
        buf.writeln('${i + 1}. *[${item.kodeInduk}] ${item.canonicalProductName}*');
        buf.writeln('   🚨 *KURANG / BUTUH: ${item.deficitKtnFormatted}* (${NumberFormat('#,##0', 'id_ID').format(item.deficitPcs)} pcs) • Isi: ${item.isiKarton}/Ktn');
        buf.writeln('   ↳ Kebutuhan Skim: ${item.totalKartonFormatted} (${NumberFormat('#,##0', 'id_ID').format(item.totalQty)} pcs)');
        buf.writeln('   ↳ Stok Gudang Saat Ini: ${item.currentStockKtnFormatted} (${NumberFormat('#,##0', 'id_ID').format(item.currentStockPcs)} pcs)');
        buf.writeln('');
      }
      buf.writeln('═════════════════════════════');
      buf.writeln('Mohon untuk segera diproses kirim / produksi dari pabrik.');
    }
    buf.writeln('✨ _PT PUTRA FIVA SEJAHTERA (Cabang Jawa Tengah)_');

    return buf.toString();
  }

  /// Prints or previews Loading Sheet PDF using [Printing.layoutPdf]
  static Future<void> printLoadingSheetPdf(VehicleLoadingSummary summary) async {
    final pdf = pw.Document();

    pw.Font fontRegular;
    pw.Font fontBold;
    try {
      fontRegular = await PdfGoogleFonts.robotoRegular();
      fontBold = await PdfGoogleFonts.robotoBold();
    } catch (_) {
      fontRegular = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    final darkNavy = PdfColor.fromHex('#0F172A');
    final primaryCyan = PdfColor.fromHex('#0284C7');
    final textDark = PdfColor.fromHex('#1E293B');
    final textGray = PdfColor.fromHex('#64748B');
    final lightBg = PdfColor.fromHex('#F8FAFC');
    final borderGray = PdfColor.fromHex('#CBD5E1');

    final nowStr = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());
    final invListStr = summary.selectedTransactions.map((t) => '#${t.invoiceNo.toString().replaceAll('#', '')}').join(', ');
    final destinationsStr = summary.distinctCustomers.join(', ');
    final citiesStr = summary.distinctCities.join(', ');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PT PUTRA FIVA SEJAHTERA (CABANG JAWA TENGAH)',
                        style: pw.TextStyle(font: fontBold, fontSize: 13, color: darkNavy),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'JL. Pembangunan II No. 27 Jatibening I, Pondok Gede, Bekasi, Tel: 021-8484308',
                        style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: textGray),
                      ),
                      pw.Text(
                        'Sistem Distribusi & Logistik Terpadu L-W.A.V.I.S',
                        style: pw.TextStyle(font: fontRegular, fontSize: 8, color: primaryCyan),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: pw.BoxDecoration(
                      color: primaryCyan,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'SURAT MUAT KENDARAAN (LOADING SHEET)',
                      style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.white),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(color: primaryCyan, thickness: 1.5),
              pw.SizedBox(height: 8),

              // Metadata card
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderGray, width: 0.8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Faktur Dimuat: $invListStr', style: pw.TextStyle(font: fontBold, fontSize: 9, color: textDark)),
                          pw.SizedBox(height: 2),
                          pw.Text('Tujuan Antar: $destinationsStr ($citiesStr)', style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: textDark)),
                        ],
                      ),
                    ),
                    pw.Container(width: 1, height: 26, color: borderGray),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Tgl / Jam Muat: $nowStr', style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: textGray)),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'TOTAL MUAT: ${summary.grandTotalKartonStr} | ${summary.grandTotalWeightKg.toStringAsFixed(1)} Kg',
                            style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: primaryCyan),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(color: borderGray, thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Dicetak otomatis oleh L-W.A.V.I.S - PT PUTRA FIVA SEJAHTERA (Jawa Tengah)',
                    style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textGray),
                  ),
                  pw.Text(
                    'Halaman ${context.pageNumber} dari ${context.pagesCount}',
                    style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textGray),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            if (summary.totalDeficitSkuCount > 0) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(7),
                margin: const pw.EdgeInsets.only(bottom: 10),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FEF2F2'),
                  borderRadius: pw.BorderRadius.circular(5),
                  border: pw.Border.all(color: PdfColor.fromHex('#EF4444'), width: 1),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('🚨 ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PERHATIAN: DEFISIT STOK GUDANG (${summary.totalDeficitSkuCount} SKU Butuh Order Pabrik)',
                            style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColor.fromHex('#991B1B')),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Kekurangan total: ${summary.totalDeficitKartonStr} (${NumberFormat("#,##0", "id_ID").format(summary.totalDeficitQty)} pcs). Barang bertanda [KURANG: X Ktn] belum mencukupi di fisik gudang.',
                            style: pw.TextStyle(font: fontRegular, fontSize: 8, color: PdfColor.fromHex('#B91C1C')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Table Rekap Kode Induk
            pw.Text(
              'REKAP MUATAN BARANG FISIK (BERDASARKAN KODE INDUK):',
              style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: darkNavy),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: borderGray, width: 0.6),
              columnWidths: const {
                0: pw.FixedColumnWidth(24),  // No
                1: pw.FixedColumnWidth(65),  // Kode Induk
                2: pw.FlexColumnWidth(2.6),  // Nama Barang Fisik & Alokasi
                3: pw.FixedColumnWidth(42),  // Isi/Ktn
                4: pw.FixedColumnWidth(48),  // Total Ktn
                5: pw.FixedColumnWidth(48),  // Total Pcs
                6: pw.FixedColumnWidth(55),  // Berat (kg)
                7: pw.FixedColumnWidth(36),  // Cek Fisik [ ]
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: primaryCyan),
                  children: [
                    _buildPdfHeaderCell('NO', fontBold, align: pw.TextAlign.center),
                    _buildPdfHeaderCell('KODE INDUK', fontBold, align: pw.TextAlign.center),
                    _buildPdfHeaderCell('NAMA BARANG & ALOKASI FAKTUR', fontBold),
                    _buildPdfHeaderCell('ISI/KTN', fontBold, align: pw.TextAlign.center),
                    _buildPdfHeaderCell('KARTON', fontBold, align: pw.TextAlign.center),
                    _buildPdfHeaderCell('PCS', fontBold, align: pw.TextAlign.center),
                    _buildPdfHeaderCell('BERAT', fontBold, align: pw.TextAlign.right),
                    _buildPdfHeaderCell('CEK', fontBold, align: pw.TextAlign.center),
                  ],
                ),
                ...summary.items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final isEven = idx % 2 == 0;
                  final rowColor = item.isDeficit
                      ? PdfColor.fromHex('#FEF2F2')
                      : (isEven ? PdfColors.white : PdfColor.fromHex('#F1F5F9'));

                  final allocStrings = item.allocations
                      .map((a) => '#${a.invoiceNo} ${a.customerName}: ${a.kartonFormatted}')
                      .join('  •  ');

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowColor),
                    children: [
                      _buildPdfBodyCell('${idx + 1}', fontRegular, align: pw.TextAlign.center),
                      _buildPdfBodyCell(item.kodeInduk, fontBold, align: pw.TextAlign.center),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              children: [
                                pw.Expanded(
                                  child: pw.Text(
                                    item.canonicalProductName,
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 8.5,
                                      color: item.isDeficit ? PdfColor.fromHex('#B91C1C') : textDark,
                                    ),
                                  ),
                                ),
                                if (item.isDeficit)
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: pw.BoxDecoration(
                                      color: PdfColor.fromHex('#FEE2E2'),
                                      borderRadius: pw.BorderRadius.circular(2),
                                      border: pw.Border.all(color: PdfColor.fromHex('#EF4444'), width: 0.5),
                                    ),
                                    child: pw.Text(
                                      'KURANG: ${item.deficitKtnFormatted}',
                                      style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColor.fromHex('#991B1B')),
                                    ),
                                  ),
                              ],
                            ),
                            pw.SizedBox(height: 1.5),
                            pw.Text('↳ $allocStrings', style: pw.TextStyle(font: fontRegular, fontSize: 7, color: textGray)),
                          ],
                        ),
                      ),
                      _buildPdfBodyCell('${item.isiKarton}', fontRegular, align: pw.TextAlign.center),
                      _buildPdfBodyCell(item.totalKartonFormatted, fontBold, align: pw.TextAlign.center),
                      _buildPdfBodyCell(NumberFormat('#,##0', 'id_ID').format(item.totalQty), fontRegular, align: pw.TextAlign.center),
                      _buildPdfBodyCell('${item.totalWeightKg.toStringAsFixed(1)} kg', fontRegular, align: pw.TextAlign.right),
                      pw.Center(
                        child: pw.Container(
                          margin: const pw.EdgeInsets.symmetric(vertical: 4),
                          width: 14,
                          height: 14,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: darkNavy, width: 1.2),
                            borderRadius: pw.BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                // Grand Total Row
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E2E8F0')),
                  children: [
                    _buildPdfBodyCell('', fontBold),
                    _buildPdfBodyCell('TOTAL', fontBold, align: pw.TextAlign.center),
                    _buildPdfBodyCell('GRAND TOTAL MUATAN MOBIL (${summary.items.length} SKU Induk)', fontBold),
                    _buildPdfBodyCell('-', fontBold, align: pw.TextAlign.center),
                    _buildPdfBodyCell(summary.grandTotalKartonStr, fontBold, align: pw.TextAlign.center),
                    _buildPdfBodyCell(NumberFormat('#,##0', 'id_ID').format(summary.grandTotalQty), fontBold, align: pw.TextAlign.center),
                    _buildPdfBodyCell('${summary.grandTotalWeightKg.toStringAsFixed(1)} kg', fontBold, align: pw.TextAlign.right),
                    _buildPdfBodyCell('', fontBold),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // Drop Point Invoices Summary
            pw.Text(
              'RINGKASAN DROP POINT PER FAKTUR / TOKO:',
              style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: darkNavy),
            ),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 8,
              runSpacing: 6,
              children: summary.invoiceSummaries.map((inv) {
                return pw.Container(
                  width: 255,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: lightBg,
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: borderGray, width: 0.6),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('#${inv.invoiceNo} - ${inv.customerName}', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: textDark)),
                            pw.Text('Kota: ${inv.city} • ${inv.itemCount} Item', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textGray)),
                          ],
                        ),
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(inv.totalKartonFormatted, style: pw.TextStyle(font: fontBold, fontSize: 9, color: primaryCyan)),
                          pw.Text('${inv.totalWeightKg.toStringAsFixed(1)} kg', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textGray)),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            pw.SizedBox(height: 24),

            // Signatures block
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildSignatureCol('Dibuat Oleh,', 'Admin Logistik', fontRegular, fontBold),
                _buildSignatureCol('Diperiksa Oleh,', 'Checker Gudang', fontRegular, fontBold),
                _buildSignatureCol('Diterima Oleh,', 'Pengemudi / Sopir', fontRegular, fontBold),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Surat_Muatan_Kendaraan_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
    );
  }

  static pw.Widget _buildPdfHeaderCell(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _buildPdfBodyCell(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColor.fromHex('#1E293B')),
      ),
    );
  }

  static pw.Widget _buildSignatureCol(String title, String role, pw.Font fontRegular, pw.Font fontBold) {
    return pw.Column(
      children: [
        pw.Text(title, style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
        pw.SizedBox(height: 38),
        pw.Container(
          width: 120,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8))),
        ),
        pw.SizedBox(height: 3),
        pw.Text('( $role )', style: pw.TextStyle(font: fontBold, fontSize: 8)),
      ],
    );
  }
}
