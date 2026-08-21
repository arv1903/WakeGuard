import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class PostTripSummaryDialog extends StatelessWidget {
  const PostTripSummaryDialog({super.key, required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final tripDuration = summary['trip_duration_s'] as num? ?? summary['duration'] as num? ?? 0;
    final avgAttention = summary['avg_attention'] as num? ?? summary['attention_avg'] as num? ?? 0;
    final maxPerclos = summary['max_perclos'] as num? ?? summary['perclos_max'] as num? ?? 0;
    final alertCount = summary['alert_count'] as num? ?? 0;
    final blinkRate = summary['avg_blinks_per_min'] as num? ?? 0;

    final durMin = (tripDuration / 60).floor();
    final durSec = (tripDuration % 60).floor();

    final safetyScore = ((avgAttention * 1.0 - alertCount * 3).clamp(0, 100)).toDouble();
    final scoreColor = safetyScore >= 80 ? AppColors.focusedGreen :
        safetyScore >= 60 ? AppColors.alertAmber : AppColors.alertRed;

    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.focusedGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.emoji_events_outlined, color: AppColors.focusedGreen, size: 22)),
                const SizedBox(width: 16),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Session Complete', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text('Post-trip summary', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ])),
              ]),
              const SizedBox(height: 24),
              const Divider(color: AppColors.textMuted, height: 1),
              const SizedBox(height: 24),
              Center(child: _SafetyScoreGauge(score: safetyScore, color: scoreColor)),
              const SizedBox(height: 24),
              _metricsGrid(durMin, durSec, avgAttention, maxPerclos, alertCount, blinkRate),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () { _exportCsv(context); },
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Export CSV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.textMuted),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    foregroundColor: AppColors.surface0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close & Return Home'),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricsGrid(int durMin, int durSec, num avgAttention, num maxPerclos, num alertCount, num blinkRate) {
    return Column(children: [
      Row(children: [
        Expanded(child: _metricItem(Icons.timer_outlined, 'TRIP DURATION', '${durMin}m ${durSec}s')),
        const SizedBox(width: 12),
        Expanded(child: _metricItem(Icons.psychology_outlined, 'AVG ATTENTION', '${avgAttention.toStringAsFixed(0)}/100')),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _metricItem(Icons.timelapse, 'MAX PERCLOS', maxPerclos.toStringAsFixed(2))),
        const SizedBox(width: 12),
        Expanded(child: _metricItem(Icons.warning_amber_outlined, 'ALERTS', '${alertCount.toInt()}', isAlert: alertCount > 0)),
      ]),
      const SizedBox(height: 12),
      _metricItem(Icons.remove_red_eye_outlined, 'AVG BLINK RATE', '${blinkRate.toStringAsFixed(0)}/min'),
    ]);
  }

  Widget _metricItem(IconData icon, String label, String value, {bool isAlert = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface0, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.surface2)),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isAlert ? AppColors.alertRed : AppColors.textPrimary)),
        ])),
      ]),
    );
  }

  void _exportCsv(BuildContext context) {
    final tripDuration = summary['trip_duration_s'] as num? ?? summary['duration'] as num? ?? 0;
    final avgAttention = summary['avg_attention'] as num? ?? summary['attention_avg'] as num? ?? 0;
    final maxPerclos = summary['max_perclos'] as num? ?? summary['perclos_max'] as num? ?? 0;
    final alertCount = summary['alert_count'] as num? ?? 0;
    final blinkRate = summary['avg_blinks_per_min'] as num? ?? 0;

    final rows = <String>[
      'Metric,Value',
      'Trip Duration (s),$tripDuration',
      'Avg Attention,$avgAttention',
      'Max PERCLOS,$maxPerclos',
      'Alert Count,$alertCount',
      'Avg Blinks/min,$blinkRate',
    ];
    final csv = rows.join('\n');
    Clipboard.setData(ClipboardData(text: csv));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trip summary CSV copied to clipboard.'),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _SafetyScoreGauge extends StatelessWidget {
  const _SafetyScoreGauge({required this.score, required this.color});
  final double score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120, height: 120,
      child: CustomPaint(
        painter: _ScorePainter(score: score, color: color),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${score.toInt()}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: color, height: 1)),
            const Text('SCORE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class _ScorePainter extends CustomPainter {
  _ScorePainter({required this.score, required this.color});
  final double score;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..color = AppColors.surface2..style = PaintingStyle.stroke..strokeWidth = 6);
    final maxSweep = 1.5 * math.pi;
    final sweep = maxSweep * (score / 100);
    canvas.drawArc(rect, -3 * math.pi / 4, sweep, false, Paint()
      ..color = color.withValues(alpha: 0.2)..style = PaintingStyle.stroke..strokeWidth = 12..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawArc(rect, -3 * math.pi / 4, sweep, false, Paint()
      ..color = color..style = PaintingStyle.stroke..strokeWidth = 6..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_ScorePainter old) => old.score != score || old.color != color;
}
