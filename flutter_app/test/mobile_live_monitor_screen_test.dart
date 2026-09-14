import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/models/monitoring_snapshot.dart';
import 'package:driver_monitor/services/monitoring_client.dart';
import 'package:driver_monitor/screens/mobile/mobile_live_monitor_screen.dart';

class _RecordingClient extends MonitoringClient {
  _RecordingClient() : super(baseUrl: 'http://localhost:8765');

  final commands = <Map<String, dynamic>>[];
  Object? nextError;

  @override
  Future<void> sendCommand(String path, [Map<String, dynamic>? payload]) async {
    if (nextError != null) throw nextError!;
    commands.add({'path': path, 'payload': payload});
  }

  void publish(Map<String, dynamic> payload) {
    snapshot = MonitoringSnapshot.fromJson(payload);
    notifyListeners();
  }
}

void main() {
  testWidgets('SENSOR FPS shows the live snapshot fps, not 30.0 LOCK',
      (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    client.publish({
      'trip_active': true,
      'attention': 88.0,
      'fps': 24.0,
    });
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MobileLiveMonitorScreen(client: client))));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('24.0'), findsOneWidget);
    expect(find.text('30.0'), findsNothing);
    expect(find.text('LOCK'), findsNothing);
  });

  testWidgets('SESSION T+ derives from snapshot tripStartedAt',
      (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    final started =
        DateTime.now().toUtc().millisecondsSinceEpoch / 1000 - 3725; // ~1h2m
    client.publish({
      'trip_active': true,
      'attention': 88.0,
      'fps': 30.0,
      'trip_started_at': started,
    });
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MobileLiveMonitorScreen(client: client))));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('01:02:'), findsOneWidget);
  });

  testWidgets('STOP SESSION posts the real stop endpoint', (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    client.publish({'trip_active': true, 'attention': 88.0, 'fps': 30.0});
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MobileLiveMonitorScreen(client: client))));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.text('STOP SESSION'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('STOP SESSION'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(client.commands, hasLength(1));
    expect(client.commands.single['path'], '/api/v1/session/stop');
  });

  testWidgets('stop failure surfaces a SnackBar instead of dying silently',
      (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    client.nextError = Exception('backend down');
    client.publish({'trip_active': true, 'attention': 88.0, 'fps': 30.0});
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MobileLiveMonitorScreen(client: client))));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.text('STOP SESSION'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('STOP SESSION'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Stop failed'), findsOneWidget);
    expect(client.commands, isEmpty); // command throws before recording
  });

  testWidgets('idle state shows standby, not a fake session', (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MobileLiveMonitorScreen(client: client))));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No Active Session'), findsOneWidget);
    expect(find.text('STOP SESSION'), findsNothing);
  });
}
