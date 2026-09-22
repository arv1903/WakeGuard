import 'dart:async';

import 'package:flutter/material.dart';

import '../services/monitoring_client.dart';
import '../theme.dart';
import '../utils/safety_grading.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.client,
    required this.onStartSession,
    this.onNavigate,
  });
  final MonitoringClient client;
  final VoidCallback onStartSession;

  /// Callback to switch AppShell tab (0=Home, 1=Analytics, 2=Settings).
  final void Function(int)? onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _tripHistory = [];
  bool _loadingHistory = false;

  MonitoringClient get client => widget.client;
  void Function(int)? get onNavigate => widget.onNavigate;

  @override
  void initState() {
    super.initState();
    _fetchTrips();
  }

  Future<void> _fetchTrips() async {
    if (_loadingHistory) return;
    _loadingHistory = true;
    try {
      final trips = await client.fetchTripHistory();
      if (mounted) setState(() => _tripHistory = trips);
    } catch (_) {}
    _loadingHistory = false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: client,
      builder: (context, _) {
        final connected =
            client.connectionState == BackendConnectionState.connected;
        final snap = client.snapshot;
        final sessionActive = snap.tripActive;
        final elapsed = snap.tripStartedAt != null
            ? DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(
                (snap.tripStartedAt! * 1000).toInt()))
            : Duration.zero;
        final width = MediaQuery.sizeOf(context).width;
        final isCompact = width < AppBreakpoints.expanded;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroCard(
                        connected: connected,
                        onStart: widget.onStartSession,
                        onNavigate: onNavigate),
                    const SizedBox(height: 24),
                    // Stats row — wraps on narrow screens
                    if (isCompact)
                      Column(children: [
                        _StatCard(
                            label: 'SESSION STATUS',
                            value: sessionActive ? 'ACTIVE' : 'IDLE',
                            subtitle: sessionActive
                                ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s elapsed'
                                : 'No active session',
                            icon: sessionActive
                                ? Icons.videocam_outlined
                                : Icons.videocam_off_outlined,
                            accent: sessionActive
                                ? AppColors.focusedGreen
                                : AppColors.textMuted),
                        const SizedBox(height: 16),
                        _StatCard(
                            label: 'AVG ATTENTION',
                            value: snap.attention.toStringAsFixed(0),
                            subtitle:
                                snap.focused ? 'Driver focused' : 'Monitoring',
                            icon: Icons.visibility_outlined,
                            accent: snap.focused
                                ? AppColors.focusedGreen
                                : AppColors.alertAmber,
                            valueSuffix: '/100'),
                        const SizedBox(height: 16),
                        _StatCard(
                            label: 'ACTIVE ALERTS',
                            value: snap.alert != null ? '1' : '0',
                            subtitle: snap.alert ?? 'None',
                            icon: Icons.warning_amber_outlined,
                            accent: snap.alert != null
                                ? AppColors.alertRed
                                : AppColors.focusedGreen,
                            isAlert: snap.alert != null),
                        const SizedBox(height: 16),
                        _SystemStatusCard(connected: connected),
                      ])
                    else
                      Row(
                        children: [
                          Expanded(
                              child: _StatCard(
                                  label: 'SESSION STATUS',
                                  value: sessionActive ? 'ACTIVE' : 'IDLE',
                                  subtitle: sessionActive
                                      ? '${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s elapsed'
                                      : 'No active session',
                                  icon: sessionActive
                                      ? Icons.videocam_outlined
                                      : Icons.videocam_off_outlined,
                                  accent: sessionActive
                                      ? AppColors.focusedGreen
                                      : AppColors.textMuted)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: _StatCard(
                                  label: 'AVG ATTENTION',
                                  value: snap.attention.toStringAsFixed(0),
                                  subtitle: snap.focused
                                      ? 'Driver focused'
                                      : 'Monitoring',
                                  icon: Icons.visibility_outlined,
                                  accent: snap.focused
                                      ? AppColors.focusedGreen
                                      : AppColors.alertAmber,
                                  valueSuffix: '/100')),
                          const SizedBox(width: 16),
                          Expanded(
                              child: _StatCard(
                                  label: 'ACTIVE ALERTS',
                                  value: snap.alert != null ? '1' : '0',
                                  subtitle: snap.alert ?? 'None',
                                  icon: Icons.warning_amber_outlined,
                                  accent: snap.alert != null
                                      ? AppColors.alertRed
                                      : AppColors.focusedGreen,
                                  isAlert: snap.alert != null)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: _SystemStatusCard(connected: connected)),
                        ],
                      ),
                    const SizedBox(height: 24),
                    // Bottom row — stacks on narrow
                    if (isCompact)
                      Column(children: [
                        _RecentTripsTable(
                          tripHistory: _tripHistory,
                          onRefresh: _fetchTrips,
                          onNavigate: onNavigate,
                        ),
                        const SizedBox(height: 24),
                        _GlobalCalibrationCard(
                          client: client,
                          onNavigate: onNavigate,
                        ),
                      ])
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              flex: 7,
                              child: _RecentTripsTable(
                                tripHistory: _tripHistory,
                                onRefresh: _fetchTrips,
                                onNavigate: onNavigate,
                              )),
                          const SizedBox(width: 24),
                          Expanded(
                              flex: 5,
                              child: _GlobalCalibrationCard(
                                client: client,
                                onNavigate: onNavigate,
                              )),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Hero Card ──────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard(
      {required this.connected, required this.onStart, this.onNavigate});
  final bool connected;
  final VoidCallback onStart;
  final void Function(int)? onNavigate;

  @override
  Widget build(BuildContext context) {
    return _HoverLift(
      clickable: false,
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surface1, AppColors.surface2],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surface2),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 700;
          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.focusedGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.focusedGreen.withValues(alpha: 0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: AppColors.focusedGreen,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text('READY FOR DEPLOYMENT',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: AppColors.focusedGreen)),
                  ]),
                ),
                const SizedBox(height: 24),
                const Text('Start New Monitoring Session',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -1)),
                const SizedBox(height: 16),
                const Text(
                  'Launch real-time camera tracking, attention metrics, and drowsiness alerts for the current fleet dispatch. System calibrated for optimal low-light detection.',
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5),
                ),
                const SizedBox(height: 32),
                Wrap(spacing: 16, runSpacing: 12, children: [
                  _GlowingButton(
                    onPressed: connected ? onStart : null,
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.play_arrow, size: 22),
                      SizedBox(width: 8),
                      Text('INITIALIZE CAMERA STREAM',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ]),
                  ),
                  OutlinedButton(
                    onPressed: () => onNavigate?.call(2),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textMuted),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.tune, size: 20),
                      SizedBox(width: 8),
                      Text('Configure Profile', style: TextStyle(fontSize: 13)),
                    ]),
                  ),
                ]),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.focusedGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                AppColors.focusedGreen.withValues(alpha: 0.2)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: AppColors.focusedGreen,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text('READY FOR DEPLOYMENT',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: AppColors.focusedGreen)),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    const Text('Start New Monitoring Session',
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -1)),
                    const SizedBox(height: 16),
                    const Text(
                      'Launch real-time camera tracking, attention metrics, and drowsiness alerts for the current fleet dispatch. System calibrated for optimal low-light detection.',
                      style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                          height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        _GlowingButton(
                          onPressed: connected ? onStart : null,
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow, size: 22),
                                SizedBox(width: 8),
                                Text('INITIALIZE CAMERA STREAM',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5)),
                              ]),
                        ),
                        OutlinedButton(
                          onPressed: () => onNavigate?.call(2),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.textMuted),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 20),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tune, size: 20),
                                SizedBox(width: 8),
                                Text('Configure Profile',
                                    style: TextStyle(fontSize: 13)),
                              ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
              Opacity(
                opacity: 0.1,
                child: Icon(Icons.shield,
                    size: 120, color: AppColors.focusedGreen),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ─── Glowing CTA Button ─────────────────────────────────────────────────────

class _GlowingButton extends StatelessWidget {
  const _GlowingButton({required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.12),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.surface0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: child,
      ),
    );
    if (onPressed == null) {
      return Tooltip(
          message: 'Backend disconnected — waiting for connection',
          child: button);
    }
    return Semantics(
        button: true, label: 'Initialize camera stream', child: button);
  }
}

