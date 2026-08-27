import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/monitoring_client.dart';
import '../../theme.dart';

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

  // Filters
  bool _showFilters = false;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  double _minSafety = 0;
  double _maxSafety = 100;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
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
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Parse [started_at] which may be a unix timestamp (num) or ISO string.
  DateTime? _parseStartedAt(dynamic value) {
    if (value == null) return null;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  List<Map<String, dynamic>> get _filteredTrips {
    return _trips.where((trip) {
      final score = (trip['safety_score'] as num?)?.toDouble() ?? 0;
      if (score < _minSafety || score > _maxSafety) return false;

      final started = _parseStartedAt(trip['started_at']);
      if (started != null) {
        if (_dateFrom != null && started.isBefore(_dateFrom!)) return false;
        if (_dateTo != null && started.isAfter(_dateTo!)) return false;
      }
      return true;
    }).toList();
  }

  Color _scoreColor(double score) {
    if (score >= 80) return Stitch.secondary;
    if (score >= 50) return Stitch.tertiary;
    return Stitch.error;
  }

  String _formatDuration(num? seconds) {
    if (seconds == null || seconds <= 0) return '—';
    final s = seconds.toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatDate(dynamic value) {
    final dt = _parseStartedAt(value);
    if (dt == null) return '—';
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final amPm = dt.hour < 12 ? 'AM' : 'PM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month]} ${dt.day}, ${dt.year} • $hour:$mm $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      color: Stitch.background,
      child: Column(
        children: [
          // Filter bar
          _buildFilterBar(),
          // Filter panel (collapsible)
          if (_showFilters) _buildFilterPanel(),
          // Trip list
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Stitch.primary))
                : _error != null
                    ? _buildError()
                    : _filteredTrips.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: _loadTrips,
                            color: Stitch.primary,
                            backgroundColor: Stitch.container,
                            child: ListView.builder(
                              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomPad),
                              itemCount: _filteredTrips.length,
                              itemBuilder: (_, i) => _buildTripCard(
                                _filteredTrips[i],
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final activeCount = [
      _dateFrom != null,
      _dateTo != null,
      _minSafety > 0 || _maxSafety < 100,
    ].where((e) => e).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          // Filter toggle
          GestureDetector(
            onTap: () => setState(() => _showFilters = !_showFilters),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Stitch.container,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_list,
                      size: 16, color: Stitch.onSurfaceVariant),
                  const SizedBox(width: 6),
                  const Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w500,
                      color: Stitch.onSurfaceVariant,
                    ),
                  ),
                  if (activeCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Stitch.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$activeCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                          color: Stitch.onPrimary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _showFilters ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more,
                        size: 16, color: Stitch.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (activeCount > 0)
            GestureDetector(
              onTap: () => setState(() {
                _dateFrom = null;
                _dateTo = null;
                _minSafety = 0;
                _maxSafety = 100;
              }),
              child: const Text(
                'Clear',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w500,
                  color: Stitch.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range
          const Text(
            'DATE RANGE',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w500,
              color: Stitch.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DateButton(
                  label: _dateFrom != null
                      ? '${_dateFrom!.month}/${_dateFrom!.day}/${_dateFrom!.year}'
                      : 'From',
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dateFrom ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Stitch.primary,
                              surface: Stitch.container,
                              onSurface: Stitch.onSurface,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) setState(() => _dateFrom = picked);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DateButton(
                  label: _dateTo != null
                      ? '${_dateTo!.month}/${_dateTo!.day}/${_dateTo!.year}'
                      : 'To',
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dateTo ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Stitch.primary,
                              surface: Stitch.container,
                              onSurface: Stitch.onSurface,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) setState(() => _dateTo = picked);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Safety score range
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SAFETY SCORE',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w500,
                  color: Stitch.onSurfaceVariant,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                '${_minSafety.round()} – ${_maxSafety.round()}',
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w500,
                  color: Stitch.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RangeSlider(
            values: RangeValues(_minSafety, _maxSafety),
            min: 0,
            max: 100,
            divisions: 20,
            activeColor: Stitch.primary,
            inactiveColor: Stitch.containerHighest,
            onChanged: (v) =>
                setState(() { _minSafety = v.start; _maxSafety = v.end; }),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final score = (trip['safety_score'] as num?)?.toDouble() ?? 0;
    final color = _scoreColor(score);
    final duration = _formatDuration(trip['duration_s']);
    final attention = (trip['avg_attention'] as num?)?.round() ?? 0;
    final alerts = (trip['alert_count'] as num?)?.toInt() ?? 0;
    final dateStr = _formatDate(trip['started_at']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Stitch.container,
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
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Stitch.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${trip['label'] ?? ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Stitch.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${score.round()}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                              const Text(
                                'Safety Score',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'JetBrains Mono',
                                  fontWeight: FontWeight.w500,
                                  color: Stitch.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Score bar
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Stitch.surface,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: (score / 100).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Stats grid
                      Row(
                        children: [
                          _StatChip(
                            icon: Icons.schedule,
                            label: 'Duration',
                            value: duration,
                            color: Stitch.primary,
                          ),
                          const SizedBox(width: 12),
                          _StatChip(
                            icon: Icons.visibility,
                            label: 'Attention',
                            value: '$attention%',
                            color: attention >= 80
                                ? Stitch.secondary
                                : Stitch.tertiary,
                          ),
                          const SizedBox(width: 12),
                          _StatChip(
                            icon: Icons.notifications,
                            label: 'Alerts',
                            value: '$alerts',
                            color: alerts == 0
                                ? Stitch.secondary
                                : alerts <= 3
                                    ? Stitch.tertiary
                                    : Stitch.error,
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
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Stitch.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'No trips recorded yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Stitch.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Trip history will appear here after driving sessions',
            style: TextStyle(
              fontSize: 13,
              color: Stitch.onSurfaceVariant.withValues(alpha: 0.6),
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
          Text(
            'Unable to load trips',
            style: TextStyle(
              fontSize: 16,
              color: Stitch.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _loadTrips,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ─── Date Button ─────────────────────────────────────────────────────────────

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Stitch.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'JetBrains Mono',
                color: label == 'From' || label == 'To'
                    ? Stitch.onSurfaceVariant.withValues(alpha: 0.5)
                    : Stitch.onSurface,
              ),
            ),
            Icon(Icons.calendar_today,
                size: 14, color: Stitch.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Chip ───────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                    color: Stitch.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Stitch.onSurface,
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
