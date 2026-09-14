import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/monitoring_client.dart';
import '../../theme.dart';
import '../../utils/safety_grading.dart';

/// Mobile trip history screen matching the Stitch "History" mockup.
///
/// Shows filter chips, scrollable trip cards with left accent bars,
/// safety score progress, and per-trip stats.
class MobileHistoryScreen extends StatefulWidget {
  const MobileHistoryScreen({super.key, required this.client});

  final MonitoringClient client;

  @override
  State<MobileHistoryScreen> createState() => _MobileHistoryScreenState();
}

class _MobileHistoryScreenState extends State<MobileHistoryScreen> {
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() { _loading = true; _error = null; });
    try {
      final trips = await widget.client.fetchTripHistory();
      if (mounted) setState(() { _trips = trips; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  DateTime? _parseStartedAt(dynamic value) {
    if (value == null) return null;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatDuration(num? seconds) {
    if (seconds == null || seconds <= 0) return '—';
    final s = seconds.toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatDateShort(dynamic value) {
    final dt = _parseStartedAt(value);
    if (dt == null) return '—';
    const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _formatTimeRange(dynamic startedAt, num? durationS) {
    final dt = _parseStartedAt(startedAt);
    if (dt == null) return '—';
    final end = durationS != null ? dt.add(Duration(seconds: durationS.toInt())) : dt;
    String fmt(DateTime t) {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${fmt(dt)} - ${fmt(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      color: Stitch.background,
      child: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Stitch.primary))
                : _error != null
                    ? _buildError()
                    : _trips.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: _loadTrips,
                            color: Stitch.primary,
                            backgroundColor: Stitch.container,
                            child: ListView.builder(
                              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomPad),
                              itemCount: _trips.length + 1, // +1 for header
                              itemBuilder: (_, i) {
                                if (i == 0) return _buildHeader();
                                return _buildTripCard(_trips[i - 1]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Log Archive',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Stitch.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_trips.length} SESSIONS',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w500,
                  color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Stitch.containerHigh,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.filter_list, size: 18, color: Stitch.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final scoreValue = safetyScoreFrom(trip);
    final color = scoreValue == null
        ? Stitch.onSurfaceVariant
        : gradeSafetyScore(scoreValue).color;
    final duration = _formatDuration(trip['duration_s']);
    final dateShort = _formatDateShort(trip['started_at']);
    final timeRange = _formatTimeRange(trip['started_at'], trip['duration_s'] as num?);
    final label = trip['label'] as String? ?? 'Driving Session';
    final alerts = (trip['alert_count'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          // All trip data is shown inline; tapping opens nothing yet, so the
          // card is honestly static until a detail view exists.
          onTap: null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Left accent bar
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Date and time
                                Row(
                                  children: [
                                    Text(
                                      dateShort.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'JetBrains Mono',
                                        fontWeight: FontWeight.w700,
                                        color: Stitch.onSurface,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: Stitch.onSurfaceVariant,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      timeRange,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'JetBrains Mono',
                                        fontWeight: FontWeight.w500,
                                        color: Stitch.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Trip name
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: Stitch.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Stats
                                Row(
                                  children: [
                                    Icon(Icons.schedule, size: 14, color: Stitch.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(
                                      duration,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontFamily: 'JetBrains Mono',
                                        fontWeight: FontWeight.w500,
                                        color: Stitch.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    if (alerts > 0) ...[
                                      Icon(Icons.warning_amber, size: 14, color: Stitch.error.withValues(alpha: 0.7)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$alerts alerts',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontFamily: 'JetBrains Mono',
                                          fontWeight: FontWeight.w500,
                                          color: Stitch.error.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Score
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                scoreValue?.round().toString() ?? '—',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontFamily: 'JetBrains Mono',
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                              Text(
                                'RATING',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'JetBrains Mono',
                                  fontWeight: FontWeight.w700,
                                  color: color.withValues(alpha: 0.7),
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Cyberpunk car SVG illustration
          SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _EmptyCarPainter(),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Sessions Recorded',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Stitch.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your driving history will appear\nhere once you complete a trip.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Stitch.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
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
          const Text('Unable to load trips',
              style: TextStyle(fontSize: 16, color: Stitch.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextButton(onPressed: _loadTrips, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ─── Empty State Car Painter ────────────────────────────────────────────────

class _EmptyCarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Stitch.containerHighest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final fillPaint = Paint()
      ..color = Stitch.containerHighest.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Car body
    final bodyPath = Path();
    bodyPath.moveTo(cx - 60, cy + 20);
    bodyPath.lineTo(cx - 50, cy - 10);
    bodyPath.lineTo(cx - 20, cy - 30);
    bodyPath.lineTo(cx + 20, cy - 30);
    bodyPath.lineTo(cx + 50, cy - 10);
    bodyPath.lineTo(cx + 60, cy + 20);
    bodyPath.close();

    canvas.drawPath(bodyPath, fillPaint);
    canvas.drawPath(bodyPath, paint);

    // Roof line
    canvas.drawLine(
      Offset(cx - 50, cy - 10),
      Offset(cx - 20, cy - 30),
      paint,
    );
    canvas.drawLine(
      Offset(cx + 20, cy - 30),
      Offset(cx + 50, cy - 10),
      paint,
    );

    // Wheels
    final wheelPaint = Paint()
      ..color = Stitch.containerHighest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(Offset(cx - 35, cy + 20), 12, fillPaint);
    canvas.drawCircle(Offset(cx - 35, cy + 20), 12, wheelPaint);
    canvas.drawCircle(Offset(cx + 35, cy + 20), 12, fillPaint);
    canvas.drawCircle(Offset(cx + 35, cy + 20), 12, wheelPaint);

    // Scanner beam
    final beamPaint = Paint()
      ..color = Stitch.primary.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final beamPath = Path();
    beamPath.moveTo(cx - 70, cy + 40);
    beamPath.lineTo(cx + 70, cy + 40);
    canvas.drawPath(beamPath, beamPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
