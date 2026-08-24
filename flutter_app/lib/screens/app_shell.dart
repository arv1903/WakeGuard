import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/monitoring_client.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'live_monitor_screen.dart';
import 'trip_analytics_screen.dart';
import 'trip_log_screen.dart';
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
    _clockTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());
    _lastConnected =
        widget.client.connectionState == BackendConnectionState.connected;
    widget.client.addListener(_checkConnection);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    widget.client.removeListener(_checkConnection);
    super.dispose();
  }

  void _checkConnection() {
    final connected =
        widget.client.connectionState == BackendConnectionState.connected;
    if (_lastConnected == true && connected == false) {
      _showConnectionBanner('Backend disconnected — reconnecting...');
      // Navigate away from Settings if currently selected, since it's hidden
      // when disconnected.
      if (_selectedIndex == 2 && !_isSessionActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedIndex = 0);
        });
      }
    } else if (_lastConnected == false && connected == true) {
      _showConnectionBanner('Backend reconnected');
    }
    _lastConnected = connected;
  }

  void _showConnectionBanner(String msg) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _connectionBannerMsg = msg);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _connectionBannerMsg == msg) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _connectionBannerMsg = null);
        });
      }
    });
  }

  void _tickClock() {
    final now = DateTime.now(); // system local time, no hardcoded offset
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    _clockText = '$hh:$mm:$ss';
    const months = [
      '',
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC'
    ];
    _dateText =
        '${now.day.toString().padLeft(2, '0')} ${months[now.month]} ${now.year}';
    if (mounted) setState(() {});
  }

  DateTime? _sessionStartTime;

  Future<void> _startSession() async {
    try {
      await widget.client.sendCommand('/api/v1/session/start');
      if (!mounted) return;
      setState(() {
        _isSessionActive = true;
        _selectedIndex = 0;
        _sessionStartTime = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Unable to start monitoring: $error'),
        backgroundColor: AppColors.alertRed,
      ));
    }
  }

  Future<void> _endSession() async {
    // Tell the backend to stop the camera/inference pipeline.
    try {
      await widget.client.sendCommand('/api/v1/session/stop');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unable to stop monitoring: $error'),
          backgroundColor: AppColors.alertRed,
        ));
      }
      return;
    }
    Map<String, dynamic> summary;
    try {
      summary = await widget.client.fetchCurrentSummary();
    } catch (_) {
      summary = <String, dynamic>{
        'trip_duration_s': 0,
        'avg_attention': 0,
        'max_perclos': 0,
        'alert_count': 0,
        'avg_blinks_per_min': 0,
      };
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => PostTripSummaryDialog(summary: summary),
    );
    if (mounted) {
      setState(() {
        _isSessionActive = false;
        _selectedIndex = 0;
        _sessionStartTime = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.medium;
    // Keep sidebar visible whenever wide (even idle) so Settings stays reachable.
    // Previously hidden when idle, forcing reliance on header nav only.
    final showSidebar = wide;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        if (_isSessionActive) ...{
          const SingleActivator(LogicalKeyboardKey.keyM): () {
            widget.client.sendCommand('/api/v1/alarm/mute').catchError((_) {});
          },
          const SingleActivator(LogicalKeyboardKey.keyC): () {
            widget.client.sendCommand('/api/v1/calibration/start',
                {'duration': 4}).catchError((_) {});
          },
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Row(
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
                      _ConnectionBanner(msg: _connectionBannerMsg),
                      _TopHeader(
                        client: widget.client,
                        isSessionActive: _isSessionActive,
                        clockText: _clockText,
                        dateText: _dateText,
                        onEndSession: _isSessionActive ? _endSession : null,
                        onNavigate: _isSessionActive
                            ? null
                            : (i) => setState(() => _selectedIndex = i),
                        selectedIndex: _selectedIndex,
                      ),
                      Expanded(child: _buildPage()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage() {
    final key = ValueKey('$_isSessionActive-$_selectedIndex');
    if (!_isSessionActive) {
      switch (_selectedIndex) {
        case 1:
          return TripLogScreen(key: key, client: widget.client);
        case 2:
          return CalibrationSettingsScreen(key: key, client: widget.client);
        default:
          return HomeScreen(
              key: key,
              client: widget.client,
              onStartSession: _startSession,
              onNavigate: (i) => setState(() => _selectedIndex = i));
      }
    }
    switch (_selectedIndex) {
      case 0:
        return LiveMonitorScreen(
            key: key,
            client: widget.client,
            sessionStartTime: _sessionStartTime);
      case 1:
        return TripAnalyticsScreen(key: key, client: widget.client);
      case 2:
        return CalibrationSettingsScreen(key: key, client: widget.client);
      default:
        return LiveMonitorScreen(
            key: key,
            client: widget.client,
            sessionStartTime: _sessionStartTime);
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
            ? AppColors.focusedGreen.withValues(alpha: 0.15)
            : AppColors.alertAmber.withValues(alpha: 0.15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              msg != null && msg!.contains('reconnected')
                  ? Icons.check_circle_outline
                  : Icons.sync_outlined,
              size: 16,
              color: msg != null && msg!.contains('reconnected')
                  ? AppColors.focusedGreen
                  : AppColors.alertAmber,
            ),
            const SizedBox(width: 8),
            Text(
              msg ?? '',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: msg != null && msg!.contains('reconnected')
                    ? AppColors.focusedGreen
                    : AppColors.alertAmber,
              ),
            ),
          ],
        ),
      ),
      crossFadeState:
          msg != null ? CrossFadeState.showSecond : CrossFadeState.showFirst,
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

  static const _sessionItems = [
    _NavEntry(icon: Icons.videocam_outlined, label: 'Live Monitor', pageIndex: 0),
    _NavEntry(icon: Icons.insights_outlined, label: 'Trip Analytics', pageIndex: 1),
    _NavEntry(icon: Icons.settings_input_component_outlined, label: 'Settings', pageIndex: 2),
  ];

  static const _idleItems = [
    _NavEntry(icon: Icons.home_outlined, label: 'Dashboard', pageIndex: 0),
    _NavEntry(icon: Icons.history, label: 'Trip Logs', pageIndex: 1),
    _NavEntry(icon: Icons.settings_input_component_outlined, label: 'Settings', pageIndex: 2),
  ];

  List<_NavEntry> get _items {
    final base = isSessionActive ? _sessionItems : _idleItems;
    if (connected) return base;
    return base.where((e) => e.label != 'Settings').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: AppColors.surface0,
      child: Column(children: [
        const SizedBox(height: 32),
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(12)),
            child:
                const Icon(Icons.shield, size: 22, color: AppColors.surface0)),
        const SizedBox(height: 40),
        for (var i = 0; i < _items.length; i++)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                button: true,
                selected: selectedIndex == _items[i].pageIndex,
                label: _items[i].label,
                child: Tooltip(
                  message: _items[i].label,
                  child: GestureDetector(
                      onTap: () => onSelect(_items[i].pageIndex),
                      child: _SidebarIcon(
                          icon: _items[i].icon,
                          selected: selectedIndex == _items[i].pageIndex,
                          showLiveBadge: i == 0 && isSessionActive)),
                ),
              )),
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
              child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: connected
                        ? AppColors.focusedGreen
                        : AppColors.offlineYellow,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: (connected
                                  ? AppColors.focusedGreen
                                  : AppColors.offlineYellow)
                              .withValues(alpha: 0.5),
                          blurRadius: 8)
                    ],
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
          decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0x33444748))),
          child: Text(key,
              style: const TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ),
      ]),
    );
  }
}

