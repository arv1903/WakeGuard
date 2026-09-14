import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/services/monitoring_client.dart';
import 'package:driver_monitor/screens/mobile/mobile_post_trip_screen.dart';

class _FakePostTripClient extends MonitoringClient {
  _FakePostTripClient({
    required this.summary,
    this.telemetryRows = const [],
  }) : super(baseUrl: 'http://localhost:8765');

  final Map<String, dynamic>? summary;
  final List<Map<String, dynamic>> telemetryRows;

  @override
  Future<Map<String, dynamic>> fetchCurrentSummary() async {
    if (summary == null) throw Exception('backend unreachable');
    return summary!;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSessionTelemetry(
      String sessionId) async {
    return telemetryRows;
  }
}

Future<void> _pumpScreen(WidgetTester tester, MonitoringClient client) async {
  await tester.pumpWidget(MaterialApp(
    home: MobilePostTripScreen(client: client),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders real incidents from alerts_by_type, not the old fakes',
      (tester) async {
    final client = _FakePostTripClient(summary: {
      'session_id': 's1',
      'trip_duration_s': 1200.0,
      'avg_attention': 88.0,
      'alert_count': 3,
      'safety_score': 85.0,
      'alerts_by_type': {'DROWSINESS DETECTED!': 3},
      'alert_times': [14.0, 305.0, 901.0],
    }, telemetryRows: [
      {'ts': 0.0, 'attention': 90.0, 'perclos': 0.1},
      {'ts': 1.0, 'attention': 86.0, 'perclos': 0.2},
    ]);
    addTearDown(client.dispose);

    await _pumpScreen(tester, client);

    expect(find.text('Drowsiness'), findsOneWidget);
    expect(find.text('×3'), findsOneWidget);
    expect(find.text('DROWSINESS DETECTED!'), findsOneWidget);
    expect(find.text('First alert T+0:14'), findsOneWidget);

    // The old hardcoded fakes must never appear again.
    expect(find.textContaining('14:22'), findsNothing);
    expect(find.textContaining('15:05'), findsNothing);
    expect(find.text('Device usage detected in cabin.'), findsNothing);
    expect(find.text('Distraction'), findsNothing);
  });

  testWidgets('zero incidents renders an explicit empty state', (tester) async {
    final client = _FakePostTripClient(summary: {
      'session_id': 's2',
      'trip_duration_s': 300.0,
      'avg_attention': 95.0,
      'alert_count': 0,
      'safety_score': 95.0,
      'alerts_by_type': <String, dynamic>{},
      'alert_times': [],
    });
    addTearDown(client.dispose);

    await _pumpScreen(tester, client);

    expect(find.text('No incidents recorded.'), findsOneWidget);
    expect(find.text('Drowsiness'), findsNothing);
  });

  testWidgets('empty telemetry shows honest unavailable state, not a fake line',
      (tester) async {
    final client = _FakePostTripClient(summary: {
      'session_id': 's3',
      'trip_duration_s': 60.0,
      'avg_attention': 90.0,
      'alert_count': 0,
      'safety_score': 90.0,
      'alerts_by_type': <String, dynamic>{},
    });
    addTearDown(client.dispose);

    await _pumpScreen(tester, client);

    expect(find.text('Telemetry unavailable for this trip'), findsOneWidget);
  });

  testWidgets('displays backend safety score with shared grade label',
      (tester) async {
    final client = _FakePostTripClient(summary: {
      'session_id': 's4',
      'trip_duration_s': 60.0,
      'avg_attention': 95.0,
      'alert_count': 0,
      'safety_score': 85.0,
      'alerts_by_type': <String, dynamic>{},
    }, telemetryRows: [
      {'ts': 0.0, 'attention': 95.0, 'perclos': 0.0},
    ]);
    addTearDown(client.dispose);

    await _pumpScreen(tester, client);

    expect(find.text('GOOD'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
    // Deterministic progress, not an indeterminate spinner.
    expect(find.byKey(const Key('grade-ring')), findsOneWidget);
  });

  testWidgets('backend failure surfaces error state with retry',
      (tester) async {
    final client = _FakePostTripClient(summary: null);
    addTearDown(client.dispose);

    await _pumpScreen(tester, client);

    expect(find.text('Unable to load summary'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
