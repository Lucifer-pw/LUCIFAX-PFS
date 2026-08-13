import 'package:flutter/material.dart';

class LiveScreenViewer extends StatelessWidget {
  final String sessionId;
  final String stationName;
  final VoidCallback? onClose;

  const LiveScreenViewer({
    super.key,
    this.sessionId = 'kacab_live',
    this.stationName = 'Komputer Kantor (Joko Setiawan)',
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.screen_share_rounded, color: Color(0xFF38BDF8), size: 40),
            const SizedBox(height: 10),
            Text(
              '📺 Live Screen: $stationName',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Fitur WebRTC Live Screen Viewer hanya tersedia saat membuka aplikasi versi Web.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
