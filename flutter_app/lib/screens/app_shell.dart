import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/monitoring_client.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'live_monitor_screen.dart';
import 'trip_analytics_screen.dart';
import 'calibration_settings_screen.dart';
import 'post_trip_summary_dialog.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.client});

  final MonitoringClient client;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _isSessionActive = false;
  Timer? _clockTimer;
  String _clockText = '';
  String _dateText = '';
  bool? _lastConnected;
  String? _connectionBannerMsg;

  @override
  void initState() {
    super.initState();
    _tickClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());
    _lastConnected = widget.client.connectionState == BackendConnectionState.connected;
    widget.client.addListener(_checkConnection);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    widget.client.removeListener(_checkConnection);
    super.dispose();
  }

  void _checkConnection() {
    final connected = widget.client.connectionState == BackendConnectionState.connected && !widget.client.isStale;
    if (_lastConnected == true && connected == false) {
      _showConnectionBanner('Backend disconnected — reconnecting...');
    } else if (_lastConnected == false && connected == true) {
      _showConnectionBanner('Backend reconnected');
    }
    _lastConnected = connected;
  }

  void _showConnectionBanner(String msg) {
    setState(() => _connectionBannerMsg = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _connectionBannerMsg == msg) setState(() => _connectionBannerMsg = null);
    });
  }

  void _tickClock() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    _clockText = '$hh:$mm:$ss WIB';
    const months = ['', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    _dateText = '${now.day.toString().padLeft(2, '0')} ${months[now.month]} ${now.year}';
    if (mounted) setState(() {});
  }

  DateTime? _sessionStartTime;

  void _startSession() {
    setState(() {
      _isSessionActive = true;
      _selectedIndex = 0;
      _sessionStartTime = DateTime.now();
    });
    widget.client.sendCommand('/api/v1/session/start').catchError((_) {});
  }

  Future<void> _endSession() async {
    Map<String, dynamic> summary;
    try {
      summary = await widget.client.fetchCurrentSummary();
    } catch (_) {
      summary = <String, dynamic>{
        'trip_duration_s': 0, 'avg_attention': 0, 'max_perclos': 0, 'alert_count': 0, 'avg_blinks_per_min': 0,
      };
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => PostTripSummaryDialog(summary: summary),
    );
    if (mounted) {
      setState(() { _isSessionActive = false; _selectedIndex = 0; _sessionStartTime = null; });
    }
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    // Only handle shortcuts when session is active and on live monitor
    if (!_isSessionActive || _selectedIndex != 0) return;

    final key = event.logicalKey;
    // M = mute/unmute
    if (key == LogicalKeyboardKey.keyM) {
      final snap = widget.client.snapshot;
      widget.client.sendCommand(snap.alarmMuted ? '/api/v1/alarm/unmute' : '/api/v1/alarm/mute');
    }
    // C = calibrate
    if (key == LogicalKeyboardKey.keyC) {
      widget.client.sendCommand('/api/v1/calibration/start', {'duration': 4});
    }
    // F = fullscreen HUD (handled by LiveMonitorScreen via a callback)
    if (key == LogicalKeyboardKey.keyF) {
      // LiveMonitorScreen handles this internally
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.client,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 880;
        final showSidebar = _isSessionActive && wide;

        return KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: _handleKey,
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                if (showSidebar)
                  _CompactSidebar(
                    selectedIndex: _selectedIndex,
                    isSessionActive: _isSessionActive,
                    connected: _lastConnected ?? false,
                    onSelect: (i) => setState(() => _selectedIndex = i),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      // Connection status banner (animated slide-in)
                      _ConnectionBanner(msg: _connectionBannerMsg),
                      _TopHeader(
                        client: widget.client,
                        isSessionActive: _isSessionActive,
                        clockText: _clockText,
                        dateText: _dateText,
                        onEndSession: _isSessionActive ? _endSession : null,
                        onNavigate: _isSessionActive ? null : (i) => setState(() => _selectedIndex = i),
                        selectedIndex: _selectedIndex,
                      ),
                      Expanded(child: Stack(
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(begin: const Offset(0.02, 0), end: Offset.zero).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: _buildPage(),
                          ),
                          // Scroll-to-top FAB
                          Positioned(
                            right: 24, bottom: 24,
                            child: _ScrollToTopFAB(),
                          ),
                        ],
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage() {
    final key = ValueKey('$_isSessionActive-$_selectedIndex');
    if (!_isSessionActive) {
      switch (_selectedIndex) {
        case 2: return CalibrationSettingsScreen(key: key, client: widget.client);
        default: return HomeScreen(key: key, client: widget.client, onStartSession: _startSession);
      }
    }
    switch (_selectedIndex) {
      case 0: return LiveMonitorScreen(key: key, client: widget.client, sessionStartTime: _sessionStartTime);
      case 1: return TripAnalyticsScreen(key: key, client: widget.client);
      case 2: return CalibrationSettingsScreen(key: key, client: widget.client);
      default: return LiveMonitorScreen(key: key, client: widget.client, sessionStartTime: _sessionStartTime);
    }
  }
}

// ─── Connection Status Banner ───────────────────────────────────────────────

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.msg});
  final String? msg;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: const SizedBox.shrink(),
      secondChild: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: msg != null && msg!.contains('reconnected')
            ? AppColors.focusedGreen.withOpacity(0.15)
            : AppColors.alertAmber.withOpacity(0.15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              msg != null && msg!.contains('reconnected') ? Icons.check_circle_outline : Icons.sync_outlined,
              size: 16,
              color: msg != null && msg!.contains('reconnected') ? AppColors.focusedGreen : AppColors.alertAmber,
            ),
            const SizedBox(width: 8),
            Text(
              msg ?? '',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: msg != null && msg!.contains('reconnected') ? AppColors.focusedGreen : AppColors.alertAmber,
              ),
            ),
          ],
        ),
      ),
      crossFadeState: msg != null ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 300),
      sizeCurve: Curves.easeOut,
    );
  }
}

