import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:driver_monitor/services/backend_recovery_service.dart';
import 'package:driver_monitor/services/connection_service.dart';
import 'package:driver_monitor/services/discovery_client.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

class _StubDiscovery extends DiscoveryClient {
  _StubDiscovery(this.results);
  final List<DiscoveredBackend> results;
  int calls = 0;

  @override
  Future<List<DiscoveredBackend>> discover() async {
    calls++;
    return results;
  }
}

DiscoveredBackend _backend(String host, {int port = 8765}) =>
    DiscoveredBackend(
      host: host,
      port: port,
      deviceName: 'DESKTOP',
      platform: 'windows',
    );

/// Records configure() calls on a real MonitoringClient.
class _RecordingClient extends MonitoringClient {
  _RecordingClient(String baseUrl) : super(baseUrl: baseUrl);

  final configuredUrls = <String>[];

  @override
  void configure({required String baseUrl, String? token}) {
    configuredUrls.add(baseUrl);
    super.configure(baseUrl: baseUrl, token: token);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('does not probe before the grace period elapses', () {
    fakeAsync((async) {
      final discovery = _StubDiscovery([_backend('192.168.1.99')]);
      final client = _RecordingClient('http://192.168.1.50:8765');
      final cs = ConnectionService(client: client);
      BackendRecoveryService? recovery;
      async.run((_) {
        () async {
          await cs.load();
          await cs.connectTo('http://192.168.1.50:8765',
              manualToken: 'pairing-token');
          recovery = BackendRecoveryService(
            connectionService: cs,
            discoveryClient: discovery,
          );
        }();
      });
      async.flushMicrotasks();

      recovery!.start();
      async.elapse(const Duration(minutes: 5));
      expect(discovery.calls, 0, reason: 'connected → not tracking');

      // Backend drops.
      client.connectionState = BackendConnectionState.disconnected;
      client.notifyListeners();

      // Still inside the 10s grace window (tick cadence is 1s).
      async.elapse(const Duration(seconds: 9));
      expect(discovery.calls, 0);

      async.elapse(const Duration(seconds: 3));
      expect(discovery.calls, 1);
    });
  });

  test('adopts the moved backend and preserves the bearer token', () {
    fakeAsync((async) {
      final discovery = _StubDiscovery([_backend('192.168.1.99')]);
      final client = _RecordingClient('http://192.168.1.50:8765');
      final cs = ConnectionService(client: client);
      BackendRecoveryService? recovery;
      async.run((_) {
        () async {
          await cs.load();
          await cs.connectTo('http://192.168.1.50:8765',
              manualToken: 'pairing-token');
          recovery = BackendRecoveryService(
            connectionService: cs,
            discoveryClient: discovery,
          );
        }();
      });
      async.flushMicrotasks();

      recovery!.start();
      client.connectionState = BackendConnectionState.disconnected;
      client.notifyListeners();
      async.elapse(const Duration(seconds: 12));

      // One configure from setup, one from the adoption — nothing else.
      expect(client.configuredUrls.length, 2);
      expect(client.configuredUrls.last, 'http://192.168.1.99:8765');
      expect(client.baseUrl, 'http://192.168.1.99:8765');
      // The pairing token must survive the move.
      expect(client.token, 'pairing-token');
    });
  });

  test('stays quiet when discovery finds the same URL', () {
    fakeAsync((async) {
      final discovery = _StubDiscovery([_backend('192.168.1.50')]);
      final client = _RecordingClient('http://192.168.1.50:8765');
      final cs = ConnectionService(client: client);
      BackendRecoveryService? recovery;
      async.run((_) {
        () async {
          await cs.load();
          await cs.connectTo('http://192.168.1.50:8765',
              manualToken: 'pairing-token');
          recovery = BackendRecoveryService(
            connectionService: cs,
            discoveryClient: discovery,
          );
        }();
      });
      async.flushMicrotasks();

      recovery!.start();
      client.connectionState = BackendConnectionState.disconnected;
      client.notifyListeners();
      async.elapse(const Duration(seconds: 12));

      expect(discovery.calls, 1);
      // Only the initial setup configure — no adoption happened.
      expect(client.configuredUrls.length, 1);
    });
  });

  test('backoff doubles between fruitless probes and is capped', () {
    fakeAsync((async) {
      final discovery = _StubDiscovery(const []);
      final client = _RecordingClient('http://192.168.1.50:8765');
      final cs = ConnectionService(client: client);
      BackendRecoveryService? recovery;
      async.run((_) {
        () async {
          await cs.load();
          await cs.connectTo('http://192.168.1.50:8765',
              manualToken: 'pairing-token');
          recovery = BackendRecoveryService(
            connectionService: cs,
            discoveryClient: discovery,
          );
        }();
      });
      async.flushMicrotasks();

      recovery!.start();
      client.connectionState = BackendConnectionState.disconnected;
      client.notifyListeners();

      // Probes at +10s, then +5s, +10s, +20s, +40s, capped 40s.
      async.elapse(const Duration(seconds: 11));
      expect(discovery.calls, 1);
      async.elapse(const Duration(seconds: 5));
      expect(discovery.calls, 2);
      async.elapse(const Duration(seconds: 10));
      expect(discovery.calls, 3);
      async.elapse(const Duration(seconds: 20));
      expect(discovery.calls, 4);
      async.elapse(const Duration(seconds: 40));
      expect(discovery.calls, 5);
      // Cap: the next delay must still be 40s, not 80s.
      async.elapse(const Duration(seconds: 41));
      expect(discovery.calls, 6);
    });
  });

  test('a successful reconnect resets backoff and stops probing', () {
    fakeAsync((async) {
      final discovery = _StubDiscovery(const []);
      final client = _RecordingClient('http://192.168.1.50:8765');
      final cs = ConnectionService(client: client);
      BackendRecoveryService? recovery;
      async.run((_) {
        () async {
          await cs.load();
          await cs.connectTo('http://192.168.1.50:8765',
              manualToken: 'pairing-token');
          recovery = BackendRecoveryService(
            connectionService: cs,
            discoveryClient: discovery,
          );
        }();
      });
      async.flushMicrotasks();

      recovery!.start();
      client.connectionState = BackendConnectionState.disconnected;
      client.notifyListeners();
      async.elapse(const Duration(seconds: 12));
      expect(discovery.calls, 1);

      // Desktop came back at the same address.
      client.connectionState = BackendConnectionState.connected;
      client.notifyListeners();
      async.elapse(const Duration(minutes: 2));
      expect(discovery.calls, 1);
      expect(recovery!.attempts, 0);

      // A later drop starts from the base delay again, not the old backoff.
      client.connectionState = BackendConnectionState.disconnected;
      client.notifyListeners();
      async.elapse(const Duration(seconds: 11));
      expect(discovery.calls, 2);
    });
  });

  test('never probes when the guard says the user is not signed in', () {
    fakeAsync((async) {
      final discovery = _StubDiscovery([_backend('192.168.1.99')]);
      var signedIn = false;
      final client = _RecordingClient('http://192.168.1.50:8765');
      final cs = ConnectionService(client: client);
      BackendRecoveryService? recovery;
      async.run((_) {
        () async {
          await cs.load();
          recovery = BackendRecoveryService(
            connectionService: cs,
            discoveryClient: discovery,
            shouldRun: () => signedIn,
          );
        }();
      });
      async.flushMicrotasks();

      recovery!.start();
      client.connectionState = BackendConnectionState.disconnected;
      client.notifyListeners();
      async.elapse(const Duration(minutes: 10));
      expect(discovery.calls, 0);

      signedIn = true;
      client.notifyListeners();
      async.elapse(const Duration(seconds: 12));
      expect(discovery.calls, 1);
    });
  });
}
