import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/monitoring_client.dart';
import '../theme.dart';
import '../utils/safety_grading.dart';

/// Screen for reviewing past trip analytics while idle.
/// Fetches session history from the backend and displays summaries
/// with the ability to drill into individual trips.
class TripLogScreen extends StatefulWidget {
  const TripLogScreen({super.key, required this.client});
  final MonitoringClient client;

  @override
  State<TripLogScreen> createState() => _TripLogScreenState();
}

class _TripLogScreenState extends State<TripLogScreen> {
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;
  String? _error;

  // Filter state
  bool _filtersExpanded = false;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  double _minSafety = 0;
  double _maxSafety = 100;

  int get _activeFilterCount {
    var count = 0;
    if (_dateFrom != null) count++;
    if (_dateTo != null) count++;
    if (_minSafety > 0) count++;
    if (_maxSafety < 100) count++;
    return count;
  }

  bool get _hasActiveFilters => _activeFilterCount > 0;

  List<Map<String, dynamic>> get _filteredTrips {
    return _trips.where((trip) {
      final startedAt = trip['started_at'] as double? ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(
          (startedAt * 1000).toInt());
      final safetyScore = safetyScoreFrom(trip);

      if (_dateFrom != null && dt.isBefore(_dateFrom!)) return false;
      if (_dateTo != null) {
        final endOfDay =
            DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
        if (dt.isAfter(endOfDay)) return false;
      }
      // A missing score is unknown, not perfect: it fails any narrowed
      // score filter instead of silently passing as an invented 100.
      if (safetyScore == null) {
        if (_minSafety > 0 || _maxSafety < 100) return false;
      } else if (safetyScore < _minSafety || safetyScore > _maxSafety) {
        return false;
      }
      return true;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _minSafety = 0;
      _maxSafety = 100;
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchTrips();
  }

  Future<void> _fetchTrips() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trips = await widget.client.fetchTripHistory();
      if (mounted) {
        setState(() {
          _trips = trips;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load trip history';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.history,
                    size: 28, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                const Text('Trip Log',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -1)),
                const Spacer(),
                _RefreshButton(onPressed: _fetchTrips),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Review past monitoring sessions and safety metrics',
              style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 16),

            // Filter bar
            _FilterBar(
              filtersExpanded: _filtersExpanded,
              onToggle: () => setState(() => _filtersExpanded = !_filtersExpanded),
              activeCount: _activeFilterCount,
              hasActive: _hasActiveFilters,
              onClear: _clearFilters,
            ),
            if (_filtersExpanded) ...[
              const SizedBox(height: 12),
              _FilterPanel(
                dateFrom: _dateFrom,
                dateTo: _dateTo,
                minSafety: _minSafety,
                maxSafety: _maxSafety,
                onDateFromChanged: (d) => setState(() => _dateFrom = d),
                onDateToChanged: (d) => setState(() => _dateTo = d),
                onSafetyChanged: (min, max) => setState(() {
                  _minSafety = min;
                  _maxSafety = max;
                }),
              ),
            ],
            const SizedBox(height: 16),

            // Content
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppColors.accent)),
      );
    }

    if (_error != null) {
      return _EmptyState(
        icon: Icons.error_outline,
        title: 'Connection Error',
        subtitle: _error!,
        actionLabel: 'Retry',
        onAction: _fetchTrips,
      );
    }

    if (_trips.isEmpty) {
      return _EmptyState(
        icon: Icons.directions_car_outlined,
        title: 'No Trip History',
        subtitle:
            'Complete a monitoring session to see your trip data here.',
        actionLabel: null,
        onAction: null,
      );
    }

    final filtered = _filteredTrips;
    if (_trips.isNotEmpty && filtered.isEmpty) {
      return _EmptyState(
        icon: Icons.filter_list_off,
        title: 'No Matching Trips',
        subtitle:
            'Try adjusting your filters to see more results.',
        actionLabel: 'Clear Filters',
        onAction: _clearFilters,
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchTrips,
      child: ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final trip = filtered[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TripCard(
              trip: trip,
              onTap: () => _showTripDetail(trip),
            ),
          );
        },
      ),
    );
  }

  void _showTripDetail(Map<String, dynamic> trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TripDetailSheet(
        trip: trip,
        client: widget.client,
      ),
    );
  }
}

