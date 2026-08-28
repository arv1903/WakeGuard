import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/monitoring_client.dart';
import '../../theme.dart';

/// Full-screen post-trip summary matching the Stitch "Trip Summary" mockup.
///
/// Shows Mission Report header, grade badge, hero stats grid,
/// attention chart, and incident log.
class MobilePostTripScreen extends StatefulWidget {
  const MobilePostTripScreen({super.key, required this.client});

  final MonitoringClient client;

  @override
  State<MobilePostTripScreen> createState() => _MobilePostTripScreenState();
}

class _MobilePostTripScreenState extends State<MobilePostTripScreen> {
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    try {
      final summary = await widget.client.fetchCurrentSummary();
      if (mounted) setState(() { _summary = summary; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Stitch.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Stitch.primary))
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 48, color: Stitch.error.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('Unable to load summary',
              style: TextStyle(fontSize: 16, color: Stitch.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextButton(onPressed: _fetchSummary, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final s = _summary!;
    final tripDuration = s['trip_duration_s'] as num? ?? s['duration'] as num? ?? 0;
    final avgAttention = s['avg_attention'] as num? ?? s['attention_avg'] as num? ?? 0;
    final alertCount = s['alert_count'] as num? ?? 0;

    final safetyScore = ((avgAttention * 1.0 - alertCount * 3).clamp(0, 100)).toDouble();
    String grade;
    Color gradeColor;
    if (safetyScore >= 90) { grade = 'A+'; gradeColor = Stitch.secondary; }
    else if (safetyScore >= 80) { grade = 'A'; gradeColor = Stitch.secondary; }
    else if (safetyScore >= 70) { grade = 'B+'; gradeColor = Stitch.secondary; }
    else if (safetyScore >= 60) { grade = 'B'; gradeColor = Stitch.tertiaryFixedDim; }
    else if (safetyScore >= 50) { grade = 'C'; gradeColor = Stitch.tertiaryFixedDim; }
    else { grade = 'D'; gradeColor = Stitch.error; }

    final durH = (tripDuration / 3600).floor();
    final durM = ((tripDuration % 3600) / 60).floor();
    final durStr = durH > 0 ? '${durH}h ${durM}m' : '${durM}m';

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Stitch.surfaceLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Stitch.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                // Mission Report label
                Text(
                  'MISSION REPORT',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w700,
                    color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                // Grade badge
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulsing ring
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: gradeColor.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                      ),
                      // Spinning ring
                      SizedBox(
                        width: 88,
                        height: 88,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: gradeColor.withValues(alpha: 0.5),
                          strokeCap: StrokeCap.butt,
                        ),
                      ),
                      // Grade circle
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Stitch.containerHigh,
                          border: Border.all(color: gradeColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: gradeColor.withValues(alpha: 0.3),
                              blurRadius: 15,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            grade,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: gradeColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Route Complete',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Stitch.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Data synched to core.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Stitch.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Hero stats grid
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        icon: Icons.schedule,
                        label: 'TIME',
                        value: durStr,
                        color: Stitch.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HeroStat(
                        icon: Icons.visibility,
                        label: 'AVG ATTN',
                        value: '${avgAttention.round()}%',
                        color: Stitch.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        icon: Icons.notifications_active,
                        label: 'ALERTS',
                        value: '${alertCount.toInt()}',
                        color: Stitch.error,
                        showWarning: alertCount > 0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HeroStat(
                        icon: Icons.speed,
                        label: 'SCORE',
                        value: '${safetyScore.round()}',
                        color: gradeColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Attention chart
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _AttentionChart(avgAttention: avgAttention),
          ),

          // Incident log
          if (alertCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _IncidentLog(),
            ),

          // Close button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Stitch.primary,
                  foregroundColor: Stitch.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                  shadowColor: Stitch.primary.withValues(alpha: 0.2),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'CLOSE LOG',
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.done, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hero Stat Card ─────────────────────────────────────────────────────────

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.showWarning = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Stitch.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w700,
                  color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
                  letterSpacing: 1,
                ),
              ),
              if (showWarning) ...[
                const Spacer(),
                Icon(Icons.warning, size: 14, color: Stitch.error.withValues(alpha: 0.7)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Attention Chart ────────────────────────────────────────────────────────

class _AttentionChart extends StatelessWidget {
  const _AttentionChart({required this.avgAttention});

  final num avgAttention;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Stitch.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ATTENTION TELEMETRY',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w700,
                  color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                'LIVE > END',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w500,
                  color: Stitch.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: Size.infinite,
              painter: _ChartPainter(avgAttention: avgAttention.toDouble()),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0h', style: TextStyle(fontSize: 10, fontFamily: 'JetBrains Mono', color: Stitch.onSurfaceVariant)),
              Text('1h', style: TextStyle(fontSize: 10, fontFamily: 'JetBrains Mono', color: Stitch.onSurfaceVariant)),
              Text('2h', style: TextStyle(fontSize: 10, fontFamily: 'JetBrains Mono', color: Stitch.onSurfaceVariant)),
              Text('END', style: TextStyle(fontSize: 10, fontFamily: 'JetBrains Mono', color: Stitch.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.avgAttention});

  final double avgAttention;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Grid lines
    final gridPaint = Paint()
      ..color = Stitch.containerHighest.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    for (final y in [h * 0.2, h * 0.5, h * 0.8]) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Generate sample data path based on avg attention
    final points = <Offset>[];
    final rng = math.Random(42);
    for (int i = 0; i <= 30; i++) {
      final x = (i / 30) * w;
      final base = avgAttention / 100;
      final noise = (rng.nextDouble() - 0.5) * 0.3;
      final y = h - ((base + noise) * h).clamp(0.0, h);
      points.add(Offset(x, y));
    }

    // Build path
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cp1 = Offset((prev.dx + curr.dx) / 2, prev.dy);
      final cp2 = Offset((prev.dx + curr.dx) / 2, curr.dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, curr.dx, curr.dy);
    }

    // Area fill
    final areaPath = Path.from(path);
    areaPath.lineTo(w, h);
    areaPath.lineTo(0, h);
    areaPath.close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Stitch.primary.withValues(alpha: 0.4),
          Stitch.primary.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(areaPath, areaPaint);

    // Line
    final linePaint = Paint()
      ..color = Stitch.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.avgAttention != avgAttention;
  }
}

// ─── Incident Log ───────────────────────────────────────────────────────────

class _IncidentLog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'INCIDENT LOG',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w700,
            color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        _IncidentItem(
          icon: Icons.phone_in_talk,
          color: Stitch.error,
          type: 'Distraction',
          time: '14:22',
          description: 'Device usage detected in cabin.',
        ),
        const SizedBox(height: 8),
        _IncidentItem(
          icon: Icons.bedtime,
          color: Stitch.tertiaryFixedDim,
          type: 'Drowsiness',
          time: '15:05',
          description: 'Eye closure threshold exceeded.',
        ),
      ],
    );
  }
}

class _IncidentItem extends StatelessWidget {
  const _IncidentItem({
    required this.icon,
    required this.color,
    required this.type,
    required this.time,
    required this.description,
  });

  final IconData icon;
  final Color color;
  final String type;
  final String time;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: color, width: 2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      type,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                        color: Stitch.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Stitch.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
