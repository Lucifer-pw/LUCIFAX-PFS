import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/walkie_talkie_service.dart';

class WalkieTalkieWidget extends StatefulWidget {
  final UserProfile currentUser;

  const WalkieTalkieWidget({
    super.key,
    required this.currentUser,
  });

  @override
  State<WalkieTalkieWidget> createState() => _WalkieTalkieWidgetState();
}

class _WalkieTalkieWidgetState extends State<WalkieTalkieWidget>
    with SingleTickerProviderStateMixin {
  final WalkieTalkieService _service = WalkieTalkieService();
  final AuthService _authService = AuthService();

  bool _isExpanded = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _service.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If not initialized yet, show nothing or mini connecting pill
    final isTransmitting = _service.isTransmitting;
    final isReceiving = _service.isReceiving;
    final isBusy = _service.isChannelBusy;

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 12, right: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.95),
          borderRadius: BorderRadius.circular(_isExpanded ? 16 : 30),
          border: Border.all(
            color: isTransmitting
                ? Colors.redAccent
                : isReceiving
                    ? const Color(0xFF38BDF8)
                    : isBusy
                        ? Colors.amber.withOpacity(0.6)
                        : const Color(0xFF38BDF8).withOpacity(0.35),
            width: isTransmitting || isReceiving ? 2.0 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isTransmitting
                  ? Colors.redAccent.withOpacity(0.35)
                  : isReceiving
                      ? const Color(0xFF38BDF8).withOpacity(0.35)
                      : isBusy
                          ? Colors.amber.withOpacity(0.25)
                          : Colors.black.withOpacity(0.4),
              blurRadius: isTransmitting || isReceiving ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _isExpanded ? _buildExpandedPanel() : _buildMinimizedPill(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // MINIMIZED PILL (NON-INTRUSIVE DOCKED AT BOTTOM-RIGHT)
  // ══════════════════════════════════════════════════════════

  Widget _buildMinimizedPill() {
    final isTransmitting = _service.isTransmitting;
    final isReceiving = _service.isReceiving;
    final isBusy = _service.isChannelBusy;

    Color badgeColor = const Color(0xFF10B981); // Emerald
    String statusLabel = 'Radio [Alt]';

    if (isTransmitting) {
      badgeColor = Colors.redAccent;
      statusLabel = 'BICARA (0s)...';
    } else if (isReceiving) {
      badgeColor = const Color(0xFF38BDF8);
      statusLabel = '${_service.currentSpeakerName ?? "Seseorang"} berbicara';
    } else if (isBusy) {
      badgeColor = Colors.amber;
      statusLabel = '${_service.currentSpeakerName} (Sibuk)';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () {
        _service.unlockAudio();
        setState(() => _isExpanded = true);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Glowing Indicator
            ScaleTransition(
              scale: (isTransmitting || isReceiving)
                  ? _pulseAnimation
                  : const AlwaysStoppedAnimation(1.0),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: badgeColor.withOpacity(0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Radio Icon
            Icon(
              isTransmitting
                  ? Icons.mic_rounded
                  : isReceiving
                      ? Icons.volume_up_rounded
                      : Icons.cell_tower_rounded,
              size: 18,
              color: isTransmitting
                  ? Colors.redAccent
                  : isReceiving
                      ? const Color(0xFF38BDF8)
                      : Colors.white70,
            ),
            const SizedBox(width: 8),

            // Text Info
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                statusLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: isTransmitting || isReceiving
                      ? FontWeight.bold
                      : FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Speaker Mute Quick Toggle
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _service.toggleSpeakerMute(),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(
                  _service.isSpeakerMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  size: 16,
                  color: _service.isSpeakerMuted
                      ? Colors.redAccent
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Expand Arrow
            const Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: Color(0xFF64748B),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // EXPANDED CONTROL PANEL
  // ══════════════════════════════════════════════════════════

  Widget _buildExpandedPanel() {
    final isTransmitting = _service.isTransmitting;
    final isReceiving = _service.isReceiving;
    final isBusy = _service.isChannelBusy;

    return Container(
      width: 310,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with minimize button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.cell_tower_rounded,
                  color: Color(0xFF38BDF8),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Radio Toko (Walkie-Talkie)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Realtime PTT • Tahan Alt',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF94A3B8),
                  size: 22,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Kecilkan',
                onPressed: () => setState(() => _isExpanded = false),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Target Selector Stream
          StreamBuilder<List<UserProfile>>(
            stream: _authService.getUsersStream(),
            builder: (context, snapshot) {
              final users = snapshot.data ?? [];
              final onlinePeers = users.where((u) {
                return u.uid != widget.currentUser.uid && u.isActuallyOnline;
              }).toList();

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _service.currentTargetId,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF0F172A),
                    icon: const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: Color(0xFF38BDF8),
                    ),
                    items: [
                      // Broadcast Option
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Row(
                          children: [
                            Icon(
                              Icons.campaign_rounded,
                              color: Color(0xFF38BDF8),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '📢 Semua Staff (Broadcast)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Peer Options
                      ...onlinePeers.map((peer) {
                        final displayName = peer.name.isNotEmpty
                            ? peer.name
                            : peer.username;
                        return DropdownMenuItem<String?>(
                          value: peer.uid,
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '👤 $displayName (${peer.role.toUpperCase()})',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: (newTargetId) {
                      String targetName = 'Semua Staff (Broadcast)';
                      if (newTargetId != null) {
                        final match = onlinePeers.firstWhere(
                          (u) => u.uid == newTargetId,
                          orElse: () => UserProfile(
                            uid: newTargetId,
                            username: '',
                            name: 'User',
                            role: '',
                          ),
                        );
                        targetName = match.name.isNotEmpty
                            ? match.name
                            : match.username;
                      }
                      _service.setTarget(
                        targetId: newTargetId,
                        targetName: targetName,
                      );
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: BoxDecoration(
              color: isTransmitting
                  ? Colors.redAccent.withOpacity(0.12)
                  : isReceiving
                      ? const Color(0xFF38BDF8).withOpacity(0.12)
                      : isBusy
                          ? Colors.amber.withOpacity(0.12)
                          : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isTransmitting
                    ? Colors.redAccent.withOpacity(0.3)
                    : isReceiving
                        ? const Color(0xFF38BDF8).withOpacity(0.3)
                        : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isTransmitting
                      ? Icons.mic_rounded
                      : isReceiving
                          ? Icons.volume_up_rounded
                          : isBusy
                              ? Icons.lock_clock_rounded
                              : Icons.check_circle_outline_rounded,
                  size: 14,
                  color: isTransmitting
                      ? Colors.redAccent
                      : isReceiving
                          ? const Color(0xFF38BDF8)
                          : isBusy
                              ? Colors.amber
                              : const Color(0xFF10B981),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isTransmitting
                        ? '🔴 Sedang Bicara ke ${_service.currentTargetName}'
                        : isReceiving
                            ? '🔊 ${_service.currentSpeakerName} sedang bicara...'
                            : isBusy
                                ? '🔒 ${_service.currentSpeakerName} sedang bicara'
                                : '● Siaga Menerima Suara',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isTransmitting
                          ? Colors.redAccent
                          : isReceiving
                              ? const Color(0xFF38BDF8)
                              : isBusy
                                  ? Colors.amber
                                  : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Large Push-to-Talk Button
          GestureDetector(
            onTapDown: (_) {
              _service.unlockAudio();
              if (!isBusy) _service.startTransmitting();
            },
            onTapUp: (_) => _service.stopTransmitting(),
            onTapCancel: () => _service.stopTransmitting(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isTransmitting
                      ? [const Color(0xFFDC2626), const Color(0xFFB91C1C)]
                      : isBusy
                          ? [const Color(0xFF334155), const Color(0xFF1E293B)]
                          : [const Color(0xFF0284C7), const Color(0xFF0369A1)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: isTransmitting
                        ? Colors.redAccent.withOpacity(0.4)
                        : const Color(0xFF0284C7).withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isTransmitting ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isTransmitting
                          ? 'LEPAS UNTUK BERHENTI'
                          : isBusy
                              ? 'SALURAN TERKUNCI'
                              : 'TAHAN [ALT] / KLIK BICARA',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Speaker Volume & Mute Row
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _service.isSpeakerMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: _service.isSpeakerMuted
                      ? Colors.redAccent
                      : const Color(0xFF38BDF8),
                  size: 20,
                ),
                tooltip: _service.isSpeakerMuted
                    ? 'Nyalakan Speaker'
                    : 'Bisukan Speaker (Mute)',
                onPressed: () => _service.toggleSpeakerMute(),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: const Color(0xFF38BDF8),
                    inactiveTrackColor: const Color(0xFF334155),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _service.speakerVolume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) {
                      _service.setVolume(val);
                      _service.unlockAudio();
                    },
                  ),
                ),
              ),
              Text(
                '${(_service.speakerVolume * 100).toInt()}%',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
