import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';

class ErpMatrixView extends StatefulWidget {
  const ErpMatrixView({super.key});

  @override
  State<ErpMatrixView> createState() => _ErpMatrixViewState();
}

class _ErpMatrixViewState extends State<ErpMatrixView> {
  String _selectedMonthYear = "";
  bool _showPcs = true; // true = Pcs, false = Kg
  List<Map<String, dynamic>> _erpRecords = [];
  bool _loadingErp = false;

  @override
  void initState() {
    super.initState();
    // Default to current month-year
    _selectedMonthYear = DateFormat('MM-yyyy').format(DateTime.now());
    _loadErpData();
  }

  Future<void> _loadErpData() async {
    setState(() {
      _loadingErp = true;
    });

    try {
      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
      final data = await trProvider.getMonthlyErpSummary(_selectedMonthYear);
      setState(() {
        _erpRecords = data;
      });
    } catch (e) {
      debugPrint("Error loading ERP summary: $e");
    } finally {
      setState(() {
        _loadingErp = false;
      });
    }
  }

  // Generate a list of month options (e.g., current month and past months)
  List<String> _getMonthOptions() {
    final List<String> options = [];
    final now = DateTime.now();
    for (int i = 0; i < 6; i++) {
      final date = DateTime(now.year, now.month - i, 1);
      options.add(DateFormat('MM-yyyy').format(date));
    }
    // Make sure we have 05-2026 and 08-2026 for testing VBA reference data
    if (!options.contains('05-2026')) options.add('05-2026');
    if (!options.contains('08-2026')) options.add('08-2026');
    if (!options.contains('09-2026')) options.add('09-2026');
    if (!options.contains('10-2026')) options.add('10-2026');
    return options.toSet().toList(); // remove duplicates
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = Provider.of<ProductProvider>(context);
    final customerProvider = Provider.of<CustomerProvider>(context);

    // Get list of customers who have ERP records for this month
    final activeCustomerIds = _erpRecords.map((r) => r['customerId'] as String).toSet().toList();
    final activeCustomers = customerProvider.customers
        .where((c) => activeCustomerIds.contains(c.id))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Controls Card
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                const Icon(Icons.filter_alt_rounded, color: Color(0xFF38BDF8)),
                const SizedBox(width: 12),
                const Text('Periode:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                const SizedBox(width: 8),
                
                // Month selector
                DropdownButton<String>(
                  value: _selectedMonthYear,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  underline: const SizedBox(),
                  items: _getMonthOptions().map((m) {
                    return DropdownMenuItem<String>(
                      value: m,
                      child: Text(m),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedMonthYear = val;
                      });
                      _loadErpData();
                    }
                  },
                ),
                const Spacer(),
                
                // Toggle Pcs vs Kg
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: () => setState(() => _showPcs = true),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          backgroundColor: _showPcs ? const Color(0xFF0284C7) : Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('PCS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      ElevatedButton(
                        onPressed: () => setState(() => _showPcs = false),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          backgroundColor: !_showPcs ? const Color(0xFF0284C7) : Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('KG', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Scrollable Grid Matrix Card
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: _loadingErp || productProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _erpRecords.isEmpty
                      ? const Center(
                          child: Text(
                            'Tidak ada data penjualan ERP untuk periode ini.',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        )
                      : Scrollbar(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                columns: [
                                  const DataColumn(label: Text('NAMA BARANG')),
                                  const DataColumn(label: Text('SIZE (G)')),
                                  // Customer columns
                                  ...activeCustomers.map((cust) {
                                    return DataColumn(
                                      label: Text(
                                        cust.aliasName,
                                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                                      ),
                                    );
                                  }),
                                  const DataColumn(
                                    label: Text(
                                      'TOTAL KELUAR',
                                      style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                                rows: productProvider.products.map((p) {
                                  double totalSum = 0.0;

                                  // Row cell values
                                  final cells = activeCustomers.map((cust) {
                                    // Find erp record for this customer
                                    final record = _erpRecords.firstWhere(
                                      (r) => r['customerId'] == cust.id,
                                      orElse: () => {},
                                    );
                                    
                                    final productsMap = record['products'] as Map<dynamic, dynamic>? ?? {};
                                    final prodData = productsMap[p.id] as Map<dynamic, dynamic>?;
                                    
                                    double val = 0.0;
                                    if (prodData != null) {
                                      val = _showPcs 
                                          ? (prodData['pcs'] ?? 0.0).toDouble()
                                          : (prodData['kg'] ?? 0.0).toDouble();
                                    }
                                    
                                    totalSum += val;

                                    return DataCell(
                                      Text(
                                        val > 0 
                                            ? (_showPcs ? val.toStringAsFixed(0) : val.toStringAsFixed(2)) 
                                            : '-',
                                        style: TextStyle(
                                          color: val > 0 ? Colors.white : const Color(0xFF475569),
                                          fontWeight: val > 0 ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    );
                                  }).toList();

                                  return DataRow(
                                    cells: [
                                      DataCell(Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 12))),
                                      DataCell(Text(p.sizeGrams.toStringAsFixed(0), style: const TextStyle(color: Color(0xFF64748B)))),
                                      ...cells,
                                      // Total Out Cell
                                      DataCell(
                                        Text(
                                          totalSum > 0
                                              ? (_showPcs ? totalSum.toStringAsFixed(0) : totalSum.toStringAsFixed(2))
                                              : '-',
                                          style: TextStyle(
                                            color: totalSum > 0 ? Colors.greenAccent : const Color(0xFF475569),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
