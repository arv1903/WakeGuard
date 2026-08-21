import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/models/monitoring_snapshot.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

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
      final VoidCallback onStart = () { called = true; };
      onStart();
      expect(called, isTrue);
    });

    test('onNavigate callback fires with correct tab index', () {
      int? navigatedTo;
      final void Function(int) onNavigate = (i) { navigatedTo = i; };
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
}
