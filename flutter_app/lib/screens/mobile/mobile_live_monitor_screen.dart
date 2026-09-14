import 'package:flutter/material.dart';

import '../../models/monitoring_snapshot.dart';
import '../../services/monitoring_client.dart';
import '../../theme.dart';
import '../../utils/gauge_math.dart';
import '../../utils/safety_grading.dart';
import '../../widgets/mjpeg_view.dart';

/// Mobile-optimised live monitoring screen matching the Stitch mockup.
///
/// Shows the live camera feed, circular attention gauge, head pose vectors,
/// session stats, and stop button.
class MobileLiveMonitorScreen extends StatefulWidget {
  const MobileLiveMonitorScreen({super.key, required this.client});

  final MonitoringClient client;

  @override
  State<MobileLiveMonitorScreen> createState() =>
      _MobileLiveMonitorScreenState();
}

class _MobileLiveMonitorScreenState extends State<MobileLiveMonitorScreen> {
  bool _stopping = false;

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

  /// Elapsed session time from the live snapshot's tripStartedAt (unix
  /// seconds), interpreted the same way as the desktop's trip timer.
  String _formatDuration(MonitoringSnapshot snap) {
    final started = snap.tripStartedAt;
    if (started == null || started <= 0) return '00:00:00';
    final start =
        DateTime.fromMillisecondsSinceEpoch((started * 1000).toInt());
    final diff = DateTime.now().difference(start);
    if (diff.isNegative) return '00:00:00';
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
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
          Container(
            width: 320,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Stitch.container,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Stitch.containerHighest),
            ),
            child: Column(
              children: [
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.sensors,
                      size: 16,
                      color:
                          Stitch.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'STANDING BY',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w500,
                        color: Stitch.onSurfaceVariant
                            .withValues(alpha: 0.5),
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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Status banner
            _buildStatusBanner(snap),
            const SizedBox(height: 16),
            // Live camera feed
            _buildCameraFeed(snap),
            const SizedBox(height: 16),
            // Main attention gauge
            _buildAttentionGauge(snap),
            const SizedBox(height: 16),
            // Head pose vectors
            _buildHeadPoseSection(snap),
            const SizedBox(height: 16),
            // Session stats grid
            _buildSessionStats(snap),
            const SizedBox(height: 16),
            // Stop button
            _buildStopButton(),
          ],
        ),
      ),
    );
  }

  // ── Status Banner ────────────────────────────────────────────────────────

  Widget _buildStatusBanner(MonitoringSnapshot snap) {
    final sev = snap.alertSeverity;
    Color color;
    String label;

    if (sev >= 3) {
      // Severity 3+ means the alarm is sounding — same red as the grade.
      color = Stitch.error;
      label = snap.alert ?? 'CRITICAL';
    } else if (sev >= 2) {
      color = Stitch.tertiaryFixedDim;
      label = snap.alert ?? 'DISTRACTED';
    } else {
      color = Stitch.secondary;
      label = 'All Clear - Safe Driving';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.8),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Live Camera Feed ─────────────────────────────────────────────────────

  Widget _buildCameraFeed(MonitoringSnapshot snap) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MjpegView(client: widget.client),
            Positioned(
              left: 12,
              top: 12,
              child: _FeedBadge(
                icon: snap.faceFound ? Icons.person : Icons.person_off,
                label: snap.faceFound ? 'DRIVER DETECTED' : 'NO FACE',
                color: snap.faceFound ? Stitch.secondary : Stitch.tertiaryFixedDim,
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: _FeedBadge(
                icon: Icons.circle,
                label: 'LIVE',
                color: Stitch.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Attention Gauge (SVG-style) ──────────────────────────────────────────

  Widget _buildAttentionGauge(MonitoringSnapshot snap) {
    final score = snap.attention.round();
    final progress = snap.attention / 100;
    // Same 80/60 band colors as the post-trip grade — one color language.
    final scoreColor = gradeSafetyScore(snap.attention).color;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _GaugePainter(
                progress: progress,
                trackColor: Stitch.containerHighest,
                fillColor: scoreColor,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SYS_SCORE',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w600,
                        color: scoreColor.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$score',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: Stitch.onSurface,
                            height: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '%',
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'JetBrains Mono',
                              fontWeight: FontWeight.w700,
                              color: scoreColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Head Pose Section ────────────────────────────────────────────────────

  Widget _buildHeadPoseSection(MonitoringSnapshot snap) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.sensors,
                      size: 16, color: Stitch.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'HEAD POSE VECTORS',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w500,
                      color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Stitch.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _PoseBar(
            label: 'PITCH',
            symbol: 'θ',
            value: snap.pitch,
            color: Stitch.primary,
          ),
          const SizedBox(height: 16),
          _PoseBar(
            label: 'YAW',
            symbol: 'ψ',
            value: snap.yaw,
            color: Stitch.secondary,
          ),
          const SizedBox(height: 16),
          _PoseBar(
            label: 'ROLL',
            symbol: 'φ',
            value: snap.roll,
            color: Stitch.primary,
          ),
        ],
      ),
    );
  }

  // ── Session Stats Grid ───────────────────────────────────────────────────

  Widget _buildSessionStats(MonitoringSnapshot snap) {
    return Row(
      children: [
        Expanded(
          child: _StatBlock(
            label: 'SESSION T+',
            value: _formatDuration(snap),
            showCursor: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatBlock(
            label: 'SENSOR FPS',
            value: snap.fps.toStringAsFixed(1),
          ),
        ),
      ],
    );
  }

  // ── Stop Button ──────────────────────────────────────────────────────────

  Widget _buildStopButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _stopping
            ? null
            : () async {
                setState(() => _stopping = true);
                try {
                  await widget.client.sendCommand('/api/v1/session/stop');
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Stop failed: $e'),
                        backgroundColor: Stitch.error,
                      ),
                    );
                  }
                }
                if (mounted) setState(() => _stopping = false);
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: Stitch.error,
          foregroundColor: Stitch.onError,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          shadowColor: Stitch.error.withValues(alpha: 0.3),
        ),
        child: _stopping
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Stitch.onError),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.stop_circle, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'STOP SESSION',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Gauge Painter ───────────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  final double progress;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;

    // Track (dashed circle)
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    // Draw dashed circle
    const dashCount = 60;
    const gapAngle = 0.04;
    for (int i = 0; i < dashCount; i++) {
      final angle = (i / dashCount) * 3.14159 * 2;
      final startAngle = angle;
      final sweepAngle = (3.14159 * 2 / dashCount) - gapAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        trackPaint,
      );
    }

    // Fill arc
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.butt;

    // Glow effect
    final glowPaint = Paint()
      ..color = fillColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.butt
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // Full-circle sweep from 12 o'clock; clamped so the arc can never
    // over-draw (the old formula shifted every value by a quarter turn).
    final sweepAngle = gaugeSweepRadians(progress);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      gaugeStartAngle,
      sweepAngle,
      false,
      glowPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      gaugeStartAngle,
      sweepAngle,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.fillColor != fillColor;
  }
}

// ─── Pose Bar ───────────────────────────────────────────────────────────────

class _PoseBar extends StatelessWidget {
  const _PoseBar({
    required this.label,
    required this.symbol,
    required this.value,
    required this.color,
  });

  final String label;
  final String symbol;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Map value to 0-100% for the bar width
    final barPercent = ((value.abs() / 30.0) * 100).clamp(10.0, 100.0);
    final sign = value >= 0 ? '+' : '';
    final display = '$sign${value.toStringAsFixed(1)}°';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$label ($symbol)',
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w500,
                color: Stitch.onSurfaceVariant,
              ),
            ),
            Text(
              display,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 8,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Stitch.containerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: barPercent / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Stat Block ─────────────────────────────────────────────────────────────

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    this.showCursor = false,
  });

  final String label;
  final String value;
  final bool showCursor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w500,
              color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w600,
                  color: Stitch.onSurface,
                ),
              ),
              if (showCursor)
                Text(
                  '_',
                  style: TextStyle(
                    fontSize: 20,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w600,
                    color: Stitch.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeedBadge extends StatelessWidget {
  const _FeedBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
