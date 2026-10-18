import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/customer.dart';
import '../providers/customer_provider.dart';
import '../services/ocr_service.dart';
import '../services/import_service.dart';
import '../services/download_helper.dart';
import '../services/file_drop_helper.dart';

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
    final provinceController = TextEditingController(text: customer?.province.isNotEmpty == true ? customer!.province : 'JAWA TENGAH');
    final countryController = TextEditingController(text: customer?.country.isNotEmpty == true ? customer!.country : 'INDONESIA');
    final phoneController = TextEditingController(text: customer?.phone ?? '');
    final ktpController = TextEditingController(text: customer?.ktpNumber ?? '');

    Uint8List? selectedKtpBytes;
    String? selectedKtpFileName;
    String existingKtpUrl = customer?.ktpImageUrl ?? '';
    bool isSaving = false;
    bool isDraggingOver = false;
    FileDropListener? dropListener;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isScanning = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            dropListener ??= FileDropListener(
              onFileDropped: (bytes, fileName) {
                setDialogState(() {
                  selectedKtpBytes = bytes;
                  selectedKtpFileName = fileName;
                });
              },
              onDragStateChanged: (isOver) {
                setDialogState(() {
                  isDraggingOver = isOver;
                });
              },
            );

            Future<void> pickKtpImageFile() async {
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                  withData: true,
                );
                if (result != null && result.files.isNotEmpty) {
                  final file = result.files.first;
                  if (file.bytes != null) {
                    setDialogState(() {
                      selectedKtpBytes = file.bytes;
                      selectedKtpFileName = file.name;
                    });
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal memilih file: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            }

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

                final bytes = await image.readAsBytes();
                setDialogState(() {
                  isScanning = true;
                  selectedKtpBytes = bytes;
                  selectedKtpFileName = image.name;
                });

                if (!kIsWeb) {
                  try {
                    final ktpData = await OcrService.scanKtp(File(image.path));
                    setDialogState(() {
                      if (ktpData.nama.isNotEmpty) nameController.text = ktpData.nama;
                      if (ktpData.nik.isNotEmpty) ktpController.text = ktpData.nik;
                      if (ktpData.fullAddress.isNotEmpty) addressController.text = ktpData.fullAddress;
                      if (ktpData.estimatedCity.isNotEmpty) {
                        cityController.text = ktpData.estimatedCity.toUpperCase();
                      }
                    });
                  } catch (ocrErr) {
                    debugPrint('OCR warning: $ocrErr');
                  }
                }

                setDialogState(() {
                  isScanning = false;
                });

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Foto KTP berhasil dipilih!'), backgroundColor: Colors.teal),
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
                  if (!isEdit && !kIsWeb)
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
                  width: 440,
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
                              decoration: _buildInputDecoration(hint: 'Kota (e.g. BLORA)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: provinceController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Provinsi (e.g. JAWA TENGAH)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: countryController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Negara (e.g. INDONESIA)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Nomor Telepon'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: ktpController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(hint: 'Nomor KTP'),
                      ),
                      const SizedBox(height: 16),
                      // Foto KTP Section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDraggingOver
                              ? const Color(0xFF0369A1).withOpacity(0.25)
                              : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDraggingOver ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                            width: isDraggingOver ? 2.0 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.badge_rounded, color: Color(0xFF38BDF8), size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Foto KTP Pelanggan',
                                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                if (selectedKtpBytes != null || existingKtpUrl.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (selectedKtpBytes != null ? Colors.amber : Colors.teal).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      selectedKtpBytes != null ? 'Siap Upload' : 'Tersimpan di Cloud',
                                      style: TextStyle(
                                        color: selectedKtpBytes != null ? Colors.amber : Colors.tealAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Image Preview Box or Drag Over Box
                            if (isDraggingOver)
                              Container(
                                height: 130,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38BDF8).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.file_download_rounded, color: Color(0xFF38BDF8), size: 40),
                                    SizedBox(height: 6),
                                    Text(
                                      'Lepaskan File Foto KTP di Sini',
                                      style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Format didukung: JPG, JPEG, PNG, WEBP',
                                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    ),
                                  ],
                                ),
                              )
                            else if (selectedKtpBytes != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        Container(
                                          height: 150,
                                          width: double.infinity,
                                          color: const Color(0xFF1E293B),
                                          child: Image.memory(selectedKtpBytes!, fit: BoxFit.contain),
                                        ),
                                        IconButton(
                                          icon: const CircleAvatar(
                                            radius: 12,
                                            backgroundColor: Colors.redAccent,
                                            child: Icon(Icons.close, size: 14, color: Colors.white),
                                          ),
                                          tooltip: 'Batalkan Foto',
                                          onPressed: () {
                                            setDialogState(() {
                                              selectedKtpBytes = null;
                                              selectedKtpFileName = null;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selectedKtpFileName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'File: $selectedKtpFileName',
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              )
                            else if (existingKtpUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  alignment: Alignment.topRight,
                                  children: [
                                    Container(
                                      height: 150,
                                      width: double.infinity,
                                      color: const Color(0xFF1E293B),
                                      child: Image.network(
                                        existingKtpUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) => const Center(
                                          child: Text('Gagal memuat preview', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Colors.redAccent,
                                        child: Icon(Icons.delete_outline, size: 14, color: Colors.white),
                                      ),
                                      tooltip: 'Hapus Foto KTP',
                                      onPressed: () {
                                        setDialogState(() {
                                          existingKtpUrl = '';
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                height: 85,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B).withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF334155)),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.drive_folder_upload_outlined, color: Color(0xFF38BDF8), size: 28),
                                    SizedBox(height: 6),
                                    Text(
                                      'Tarik & Lepas (Drag & Drop) foto KTP ke sini',
                                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'atau klik tombol Pilih File / Kamera di bawah',
                                      style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 10),
                            // Action Buttons to pick
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF38BDF8),
                                    side: const BorderSide(color: Color(0xFF0284C7)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  onPressed: isSaving ? null : pickKtpImageFile,
                                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                                  label: const Text('Pilih File (Flashdisk / PC)', style: TextStyle(fontSize: 11)),
                                ),
                                if (!kIsWeb)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF38BDF8),
                                      side: const BorderSide(color: Color(0xFF0284C7)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    ),
                                    onPressed: (isScanning || isSaving) ? null : scanKtp,
                                    icon: isScanning
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.camera_alt_rounded, size: 16),
                                    label: Text(isScanning ? 'Memindai...' : 'Kamera / Scan', style: const TextStyle(fontSize: 11)),
                                  ),
                              ],
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
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final custName = nameController.text.trim();
                          final alias = aliasController.text.trim();
                          final address = addressController.text.trim();
                          final city = cityController.text.trim();
                          final province = provinceController.text.trim();
                          final country = countryController.text.trim();
                          final phone = phoneController.text.trim();
                          final ktp = ktpController.text.trim();

                          if (custName.isEmpty || alias.isEmpty || city.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Nama Toko, Nama Pemilik, dan Kota wajib diisi!'), backgroundColor: Colors.orange),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          try {
                            final custProvider = Provider.of<CustomerProvider>(context, listen: false);
                            String finalId = isEdit ? customer.id : await custProvider.getNextCustomerID(city);

                            String finalKtpUrl = existingKtpUrl;
                            if (selectedKtpBytes != null) {
                              finalKtpUrl = await custProvider.uploadCustomerKtp(
                                customerId: finalId,
                                imageBytes: selectedKtpBytes!,
                              );
                            } else if (existingKtpUrl.isEmpty && (customer?.ktpImageUrl.isNotEmpty ?? false)) {
                              await custProvider.deleteCustomerKtp(finalId);
                            }

                            final newCustomer = Customer(
                              id: finalId,
                              customerName: custName,
                              aliasName: alias,
                              address: address,
                              city: city,
                              province: province.isNotEmpty ? province : 'JAWA TENGAH',
                              country: country.isNotEmpty ? country : 'INDONESIA',
                              phone: phone,
                              ktpNumber: ktp,
                              ktpImageUrl: finalKtpUrl,
                              depositBalance: customer?.depositBalance ?? 0.0,
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
                              setDialogState(() => isSaving = false);
                              final errMsg = e.toString().replaceAll('TimeoutException: ', '').replaceAll('Exception: ', '');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(errMsg), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            SizedBox(width: 8),
                            Text('Menyimpan...', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        )
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => dropListener?.dispose());
  }

  void _showKtpPreviewDialog(Customer customer) {
    bool isDownloading = false;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 750, maxHeight: 680),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Foto KTP - ${customer.aliasName.isNotEmpty ? customer.aliasName : customer.customerName}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'NIK: ${customer.ktpNumber.isNotEmpty ? customer.ktpNumber : '-'} | Pemilik: ${customer.customerName}',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                            tooltip: 'Tutup',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: customer.ktpImageUrl.isEmpty
                                ? const Center(
                                    child: Text('Tidak ada foto KTP', style: TextStyle(color: Color(0xFF64748B))),
                                  )
                                : InteractiveViewer(
                                    minScale: 0.5,
                                    maxScale: 4.0,
                                    child: Center(
                                      child: Image.network(
                                        customer.ktpImageUrl,
                                        fit: BoxFit.contain,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          final total = loadingProgress.expectedTotalBytes;
                                          final loaded = loadingProgress.cumulativeBytesLoaded;
                                          final progress = total != null ? loaded / total : null;
                                          return Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CircularProgressIndicator(value: progress, color: const Color(0xFF38BDF8)),
                                                const SizedBox(height: 12),
                                                const Text('Memuat Foto KTP...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                              ],
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) => const Center(
                                          child: Text('Gagal memuat foto KTP', style: TextStyle(color: Colors.redAccent)),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0369A1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: const Text('Buka Ukuran Penuh', style: TextStyle(fontSize: 13)),
                            onPressed: customer.ktpImageUrl.isNotEmpty
                                ? () async {
                                    final uri = Uri.parse(customer.ktpImageUrl);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  }
                                : null,
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: isDownloading
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.download_rounded, size: 16),
                            label: Text(
                              isDownloading ? 'Mengunduh...' : 'Unduh Foto KTP',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            onPressed: (isDownloading || customer.ktpImageUrl.isEmpty)
                                ? null
                                : () async {
                                    setDialogState(() => isDownloading = true);
                                    try {
                                      final resp = await http.get(Uri.parse(customer.ktpImageUrl));
                                      if (resp.statusCode == 200) {
                                        final safeName = customer.aliasName.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '_');
                                        final fileName = 'KTP_${customer.id}_$safeName.jpg';
                                        await downloadFileBytes(
                                          bytes: resp.bodyBytes,
                                          fileName: fileName,
                                          mimeType: 'image/jpeg',
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Foto KTP berhasil diunduh: $fileName'),
                                              backgroundColor: Colors.teal,
                                            ),
                                          );
                                        }
                                      } else {
                                        throw Exception('Gagal mendownload foto (${resp.statusCode})');
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Error unduh: $e'),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (context.mounted) {
                                        setDialogState(() => isDownloading = false);
                                      }
                                    }
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
        withData: true,
      );

      if (result == null) return;
      final bytes = result.files.single.bytes ??
          (result.files.single.path != null ? await File(result.files.single.path!).readAsBytes() : null);
      if (bytes == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
        ),
      );

      final importResult = await ImportService().importCustomers(bytes);

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
      final q = _searchQuery.toLowerCase();
      final nameMatches = c.customerName.toLowerCase().contains(q);
      final aliasMatches = c.aliasName.toLowerCase().contains(q);
      final displayMatches = c.displayName.toLowerCase().contains(q);
      final idMatches = c.id.toLowerCase().contains(q);
      final cityMatches = c.city.toLowerCase().contains(q);
      final provinceMatches = c.province.toLowerCase().contains(q);
      final countryMatches = c.country.toLowerCase().contains(q);
      return nameMatches || aliasMatches || displayMatches || idMatches || cityMatches || provinceMatches || countryMatches;
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
                      hintText: 'Cari pelanggan berdasarkan ID, nama toko, pemilik, kota, atau negara...',
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
                        : Scrollbar(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 10,
                                  horizontalMargin: 10,
                                  headingRowHeight: 42,
                                  dataRowMinHeight: 44,
                                  dataRowMaxHeight: 44,
                                  headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                  headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11),
                                  columns: const [
                                    DataColumn(label: Text('ID CUST')),
                                    DataColumn(label: Text('NAMA TOKO (ALIAS)')),
                                    DataColumn(label: Text('PEMILIK')),
                                    DataColumn(label: Text('ALAMAT')),
                                    DataColumn(label: Text('KOTA')),
                                    DataColumn(label: Text('PROVINSI')),
                                    DataColumn(label: Text('NEGARA')),
                                    DataColumn(label: Text('TELEPON')),
                                    DataColumn(label: Text('FOTO KTP')),
                                    DataColumn(label: Text('AKSI')),
                                  ],
                                  rows: filteredCustomers.map((c) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(c.id, style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                        DataCell(Text(c.aliasName, style: const TextStyle(color: Colors.white, fontSize: 11))),
                                        DataCell(Text(c.customerName, style: const TextStyle(color: Colors.white, fontSize: 11))),
                                        DataCell(Text(c.address, style: const TextStyle(color: Colors.white, fontSize: 11))),
                                        DataCell(Text(c.city, style: const TextStyle(color: Colors.white, fontSize: 11))),
                                        DataCell(Text(c.province.isNotEmpty ? c.province : 'JAWA TENGAH', style: const TextStyle(color: Colors.white, fontSize: 11))),
                                        DataCell(Text(c.country.isNotEmpty ? c.country : 'INDONESIA', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                                        DataCell(Text(c.phone.isNotEmpty ? c.phone : '-', style: const TextStyle(color: Colors.white, fontSize: 11))),
                                        DataCell(
                                          c.ktpImageUrl.isNotEmpty
                                              ? InkWell(
                                                  onTap: () => _showKtpPreviewDialog(c),
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF0369A1).withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.badge_rounded, size: 14, color: Color(0xFF38BDF8)),
                                                        SizedBox(width: 4),
                                                        Text('Lihat KTP', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                                                      ],
                                                    ),
                                                  ),
                                                )
                                              : const Text('-', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                        ),
                                        DataCell(
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20),
                                            color: const Color(0xFF1E293B),
                                            tooltip: 'Menu Aksi',
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              side: const BorderSide(color: Color(0xFF334155)),
                                            ),
                                            onSelected: (value) {
                                              if (value == 'view_ktp') {
                                                _showKtpPreviewDialog(c);
                                              } else if (value == 'edit') {
                                                _showCustomerDialog(c);
                                              } else if (value == 'delete') {
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
                                                        child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              if (c.ktpImageUrl.isNotEmpty)
                                                const PopupMenuItem(
                                                  value: 'view_ktp',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.badge_outlined, color: Color(0xFF38BDF8), size: 18),
                                                      SizedBox(width: 10),
                                                      Text('Lihat Foto KTP', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 18),
                                                    SizedBox(width: 10),
                                                    Text('Edit Pelanggan', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                    SizedBox(width: 10),
                                                    Text('Hapus Pelanggan', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                                  ],
                                                ),
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
