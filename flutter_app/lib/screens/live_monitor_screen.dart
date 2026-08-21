import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/monitoring_snapshot.dart';
import '../services/monitoring_client.dart';
import '../theme.dart';

class LiveMonitorScreen extends StatefulWidget {
  const LiveMonitorScreen(
      {super.key, required this.client, this.sessionStartTime});
  final MonitoringClient client;
  final DateTime? sessionStartTime;

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  bool _fullscreenHud = false;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onClientUpdate);
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClientUpdate);
    super.dispose();
  }

  void _onClientUpdate() {
    // Single rebuild path: ValueNotifier latestFrameBytes already drives
    // MjpegView, so we only rebuild telemetry. Use post-frame to avoid
    // setState during build, but avoid double rebuild by not also using
    // ListenableBuilder elsewhere for same client (see TelemetryColumn).
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  String get _sessionElapsed {
    final startTime = widget.sessionStartTime;
    if (startTime == null) return '00:00';
    final diff = DateTime.now().difference(startTime);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (h > 0)
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.client.snapshot;

    if (_fullscreenHud) {
      return _FullscreenHud(
          snap: snap,
          client: widget.client,
          onExit: () => setState(() => _fullscreenHud = false));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (snap.alert != null) _AnimatedAlertBanner(snap: snap),
              if (snap.alert != null) const SizedBox(height: 16),
              if (isNarrow)
                Column(
                  children: [
                    _VideoSection(
                        client: widget.client,
                        snap: snap,
                        onFullscreen: () =>
                            setState(() => _fullscreenHud = true),
                        sessionElapsed: _sessionElapsed),
                    const SizedBox(height: 24),
                    _TelemetryColumn(snap: snap),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 7,
                        child: _VideoSection(
                            client: widget.client,
                            snap: snap,
                            onFullscreen: () =>
                                setState(() => _fullscreenHud = true),
                            sessionElapsed: _sessionElapsed)),
                    const SizedBox(width: 24),
                    Expanded(flex: 5, child: _TelemetryColumn(snap: snap)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Animated Alert Banner ──────────────────────────────────────────────────

class _AnimatedAlertBanner extends StatelessWidget {
  const _AnimatedAlertBanner({required this.snap});
  final MonitoringSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.severity(snap.alertSeverity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 16)
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(Icons.warning_rounded, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(snap.alert!.toUpperCase(),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(
                    'Severity: ${snap.alertSeverity} | Confidence: ${(snap.emaDrowsy * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.3))),
            child: Text('SEV ${snap.alertSeverity}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}

// ─── Fullscreen HUD ─────────────────────────────────────────────────────────

class _FullscreenHud extends StatelessWidget {
  const _FullscreenHud(
      {required this.snap, required this.client, required this.onExit});
  final MonitoringSnapshot snap;
  final MonitoringClient client;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _MjpegView(client: client)),
        Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('IR-DMS LIVE',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(
                        '${snap.fps.toStringAsFixed(0)} fps | ${snap.attention.toStringAsFixed(0)}% attention',
                        style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.white54)),
                  ]),
            )),
        Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent])),
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _hudMetric(
                            'EAR',
                            snap.ear != null
                                ? snap.ear!.toStringAsFixed(2)
                                : '--'),
                        _hudMetric('PERCLOS', snap.perclos.toStringAsFixed(2)),
                        _hudMetric(
                            'PITCH', '${snap.pitch.toStringAsFixed(1)}\u00B0'),
                        _hudMetric(
                            'YAW', '${snap.yaw.toStringAsFixed(1)}\u00B0'),
                        _hudMetric(
                            'ROLL', '${snap.roll.toStringAsFixed(1)}\u00B0'),
                        _hudMetric('STATUS', snap.alert ?? snap.status),
                      ])),
            )),
        Positioned(
            top: 16,
            right: 16,
            child: Tooltip(
              message: 'Exit fullscreen HUD',
              child: IconButton(
                onPressed: onExit,
                icon: const Icon(Icons.fullscreen_exit,
                    color: Colors.white70, size: 28),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    shape: const CircleBorder()),
              ),
            )),
      ],
    );
  }

  Widget _hudMetric(String label, String value) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Colors.white54)),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: Colors.white)),
    ]);
  }
}

// ─── Video Section with Face Tracking + Session Timer ───────────────────────

