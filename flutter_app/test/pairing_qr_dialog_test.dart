import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:driver_monitor/screens/pairing_qr_dialog.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

class _StubClient extends MonitoringClient {
  _StubClient() : super(baseUrl: 'http://127.0.0.1:8765');

  Object? fetchError;
  int fetchCalls = 0;
  Map<String, dynamic> Function() pairingResponse = () => {
        'code': 'AB12CD34',
        'expires_at': DateTime.now().millisecondsSinceEpoch / 1000 + 120,
        'pairing_uri': 'driver-monitor://pair?code=AB12CD34',
      };

  @override
  Future<Map<String, dynamic>> fetchPairing() async {
    fetchCalls++;
    if (fetchError != null) throw fetchError!;
    return pairingResponse();
  }
}

Future<void> _pumpDialog(WidgetTester tester, _StubClient client) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: PairingQrDialog(client: client)),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('renders a QR from the live pairing code', (tester) async {
    final client = _StubClient();
    await _pumpDialog(tester, client);

    expect(client.fetchCalls, 1);
    expect(find.text('AB12CD34'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('shows a countdown derived from expires_at', (tester) async {
    final client = _StubClient();
    client.pairingResponse = () => {
          'code': 'AB12CD34',
          'expires_at': DateTime.now().millisecondsSinceEpoch / 1000 + 60,
        };
    await _pumpDialog(tester, client);

    expect(find.textContaining('EXPIRES IN'), findsOneWidget);
  });

  testWidgets('omits the countdown when the backend gives no expiry',
      (tester) async {
    final client = _StubClient();
    client.pairingResponse = () => {'code': 'AB12CD34'};
    await _pumpDialog(tester, client);

    expect(find.text('AB12CD34'), findsOneWidget);
    expect(find.textContaining('EXPIRES IN'), findsNothing);
  });

  testWidgets('refresh fetches a fresh code', (tester) async {
    final client = _StubClient();
    await _pumpDialog(tester, client);

    await tester.tap(find.text('REFRESH'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(client.fetchCalls, 2);
  });

  testWidgets('fetch failure shows retry, never a crash', (tester) async {
    final client = _StubClient();
    client.fetchError = const HttpException('backend down');
    await _pumpDialog(tester, client);

    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('RETRY'), findsOneWidget);

    // Retry succeeds when the backend comes back.
    client.fetchError = null;
    await tester.tap(find.text('RETRY'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(QrImageView), findsOneWidget);
  });
}
