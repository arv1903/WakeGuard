import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:driver_monitor/screens/mobile/mobile_app_shell.dart';
import 'package:driver_monitor/screens/pairing_scanner_screen.dart';
import 'package:driver_monitor/services/auth_service.dart';
import 'package:driver_monitor/services/connection_service.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

/// Regression test: the shell rendered [ConnectionSetupScreen] without
/// `onScanQr`, so the QR pairing entry was invisible in the real app even
/// though screen-level tests (which inject the handler) passed.
void main() {
  testWidgets('setup screen reached from the shell offers QR scanning',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MonitoringClient(baseUrl: 'http://127.0.0.1:8765');
    final cs = ConnectionService(client: client);
    await cs.load();

    await tester.pumpWidget(MaterialApp(
      home: MobileAppShell(connectionService: cs, authService: AuthService()),
    ));
    // Let the setup screen build and the auto-discovery probe resolve.
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Scan QR Code'), findsOneWidget);

    await tester.ensureVisible(find.text('Scan QR Code'));
    await tester.tap(find.text('Scan QR Code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PairingScannerScreen), findsOneWidget);
    // Burn the scanner's 1.5s detection-timeout timer so no timer is
    // pending when the test framework verifies invariants.
    await tester.pump(const Duration(seconds: 2));
  });
}