// ─── Stat Cards ─────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label,
      required this.value,
      required this.subtitle,
      required this.icon,
      required this.accent,
      this.valueSuffix,
      this.isAlert = false});
  final String label, value, subtitle;
  final IconData icon;
  final Color accent;
  final String? valueSuffix;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    return _HoverLift(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surface2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: isAlert
                            ? AppColors.alertRed
                            : AppColors.textPrimary)),
                if (valueSuffix != null)
                  Text(valueSuffix!,
                      style: const TextStyle(
                          fontSize: 20, color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 13, color: accent)),
            ]),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: AppColors.textSecondary, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemStatusCard extends StatelessWidget {
  const _SystemStatusCard({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return _HoverLift(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surface2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SYSTEM STATUS',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(children: [
                Text(connected ? 'Active' : 'Offline',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 12),
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: connected
                          ? AppColors.focusedGreen
                          : AppColors.offlineYellow,
                      shape: BoxShape.circle,
                    )),
              ]),
            ]),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.focusedGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.focusedGreen.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.health_and_safety,
                  color: AppColors.focusedGreen, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Recent Trips Table ─────────────────────────────────────────────────────

class _RecentTripsTable extends StatelessWidget {
  const _RecentTripsTable({
    required this.tripHistory,
    required this.onRefresh,
    this.onNavigate,
  });

