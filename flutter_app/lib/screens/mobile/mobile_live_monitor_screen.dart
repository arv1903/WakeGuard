import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/monitoring_snapshot.dart';
import '../../services/monitoring_client.dart';
import '../../theme.dart';

/// Mobile-optimised live monitoring screen.
///
/// Shows camera feed, status banner, metric cards, and alert history —
/// matching the Stitch "Live Monitor" mockup with vertical layout.
class MobileLiveMonitorScreen extends StatefulWidget {
  const MobileLiveMonitorScreen({
    super.key,
    required this.client,
    this.sessionStartTime,
  });

  final MonitoringClient client;
  final DateTime? sessionStartTime;

  @override
  State<MobileLiveMonitorScreen> createState() =>
      _MobileLiveMonitorScreenState();
}

class _MobileLiveMonitorScreenState extends State<MobileLiveMonitorScreen> {
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onUpdate);
  }

  @override
  void dispose() {
    widget.client.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.client.snapshot;
    final tripActive = snap.tripActive;

    if (!tripActive) return _buildIdleState();

    return _buildActiveState(snap);
  }

  // ── Idle state ───────────────────────────────────────────────────────────

  Widget _buildIdleState() {
    return Container(
      color: Stitch.background,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Connected badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Stitch.containerHigh,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Stitch.containerHighest),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Stitch.secondary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Stitch.secondary.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'SYSTEM CONNECTED',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    color: Stitch.secondary,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Card
          Container(
            width: 320,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Stitch.container,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Stitch.containerHighest),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Column(
              children: [
                // Shield icon in circle
                Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    color: Stitch.surfaceLow,
                    shape: BoxShape.circle,
                    border: Border.all(color: Stitch.containerHighest),
                  ),
                  child: Icon(
                    Icons.local_police,
                    size: 64,
                    color: Stitch.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'No Active Session',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Stitch.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Waiting for driver to initiate safety monitoring...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Stitch.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Divider
                Container(
                  height: 1,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Stitch.containerHighest,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Standing by
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.sensors,
                      size: 16,
                      color: Stitch.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'STANDING BY',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w500,
                        color:
                            Stitch.onSurfaceVariant.withValues(alpha: 0.5),
                        letterSpacing: 2,
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

  // ── Active state ─────────────────────────────────────────────────────────

  Widget _buildActiveState(MonitoringSnapshot snap) {
    return Container(
      color: Stitch.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          children: [
            // Camera feed
            _buildCameraFeed(),
            // Status banner
            _buildStatusBanner(snap),
            // Metric cards grid
            _buildMetricGrid(snap),
            // Alert history
            _buildAlertHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraFeed() {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: widget.client.latestFrameBytes,
      builder: (_, bytes, __) {
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
          width: double.infinity,
          color: Colors.black,
          child: bytes != null
              ? Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  opacity: const AlwaysStoppedAnimation(0.85),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Stitch.primary.withValues(alpha: 0.2),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        size: 32,
                        color: Stitch.primary,
                      ),
                    ),
                    // REC badge
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Stitch.containerHighest.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Stitch.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'REC',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'JetBrains Mono',
                                fontWeight: FontWeight.w500,
                                color: Stitch.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Camera label
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Stitch.containerHighest.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'IR_CAM_01',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'JetBrains Mono',
                            fontWeight: FontWeight.w500,
                            color: Stitch.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBanner(MonitoringSnapshot snap) {
    final sev = snap.alertSeverity;
    Color bgColor;
    Color fgColor;
    String label;
    String subtitle;

    if (sev >= 4) {
      bgColor = Stitch.errorContainer;
      fgColor = Stitch.onErrorContainer;
      label = 'CRITICAL';
      subtitle = 'Immediate attention required';
    } else if (sev >= 3) {
      bgColor = Stitch.tertiaryContainer.withValues(alpha: 0.3);
      fgColor = Stitch.tertiary;
      label = 'DROWSY';
      subtitle = 'Driver showing fatigue signs';
    } else if (sev >= 2) {
      bgColor = Stitch.tertiary.withValues(alpha: 0.15);
      fgColor = Stitch.tertiary;
      label = 'DISTRACTED';
      subtitle = 'Head pose deviation detected';
    } else if (snap.focused) {
      bgColor = Stitch.secondaryContainer;
      fgColor = Stitch.onSecondaryContainer;
      label = 'FOCUSED';
      subtitle = 'Wakefulness optimal';
    } else if (snap.unfocused) {
      bgColor = Stitch.tertiaryContainer.withValues(alpha: 0.2);
      fgColor = Stitch.tertiary;
      label = 'UNFOCUSED';
      subtitle = 'Attention below threshold';
    } else if (snap.faceLost) {
      bgColor = Stitch.containerHighest;
      fgColor = Stitch.onSurfaceVariant;
      label = 'FACE LOST';
      subtitle = 'Driver not detected';
    } else {
      bgColor = Stitch.secondaryContainer;
      fgColor = Stitch.onSecondaryContainer;
      label = 'MONITORING';
      subtitle = 'System active';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    color: fgColor.withValues(alpha: 0.7),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                  ),
                ),
              ],
            ),
          ),
          // Circular attention gauge
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: snap.attention / 100,
                  strokeWidth: 5,
                  backgroundColor: fgColor.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(fgColor),
                ),
                Text(
                  '${snap.attention.round()}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    color: fgColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid(MonitoringSnapshot snap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.psychology,
                  label: 'Attention',
                  value: '${snap.attention.round()}%',
                  color: Stitch.secondary,
                  barValue: snap.attention / 100,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  icon: Icons.visibility_off,
                  label: 'PERCLOS',
                  value: '${(snap.perclos * 100).round()}%',
                  color: snap.perclos > 0.5 ? Stitch.error : Stitch.primary,
                  barValue: snap.perclos,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.remove_red_eye,
                  label: 'EAR',
                  value: snap.ear != null
                      ? snap.ear!.toStringAsFixed(2)
                      : '—',
                  color: Stitch.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  icon: Icons.speed,
                  label: 'Blinks/Min',
                  value: '${snap.blinksPerMin.round()}',
                  color: Stitch.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.swap_vert,
                  label: 'Head Pitch',
                  value: '${snap.pitch.round()}°',
                  color: Stitch.tertiaryFixedDim,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  icon: Icons.swap_horiz,
                  label: 'Head Yaw',
                  value: '${snap.yaw.round()}°',
                  color: Stitch.tertiaryContainer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertHistory() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Alert History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Stitch.onSurface,
                ),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.filter_list, size: 16),
                label: const Text(
                  'FILTER',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Stitch.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Sample alerts (would be wired to real alert history)
          _AlertItem(
            icon: Icons.warning,
            bgColor: Stitch.errorContainer,
            fgColor: Stitch.onErrorContainer,
            title: 'Microsleep Detected',
            subtitle: 'PERCLOS spike > 15%',
            time: '10:42 AM',
          ),
          const SizedBox(height: 8),
          _AlertItem(
            icon: Icons.phone_in_talk,
            bgColor: Stitch.tertiaryContainer.withValues(alpha: 0.2),
            fgColor: Stitch.tertiary,
            title: 'Distraction: Device',
            subtitle: 'Head yaw deviation',
            time: '09:15 AM',
          ),
          const SizedBox(height: 8),
          _AlertItem(
            icon: Icons.info,
            bgColor: Stitch.containerHighest,
            fgColor: Stitch.onSurfaceVariant,
            title: 'Session Started',
            subtitle: 'Calibration successful',
            time: '08:00 AM',
            dimmed: true,
          ),
        ],
      ),
    );
  }
}

// ─── Metric Card ─────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.barValue,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double? barValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: Stitch.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w500,
                          color: Stitch.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (barValue != null) ...[
            const SizedBox(height: 8),
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: Stitch.containerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                widthFactor: barValue!.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Alert Item ──────────────────────────────────────────────────────────────

class _AlertItem extends StatelessWidget {
  const _AlertItem({
    required this.icon,
    required this.bgColor,
    required this.fgColor,
    required this.title,
    required this.subtitle,
    required this.time,
    this.dimmed = false,
  });

  final IconData icon;
  final Color bgColor;
  final Color fgColor;
  final String title;
  final String subtitle;
  final String time;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: fgColor, size: 22),
          ),
          const SizedBox(width: 14),
          // Text
          Expanded(
            child: Opacity(
              opacity: dimmed ? 0.7 : 1.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w500,
                      color: fgColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Stitch.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w500,
              color: Stitch.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