class _VideoSection extends StatelessWidget {
  const _VideoSection(
      {required this.client,
      required this.snap,
      required this.onFullscreen,
      required this.sessionElapsed});
  final MonitoringClient client;
  final MonitoringSnapshot snap;
  final VoidCallback onFullscreen;
  final String sessionElapsed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with session timer — responsive: Wrap on narrow, Row on wide
        LayoutBuilder(builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 650;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.fiber_manual_record,
                      color: AppColors.focusedGreen, size: 16),
                  const SizedBox(width: 8),
                  const Text('Live Camera Feed',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x33444748))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.timer_outlined,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(sessionElapsed,
                          style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    if (snap.microsleep) ...[
                      _LiveBadge(
                          label: 'MICROSLEEP',
                          color: AppColors.alertRed,
                          icon: Icons.bedtime_outlined),
                      const SizedBox(width: 8),
                    ],
                    _ActionButton(
                        icon: snap.alarmMuted
                            ? Icons.volume_up
                            : Icons.volume_off,
                        label: snap.alarmMuted ? 'Unmute' : 'Mute',
                        onTap: () => client.sendCommand(snap.alarmMuted
                            ? '/api/v1/alarm/unmute'
                            : '/api/v1/alarm/mute')),
                    const SizedBox(width: 8),
                    _ActionButton(
                        icon: Icons.tune,
                        label: 'Calibrate',
                        onTap: () => client.sendCommand(
                            '/api/v1/calibration/start', {'duration': 4})),
                    const SizedBox(width: 8),
                    _ActionButton(
                        icon: Icons.fullscreen,
                        label: 'HUD',
                        onTap: onFullscreen),
                  ]),
                ),
              ],
            );
          }
          return Row(
            children: [
              Icon(Icons.fiber_manual_record,
                  color: AppColors.focusedGreen, size: 16),
              const SizedBox(width: 8),
              const Text('Live Camera Feed',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x33444748))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(sessionElapsed,
                      style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ]),
              ),
              const SizedBox(width: 8),
              if (snap.microsleep)
                _LiveBadge(
                    label: 'MICROSLEEP',
                    color: AppColors.alertRed,
                    icon: Icons.bedtime_outlined),
              const SizedBox(width: 8),
              _ActionButton(
                  icon: snap.alarmMuted ? Icons.volume_up : Icons.volume_off,
                  label: snap.alarmMuted ? 'Unmute' : 'Mute',
                  onTap: () => client.sendCommand(snap.alarmMuted
                      ? '/api/v1/alarm/unmute'
                      : '/api/v1/alarm/mute')),
              const SizedBox(width: 8),
              _ActionButton(
                  icon: Icons.tune,
                  label: 'Calibrate',
                  onTap: () => client.sendCommand(
                      '/api/v1/calibration/start', {'duration': 4})),
              const SizedBox(width: 8),
              _ActionButton(
                  icon: Icons.fullscreen, label: 'HUD', onTap: onFullscreen),
            ],
          );
        }),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _MjpegView(client: client),
                Positioned(
                    left: 12,
                    top: 12,
                    child: _Badge(
                        icon: snap.faceFound ? Icons.person : Icons.person_off,
                        label: snap.faceFound ? 'Driver detected' : 'No face',
                        color: snap.faceFound
                            ? AppColors.focusedGreen
                            : AppColors.alertOrange)),
                Positioned(
                    right: 12,
                    bottom: 12,
                    child: _Badge(
                        icon: Icons.speed,
                        label: '${snap.fps.toStringAsFixed(0)} fps',
                        color: AppColors.textMuted)),
                Positioned(
                    left: 12,
                    bottom: 12,
                    child: _Badge(
                        icon: Icons.access_time,
                        label: 'IR-DMS',
                        color: Colors.white54)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Live Badge (for microsleep etc.) ───────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  const _LiveBadge(
      {required this.label, required this.color, required this.icon});
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: color)),
      ]),
    );
  }
}

// ─── Telemetry Column (expanded with blink rate, yawn) ──────────────────────