  final List<Map<String, dynamic>> tripHistory;
  final Future<void> Function() onRefresh;
  final void Function(int)? onNavigate;

  @override
  Widget build(BuildContext context) {
    return _HoverLift(
      clickable: false,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surface2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Row(children: [
                Icon(Icons.history, size: 20, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Text('Recent Trip Analytics',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ]),
              Semantics(
                  button: true,
                  label: 'View all trip logs',
                  child: TextButton(
                    onPressed: () {
                      onNavigate?.call(1);
                    },
                    child: const Text('View All Logs',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary)),
                  )),
            ]),
            const SizedBox(height: 16),
            // Column headers
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                  color: AppColors.surface0,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Expanded(flex: 3, child: _headerCell('SESSION')),
                Expanded(flex: 2, child: _headerCell('DURATION')),
                Expanded(flex: 2, child: _headerCell('AVG ATTENTION')),
                Expanded(
                    flex: 2,
                    child: _headerCell('SAFETY', align: TextAlign.end)),
              ]),
            ),
            const SizedBox(height: 4),
            if (tripHistory.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No trip history yet — start a session to see data here.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ),
              )
            else
              ...tripHistory.take(5).map((trip) {
                final dur = trip['duration_s'] as double? ?? 0;
                final durMin = (dur / 60).floor();
                final durSec = (dur % 60).floor();
                final avgAtt =
                    (trip['avg_attention'] as num?)?.toDouble() ?? 100.0;
                final score = safetyScoreFrom(trip);
                final sid = trip['session_id'] as String? ?? 'unknown';
                final shortSid = sid.length > 8 ? sid.substring(0, 8) : sid;
                final scoreColor = score == null
                    ? AppColors.textMuted
                    : switch (gradeSafetyScore(score).band) {
                        SafetyBand.good => AppColors.focusedGreen,
                        SafetyBand.fair => AppColors.alertAmber,
                        SafetyBand.poor => AppColors.alertRed,
                      };
                final scoreText = score == null ? '—/100' : '${score.round()}/100';
                return _TripRow(
                  route: shortSid,
                  duration: '${durMin}m ${durSec}s',
                  score: scoreText,
                  scoreColor: scoreColor,
                  attention: '${avgAtt.toStringAsFixed(0)}/100',
                  onTap: () => onNavigate?.call(1),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text, {TextAlign align = TextAlign.left}) {
    return Text(text,
        textAlign: align,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.textSecondary));
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow(
      {required this.route,
      required this.duration,
      required this.score,
      required this.scoreColor,
      required this.attention,
      this.onTap});
  final String route, duration, score, attention;
  final Color scoreColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Navigates to Trip Analytics or displays trip detail when selected
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(children: [
        Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(route,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                      color: AppColors.textPrimary)),
            ])),
        Expanded(
            flex: 2,
            child: Text(duration,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary))),
        Expanded(
            flex: 2,
            child: Text(attention,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary))),
        Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(score,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scoreColor)),
              ),
            )),
      ]),
    );
    if (onTap != null) {
      return Semantics(
          button: true,
          label: 'View trip $route details',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              hoverColor: AppColors.surface2.withValues(alpha: 0.5),
              onTap: onTap,
              child: content,
            ),
          ));
    }
    // Non-interactive fallback: no InkWell affordance
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(children: [
          Expanded(
              flex: 3,
              child: Text(route,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                      color: AppColors.textPrimary))),
          Expanded(
              flex: 2,
              child: Text(duration,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textSecondary))),
          Expanded(
              flex: 2,
              child: Text(attention,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textSecondary))),
          Expanded(
              flex: 2,
              child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: scoreColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(score,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scoreColor))))),
        ]));
  }
}

