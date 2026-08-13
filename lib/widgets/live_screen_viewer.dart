import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui_web' as ui_web;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import '../services/webrtc_service.dart';

class LiveScreenViewer extends StatefulWidget {
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
  State<LiveScreenViewer> createState() => _LiveScreenViewerState();
}

class _LiveScreenViewerState extends State<LiveScreenViewer> {
  final WebRtcScreenService _webrtcService = WebRtcScreenService();
  html.VideoElement? _videoElement;
  html.MediaStream? _currentStream;
  late final String _viewId;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isPlaying = false;
  String _statusText = 'Menghubungkan ke siaran layar...';

  @override
  void initState() {
    super.initState();
    _viewId = 'webrtc-video-${DateTime.now().millisecondsSinceEpoch}';

    if (kIsWeb) {
      final container = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'relative'
        ..style.backgroundColor = '#000000'
        ..style.overflow = 'hidden';

      _videoElement = html.VideoElement()
        ..autoplay = true
        ..controls = false
        ..muted = true
        ..defaultMuted = true
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain';

      _videoElement!.setAttribute('playsinline', 'true');
      _videoElement!.setAttribute('webkit-playsinline', 'true');
      _videoElement!.setAttribute('autoplay', 'true');
      _videoElement!.setAttribute('muted', 'true');

      _videoElement!.onLoadedMetadata.listen((_) {
        _videoElement?.play();
      });

      _videoElement!.onCanPlay.listen((_) {
        _videoElement?.play();
      });

      _videoElement!.onPlaying.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = true;
            _isConnected = true;
            _isConnecting = false;
            _statusText = 'Live Stream Aktif (60 FPS)';
          });
        }
      });

      container.append(_videoElement!);

      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int viewId) => container,
      );

      _connect();
    }
  }

  Future<void> _connect() async {
    if (!mounted) return;
    setState(() {
      _isConnecting = true;
      _statusText = 'Menyambungkan ke layar...';
    });

    try {
      await _webrtcService.connectToBroadcast(
        sessionId: widget.sessionId,
        onStatusUpdate: (status) {
          if (mounted) {
            setState(() {
              _statusText = status;
              if (status.contains('Terhubung') || status.contains('Lancar')) {
                _isConnected = true;
                _isConnecting = false;
              }
            });
          }
        },
        onRemoteStreamReceived: (stream) {
          _currentStream = stream;
          if (_videoElement != null) {
            try {
              js_util.setProperty(_videoElement!, 'srcObject', stream);
              _videoElement!.srcObject = stream;
              _videoElement!.play().catchError((e) {
                debugPrint("Auto-play error: $e");
              });
            } catch (e) {
              debugPrint("Video assignment error: $e");
            }

            if (mounted) {
              setState(() {
                _isConnected = true;
                _isConnecting = false;
                _statusText = 'Live Stream Aktif (60 FPS)';
              });
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
          _statusText = 'Gagal terhubung: $e';
        });
      }
    }
  }

  void _manualPlay() {
    if (_videoElement != null) {
      if (_currentStream != null && _videoElement!.srcObject == null) {
        js_util.setProperty(_videoElement!, 'srcObject', _currentStream);
        _videoElement!.srcObject = _currentStream;
      }
      _videoElement!.play().then((_) {
        if (mounted) {
          setState(() {
            _isPlaying = true;
            _statusText = 'Live Stream Aktif (60 FPS)';
          });
        }
      }).catchError((e) {
        debugPrint("Manual play error: $e");
      });
    }
  }

  void _openPopoutWindow() {
    if (_currentStream == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesi belum menerima stream video. Klik tombol Muat Ulang Sambungan.'),
          backgroundColor: Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final newWin = html.window.open('', 'LiveScreenPopout', 'width=1280,height=720');
      if (newWin != null) {
        final doc = js_util.getProperty(newWin, 'document');
        if (doc != null) {
          js_util.setProperty(doc, 'title', 'Live Screen: ${widget.stationName}');
          final body = js_util.getProperty(doc, 'body');
          if (body != null) {
            final style = js_util.getProperty(body, 'style');
            js_util.setProperty(style, 'margin', '0');
            js_util.setProperty(style, 'backgroundColor', '#000000');
            js_util.setProperty(style, 'overflow', 'hidden');

            final popoutVideo = html.VideoElement()
              ..autoplay = true
              ..controls = true
              ..muted = true
              ..style.width = '100vw'
              ..style.height = '100vh'
              ..style.objectFit = 'contain';

            popoutVideo.setAttribute('playsinline', 'true');
            popoutVideo.setAttribute('autoplay', 'true');
            popoutVideo.setAttribute('muted', 'true');

            js_util.setProperty(popoutVideo, 'srcObject', _currentStream);
            popoutVideo.srcObject = _currentStream;
            js_util.callMethod(body, 'append', [popoutVideo]);
            popoutVideo.play();
          }
        }
      }
    } catch (e) {
      debugPrint("Popout error: $e");
    }
  }

  void _toggleFullscreen() {
    if (_videoElement != null) {
      try {
        if (html.document.fullscreenElement != null) {
          html.document.exitFullscreen();
        } else {
          _videoElement!.requestFullscreen();
        }
      } catch (e) {
        debugPrint("Fullscreen error: $e");
      }
    }
  }

  @override
  void dispose() {
    _webrtcService.disconnectViewer();
    if (_videoElement != null) {
      try {
        js_util.setProperty(_videoElement!, 'srcObject', null);
        _videoElement!.srcObject = null;
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _isConnected ? const Color(0xFF4ADE80) : Colors.amberAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '📺 LIVE SCREEN: ${widget.stationName}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isConnected
                          ? const Color(0xFF10B981).withOpacity(0.2)
                          : Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _isConnected
                            ? const Color(0xFF34D399)
                            : Colors.amberAccent,
                      ),
                    ),
                    child: Text(
                      _statusText,
                      style: TextStyle(
                        color: _isConnected ? const Color(0xFF34D399) : Colors.amberAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF38BDF8), size: 18),
                    tooltip: 'Buka di Jendela Pop-up Terpisah',
                    splashRadius: 16,
                    onPressed: _openPopoutWindow,
                  ),
                  IconButton(
                    icon: const Icon(Icons.fullscreen_rounded, color: Color(0xFF38BDF8), size: 20),
                    tooltip: 'Layar Penuh (Fullscreen)',
                    splashRadius: 16,
                    onPressed: _toggleFullscreen,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 18),
                    tooltip: 'Muat Ulang Sambungan',
                    splashRadius: 16,
                    onPressed: _connect,
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                      tooltip: 'Tutup Layar',
                      splashRadius: 16,
                      onPressed: widget.onClose,
                    ),
                ],
              ),
            ),

            // Video Player Container
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (kIsWeb)
                    HtmlElementView(viewType: _viewId)
                  else
                    const Center(
                      child: Text('WebRTC Screen Share hanya didukung pada Web Browser.',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  if (!_isPlaying && _isConnected)
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 18),
                            label: const Text('Pop-out Jendela', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: _openPopoutWindow,
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                            label: const Text('▶️ Putar Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: _manualPlay,
                          ),
                        ],
                      ),
                    ),
                  if (_isConnecting)
                    Container(
                      color: Colors.black.withOpacity(0.6),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF38BDF8)),
                            SizedBox(height: 12),
                            Text('Menghubungkan ke siaran layar...',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