class _TelemetryColumn extends StatelessWidget {
  const _TelemetryColumn({required this.snap});
  final MonitoringSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.severity(snap.alertSeverity);
    return Column(
      children: [
        // Attention Index
        Card(
            child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('ATTENTION INDEX',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppColors.textSecondary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.3))),
                child: Text(
                    snap.focused
                        ? 'OPTIMAL'
                        : snap.alert != null
                            ? 'WARNING'
                            : 'MONITORING',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ]),
            const SizedBox(height: 16),
            _AttentionGauge(value: snap.attention, color: color),
            const SizedBox(height: 12),
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: (snap.attention / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.surface2,
                    color: color)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _MiniStat(
                      label: 'FATIGUE LVL',
                      value: snap.emaDrowsy < 0.3
                          ? 'LOW'
                          : snap.emaDrowsy < 0.6
                              ? 'MED'
                              : 'HIGH',
                      color: snap.emaDrowsy < 0.3
                          ? AppColors.focusedGreen
                          : snap.emaDrowsy < 0.6
                              ? AppColors.alertAmber
                              : AppColors.alertRed)),
              const SizedBox(width: 8),
              Expanded(
                  child: _MiniStat(
                      label: 'DISTRACTION',
                      value: snap.lookingAway ? 'YES' : 'NO',
                      color: snap.lookingAway
                          ? AppColors.alertAmber
                          : AppColors.focusedGreen)),
            ]),
          ]),
        )),
        const SizedBox(height: 16),
        // Live Metrics (expanded from just Eye Metrics)
        Card(
            child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('LIVE METRICS',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            _MetricWithBar(
                label: 'PERCLOS',
                value: snap.perclos.toStringAsFixed(2),
                pct: snap.perclos.clamp(0, 1),
                color: snap.perclos > 0.5
                    ? AppColors.alertRed
                    : AppColors.focusedGreen),
            const SizedBox(height: 12),
            _MetricWithBar(
                label: 'Blink Rate',
                value: '${snap.blinksPerMin.toStringAsFixed(0)} bpm',
                pct: (snap.blinksPerMin / 30).clamp(0.0, 1.0),
                color: AppColors.focusedGreen),
            const SizedBox(height: 12),
            _MetricWithBar(
                label: 'EAR',
                value: snap.ear != null ? snap.ear!.toStringAsFixed(2) : '--',
                pct: snap.ear != null ? (snap.ear! / 0.4).clamp(0.0, 1.0) : 0,
                color: snap.ear != null && snap.ear! < 0.2
                    ? AppColors.alertRed
                    : AppColors.focusedGreen),
          ]),
        )),
        const SizedBox(height: 16),
        // Head Pose
        Card(
            child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('HEAD POSE EULER ANGLES',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: AppColors.textSecondary)),
                  Icon(Icons.threed_rotation,
                      size: 16, color: AppColors.textSecondary),
                ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: _PoseTile(
                      label: 'PITCH',
                      value: '${snap.pitch.toStringAsFixed(1)}\u00B0',
                      nominal: snap.poseValid && !snap.headDown)),
              const SizedBox(width: 8),
              Expanded(
                  child: _PoseTile(
                      label: 'YAW',
                      value: '${snap.yaw.toStringAsFixed(1)}\u00B0',
                      nominal: snap.poseValid && !snap.lookingAway)),
              const SizedBox(width: 8),
              Expanded(
                  child: _PoseTile(
                      label: 'ROLL',
                      value: '${snap.roll.toStringAsFixed(1)}\u00B0',
                      nominal: snap.poseValid && !snap.headTilt)),
            ]),
            const SizedBox(height: 12),
            _HeadPoseBar(pitch: snap.pitch, yaw: snap.yaw, roll: snap.roll),
          ]),
        )),
      ],
    );
  }
}

// ─── Metric with progress bar ───────────────────────────────────────────────

class _MetricWithBar extends StatelessWidget {
  const _MetricWithBar(
      {required this.label,
      required this.value,
      required this.pct,
      required this.color});
  final String label, value;
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: AppColors.textPrimary)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppColors.surface2,
              color: color)),
    ]);
  }
}

// ─── Mini Stat ──────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: AppColors.surface0,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x33444748))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ─── Head Pose Bar Visualization ────────────────────────────────────────────

class _HeadPoseBar extends StatelessWidget {
  const _HeadPoseBar(
      {required this.pitch, required this.yaw, required this.roll});
  final double pitch, yaw, roll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.surface0,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x33444748))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _barColumn('Pitch', pitch.abs(), 30),
        _barColumn('Yaw', yaw.abs(), 40),
        _barColumn('Roll', roll.abs(), 20),
      ]),
    );
  }

  Widget _barColumn(String label, double value, double max) {
    final pct = (value / max).clamp(0.0, 1.0);
    final barColor = pct > 0.7 ? AppColors.alertAmber : AppColors.focusedGreen;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      SizedBox(
          width: 6,
          height: 24,
          child: Stack(children: [
            Container(
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(3))),
            Positioned(
                bottom: 0,
                child: Container(
                    width: 6,
                    height: 24 * pct,
                    decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(3)))),
          ])),
    ]);
  }
}

// ─── Attention Gauge ────────────────────────────────────────────────────────

