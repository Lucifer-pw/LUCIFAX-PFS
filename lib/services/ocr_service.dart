import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Parsed KTP data extracted via OCR
class KtpData {
  final String nik;
  final String nama;
  final String tempatLahir;
  final String tanggalLahir;
  final String alamat;
  final String rtRw;
  final String kelDesa;
  final String kecamatan;
  final String agama;
  final String jenisKelamin;
  final String rawText;

  KtpData({
    this.nik = '',
    this.nama = '',
    this.tempatLahir = '',
    this.tanggalLahir = '',
    this.alamat = '',
    this.rtRw = '',
    this.kelDesa = '',
    this.kecamatan = '',
    this.agama = '',
    this.jenisKelamin = '',
    this.rawText = '',
  });

  /// Build full address string from components
  String get fullAddress {
    final parts = [alamat, rtRw, kelDesa, kecamatan].where((s) => s.isNotEmpty);
    return parts.join(', ');
  }

  /// Try to extract city name from province/kecamatan
  String get estimatedCity {
    if (kecamatan.isNotEmpty) return kecamatan;
    return '';
  }
}

class OcrService {
  /// Process image file and extract KTP data
  static Future<KtpData> scanKtp(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final rawText = recognizedText.text;
      debugPrint('OCR Raw Text:\n$rawText');

      return _parseKtpText(rawText);
    } finally {
      textRecognizer.close();
    }
  }

  /// Parse raw OCR text into structured KTP data
  static KtpData _parseKtpText(String rawText) {
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    String nik = '';
    String nama = '';
    String tempatLahir = '';
    String tanggalLahir = '';
    String alamat = '';
    String rtRw = '';
    String kelDesa = '';
    String kecamatan = '';
    String agama = '';
    String jenisKelamin = '';

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineUpper = line.toUpperCase();

      // Extract NIK (16 digits)
      if (nik.isEmpty) {
        final nikMatch = RegExp(r'\b(\d{16})\b').firstMatch(line);
        if (nikMatch != null) {
          nik = nikMatch.group(1)!;
          continue;
        }
      }

      // Extract fields after label with colon
      if (lineUpper.contains('NAMA') && !lineUpper.contains('PELANGGAN')) {
        nama = _extractValue(line);
        if (nama.isEmpty && i + 1 < lines.length) {
          nama = lines[i + 1];
        }
      } else if (lineUpper.contains('TEMPAT') && lineUpper.contains('LAHIR')) {
        final val = _extractValue(line);
        final parts = val.split(',');
        tempatLahir = parts.isNotEmpty ? parts[0].trim() : val;
        if (parts.length > 1) tanggalLahir = parts.sublist(1).join(',').trim();
      } else if (lineUpper.contains('ALAMAT')) {
        alamat = _extractValue(line);
        if (alamat.isEmpty && i + 1 < lines.length) {
          alamat = lines[i + 1];
        }
      } else if (lineUpper.contains('RT') && lineUpper.contains('RW')) {
        rtRw = _extractValue(line);
        if (rtRw.isEmpty) rtRw = line;
      } else if (lineUpper.contains('KEL') || lineUpper.contains('DESA')) {
        kelDesa = _extractValue(line);
        if (kelDesa.isEmpty) kelDesa = line;
      } else if (lineUpper.contains('KECAMATAN') || lineUpper.contains('KEC')) {
        kecamatan = _extractValue(line);
        if (kecamatan.isEmpty) kecamatan = line;
      } else if (lineUpper.contains('AGAMA')) {
        agama = _extractValue(line);
      } else if (lineUpper.contains('JENIS KELAMIN') || lineUpper.contains('JK')) {
        jenisKelamin = _extractValue(line);
      }
    }

    return KtpData(
      nik: nik,
      nama: nama,
      tempatLahir: tempatLahir,
      tanggalLahir: tanggalLahir,
      alamat: alamat,
      rtRw: rtRw,
      kelDesa: kelDesa,
      kecamatan: kecamatan,
      agama: agama,
      jenisKelamin: jenisKelamin,
      rawText: rawText,
    );
  }

  /// Extract value after colon in "LABEL : VALUE" format
  static String _extractValue(String line) {
    final colonIndex = line.indexOf(':');
    if (colonIndex != -1 && colonIndex < line.length - 1) {
      return line.substring(colonIndex + 1).trim();
    }
    return '';
  }
}
