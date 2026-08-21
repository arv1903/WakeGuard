import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/monitoring_client.dart';
import '../theme.dart';

class TripAnalyticsScreen extends StatefulWidget {
  const TripAnalyticsScreen({super.key, required this.client});
  final MonitoringClient client;

  @override
  State<TripAnalyticsScreen> createState() => _TripAnalyticsScreenState();
}

class _TripAnalyticsScreenState extends State<TripAnalyticsScreen> {
  final List<_TelemetryPoint> _telemetryBuffer = [];
  final List<_LogEntry> _eventLog = [];
  static const int _maxBuffer = 360;
  String _filterLevel = 'All';

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onSnapshot);
  }

  @override
  void dispose() {
    widget.client.removeListener(_onSnapshot);
    super.dispose();
  }

  void _onSnapshot() {
    final snap = widget.client.snapshot;
    if (snap.sequence <= 0) return;

    setState(() {
      _telemetryBuffer.add(_TelemetryPoint(
        time: DateTime.now(),
        attention: snap.attention,
        perclos: snap.perclos,
      ));
      if (_telemetryBuffer.length > _maxBuffer) {
        _telemetryBuffer.removeAt(0);
      }

      if (snap.alert != null) {
        final now = DateTime.now();
        final duplicate = _eventLog.any((e) =>
            e.type == snap.alert && now.difference(e.time).inSeconds < 5);
        if (!duplicate) {
          _eventLog.insert(0, _LogEntry(
            time: now,
            type: snap.alert!,
            severity: snap.alertSeverity,
          ));
          if (_eventLog.length > 200) _eventLog.removeLast();
        }
      }
    });
  }

  List<_LogEntry> get _filteredLog {
    if (_filterLevel == 'All') return _eventLog;
    if (_filterLevel == 'Critical') return _eventLog.where((e) => e.severity >= 4).toList();
    if (_filterLevel == 'Warning') return _eventLog.where((e) => e.severity >= 2 && e.severity < 4).toList();
    return _eventLog;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.client,
      builder: (context, _) {
        final snap = widget.client.snapshot;
        final elapsed = snap.tripStartedAt != null
            ? DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch((snap.tripStartedAt! * 1000).toInt()))
            : Duration.zero;
        final mins = elapsed.inMinutes;
        final secs = elapsed.inSeconds % 60;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Trip Analytics & Logs',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -1)),
              const SizedBox(height: 24),
              // KPI Cards with sparklines
              Row(children: [
                Expanded(child: _KpiCard(
                  title: 'TRIP DURATION', value: '${mins}m ${secs}s',
                  subtitle: snap.tripActive ? 'Ongoing' : 'Stopped',
                  icon: Icons.timer_outlined, accent: AppColors.focusedGreen,
                  sparkData: _telemetryBuffer.map((p) => p.attention).toList(),
                  sparkColor: AppColors.focusedGreen,
                )),
                const SizedBox(width: 16),
                Expanded(child: _KpiCard(
                  title: 'AVG ATTENTION', value: '${snap.attention.toStringAsFixed(0)}/100',
                  subtitle: snap.focused ? 'Focused' : 'Degrading',
                  icon: Icons.visibility_outlined, accent: const Color(0xFF22d3ee),
                  sparkData: _telemetryBuffer.map((p) => p.attention).toList(),
                  sparkColor: const Color(0xFF22d3ee),
                )),
                const SizedBox(width: 16),
                Expanded(child: _KpiCard(
                  title: 'CRITICAL EVENTS', value: '${_eventLog.where((e) => e.severity >= 4).length}',
                  subtitle: snap.alert ?? 'None',
                  icon: Icons.warning_amber_outlined, accent: AppColors.alertRed, isAlert: snap.alert != null,
                )),
                const SizedBox(width: 16),
                Expanded(child: _KpiCard(
                  title: 'BLINK RATE', value: '${snap.blinksPerMin.toStringAsFixed(0)}/min',
                  subtitle: 'Normal', icon: Icons.remove_red_eye_outlined, accent: AppColors.focusedGreen,
                )),
              ]),
              const SizedBox(height: 24),
              // Chart
              Card(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Session Telemetry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      SizedBox(height: 4),
                      Text('Attention Score vs PERCLOS (live)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                    Row(children: [
                      _legendDot(AppColors.focusedGreen, 'Attention'),
                      const SizedBox(width: 16),
                      _legendDot(AppColors.alertRed, 'PERCLOS'),
                    ]),
                  ]),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 240,
                    child: _telemetryBuffer.isEmpty
                        ? _ChartEmptyState()
                        : _TelemetryChart(data: _telemetryBuffer),
                  ),
                ]),
              )),
              const SizedBox(height: 24),
              // Event Log
              Card(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Event Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0x33444748))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _filterLevel,
                            isDense: true,
                            dropdownColor: AppColors.surface1,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            items: ['All', 'Critical', 'Warning'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                            onChanged: (v) => setState(() => _filterLevel = v ?? 'All'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _LogButton(icon: Icons.download, label: 'Export CSV', onTap: _exportCsv),
                    ]),
                  ]),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0x33444748)),
                  if (_filteredLog.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No events recorded', style: TextStyle(color: AppColors.textMuted, fontSize: 13))),
                    )
                  else
                    ..._filteredLog.map((e) => _EventRow(
                      time: DateFormat('HH:mm:ss').format(e.time),
                      type: e.type,
                      severity: e.severity,
                    )),
                ]),
              )),
            ],
          ),
        );
      },
    );
  }

  void _exportCsv() async {
    final rows = <String>[
      'Time,Attention,PERCLOS',
      ..._telemetryBuffer.map((p) =>
        '${DateFormat('HH:mm:ss').format(p.time)},${p.attention.toStringAsFixed(2)},${p.perclos.toStringAsFixed(4)}'),
    ];
    final csv = rows.join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trip telemetry CSV copied to clipboard.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    ]);
  }
}