class _AttentionGauge extends StatelessWidget {
  const _AttentionGauge({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: 200,
        height: 110,
        child: CustomPaint(
          painter: _GaugePainter(value: value, color: color),
          child: Center(
              child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(value.toStringAsFixed(0),
                  style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1.0)),
              const SizedBox(height: 2),
              const Text('ATTENTION',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600)),
            ]),
          )),
        ));
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 2);
    final radius = size.width / 2 - 16;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = AppColors.gaugeTrack
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawArc(rect, math.pi, math.pi, false, track);
    final sweep = math.pi * (value.clamp(0.0, 100.0) / 100);
    if (sweep > 0) {
      canvas.drawArc(rect, math.pi, sweep, false, glow);
      canvas.drawArc(rect, math.pi, sweep, false, fill);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}

// ─── Metric / Pose Tiles ────────────────────────────────────────────────────

class _PoseTile extends StatelessWidget {
  const _PoseTile(
      {required this.label, required this.value, required this.nominal});
  final String label, value;
  final bool nominal;

  @override
  Widget build(BuildContext context) {
    final color = nominal ? AppColors.focusedGreen : AppColors.alertAmber;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.surface0,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x33444748))),
      child: Column(children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(nominal ? 'NOMINAL' : 'ALERT',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ─── Shared Widgets ─────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ]))));
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step)
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    for (double y = 0; y < size.height; y += step)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── MJPEG View ────────────────────────────────────────────────────────────

class _MjpegView extends StatefulWidget {
  const _MjpegView({required this.client});
  final MonitoringClient client;
  @override
  State<_MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<_MjpegView> {
  ui.Image? _frame;
  bool _decoding = false;
  Uint8List? _pendingBytes;
  DateTime _lastDecodeTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Minimum interval between decodes to prevent CPU thrashing
  static const _minDecodeInterval = Duration(milliseconds: 30);

  @override
  void initState() {
    super.initState();
    widget.client.latestFrameBytes.addListener(_onFrame);
    final existing = widget.client.latestFrameBytes.value;
    if (existing != null) _onFrame();
  }

  @override
  void didUpdateWidget(_MjpegView old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) {
      old.client.latestFrameBytes.removeListener(_onFrame);
      widget.client.latestFrameBytes.addListener(_onFrame);
    }
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    widget.client.latestFrameBytes.removeListener(_onFrame);
    _frame?.dispose();
    _decoding = false;
    super.dispose();
  }

  void _onFrame() {
    final bytes = widget.client.latestFrameBytes.value;
    if (bytes == null) return;
    if (_decoding) {
      // A decode is in progress — keep only the latest frame, discard stale ones
      _pendingBytes = bytes;
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastDecodeTime) < _minDecodeInterval &&
        _frame != null) {
      // Too soon after last decode and we already have a frame — queue it
      _pendingBytes = bytes;
      _schedulePendingDecode();
      return;
    }
    _decode(bytes);
  }

  Timer? _pendingTimer;
  void _schedulePendingDecode() {
    if (_pendingTimer != null) return;
    _pendingTimer = Timer(_minDecodeInterval, () {
      _pendingTimer = null;
      if (!mounted) return;
      final pending = _pendingBytes;
      if (pending != null && !_decoding) {
        _pendingBytes = null;
        _decode(pending);
      }
    });
  }

  void _decode(Uint8List bytes) {
    _decoding = true;
    _lastDecodeTime = DateTime.now();
    ui.instantiateImageCodec(bytes).then((codec) {
      if (!mounted || !_decoding) {
        codec.dispose();
        return;
      }
      codec.getNextFrame().then((info) {
        if (!mounted || !_decoding) {
          info.image.dispose();
          codec.dispose();
          return;
        }
        codec.dispose();
        final oldFrame = _frame;
        _frame = info.image;
        _decoding = false;
        setState(() {});
        oldFrame?.dispose();
        // If new frames arrived while we were decoding, process the latest
        final pending = _pendingBytes;
        if (pending != null) {
          _pendingBytes = null;
          _decode(pending);
        }
      });
    }).catchError((_) {
      _decoding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null) {
      return ColoredBox(
          color: AppColors.surface0, child: const _CameraLoadingPlaceholder());
    }
    return RawImage(
        image: frame, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
  }
}

// ─── Camera Loading Placeholder with Scanning Animation ────────────────────

class _CameraLoadingPlaceholder extends StatelessWidget {
  const _CameraLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(size: Size.infinite, painter: _GridPainter()),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x33444748))),
              child: const Icon(Icons.videocam_outlined,
                  size: 24, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          const Text('Connecting to camera...',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                  backgroundColor: AppColors.surface2,
                  color: AppColors.focusedGreen.withValues(alpha: 0.5),
                  minHeight: 2)),
        ]),
      ],
    );
  }
}