// ─── Compact Sidebar ────────────────────────────────────────────────────────

class _CompactSidebar extends StatelessWidget {
  const _CompactSidebar({
    required this.selectedIndex,
    required this.isSessionActive,
    required this.connected,
    required this.onSelect,
  });
  final int selectedIndex;
  final bool isSessionActive;
  final bool connected;
  final void Function(int) onSelect;

  static const _items = [
    _NavEntry(icon: Icons.videocam_outlined, label: 'Live Monitor'),
    _NavEntry(icon: Icons.insights_outlined, label: 'Trip Analytics'),
    _NavEntry(icon: Icons.settings_input_component_outlined, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: AppColors.surface0,
      child: Column(children: [
        const SizedBox(height: 32),
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.shield, size: 22, color: AppColors.surface0)),
        const SizedBox(height: 40),
        for (var i = 0; i < _items.length; i++)
          Tooltip(message: _items[i].label, preferBelow: false, waitDuration: const Duration(milliseconds: 400),
            child: Padding(padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(onTap: () => onSelect(i),
                child: _SidebarIcon(icon: _items[i].icon, selected: selectedIndex == i, showLiveBadge: i == 0 && isSessionActive)))),
        const Spacer(),
        // Keyboard shortcut hints (when session active)
        if (isSessionActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(children: [
              _shortcutHint('M', 'Mute'),
              _shortcutHint('C', 'Calibrate'),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Tooltip(
            message: connected ? 'System Online' : 'Disconnected',
            child: Container(width: 12, height: 12,
              decoration: BoxDecoration(
                color: connected ? AppColors.focusedGreen : AppColors.offlineYellow,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: (connected ? AppColors.focusedGreen : AppColors.offlineYellow).withOpacity(0.5), blurRadius: 8)],
              )),
          )),
      ]),
    );
  }

  Widget _shortcutHint(String key, String action) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(3), border: Border.all(color: const Color(0x33444748))),
          child: Text(key, style: const TextStyle(fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ),
      ]),
    );
  }
}

class _NavEntry {
  const _NavEntry({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _SidebarIcon extends StatelessWidget {
  const _SidebarIcon({required this.icon, required this.selected, required this.showLiveBadge});
  final IconData icon;
  final bool selected;
  final bool showLiveBadge;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: selected ? AppColors.accent.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(alignment: Alignment.center, children: [
        Icon(icon, size: 22, color: selected ? AppColors.accent : AppColors.textSecondary),
        if (showLiveBadge) Positioned(top: 4, right: 4, child: _PulsingDot()),
      ]),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _opacityAnim = Tween(begin: 0.9, end: 0.3).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Stack(alignment: Alignment.center, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: AppColors.alertRed.withOpacity(_opacityAnim.value * 0.4), shape: BoxShape.circle)),
        Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.alertRed, shape: BoxShape.circle, border: Border.all(color: AppColors.surface0, width: 1))),
      ]),
    );
  }
}

