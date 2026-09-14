import 'package:flutter_test/flutter_test.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

void main() {
  group('MonitoringClient URL handling', () {
    test('cleanBaseUrl trims trailing slash', () {
      final client = MonitoringClient(baseUrl: 'http://localhost:8765/');
      expect(client.baseUrl, 'http://localhost:8765');
    });

    test('cleanBaseUrl preserves URL without trailing slash', () {
      final client = MonitoringClient(baseUrl: 'http://localhost:8765');
      expect(client.baseUrl, 'http://localhost:8765');
    });

    test('cleanBaseUrl defaults to localhost when empty', () {
      final client = MonitoringClient(baseUrl: '');
      expect(client.baseUrl, 'http://127.0.0.1:8765');
    });

    test('cleanBaseUrl trims whitespace', () {
      final client = MonitoringClient(baseUrl: '  http://myhost:9000  ');
      expect(client.baseUrl, 'http://myhost:9000');
    });

    test('configure updates baseUrl and resets state', () {
      final client = MonitoringClient(baseUrl: 'http://old:8765');
      client.configure(baseUrl: 'http://new:9999');
      expect(client.baseUrl, 'http://new:9999');
    });
  });

  group('MonitoringClient initial state', () {
    test('starts disconnected', () {
      final client = MonitoringClient(baseUrl: 'http://localhost:8765');
      expect(client.connectionState, BackendConnectionState.disconnected);
      expect(client.snapshot.sequence, 0);
      expect(client.errorMessage, isNull);
      expect(client.lastUpdate, isNull);
    });

    test('isStale returns true when never updated', () {
      final client = MonitoringClient(baseUrl: 'http://localhost:8765');
      expect(client.isStale, isTrue);
    });

    test('snapshot starts at initial', () {
      final client = MonitoringClient(baseUrl: 'http://localhost:8765');
      expect(client.snapshot.attention, 100.0);
      expect(client.snapshot.tripActive, false);
    });
  });

  group('BackendConnectionState', () {
    test('has all expected states', () {
      expect(BackendConnectionState.values.length, 5);
      expect(BackendConnectionState.disconnected, isNotNull);
      expect(BackendConnectionState.connecting, isNotNull);
      expect(BackendConnectionState.connected, isNotNull);
      expect(BackendConnectionState.error, isNotNull);
      expect(BackendConnectionState.authRejected, isNotNull);
    });
  });
}
