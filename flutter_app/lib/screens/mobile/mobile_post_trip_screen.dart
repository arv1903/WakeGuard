import 'package:flutter/material.dart';

import '../../services/monitoring_client.dart';
import '../../theme.dart';

/// Full-screen post-trip summary for the mobile companion.
///
/// Fetches the session summary from the backend and displays key metrics
/// in a vertical layout matching the Stitch design system.
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
          Text("Unable to load summary",
              style: TextStyle(fontSize: 16, color: Stitch.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextButton(onPressed: _fetchSummary, child: const Text("Retry")),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final s = _summary!;
    final tripDuration = s["trip_duration_s"] as num? ?? s["duration"] as num? ?? 0;
    final avgAttention = s["avg_attention"] as num? ?? s["attention_avg"] as num? ?? 0;
    final maxPerclos = s["max_perclos"] as num? ?? s["perclos_max"] as num? ?? 0;
    final alertCount = s["alert_count"] as num? ?? 0;
    final blinkRate = s["avg_blinks_per_min"] as num? ?? 0;

    final safetyScore = ((avgAttention * 1.0 - alertCount * 3).clamp(0, 100)).toDouble();
    final scoreColor = safetyScore >= 80
        ? Stitch.secondary
        : safetyScore >= 60
            ? Stitch.tertiary
            : Stitch.error;

    final durMin = (tripDuration / 60).floor();
    final durSec = (tripDuration % 60).floor();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Stitch.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.emoji_events_outlined, color: Stitch.secondary, size: 22),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Session Complete", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Stitch.onSurface)),
                    Text("Post-trip summary", style: TextStyle(fontSize: 13, color: Stitch.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Safety score gauge
          SizedBox(
            width: 120, height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120, height: 120,
                  child: CircularProgressIndicator(
                    value: safetyScore / 100,
                    strokeWidth: 8,
                    backgroundColor: Stitch.containerHighest,
                    valueColor: AlwaysStoppedAnimation(scoreColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("${safetyScore.toInt()}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: scoreColor, height: 1)),
                    const Text("SCORE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2, color: Stitch.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Metrics
          _MetricRow(
            left: _MetricCard(icon: Icons.timer_outlined, label: "DURATION", value: "${durMin}m ${durSec}s"),
            right: _MetricCard(icon: Icons.psychology_outlined, label: "AVG ATTENTION", value: "${avgAttention.toStringAsFixed(0)}/100"),
          ),
          const SizedBox(height: 12),
          _MetricRow(
            left: _MetricCard(icon: Icons.timelapse, label: "MAX PERCLOS", value: maxPerclos.toStringAsFixed(2)),
            right: _MetricCard(icon: Icons.warning_amber_outlined, label: "ALERTS", value: "${alertCount.toInt()}", isAlert: alertCount > 0),
          ),
          const SizedBox(height: 12),
          _MetricRow(
            left: _MetricCard(icon: Icons.remove_red_eye_outlined, label: "BLINK RATE", value: "${blinkRate.toStringAsFixed(0)}/min"),
            right: const SizedBox.shrink(),
          ),
          const SizedBox(height: 40),

          // Done button
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Stitch.primary,
                foregroundColor: Stitch.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text("DONE", style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value, this.isAlert = false});
  final IconData icon;
  final String label;
  final String value;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Stitch.container,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Stitch.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: Stitch.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isAlert ? Stitch.error : Stitch.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
