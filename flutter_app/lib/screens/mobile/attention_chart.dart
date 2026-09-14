import 'package:flutter/material.dart';

import '../../theme.dart';
import 'post_trip_data.dart';

/// Attention chart for the post-trip report, drawn from real telemetry
/// samples (`/api/v1/sessions/{id}/telemetry`). Renders an explicit
/// unavailable state instead of fabricating a curve when no data exists.
class AttentionChart extends StatelessWidget {
  const AttentionChart({super.key, required this.points});

  final List<TripPoint> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ATTENTION TELEMETRY',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w700,
              color: Stitch.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (points.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.query_stats,
                        size: 28,
                        color: Stitch.onSurfaceVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    const Text(
                      'Telemetry unavailable for this trip',
                      style: TextStyle(
                        fontSize: 12,
                        color: Stitch.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 120,
              child: CustomPaint(
                size: Size.infinite,
                painter: _ChartPainter(
                    points: downsample(points, 60)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _AxisLabel(formatElapsed(points.first.t)),
                if (points.length > 2)
                  _AxisLabel(formatElapsed(
                      (points.first.t + points.last.t) / 2)),
                _AxisLabel(formatElapsed(points.last.t)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 10,
          fontFamily: 'JetBrains Mono',
          color: Stitch.onSurfaceVariant),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.points});

  final List<TripPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final maxT = points.last.t <= 0 ? 1.0 : points.last.t;

    // Grid lines at 20/50/80% of the true 0–100 scale.
    final gridPaint = Paint()
      ..color = Stitch.containerHighest.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final frac in [0.2, 0.5, 0.8]) {
      canvas.drawLine(
          Offset(0, h * frac), Offset(w, h * frac), gridPaint);
    }

    Offset xy(TripPoint p) => Offset(
          (p.t / maxT) * w,
          h - (p.attention / 100).clamp(0.0, 1.0) * h,
        );

    final path = Path()..moveTo(xy(points.first).dx, xy(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      final prev = xy(points[i - 1]);
      final curr = xy(points[i]);
      final midX = (prev.dx + curr.dx) / 2;
      path.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
    }

    final areaPath = Path.from(path)
      ..lineTo(xy(points.last).dx, h)
      ..lineTo(xy(points.first).dx, h)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Stitch.primary.withValues(alpha: 0.4),
            Stitch.primary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = Stitch.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.points != points;
}
