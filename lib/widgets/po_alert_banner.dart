import 'package:flutter/material.dart';
import '../models/po_notification_alert.dart';

class PoAlertBanner extends StatelessWidget {
  final PoNotificationAlert alert;
  final VoidCallback onDismiss;
  final void Function(String invoiceNo) onOpenInvoice;
  final VoidCallback onOpenHistory;

  const PoAlertBanner({
    super.key,
    required this.alert,
    required this.onDismiss,
    required this.onOpenInvoice,
    required this.onOpenHistory,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 10.0 : 24.0,
            vertical: 10.0,
          ),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(16),
            shadowColor: Colors.black.withOpacity(0.5),
            color: const Color(0xFF064E3B), // Deep Emerald Green
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF064E3B),
                    Color(0xFF065F46),
                    Color(0xFF042F2E),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: EdgeInsets.all(isMobile ? 12 : 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Bell + Title + Close Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Pulsing-style icon badge
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.25),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF34D399), width: 1.5),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Color(0xFF34D399),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Title & Sender
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  alert.isMultiInvoice
                                      ? '🎉 ${alert.invoiceNos.length} PO WhatsApp Otomatis Jadi Invoice!'
                                      : '🎉 PO WhatsApp Otomatis Jadi Invoice!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: isMobile ? 12.5 : 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Pengirim: ${alert.senderName.isNotEmpty ? alert.senderName : "Customer WA"} (${alert.senderPhone.isNotEmpty ? alert.senderPhone : "Chat"})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFA7F3D0),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Close Button
                      InkWell(
                        onTap: onDismiss,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Bottom Action Row: Adaptive Invoice Buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Single Invoice direct button
                      if (!alert.isMultiInvoice && alert.invoiceNos.isNotEmpty)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.receipt_long_rounded, size: 15),
                          label: Text(
                            'Lihat Invoice #${alert.invoiceNos.first}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          onPressed: () => onOpenInvoice(alert.invoiceNos.first),
                        ),

                      // Multiple Invoices chips
                      if (alert.isMultiInvoice) ...[
                        for (final inv in alert.invoiceNos)
                          ActionChip(
                            avatar: const Icon(Icons.receipt_rounded, size: 14, color: Colors.tealAccent),
                            backgroundColor: const Color(0xFF042F2E),
                            side: const BorderSide(color: Color(0xFF10B981)),
                            label: Text(
                              '#$inv',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11.5,
                              ),
                            ),
                            onPressed: () => onOpenInvoice(inv),
                          ),
                      ],

                      // Open History Button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFA7F3D0),
                          side: const BorderSide(color: Color(0xFF34D399), width: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.history_rounded, size: 14),
                        label: Text(
                          isMobile ? 'Histori' : 'Buka Histori Transaksi',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                        onPressed: onOpenHistory,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