class _NavEntry {
  const _NavEntry({required this.icon, required this.label, required this.pageIndex});
  final IconData icon;
  final String label;
  final int pageIndex;
}

class _SidebarIcon extends StatelessWidget {
  const _SidebarIcon(
      {required this.icon,
      required this.selected,
      required this.showLiveBadge});
  final IconData icon;
  final bool selected;
  final bool showLiveBadge;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(alignment: Alignment.center, children: [
        Icon(icon,
            size: 22,
            color: selected ? AppColors.accent : AppColors.textSecondary),
        if (showLiveBadge) Positioned(top: 4, right: 4, child: _PulsingDot()),
      ]),
    );
  }
}

class _PulsingDot extends StatelessWidget {
  const _PulsingDot();

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: AppColors.alertRed.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: AppColors.alertRed.withValues(alpha: 0.3),
                    blurRadius: 6)
              ])),
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: AppColors.alertRed,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface0, width: 1))),
    ]);
  }
}

// ─── Top Header ─────────────────────────────────────────────────────────────

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.client,
    required this.isSessionActive,
    required this.clockText,
    required this.dateText,
    this.onEndSession,
    this.onNavigate,
    this.selectedIndex = 0,
  });
  final MonitoringClient client;
  final bool isSessionActive;
  final String clockText, dateText;
  final VoidCallback? onEndSession;
  final void Function(int)? onNavigate;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final connected =
        client.connectionState == BackendConnectionState.connected;
    final color = connected ? AppColors.focusedGreen : AppColors.offlineYellow;
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.medium;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Color(0x44444748), width: 0.5))),
      child: Row(children: [
        if (!isSessionActive) ...[
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.shield,
                  size: 18, color: AppColors.surface0)),
          const SizedBox(width: 12),
          const Text('WakeGuard',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          // Avoid duplication: when sidebar is visible (wide), header nav links are redundant
          if (!wide) ...[
            const SizedBox(width: 32),
            _HeaderNavLink(
                label: 'Dashboard',
                icon: Icons.home_outlined,
                selected: selectedIndex == 0,
                onTap: () => onNavigate?.call(0)),
            const SizedBox(width: 4),
            _HeaderNavLink(
                label: 'Trip Logs',
                icon: Icons.history,
                selected: selectedIndex == 1,
                onTap: () => onNavigate?.call(1)),
            if (connected) ...[
              const SizedBox(width: 4),
              _HeaderNavLink(
                  label: 'Settings',
                  icon: Icons.settings_outlined,
                  selected: selectedIndex == 2,
                  onTap: () => onNavigate?.call(2)),
            ],
          ],
        ] else ...[
          _ConnectionPill(connected: connected, color: color),
        ],
        const Spacer(),
        if (onEndSession != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _EndSessionButton(onPressed: onEndSession!),
          ),
        Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(clockText, style: AppTextStyles.mono),
              Text(dateText,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.textSecondary)),
            ]),
        const SizedBox(width: 24),
        Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Operator',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Text('DRIVER',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.textSecondary)),
            ]),
        const SizedBox(width: 12),
        Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
                color: AppColors.textPrimary, shape: BoxShape.circle),
            child:
                const Icon(Icons.person, size: 18, color: AppColors.surface0)),
      ]),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.connected, required this.color});
  final bool connected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color.withValues(alpha: connected ? 0.9 : 1.0),
                shape: BoxShape.circle,
                boxShadow: connected
                    ? [
                        BoxShadow(
                            color: color.withValues(alpha: 0.4), blurRadius: 6)
                      ]
                    : null)),
        const SizedBox(width: 8),
        Text(connected ? 'Backend Connected' : 'Backend Disconnected',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _EndSessionButton extends StatelessWidget {
  const _EndSessionButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: AppColors.alertRed.withValues(alpha: 0.25),
                blurRadius: 12)
          ]),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.stop, size: 18),
        label: const Text('END SESSION',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.alertRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            elevation: 0),
      ),
    );
  }
}

class _HeaderNavLink extends StatelessWidget {
  const _HeaderNavLink(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon,
                      size: 16,
                      color: selected
                          ? AppColors.accent
                          : AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary)),
                ]))));
  }
}

// ─── Scroll-to-Top FAB ─────────────────────────────────────────────────────
