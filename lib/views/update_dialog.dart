import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/update_provider.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.info,
    this.currentVersion = '1.0.0',
  });

  /// Convenience method to show the dialog from anywhere.
  static Future<void> show(BuildContext context, UpdateInfo info, {String currentVersion = '1.0.0'}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info, currentVersion: currentVersion),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryCyan = Color(0xFF38BDF8);
    const Color surface = Color(0xFF1E293B);
    const Color background = Color(0xFF0F172A);
    const Color mutedText = Color(0xFF94A3B8);
    const Color gradientStart = Color(0xFF0284C7);
    const Color gradientEnd = Color(0xFF38BDF8);

    return AlertDialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryCyan.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: primaryCyan,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Update Tersedia!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // --- Version comparison ---
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  // Current version badge
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'Versi Saat Ini',
                          style: TextStyle(color: mutedText, fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'v$currentVersion',
                            style: const TextStyle(
                              color: mutedText,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Arrow
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: primaryCyan,
                      size: 22,
                    ),
                  ),

                  // New version badge
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'Versi Baru',
                          style: TextStyle(color: mutedText, fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [gradientStart, gradientEnd],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'v${info.latestVersion}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --- Release notes header ---
            const Row(
              children: [
                Icon(Icons.description_outlined, color: primaryCyan, size: 18),
                SizedBox(width: 6),
                Text(
                  'Catatan Rilis',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // --- Release notes body ---
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primaryCyan.withOpacity(0.15),
                ),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: const TextStyle(
                      color: mutedText,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        // "Nanti Saja" button
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: mutedText,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text(
            'Nanti Saja',
            style: TextStyle(fontSize: 14),
          ),
        ),

        // "Download & Update" button
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [gradientStart, gradientEnd],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: primaryCyan.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                Provider.of<UpdateProvider>(context, listen: false)
                    .launchUpdate();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.download_rounded, size: 20),
              label: const Text(
                'Download & Update',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