// ─── Telemetry Chart (fl_chart) ─────────────────────────────────────────────

class _TelemetryChart extends StatelessWidget {
  const _TelemetryChart({required this.data});
  final List<_TelemetryPoint> data;

  @override
  Widget build(BuildContext context) {
    final attentionSpots = <FlSpot>[];
    final perclosSpots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      attentionSpots.add(FlSpot(i.toDouble(), data[i].attention.clamp(0, 100)));
      perclosSpots.add(FlSpot(i.toDouble(), data[i].perclos.clamp(0, 1) * 100));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true, drawVerticalLine: false, horizontalInterval: 25,
          getDrawingHorizontalLine: (v) => FlLine(color: AppColors.textMuted.withValues(alpha:0.15), strokeWidth: 1),
        ),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface1,
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              '${s.y.toStringAsFixed(1)}',
              TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s.bar.color),
            )).toList(),
          ),
        ),
        minY: 0, maxY: 105,
        lineBarsData: [
          LineChartBarData(
            spots: attentionSpots, isCurved: true, curveSmoothness: 0.3,
            color: AppColors.focusedGreen, barWidth: 2, isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [AppColors.focusedGreen.withValues(alpha:0.2), AppColors.focusedGreen.withValues(alpha:0)],
              ),
            ),
          ),
          LineChartBarData(
            spots: perclosSpots, isCurved: true, curveSmoothness: 0.3,
            color: AppColors.alertRed, barWidth: 2, isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [AppColors.alertRed.withValues(alpha:0.15), AppColors.alertRed.withValues(alpha:0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Data models ────────────────────────────────────────────────────────────

class _TelemetryPoint {
  final DateTime time;
  final double attention;
  final double perclos;
  _TelemetryPoint({required this.time, required this.attention, required this.perclos});
}

class _LogEntry {
  final DateTime time;
  final String type;
  final int severity;
  _LogEntry({required this.time, required this.type, required this.severity});
}

// ─── KPI Card with optional sparkline ───────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title, required this.value, required this.subtitle,
    required this.icon, required this.accent,
    this.isAlert = false, this.sparkData, this.sparkColor,
  });
  final String title, value, subtitle;
  final IconData icon;
  final Color accent;
  final bool isAlert;
  final List<double>? sparkData;
  final Color? sparkColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
            Icon(icon, size: 16, color: AppColors.textSecondary),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: isAlert ? AppColors.alertRed : AppColors.textPrimary)),
          Text(subtitle, style: TextStyle(fontSize: 12, color: accent)),
          // Mini sparkline
          if (sparkData != null && sparkData!.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 24,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _SparklinePainter(data: sparkData!, color: sparkColor ?? accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Minimal sparkline painter — just a filled line, no axes.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.data, required this.color});
  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final maxVal = data.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final minVal = data.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).clamp(0.001, double.infinity);

    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Fill gradient
    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [color.withValues(alpha:0.15), color.withValues(alpha:0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    // Stroke
    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha:0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => !identical(old.data, data) || old.color != color;
}

// ─── Log Button ─────────────────────────────────────────────────────────────

class _LogButton extends StatelessWidget {
  const _LogButton({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(
      borderRadius: BorderRadius.circular(8), onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ])),
    ));
  }
}

// ─── Event Row ──────────────────────────────────────────────────────────────

class _EventRow extends StatelessWidget {
  const _EventRow({required this.time, required this.type, required this.severity});
  final String time, type;
  final int severity;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.severity(severity);
    final label = severity >= 4 ? 'Critical' : severity >= 2 ? 'Warning' : 'Info';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Text(time, style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: AppColors.textSecondary)),
        const SizedBox(width: 24),
        Expanded(child: Text(type, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w500))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ),
      ]),
    );
  }
}


// ─── Chart Empty State ─────────────────────────────────────────────────────

class _ChartEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x22444748)),
          ),
          child: const Icon(Icons.show_chart, size: 32, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        const Text('No telemetry data yet',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Text('Attention and PERCLOS will appear here\nas the session progresses.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.5)),
      ]),
    );
  }
}
