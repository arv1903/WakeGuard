import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:driver_monitor/screens/mobile/mobile_app_shell.dart';
import 'package:driver_monitor/screens/pairing_scanner_screen.dart';
import 'package:driver_monitor/services/auth_service.dart';
import 'package:driver_monitor/services/connection_service.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

/// Structural smoke tests over the real [MobileAppShell].
///
/// The QR-scan entry regression (shell built ConnectionSetupScreen without
/// `onScanQr`, hiding the scanner in production while screen-level tests
/// passed) is exactly what this suite guards: each shell state is pumped
/// through the real shell widget at a phone-sized viewport and its critical
/// UI surfaces are asserted.
void main() {
  late MonitoringClient client;
  late ConnectionService cs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = MonitoringClient(baseUrl: 'http://127.0.0.1:8765');
    cs = ConnectionService(client: client);
  });

  tearDown(() {
    client.dispose();
  });

  Future<void> pumpShell(WidgetTester tester) async {
    // Phone-sized viewport: the shell adds a header and bottom nav around
    // each screen, and the desktop-default 800x600 test surface starves
    // them (RenderFlex overflow in the live monitor).
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await cs.load(); // shell spins forever until isInitialised
    await tester.pumpWidget(MaterialApp(
      home: MobileAppShell(connectionService: cs, authService: AuthService()),
    ));
    // Let the setup screen build and the auto-discovery probe resolve.
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('unpaired: setup screen offers QR scan and manual entry',
      (tester) async {
    await pumpShell(tester);

    expect(find.text('WakeGuard'), findsOneWidget);
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(find.text('BACKEND SERVER'), findsOneWidget);
  });

  testWidgets('unpaired: tapping Scan QR Code opens the scanner',
      (tester) async {
    await pumpShell(tester);

    await tester.ensureVisible(find.text('Scan QR Code'));
    await tester.tap(find.text('Scan QR Code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PairingScannerScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // scanner timeout timer
  });

  testWidgets('paired: shell shows all three tabs', (tester) async {
    SharedPreferences.setMockInitialValues({
      'wg_backend_url': 'http://192.168.1.50:8765',
      'wg_bearer_token': 'pair-token',
    });
    cs = ConnectionService(client: client);
    await pumpShell(tester);

    expect(find.text('Monitor'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(PairingScannerScreen), findsNothing);
  });

  testWidgets('paired + signed out: returns to setup with scan entry intact',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'wg_backend_url': 'http://192.168.1.50:1',
      'wg_bearer_token': 'pair-token',
    });
    cs = ConnectionService(client: client);
    await pumpShell(tester);
    expect(find.text('Monitor'), findsWidgets);

    // Sign out — the shell must drop back to the setup screen, and that
    // screen must again offer every pairing path.
    await cs.forgetDevice();
    await tester.pump(const Duration(seconds: 3));
    // The setup screen mounts during the pump above, arming its discovery
    // timeout timer at the new fake time — one more pump fires it.
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('WakeGuard'), findsOneWidget);
    expect(find.text('Scan QR Code'), findsOneWidget);
  });

  testWidgets('expired pairing token: setup screen shows again',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'wg_backend_url': 'http://192.192.192.192:1',
      'wg_bearer_token': 'pair-token',
      'wg_token_expiry_ms': DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    });
    cs = ConnectionService(client: client);
    await pumpShell(tester);

    expect(find.text('WakeGuard'), findsOneWidget);
  });
}
