import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:driver_monitor/screens/mobile/connection_setup_screen.dart';
import 'package:driver_monitor/screens/pairing_scanner_screen.dart';
import 'package:driver_monitor/services/auth_service.dart';
import 'package:driver_monitor/services/connection_service.dart';
import 'package:driver_monitor/services/discovery_client.dart';
import 'package:driver_monitor/services/monitoring_client.dart';
import 'package:driver_monitor/services/pairing_scanner_controller.dart';

class _StubDiscovery extends DiscoveryClient {
  @override
  Future<List<DiscoveredBackend>> discover() async => const [];
}

class _FakeConnectionService extends ConnectionService {
  _FakeConnectionService(MonitoringClient client) : super(client: client);

  final connectedUrls = <String>[];
  final exchangedCodes = <String>[];
  Object? exchangeError;

  @override
  Future<void> connectTo(String url, {String? manualToken}) async {
    connectedUrls.add(url);
  }

  @override
  Future<void> completePairing(String code) async {
    exchangedCodes.add(code);
    if (exchangeError != null) throw exchangeError!;
  }
}

const _validQr =
    '{"v":1,"code":"AB12CD34","host":"192.168.1.50","port":8765}';

Future<void> _pumpSetup(
  WidgetTester tester,
  _FakeConnectionService cs, {
  void Function(BuildContext)? onScanQr,
}) async {
  onScanQr ??= (_) {};
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(MaterialApp(
    home: ConnectionSetupScreen(
      connectionService: cs,
      authService: AuthService(),
      discoveryClient: _StubDiscovery(),
      onScanQr: onScanQr,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('setup screen offers a Scan QR Code entry', (tester) async {
    final cs = _FakeConnectionService(MonitoringClient(baseUrl: 'http://x:1'));
    await _pumpSetup(tester, cs);

    expect(find.text('Scan QR Code'), findsOneWidget);
  });

  testWidgets('scanning a valid QR connects and exchanges the code',
      (tester) async {
    final cs = _FakeConnectionService(MonitoringClient(baseUrl: 'http://x:1'));
    final controller = PairingScannerController();
    await _pumpSetup(tester, cs, onScanQr: (ctx) {
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => PairingScannerScreen(
            connectionService: cs,
            controller: controller,
          ),
        ),
      );
    });

    await tester.tap(find.text('Scan QR Code'));
    await tester.pumpAndSettle();
    expect(find.text('Scan Pairing QR'), findsOneWidget);

    // Simulate the camera delivering the QR payload.
    controller.handleRawPayload(_validQr);
    await tester.pump(const Duration(milliseconds: 50));

    expect(cs.connectedUrls, ['http://192.168.1.50:8765']);
    expect(cs.exchangedCodes, ['AB12CD34']);
    // Success pops back to setup; pump past the 300ms route transition.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Scan Pairing QR'), findsNothing);
  });

  testWidgets('an unrelated QR shows an error and stays put', (tester) async {
    final cs = _FakeConnectionService(MonitoringClient(baseUrl: 'http://x:1'));
    final controller = PairingScannerController();
    await _pumpSetup(tester, cs, onScanQr: (ctx) {
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => PairingScannerScreen(
            connectionService: cs,
            controller: controller,
          ),
        ),
      );
    });

    await tester.tap(find.text('Scan QR Code'));
    await tester.pumpAndSettle();

    controller.handleRawPayload('{"v":2,"code":"X","host":"h","port":1}');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Not a WakeGuard QR code'), findsOneWidget);
    expect(cs.exchangedCodes, isEmpty);
    expect(find.text('Scan Pairing QR'), findsOneWidget);
  });

  testWidgets('a failed exchange surfaces the error on the scanner',
      (tester) async {
    final cs = _FakeConnectionService(MonitoringClient(baseUrl: 'http://x:1'));
    cs.exchangeError = Exception('invalid pairing code');
    final controller = PairingScannerController();
    await _pumpSetup(tester, cs, onScanQr: (ctx) {
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => PairingScannerScreen(
            connectionService: cs,
            controller: controller,
          ),
        ),
      );
    });

    await tester.tap(find.text('Scan QR Code'));
    await tester.pumpAndSettle();

    controller.handleRawPayload(_validQr);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('invalid pairing code'), findsOneWidget);
    expect(find.text('Scan Pairing QR'), findsOneWidget);
  });
}