/// A single trip card in the list.
class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onTap});
  final Map<String, dynamic> trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final startedAt = trip['started_at'] as double? ?? 0;
    final dt = DateTime.fromMillisecondsSinceEpoch((startedAt * 1000).toInt());
    final duration = trip['duration_s'] as double? ?? 0;
    final durMin = (duration / 60).floor();
    final durSec = (duration % 60).floor();
    final avgAttention = (trip['avg_attention'] as num?)?.toDouble() ?? 100;
    final alertCount = (trip['alert_count'] as num?)?.toInt() ?? 0;
    final scoreValue = safetyScoreFrom(trip);
    final scoreColor = scoreValue == null
        ? AppColors.textMuted
        : switch (gradeSafetyScore(scoreValue).band) {
            SafetyBand.good => AppColors.focusedGreen,
            SafetyBand.fair => AppColors.alertAmber,
            SafetyBand.poor => AppColors.alertRed,
          };
    final scoreLabel = scoreValue == null ? '—/100' : '${scoreValue.round()}/100';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: AppColors.surface2.withValues(alpha: 0.5),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surface2),
          ),
          child: Row(
            children: [
              // Date/Time column
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMM d, yyyy').format(dt),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('HH:mm').format(dt),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),

              // Duration
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DURATION',
                        style: AppTextStyles.labelSm),
                    const SizedBox(height: 4),
                    Text(
                      '${durMin}m ${durSec}s',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              // Attention
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ATTENTION',
                        style: AppTextStyles.labelSm),
                    const SizedBox(height: 4),
                    Text(
                      '${avgAttention.toStringAsFixed(0)}/100',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: avgAttention >= 70
                            ? AppColors.focusedGreen
                            : AppColors.alertAmber,
                      ),
                    ),
                  ],
                ),
              ),

              // Alerts
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ALERTS',
                        style: AppTextStyles.labelSm),
                    const SizedBox(height: 4),
                    Text(
                      '$alertCount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: alertCount > 0
                            ? AppColors.alertRed
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              // Safety Score
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('SAFETY',
                        style: AppTextStyles.labelSm),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        scoreLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: scoreColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet showing detailed trip information with sparkline charts.
class _TripDetailSheet extends StatefulWidget {
  const _TripDetailSheet({required this.trip, required this.client});
  final Map<String, dynamic> trip;
  final MonitoringClient client;

  @override
  State<_TripDetailSheet> createState() => _TripDetailSheetState();
}

class _TripDetailSheetState extends State<_TripDetailSheet> {
  List<Map<String, dynamic>> _telemetry = [];
  bool _loadingTelemetry = true;

  @override
  void initState() {
    super.initState();
    _fetchTelemetry();
  }

  Future<void> _fetchTelemetry() async {
    final sessionId = widget.trip['session_id'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      if (mounted) setState(() => _loadingTelemetry = false);
      return;
    }
    final data = await widget.client.fetchSessionTelemetry(sessionId);
    if (mounted) {
      setState(() {
        _telemetry = data;
        _loadingTelemetry = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final startedAt = trip['started_at'] as double? ?? 0;
    final dt = DateTime.fromMillisecondsSinceEpoch((startedAt * 1000).toInt());
    final duration = trip['duration_s'] as double? ?? 0;
    final durMin = (duration / 60).floor();
    final durSec = (duration % 60).floor();
    final avgAttention = (trip['avg_attention'] as num?)?.toDouble() ?? 100;
    final alertCount = (trip['alert_count'] as num?)?.toInt() ?? 0;
    final scoreValue = safetyScoreFrom(trip);
    final sessionId = trip['session_id'] as String? ?? 'unknown';
    final shortId =
        sessionId.length > 12 ? sessionId.substring(0, 12) : sessionId;
    final scoreColor = scoreValue == null
        ? AppColors.textMuted
        : switch (gradeSafetyScore(scoreValue).band) {
            SafetyBand.good => AppColors.focusedGreen,
            SafetyBand.fair => AppColors.alertAmber,
            SafetyBand.poor => AppColors.alertRed,
          };
    final scoreLabel = scoreValue == null ? '—/100' : '${scoreValue.round()}/100';
    final barProgress = scoreValue == null ? 0.0 : scoreValue / 100;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface0,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Trip Details',
                style: AppTextStyles.headlineMd,
              ),
              const SizedBox(height: 4),
              Text(
                shortId,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 24),

              // Metrics grid
              Row(
                children: [
                  Expanded(
                    child: _DetailMetric(
                      label: 'STARTED',
                      value: DateFormat('MMM d, HH:mm').format(dt),
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DetailMetric(
                      label: 'DURATION',
                      value: '${durMin}m ${durSec}s',
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DetailMetric(
                      label: 'AVG ATTENTION',
                      value: '${avgAttention.toStringAsFixed(1)}/100',
                      color: avgAttention >= 70
                          ? AppColors.focusedGreen
                          : AppColors.alertAmber,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DetailMetric(
                      label: 'ALERTS',
                      value: '$alertCount',
                      color: alertCount > 0
                          ? AppColors.alertRed
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Safety score bar
              const Text('SAFETY SCORE', style: AppTextStyles.labelCaps),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: barProgress,
                        minHeight: 12,
                        backgroundColor: AppColors.surface2,
                        color: scoreColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    scoreLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scoreColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Attention bar
              const Text('ATTENTION LEVEL', style: AppTextStyles.labelCaps),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: avgAttention / 100,
                        minHeight: 12,
                        backgroundColor: AppColors.surface2,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${avgAttention.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Sparkline Charts ──
              if (_loadingTelemetry)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.textSecondary),
                      ),
                    ),
                  ),
                )
              else if (_telemetry.isNotEmpty) ...[
                // Attention sparkline
                const Text('ATTENTION OVER TIME',
                    style: AppTextStyles.labelCaps),
                const SizedBox(height: 12),
                Container(
                  height: 100,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surface2),
                  ),
                  child: _SparklineChart(
                    data: _telemetry
                        .map((e) => (e['attention'] as num?)?.toDouble() ?? 0)
                        .toList(),
                    color: AppColors.focusedGreen,
                    minY: 0,
                    maxY: 100,
                  ),
                ),
                const SizedBox(height: 20),

                // PERCLOS sparkline
                const Text('PERCLOS OVER TIME',
                    style: AppTextStyles.labelCaps),
                const SizedBox(height: 12),
                Container(
                  height: 100,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surface2),
                  ),
                  child: _SparklineChart(
                    data: _telemetry
                        .map((e) =>
                            ((e['perclos'] as num?)?.toDouble() ?? 0) * 100)
                        .toList(),
                    color: AppColors.alertRed,
                    minY: 0,
                    maxY: 100,
                  ),
                ),
                const SizedBox(height: 16),

                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _legendDot(AppColors.focusedGreen, 'Attention'),
                    const SizedBox(width: 20),
                    _legendDot(AppColors.alertRed, 'PERCLOS'),
                    const SizedBox(width: 20),
                    Text('${_telemetry.length} samples',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No telemetry data available for this session',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textMuted),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    ]);
  }
}

/// A metric displayed in the detail sheet.
class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surface2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.labelSm),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight sparkline chart rendered with CustomPaint.
class _SparklineChart extends StatelessWidget {
  const _SparklineChart({
    required this.data,
    required this.color,
    this.minY = 0,
    this.maxY = 100,
  });
  final List<double> data;
  final Color color;
  final double minY;
  final double maxY;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _ChartPainter(
        data: data,
        color: color,
        minY: minY,
        maxY: maxY,
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.data,
    required this.color,
    required this.minY,
    required this.maxY,
  });
  final List<double> data;
  final Color color;
  final double minY;
  final double maxY;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final range = (maxY - minY).clamp(0.001, double.infinity);

    // Grid lines
    final gridPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    for (final y in [0.25, 0.5, 0.75]) {
      final py = size.height * (1 - y);
      canvas.drawLine(Offset(0, py), Offset(size.width, py), gridPaint);
    }

    // Fill path
    final fillPath = Path();
    final strokePath = Path();
    for (var i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final ratio = ((data[i] - minY) / range).clamp(0.0, 1.0);
      final y = size.height * (1 - ratio);
      if (i == 0) {
        strokePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        strokePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.2),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    canvas.drawPath(
        strokePath,
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      !identical(old.data, data) || old.color != color;
}

/// Collapsible filter bar header.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filtersExpanded,
    required this.onToggle,
    required this.activeCount,
    required this.hasActive,
    required this.onClear,
  });
  final bool filtersExpanded;
  final VoidCallback onToggle;
  final int activeCount;
  final bool hasActive;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surface2),
          ),
          child: Row(
            children: [
              Icon(
                filtersExpanded
                    ? Icons.filter_list_off
                    : Icons.filter_list,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                'Filters',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (activeCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (hasActive)
                GestureDetector(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: filtersExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.expand_more,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expandable filter panel with date range and safety score controls.
class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.dateFrom,
    required this.dateTo,
    required this.minSafety,
    required this.maxSafety,
    required this.onDateFromChanged,
    required this.onDateToChanged,
    required this.onSafetyChanged,
  });
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final double minSafety;
  final double maxSafety;
  final ValueChanged<DateTime?> onDateFromChanged;
  final ValueChanged<DateTime?> onDateToChanged;
  final void Function(double min, double max) onSafetyChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surface2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range
          const Text('DATE RANGE', style: AppTextStyles.labelCaps),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DateButton(
                  label: 'From',
                  date: dateFrom,
                  onTap: () => _pickDate(context, isFrom: true),
                  onClear: dateFrom != null
                      ? () => onDateFromChanged(null)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateButton(
                  label: 'To',
                  date: dateTo,
                  onTap: () => _pickDate(context, isFrom: false),
                  onClear:
                      dateTo != null ? () => onDateToChanged(null) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Safety score range
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SAFETY SCORE', style: AppTextStyles.labelCaps),
              Text(
                '${minSafety.toInt()} – ${maxSafety.toInt()}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RangeSlider(
            values: RangeValues(minSafety, maxSafety),
            min: 0,
            max: 100,
            divisions: 20,
            activeColor: AppColors.accent,
            inactiveColor: AppColors.surface2,
            labels: RangeLabels(
              minSafety.toInt().toString(),
              maxSafety.toInt().toString(),
            ),
            onChanged: (values) =>
                onSafetyChanged(values.start, values.end),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0',
                  style: TextStyle(
                      fontSize: 10, color: AppColors.textMuted)),
              Text('100',
                  style: TextStyle(
                      fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final initial = isFrom
        ? (dateFrom ?? DateTime.now())
        : (dateTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.surface1,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (isFrom) {
      onDateFromChanged(picked);
    } else {
      onDateToChanged(picked);
    }
  }
}

/// Date picker button.
class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.date,
    required this.onTap,
    this.onClear,
  });
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface0,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: date != null
                  ? AppColors.accent.withValues(alpha: 0.3)
                  : AppColors.surface2,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today,
                  size: 14,
                  color: date != null
                      ? AppColors.accent
                      : AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppColors.textMuted,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      date != null
                          ? DateFormat('MMM d, yyyy').format(date!)
                          : 'Any date',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: date != null
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close,
                      size: 14, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state widget.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface2),
            ),
            child: Icon(icon, size: 40, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary.withValues(alpha: 0.7))),
          if (actionLabel != null) ...[
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface2,
                foregroundColor: AppColors.textPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Refresh button with loading indicator.
class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _refreshing = false;

  Future<void> _handleTap() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    widget.onPressed();
    // Wait a bit for the parent to start loading
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _handleTap,
      icon: _refreshing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation(AppColors.textSecondary)),
            )
          : const Icon(Icons.refresh,
              size: 20, color: AppColors.textSecondary),
      tooltip: 'Refresh',
    );
  }
}
