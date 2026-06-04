import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/customer.dart';
import '../providers/customer_provider.dart';
import '../services/ocr_service.dart';
import '../services/import_service.dart';

class CustomerListView extends StatefulWidget {
  const CustomerListView({super.key});

  @override
  State<CustomerListView> createState() => _CustomerListViewState();
}

class _CustomerListViewState extends State<CustomerListView> {
  final _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showCustomerDialog([Customer? customer]) {
    final isEdit = customer != null;
    final nameController = TextEditingController(text: customer?.customerName ?? '');
    final aliasController = TextEditingController(text: customer?.aliasName ?? '');
    final addressController = TextEditingController(text: customer?.address ?? '');
    final cityController = TextEditingController(text: customer?.city ?? '');
    final provinceController = TextEditingController(text: customer?.province ?? 'JAWA TENGAH');
    final phoneController = TextEditingController(text: customer?.phone ?? '');
    final ktpController = TextEditingController(text: customer?.ktpNumber ?? '');

    showDialog(
      context: context,
      builder: (context) {
        bool isScanning = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> scanKtp() async {
              try {
                // Select image source
                final source = await showDialog<ImageSource>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E293B),
                    title: const Text('Pilih Sumber Foto KTP', style: TextStyle(color: Colors.white)),
                    actions: [
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context, ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF38BDF8)),
                        label: const Text('Kamera', style: TextStyle(color: Colors.white)),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context, ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded, color: Color(0xFF38BDF8)),
                        label: const Text('Galeri', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );

                if (source == null) return;

                final picker = ImagePicker();
                final XFile? image = await picker.pickImage(source: source);
                if (image == null) return;

                setDialogState(() {
                  isScanning = true;
                });

                final ktpData = await OcrService.scanKtp(File(image.path));

                setDialogState(() {
                  isScanning = false;
                  if (ktpData.nama.isNotEmpty) nameController.text = ktpData.nama;
                  if (ktpData.nik.isNotEmpty) ktpController.text = ktpData.nik;
                  if (ktpData.fullAddress.isNotEmpty) addressController.text = ktpData.fullAddress;
                  if (ktpData.estimatedCity.isNotEmpty) {
                    cityController.text = ktpData.estimatedCity.toUpperCase();
                  }
                });

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('KTP berhasil dipindai dan data diisi otomatis!'), backgroundColor: Colors.teal),
                  );
                }
              } catch (e) {
                setDialogState(() {
                  isScanning = false;
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal scan KTP: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isEdit ? 'Edit Pelanggan' : 'Tambah Pelanggan', style: const TextStyle(color: Colors.white)),
                  if (!isEdit)
                    ElevatedButton.icon(
                      onPressed: isScanning ? null : scanKtp,
                      icon: isScanning
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.document_scanner_rounded, size: 16, color: Colors.white),
                      label: Text(isScanning ? 'Memindai...' : 'Scan KTP', style: const TextStyle(fontSize: 12, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0369A1),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isEdit) ...[
                        TextFormField(
                          initialValue: customer.id,
                          enabled: false,
                          style: const TextStyle(color: Colors.white),
                          decoration: _buildInputDecoration(hint: 'ID Customer'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: aliasController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(hint: 'Nama Toko / Alias (e.g. MISTER SOSIS)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(hint: 'Nama Lengkap Pemilik (e.g. SUSILO HARYAWAN)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(hint: 'Alamat Lengkap'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: cityController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Kota (e.g. JEPARA)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: provinceController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Provinsi'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(hint: 'Nomor Telepon'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: ktpController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(hint: 'Nomor KTP'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  onPressed: () async {
                    final custName = nameController.text.trim();
                    final alias = aliasController.text.trim();
                    final address = addressController.text.trim();
                    final city = cityController.text.trim();
                    final province = provinceController.text.trim();
                    final phone = phoneController.text.trim();
                    final ktp = ktpController.text.trim();

                    if (custName.isEmpty || alias.isEmpty || city.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nama Toko, Nama Pemilik, dan Kota wajib diisi!'), backgroundColor: Colors.orange),
                      );
                      return;
                    }

                    try {
                      final custProvider = Provider.of<CustomerProvider>(context, listen: false);
                      String finalId;

                      if (isEdit) {
                        finalId = customer.id;
                      } else {
                        // Automatically generate customer ID based on city and plate code logic
                        finalId = await custProvider.getNextCustomerID(city);
                      }

                      final newCustomer = Customer(
                        id: finalId,
                        customerName: custName,
                        aliasName: alias,
                        address: address,
                        city: city,
                        province: province,
                        country: 'INDONESIA',
                        phone: phone,
                        ktpNumber: ktp,
                      );

                      await custProvider.saveCustomer(newCustomer);

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isEdit
                                ? 'Pelanggan ${newCustomer.aliasName} berhasil diperbarui.'
                                : 'Pelanggan berhasil ditambahkan dengan ID: $finalId'),
                            backgroundColor: Colors.teal,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.redAccent),
                        );
                      }
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _importCustomersFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null || result.files.single.path == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
        ),
      );

      final file = File(result.files.single.path!);
      final importResult = await ImportService().importCustomers(file);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Show result dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Hasil Import Excel', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Baris data: ${importResult.totalRows}', style: const TextStyle(color: Colors.white)),
                Text('Sukses: ${importResult.successCount}', style: const TextStyle(color: Colors.greenAccent)),
                Text('Gagal: ${importResult.errorCount}', style: const TextStyle(color: Colors.redAccent)),
                if (importResult.errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Rincian Error:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        importResult.errors.join('\n'),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup', style: TextStyle(color: Color(0xFF38BDF8))),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengimport: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerProvider = Provider.of<CustomerProvider>(context);

    // Apply local query filter
    final filteredCustomers = customerProvider.customers.where((c) {
      final nameMatches = c.customerName.toLowerCase().contains(_searchQuery.toLowerCase());
      final aliasMatches = c.aliasName.toLowerCase().contains(_searchQuery.toLowerCase());
      final idMatches = c.id.toLowerCase().contains(_searchQuery.toLowerCase());
      final cityMatches = c.city.toLowerCase().contains(_searchQuery.toLowerCase());
      return nameMatches || aliasMatches || idMatches || cityMatches;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF38BDF8),
        onPressed: () => _showCustomerDialog(),
        child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Search Input Header with Excel Import
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Cari pelanggan berdasarkan ID, nama toko, pemilik, atau kota...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _importCustomersFromExcel,
                  icon: const Icon(Icons.file_upload_rounded, color: Colors.white),
                  label: const Text('Import Excel', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Customer List Table View
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: customerProvider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredCustomers.isEmpty
                        ? const Center(
                            child: Text(
                              'Tidak ada pelanggan ditemukan.',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SizedBox(
                              width: double.infinity,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                dataRowMinHeight: 56,
                                dataRowMaxHeight: 56,
                                headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                                columns: const [
                                  DataColumn(label: Text('ID CUST')),
                                  DataColumn(label: Text('NAMA TOKO (ALIAS)')),
                                  DataColumn(label: Text('PEMILIK')),
                                  DataColumn(label: Text('ALAMAT')),
                                  DataColumn(label: Text('KOTA')),
                                  DataColumn(label: Text('TELEPON')),
                                  DataColumn(label: Text('')),
                                ],
                                rows: filteredCustomers.map((c) {
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(c.id, style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                      DataCell(Text(c.aliasName, style: const TextStyle(color: Colors.white))),
                                      DataCell(Text(c.customerName, style: const TextStyle(color: Colors.white))),
                                      DataCell(Text(c.address, style: const TextStyle(color: Colors.white, fontSize: 13))),
                                      DataCell(Text(c.city, style: const TextStyle(color: Colors.white))),
                                      DataCell(Text(c.phone.isNotEmpty ? c.phone : '-', style: const TextStyle(color: Colors.white))),
                                      DataCell(
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 20),
                                              onPressed: () => _showCustomerDialog(c),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                              onPressed: () {
                                                // Confirm delete
                                                showDialog(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    backgroundColor: const Color(0xFF1E293B),
                                                    title: const Text('Hapus Pelanggan', style: TextStyle(color: Colors.white)),
                                                    content: Text('Apakah Anda yakin ingin menghapus "${c.aliasName}"?', style: const TextStyle(color: Color(0xFF94A3B8))),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(context),
                                                        child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                                                      ),
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                        onPressed: () async {
                                                          await customerProvider.deleteCustomer(c.id);
                                                          if (context.mounted) Navigator.pop(context);
                                                        },
                                                        child: const Text('Hapus'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
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
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: BorderSide.none,
      ),
    );
  }
}
