import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Helper to parse coordinates and URLs for Google Maps
class MapsLocationParser {
  /// Extracts (latitude, longitude) from text or various Google Maps URL formats.
  static ({double lat, double lng})? extractCoordinates(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    // Direct coordinates: "-6.982123, 110.409876" or "-6.982123,110.409876"
    final directMatch = RegExp(r'^(-?\d+\.\d+)[,\s]+(-?\d+\.\d+)$').firstMatch(text);
    if (directMatch != null) {
      final lat = double.tryParse(directMatch.group(1)!);
      final lng = double.tryParse(directMatch.group(2)!);
      if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
        return (lat: lat, lng: lng);
      }
    }

    // Google Maps URL with @lat,lng,zoom: ".../@-6.982123,110.409876,17z..."
    final atMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(text);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1)!);
      final lng = double.tryParse(atMatch.group(2)!);
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }

    // Google Maps query param: "?q=-6.982123,110.409876" or "&query=-6.982123,110.409876" or "ll=-6.982123,110.409876"
    final queryMatch = RegExp(r'[?&/](?:q|query|ll)=(-?\d+\.\d+)[,\s]+(-?\d+\.\d+)').firstMatch(text);
    if (queryMatch != null) {
      final lat = double.tryParse(queryMatch.group(1)!);
      final lng = double.tryParse(queryMatch.group(2)!);
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }

    return null;
  }

  /// Builds a Google Maps search URL from address text
  static String buildSearchUrl({required String address, String city = '', String province = ''}) {
    final parts = [address.trim(), city.trim(), province.trim()].where((p) => p.isNotEmpty).join(', ');
    if (parts.isEmpty) return 'https://www.google.com/maps';
    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(parts)}';
  }

  /// Safely launch Google Maps URL in external application / browser
  static Future<bool> launchMaps(String urlOrCoords) async {
    final text = urlOrCoords.trim();
    if (text.isEmpty) return false;

    Uri? uri;
    if (text.startsWith('http://') || text.startsWith('https://')) {
      uri = Uri.tryParse(text);
    } else {
      // Treat as coordinates or search query
      final coords = extractCoordinates(text);
      if (coords != null) {
        uri = Uri.tryParse('https://www.google.com/maps/search/?api=1&query=${coords.lat},${coords.lng}');
      } else {
        uri = Uri.tryParse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(text)}');
      }
    }

    if (uri != null) {
      try {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}

/// Shopee-style interactive Minimap & Google Maps Link Form Field
class CustomerMinimapWidget extends StatefulWidget {
  final TextEditingController controller;
  final String? initialStoreName;
  final String Function()? getStoreNameCallback;
  final String Function()? getAddressCallback;
  final String Function()? getCityCallback;
  final String Function()? getProvinceCallback;
  final void Function(double? lat, double? lng)? onCoordinatesChanged;
  final double? initialLat;
  final double? initialLng;

  const CustomerMinimapWidget({
    super.key,
    required this.controller,
    this.initialStoreName,
    this.getStoreNameCallback,
    this.getAddressCallback,
    this.getCityCallback,
    this.getProvinceCallback,
    this.onCoordinatesChanged,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<CustomerMinimapWidget> createState() => _CustomerMinimapWidgetState();
}

class _CustomerMinimapWidgetState extends State<CustomerMinimapWidget> {
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
    if (_lat == null || _lng == null) {
      _parseFromController();
    }
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    _parseFromController();
  }

  void _parseFromController() {
    final coords = MapsLocationParser.extractCoordinates(widget.controller.text);
    if (coords != null) {
      if (_lat != coords.lat || _lng != coords.lng) {
        setState(() {
          _lat = coords.lat;
          _lng = coords.lng;
        });
        widget.onCoordinatesChanged?.call(_lat, _lng);
      }
    } else {
      if (_lat != null || _lng != null) {
        setState(() {
          _lat = null;
          _lng = null;
        });
        widget.onCoordinatesChanged?.call(null, null);
      }
    }
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      widget.controller.text = data.text!.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 Link/Koordinat berhasil ditempel!'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _generateFromAddress() {
    final addr = widget.getAddressCallback?.call() ?? '';
    final city = widget.getCityCallback?.call() ?? '';
    final prov = widget.getProvinceCallback?.call() ?? '';

    if (addr.trim().isEmpty && city.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi Alamat atau Kota terlebih dahulu!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final url = MapsLocationParser.buildSearchUrl(address: addr, city: city, province: prov);
    widget.controller.text = url;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎯 Link pencarian Google Maps berhasil dibuat dari Alamat!'),
        backgroundColor: Color(0xFF0284C7),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openInGoogleMaps() {
    final url = widget.controller.text.trim();
    if (url.isNotEmpty) {
      MapsLocationParser.launchMaps(url);
    } else {
      _generateFromAddress();
      final newUrl = widget.controller.text.trim();
      if (newUrl.isNotEmpty) {
        MapsLocationParser.launchMaps(newUrl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = widget.controller.text.trim().isNotEmpty;
    final hasCoords = _lat != null && _lng != null;
    final dynamicName = widget.getStoreNameCallback?.call();
    final storeName = (dynamicName != null && dynamicName.trim().isNotEmpty)
        ? dynamicName.trim()
        : (widget.initialStoreName?.trim().isNotEmpty == true ? widget.initialStoreName!.trim() : 'Toko Pelanggan');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasCoords
              ? const Color(0xFF10B981).withOpacity(0.4)
              : (hasLink ? const Color(0xFF38BDF8).withOpacity(0.3) : const Color(0xFF334155)),
          width: hasCoords ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Status Bar (Shopee style) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: hasCoords
                  ? const Color(0xFF10B981).withOpacity(0.12)
                  : (hasLink ? const Color(0xFF0284C7).withOpacity(0.12) : const Color(0xFF1E293B)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  size: 16,
                  color: hasCoords ? const Color(0xFF10B981) : (hasLink ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 6),
                Text(
                  'Titik Lokasi Peta (Minimap)',
                  style: TextStyle(
                    color: hasCoords ? const Color(0xFF10B981) : (hasLink ? const Color(0xFF38BDF8) : Colors.white70),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasCoords
                        ? const Color(0xFF10B981).withOpacity(0.2)
                        : (hasLink ? const Color(0xFF0284C7).withOpacity(0.2) : Colors.white.withOpacity(0.06)),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: hasCoords
                          ? const Color(0xFF10B981).withOpacity(0.5)
                          : (hasLink ? const Color(0xFF38BDF8).withOpacity(0.4) : Colors.transparent),
                      width: 0.6,
                    ),
                  ),
                  child: Text(
                    hasCoords ? '✓ Koordinat Terpasang' : (hasLink ? '✓ Link Terhubung' : 'Belum Ada Titik'),
                    style: TextStyle(
                      color: hasCoords ? const Color(0xFF10B981) : (hasLink ? const Color(0xFF38BDF8) : const Color(0xFF64748B)),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Minimap Preview Box ──
          InkWell(
            onTap: _openInGoogleMaps,
            borderRadius: BorderRadius.zero,
            child: Container(
              height: 130,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: Color(0xFF090D16),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 1. Map Tile Background or Stylized Vector Grid
                  if (hasCoords)
                    Image.network(
                      'https://staticmap.openstreetmap.de/staticmap.php?center=$_lat,$_lng&zoom=15&size=500x160&maptype=mapnik',
                      width: double.infinity,
                      height: 130,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildFallbackVectorMap(),
                    )
                  else
                    _buildFallbackVectorMap(),

                  // 2. Subtle Dark Vignette Gradient
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.35),
                          Colors.transparent,
                          Colors.black.withOpacity(0.5),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),

                  // 3. Shopee-style Center Pin Marker with Store Label
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.8), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.store_rounded, size: 12, color: Color(0xFFEF4444)),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                storeName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Ripple pulse effect under pin
                          Container(
                            width: 22,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const Icon(
                            Icons.location_on,
                            size: 32,
                            color: Color(0xFFEF4444), // Vibrant Shopee Red
                          ),
                        ],
                      ),
                    ],
                  ),

                  // 4. Overlay: Top Right "Buka Peta" Pill
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new_rounded, size: 12, color: Color(0xFF38BDF8)),
                          SizedBox(width: 4),
                          Text('Buka Maps', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),

                  // 5. Overlay: Bottom Left Coordinates / Address Tag
                  Positioned(
                    bottom: 6,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        hasCoords
                            ? '📍 ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}'
                            : (hasLink ? '📍 Link Google Maps Aktif' : '📍 Ketuk untuk tandai titik lokasi'),
                        style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Input & Action Controls ──
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: widget.controller,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Tempel link Google Maps atau koordinat (lat, lng)...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                    prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF38BDF8), size: 18),
                    suffixIcon: widget.controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 16),
                            onPressed: () {
                              widget.controller.clear();
                              setState(() {
                                _lat = null;
                                _lng = null;
                              });
                              widget.onCoordinatesChanged?.call(null, null);
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Action Buttons Bar (Paste, Cari dari Alamat, Buka Google Maps)
                Row(
                  children: [
                    // Paste Button
                    Expanded(
                      child: InkWell(
                        onTap: _pasteFromClipboard,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF475569)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.content_paste_rounded, size: 13, color: Color(0xFF38BDF8)),
                              SizedBox(width: 4),
                              Text('Paste', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Ambil dari Alamat Button
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: _generateFromAddress,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF0284C7)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.my_location_rounded, size: 13, color: Colors.cyanAccent),
                              SizedBox(width: 4),
                              Text('Cari dari Alamat', style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Buka Google Maps Button
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: _openInGoogleMaps,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF10B981)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.map_rounded, size: 13, color: Color(0xFF34D399)),
                              SizedBox(width: 4),
                              Text('Buka Maps ↗', style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
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

  /// Stylized dark vector blueprint map for offline or empty state
  Widget _buildFallbackVectorMap() {
    return Container(
      color: const Color(0xFF0F172A),
      child: CustomPaint(
        painter: _VectorMapPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Custom painter to draw aesthetic city map roads & grid lines (Shopee-like vector minimap)
class _VectorMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0B132B);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final roadPaint = Paint()
      ..color = const Color(0xFF1C2A4A)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    final secondaryRoadPaint = Paint()
      ..color = const Color(0xFF17233D)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final riverPaint = Paint()
      ..color = const Color(0xFF0D324D).withOpacity(0.6)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke;

    // Curved river path
    final riverPath = Path()
      ..moveTo(0, size.height * 0.2)
      ..cubicTo(size.width * 0.3, size.height * 0.4, size.width * 0.7, size.height * 0.1, size.width, size.height * 0.6);
    canvas.drawPath(riverPath, riverPaint);

    // Primary grid roads
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), roadPaint);
    canvas.drawLine(Offset(size.width * 0.45, 0), Offset(size.width * 0.45, size.height), roadPaint);
    canvas.drawLine(Offset(size.width * 0.8, 0), Offset(size.width * 0.8, size.height), roadPaint);

    // Diagonal road
    canvas.drawLine(Offset(0, size.height * 0.9), Offset(size.width * 0.6, 0), secondaryRoadPaint);

    // Secondary grid roads
    for (double y = 15; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), secondaryRoadPaint);
    }
    for (double x = 20; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), secondaryRoadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
