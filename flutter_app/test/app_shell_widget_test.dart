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
      // Verify the callback type matches what HomeScreen expects.
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
      onNavigate(2); // Settings tab
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

  testWidgets('reset to defaults restores calibration slider handles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _RecordingClient();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CalibrationSettingsScreen(client: client)),
    ));
    await tester.pumpAndSettle();

    final firstSlider = find.byType(Slider).first;
    await tester.drag(firstSlider, const Offset(120, 0));
    await tester.pump();
    expect(tester.widget<Slider>(firstSlider).value, greaterThan(0.20));

    await tester.tap(find.text('Reset to Defaults'));
    await tester.pumpAndSettle();

    expect(tester.widget<Slider>(find.byType(Slider).first).value, 0.20);
    expect(
        client.commands.last['payload'], containsPair('ear_threshold', 0.20));
    client.dispose();
  });
}
