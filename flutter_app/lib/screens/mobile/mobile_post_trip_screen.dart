import 'package:flutter/material.dart';

import '../../services/monitoring_client.dart';
import '../../theme.dart';
import '../../utils/safety_grading.dart';
import 'attention_chart.dart';
import 'post_trip_data.dart';

/// Full-screen post-trip summary matching the Stitch "Trip Summary" mockup.
///
/// Every figure comes from the backend: the summary endpoint supplies score,
/// duration, attention, and alert counts; the telemetry endpoint supplies the
/// attention curve. Nothing on this screen is fabricated.
class MobilePostTripScreen extends StatefulWidget {
  const MobilePostTripScreen({super.key, required this.client});

  final MonitoringClient client;

  @override
  State<MobilePostTripScreen> createState() => _MobilePostTripScreenState();
}

class _MobilePostTripScreenState extends State<MobilePostTripScreen> {
  Map<String, dynamic>? _summary;
  List<TripPoint> _telemetry = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await widget.client.fetchCurrentSummary();
      var telemetry = const <TripPoint>[];
      final sessionId =
          summary['session_id'] as String? ?? widget.client.snapshot.sessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        final rows = await widget.client.fetchSessionTelemetry(sessionId);
        telemetry = parseTelemetry(rows);
      }
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _telemetry = telemetry;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Stitch.background,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Stitch.primary))
            : _error != null || _summary == null
                ? _buildError()
                : _buildContent(_summary!),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off,
              size: 48, color: Stitch.error.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text('Unable to load summary',
              style:
                  TextStyle(fontSize: 16, color: Stitch.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> s) {
    final tripDuration = s['trip_duration_s'] as num? ?? 0;
    final avgAttention = s['avg_attention'] as num? ?? 0;
    final alertCount = s['alert_count'] as num? ?? 0;
    final incidents = summarizeIncidents(s);

    final grade = safetyScoreFrom(s) == null
        ? null
        : gradeSafetyScore(safetyScoreFrom(s)!);
    final gradeColor = grade?.color ?? Stitch.onSurfaceVariant;

    final durH = (tripDuration / 3600).floor();
    final durM = ((tripDuration % 3600) / 60).floor();
    final durStr = durH > 0 ? '${durH}h ${durM}m' : '${durM}m';

    final synced = widget.client.connectionState ==
        BackendConnectionState.connected;

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(durStr, grade, gradeColor, synced),
          _buildStatsGrid(tripDuration, avgAttention, alertCount, gradeColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: AttentionChart(points: _telemetry),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _IncidentLog(summary: incidents),
          ),
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
                      borderRadius: BorderRadius.circular(12)),
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

  Widget _buildHeader(
      String durStr, SafetyGrade? grade, Color gradeColor, bool synced) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'MISSION REPORT',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w700,
              color: Stitch.onSurfaceVariant,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          // Ring shows the real score out of 100 — not a decorative spinner.
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(
                    key: const Key('grade-ring'),
                    value: grade == null ? 0 : grade.score / 100,
                    strokeWidth: 2,
                    color: gradeColor.withValues(alpha: 0.5),
                    backgroundColor:
                        Stitch.outlineVariant.withValues(alpha: 0.2),
                    strokeCap: StrokeCap.butt,
                  ),
                ),
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
                      grade == null ? '—' : grade.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: grade == null ? 28 : 20,
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
            synced ? 'Data synched to core.' : 'Loaded from last session.',
            style: const TextStyle(
              fontSize: 14,
              color: Stitch.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(num tripDuration, num avgAttention, num alertCount,
      Color gradeColor) {
    final durH = (tripDuration / 3600).floor();
    final durM = ((tripDuration % 3600) / 60).floor();
    final durStr = durH > 0 ? '${durH}h ${durM}m' : '${durM}m';
    return Padding(
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
                  value: safetyScoreFrom(_summary ?? const {}) == null
                      ? '—'
                      : '${safetyScoreFrom(_summary!)!.round()}',
                  color: gradeColor,
                ),
              ),
            ],
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
        border:
            Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.3)),
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
                Icon(Icons.warning,
                    size: 14, color: Stitch.error.withValues(alpha: 0.7)),
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

// ─── Incident Log ───────────────────────────────────────────────────────────

class _IncidentLog extends StatelessWidget {
  const _IncidentLog({required this.summary});

  final IncidentSummary summary;

  @override
  Widget build(BuildContext context) {
    final first = summary.firstAlertAt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Stitch.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Stitch.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'INCIDENT LOG',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w700,
                  color: Stitch.onSurfaceVariant,
                  letterSpacing: 1.5,
                ),
              ),
              if (first != null)
                Text(
                  'First alert T+${formatElapsed(first)}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'JetBrains Mono',
                    color: Stitch.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (summary.incidents.isEmpty)
            const Text(
              'No incidents recorded.',
              style: TextStyle(fontSize: 13, color: Stitch.onSurfaceVariant),
            )
          else
            for (final incident in summary.incidents)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _IncidentItem(incident: incident),
              ),
        ],
      ),
    );
  }
}

class _IncidentItem extends StatelessWidget {
  const _IncidentItem({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (incident.type) {
      'Distraction' => (Icons.phone_in_talk, Stitch.tertiaryFixedDim),
      'Drowsiness' => (Icons.bedtime, Stitch.error),
      'Fatigue' => (Icons.battery_alert, Stitch.primary),
      _ => (Icons.warning_amber, Stitch.onSurfaceVariant),
    };
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
                      incident.type,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                    ),
                    Text(
                      '×${incident.count}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w700,
                        color: Stitch.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  incident.description,
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