// ─── Top Header ─────────────────────────────────────────────────────────────

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.client, required this.isSessionActive, required this.clockText, required this.dateText,
    this.onEndSession, this.onNavigate, this.selectedIndex = 0,
  });
  final MonitoringClient client;
  final bool isSessionActive;
  final String clockText, dateText;
  final VoidCallback? onEndSession;
  final void Function(int)? onNavigate;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final connected = client.connectionState == BackendConnectionState.connected && !client.isStale;
    final color = connected ? AppColors.focusedGreen : AppColors.offlineYellow;

    return Container(
      height: 64, padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x44444748), width: 0.5))),
      child: Row(children: [
        if (!isSessionActive) ...[
          Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(4)),
            child: const Icon(Icons.shield, size: 18, color: AppColors.surface0)),
          const SizedBox(width: 12),
          const Text('WakeGuard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(width: 32),
          _HeaderNavLink(label: 'Dashboard', icon: Icons.home_outlined, selected: selectedIndex == 0, onTap: () => onNavigate?.call(0)),
          const SizedBox(width: 4),
          _HeaderNavLink(label: 'Settings', icon: Icons.settings_outlined, selected: selectedIndex == 2, onTap: () => onNavigate?.call(2)),
        ] else ...[
          _ConnectionPill(connected: connected, color: color),
        ],
        const Spacer(),
        if (onEndSession != null)
          Padding(padding: const EdgeInsets.only(right: 16), child: _EndSessionButton(onPressed: onEndSession!),),
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(clockText, style: AppTextStyles.mono),
          Text(dateText, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
        ]),
        const SizedBox(width: 24),
        const Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Chief Analyst', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Text('SUPERVISOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
        ]),
        const SizedBox(width: 12),
        Container(width: 32, height: 32,
          decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
          child: const Icon(Icons.person, size: 18, color: AppColors.surface0)),
      ]),
    );
  }
}

class _ConnectionPill extends StatefulWidget {
  const _ConnectionPill({required this.connected, required this.color});
  final bool connected;
  final Color color;
  @override
  State<_ConnectionPill> createState() => _ConnectionPillState();
}

class _ConnectionPillState extends State<_ConnectionPill> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  @override
  void initState() { super.initState(); _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true); }
  @override
  void dispose() { _pulseCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(animation: _pulseCtrl, builder: (context, _) {
          final opacity = widget.connected ? (0.5 + _pulseCtrl.value * 0.5) : 1.0;
          return Container(width: 8, height: 8, decoration: BoxDecoration(
            color: widget.color.withOpacity(opacity), shape: BoxShape.circle,
            boxShadow: widget.connected ? [BoxShadow(color: widget.color.withOpacity(opacity * 0.4), blurRadius: 6)] : null));
        }),
        const SizedBox(width: 8),
        Text(widget.connected ? 'Backend Connected' : 'Backend Disconnected', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _EndSessionButton extends StatefulWidget {
  const _EndSessionButton({required this.onPressed});
  final VoidCallback onPressed;
  @override
  State<_EndSessionButton> createState() => _EndSessionButtonState();
}

class _EndSessionButtonState extends State<_EndSessionButton> with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  @override
  void initState() { super.initState(); _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true); }
  @override
  void dispose() { _glowCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _glowCtrl, builder: (context, _) {
      return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: AppColors.alertRed.withOpacity(0.15 + _glowCtrl.value * 0.15), blurRadius: 12 + _glowCtrl.value * 6)]),
        child: ElevatedButton.icon(
          onPressed: widget.onPressed, icon: const Icon(Icons.stop, size: 18),
          label: const Text('END SESSION', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.alertRed, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), elevation: 0),
        ),
      );
    });
  }
}

class _HeaderNavLink extends StatelessWidget {
  const _HeaderNavLink({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withOpacity(0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: selected ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? AppColors.textPrimary : AppColors.textSecondary)),
          ]))));
  }
}

// ─── Scroll-to-Top FAB ─────────────────────────────────────────────────────

class _ScrollToTopFAB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Scroll to top',
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33444748)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () {
              // Find the nearest Scrollable and scroll to top
              final state = Scrollable.maybeOf(context);
              state?.position.jumpTo(0);
            },
            borderRadius: BorderRadius.circular(22),
            child: const Icon(Icons.keyboard_arrow_up, size: 22, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}