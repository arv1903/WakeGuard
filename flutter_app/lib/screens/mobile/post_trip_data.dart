/// Pure data helpers for the mobile post-trip report.
///
/// Kept free of Flutter widgets so parsing, downsampling, and incident
/// classification can be unit-tested directly against real backend payload
/// shapes (see tests/post_trip_data_test.dart).

/// One real attention sample from `/api/v1/sessions/{id}/telemetry`.
class TripPoint {
  const TripPoint({required this.t, required this.attention});

  final double t; // seconds since trip start
  final double attention; // 0–100
}

class Incident {
  const Incident({
    required this.type,
    required this.description,
    required this.count,
  });

  /// Display bucket: 'Distraction', 'Fatigue', 'Drowsiness', or 'Alert'.
  final String type;

  /// Verbatim backend alert label, e.g. 'DROWSINESS DETECTED!'.
  final String description;
  final int count;
}

class IncidentSummary {
  const IncidentSummary({required this.incidents, required this.firstAlertAt});

  final List<Incident> incidents;

  /// Seconds into the trip when the first alert fired, if known.
  final double? firstAlertAt;
}

/// Parses backend telemetry rows (`{ts, attention, perclos}`) into sorted
/// points, dropping rows without numeric attention values.
List<TripPoint> parseTelemetry(List<dynamic> rows) {
  final points = <TripPoint>[];
  for (final row in rows) {
    if (row is! Map) continue;
    final att = row['attention'];
    final ts = row['ts'];
    if (att is! num || ts is! num) continue;
    points.add(TripPoint(t: ts.toDouble(), attention: att.toDouble()));
  }
  points.sort((a, b) => a.t.compareTo(b.t));
  return points;
}

/// Reduces points to at most [cap] samples, always keeping the first and
/// last so the chart's start and end state survive.
List<TripPoint> downsample(List<TripPoint> points, int cap) {
  if (points.length <= cap || cap < 2) return points;
  final stride = points.length / (cap - 1);
  final out = <TripPoint>[
    for (var i = 0; i < cap - 1; i++) points[(i * stride).floor()],
    points.last,
  ];
  return out;
}

/// Formats seconds as m:ss (or h:mm:ss past one hour).
String formatElapsed(num seconds) {
  if (seconds.isNaN || seconds.isInfinite || seconds < 0) return '0:00';
  final total = seconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Maps a verbatim backend alert label (yolo/config.py AlertMessages) to a
/// display bucket. Distraction is checked first so 'FACE LOST — POSSIBLE
/// MICROSLEEP!' counts as a distraction (face/focus event), not drowsiness.
String classifyIncident(String label) {
  final l = label.toUpperCase();
  if (l.contains('DISTRACTED') ||
      l.contains('WATCH ROAD') ||
      l.contains('HEAD AWAY') ||
      l.contains('FACE LOST')) {
    return 'Distraction';
  }
  if (l.contains('FATIGUE') ||
      l.contains('EYE CLOSURE') ||
      l.contains('LOW BLINK RATE')) {
    return 'Fatigue';
  }
  if (l.contains('MICROSLEEP') ||
      l.contains('DROWSINESS') ||
      l.contains('HEAD NODDING')) {
    return 'Drowsiness';
  }
  return 'Alert';
}

/// Builds the incident list from the summary payload's `alerts_by_type` and
/// `alert_times`. One row per alert label (bucketed), highest count first.
/// `alert_times` cannot be attributed to individual labels by the backend,
/// so only the trip-wide first-alert time is exposed — never per-row times.
IncidentSummary summarizeIncidents(Map<String, dynamic> summary) {
  final byType = summary['alerts_by_type'];
  final incidents = <Incident>[];
  if (byType is Map) {
    byType.forEach((key, value) {
      final count = value is num ? value.toInt() : 0;
      if (count <= 0) return;
      final label = key.toString();
      incidents.add(Incident(
        type: classifyIncident(label),
        description: label,
        count: count,
      ));
    });
  }
  incidents.sort((a, b) => b.count.compareTo(a.count));

  final times = summary['alert_times'];
  double? firstAt;
  if (times is List) {
    final numeric = times.whereType<num>().toList();
    if (numeric.isNotEmpty) {
      firstAt = numeric.reduce((a, b) => a < b ? a : b).toDouble();
    }
  }
  return IncidentSummary(incidents: incidents, firstAlertAt: firstAt);
}