// ─── Global Calibration Card ────────────────────────────────────────────────

class _GlobalCalibrationCard extends StatelessWidget {
  const _GlobalCalibrationCard({required this.client, this.onNavigate});
  final MonitoringClient client;
  final void Function(int)? onNavigate;

  @override
  Widget build(BuildContext context) {
    // Bind bars to live monitoring snapshot
    return ListenableBuilder(
      listenable: client,
      builder: (context, _) {
        final snap = client.snapshot;
        // Derive sensitivity from attention & alert state (live).
        final att = snap.attention.clamp(0, 100) / 100;
        final isHigh = att > 0.7 && snap.alert == null;
        final drowsinessPct = att;
        final distractionActive = !snap.lookingAway && !snap.headDown;
        return _HoverLift(
          clickable: false,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surface2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.tune,
                            size: 20, color: AppColors.textSecondary),
                        SizedBox(width: 8),
                        Text('Global Calibration',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ])),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(
                            snap.poseValid ? 'CALIBRATED' : 'DEFAULT PROFILE',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: AppColors.textSecondary)),
                      ),
                    ]),
                const SizedBox(height: 24),
                _calibrationBar(
                    'DROWSINESS SENSITIVITY',
                    isHigh
                        ? 'High'
                        : snap.alert != null
                            ? 'Alert'
                            : 'Medium',
                    drowsinessPct,
                    const Color(0xFF22d3ee)),
                const SizedBox(height: 20),
                _calibrationBar(
                    'DISTRACTION ALERTS',
                    distractionActive ? 'Active' : 'Triggered',
                    distractionActive ? 1.0 : 0.4,
                    AppColors.focusedGreen),
                const SizedBox(height: 24),
                const Divider(color: AppColors.textMuted, height: 1),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: AppColors.surface2,
                              shape: BoxShape.circle),
                          child: const Icon(Icons.camera_front,
                              size: 20, color: AppColors.textSecondary)),
                      const SizedBox(width: 12),
                      const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Camera Alignment',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary)),
                            Text('Auto-calibrated',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ]),
                    ]),
                    Semantics(
                        button: true,
                        label: 'Verify calibration settings',
                        child: TextButton(
                          onPressed: () {
                            onNavigate?.call(2);
                          },
                          child: const Text('Verify'),
                        )),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _calibrationBar(String label, String value, double pct, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppColors.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: AppColors.surface2,
            color: color),
      ),
    ]);
  }
}

// ─── Shared Hover Lift Widget ───────────────────────────────────────────────

class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.child, this.clickable = true});
  final Widget child;
  final bool clickable;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: widget.clickable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
            0, _hovering && widget.clickable ? -2 : 0, 0),
        transformAlignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}
