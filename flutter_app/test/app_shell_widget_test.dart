import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/models/monitoring_snapshot.dart';
import 'package:driver_monitor/screens/calibration_settings_screen.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

class _RecordingClient extends MonitoringClient {
  _RecordingClient() : super(baseUrl: 'http://localhost:8765');

  final commands = <Map<String, dynamic>>[];

  @override
  Future<void> sendCommand(String path, [Map<String, dynamic>? payload]) async {
    commands.add({'path': path, 'payload': payload});
  }

  void publish(Map<String, dynamic> payload) {
    snapshot = MonitoringSnapshot.fromJson(payload);
    notifyListeners();
  }
}

void main() {
  group('AppShell smoke', () {
    test('MonitoringClient can be instantiated', () {
      final client = MonitoringClient(baseUrl: 'http://localhost:8765');
      expect(client.baseUrl, 'http://localhost:8765');
      expect(client.connectionState, BackendConnectionState.disconnected);
      client.dispose();
    });

    test('HomeScreen onStartSession callback fires', () {
      var called = false;
      final VoidCallback onStart = () {
        called = true;
      };
      onStart();
      expect(called, isTrue);
    });

    test('onNavigate callback fires with correct tab index', () {
      int? navigatedTo;
      final void Function(int) onNavigate = (i) {
        navigatedTo = i;
      };
      onNavigate(2);
      expect(navigatedTo, 2);
    });

    test('MonitoringSnapshot.fromJson produces valid status', () {
      final snap = MonitoringSnapshot.fromJson({
        'alert_severity': 4,
        'alert': 'MICROSLEEP',
      });
      expect(snap.status, 'Critical');
    });
  });

  testWidgets('reset to defaults restores Balanced preset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _RecordingClient();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CalibrationSettingsScreen(client: client)),
    ));
    await tester.pumpAndSettle();

    // Tap the Alert preset
    final beforeCount = client.commands.length;
    await tester.tap(find.text('Alert'));
    await tester.pumpAndSettle();

    // Verify Alert preset sent 5 settings commands
    final alertCommands = client.commands.sublist(beforeCount);
    expect(alertCommands.length, 5);
    expect(
        alertCommands.any((c) =>
            c['payload'] != null &&
            (c['payload'] as Map).containsKey('ear_threshold')),
        isTrue);

    // Tap Reset to Defaults
    final beforeResetCount = client.commands.length;
    await tester.tap(find.text('Reset to Defaults'));
    await tester.pumpAndSettle();

    // Verify reset sent Balanced preset values
    final resetCommands = client.commands.sublist(beforeResetCount);
    expect(resetCommands.isNotEmpty, isTrue);
    expect(
        resetCommands.any((c) =>
            c['payload'] != null &&
            (c['payload'] as Map)['ear_threshold'] == 0.20),
        isTrue);
    client.dispose();
  });

  testWidgets('calibration progress follows running backend snapshots',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _RecordingClient();
    client.publish({
      'calibration_state': 'running',
      'calibration_progress': 0.25,
      'calibration_valid_samples': 4,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CalibrationSettingsScreen(client: client)),
    ));
    await tester.pump();
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('4 samples'), findsOneWidget);

    client.publish({
      'calibration_state': 'running',
      'calibration_progress': 0.6,
      'calibration_valid_samples': 12,
    });
    await tester.pump();
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('12 samples'), findsOneWidget);
    expect(find.text('Calibration completed successfully'), findsNothing);
    client.dispose();
  });
}
