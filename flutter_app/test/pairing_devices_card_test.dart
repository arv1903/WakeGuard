import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/screens/pairing_devices_card.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

class _StubClient extends MonitoringClient {
  _StubClient() : super(baseUrl: 'http://127.0.0.1:8765');

  Object? listError;
  int listCalls = 0;
  final revokedPreviews = <String>[];
  List<PairingDevice> devices = [
    PairingDevice(
      tokenPreview: 'AB12CD34',
      deviceName: "Marvin's Phone",
      issuedAt: DateTime.now().subtract(const Duration(hours: 2)),
      expiresAt: DateTime.now().add(const Duration(hours: 22)),
    ),
    PairingDevice(
      tokenPreview: 'ZZ99YY88',
      deviceName: '',
      issuedAt: DateTime.now().subtract(const Duration(hours: 25)),
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  ];

  @override
  Future<List<PairingDevice>> listPairings() async {
    listCalls++;
    if (listError != null) throw listError!;
    return List<PairingDevice>.of(devices);
  }

  @override
  Future<bool> revokePairing(String tokenPreview) async {
    revokedPreviews.add(tokenPreview);
    devices.removeWhere((d) => d.tokenPreview == tokenPreview);
    return true;
  }
}

Future<void> _pumpCard(WidgetTester tester, _StubClient client) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: PairingDevicesCard(
      client: client,
      onShowQr: () {},
    ))),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('lists paired devices with name and remaining time',
      (tester) async {
    final client = _StubClient();
    await _pumpCard(tester, client);

    expect(find.text("Marvin's Phone"), findsOneWidget);
    // Time remaining shows hours (not yet expired, no negative numbers).
    expect(find.textContaining(RegExp(r'2\d?h \d+m left')), findsOneWidget);
    // Unnamed devices are labeled, not blank.
    expect(find.text('Unknown'), findsOneWidget);
    // Expired devices say so, not a negative countdown.
    expect(find.textContaining('EXPIRED'), findsOneWidget);
  });

  testWidgets('revoking removes the device and hits the right preview',
      (tester) async {
    final client = _StubClient();
    await _pumpCard(tester, client);

    // Revoke the first device by tapping its row's delete control.
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump(const Duration(milliseconds: 50));

    expect(client.revokedPreviews, ['AB12CD34']);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text("Marvin's Phone"), findsNothing);
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('shows an honest empty state', (tester) async {
    final client = _StubClient();
    client.devices = [];
    await _pumpCard(tester, client);

    expect(find.textContaining('No paired devices'), findsOneWidget);
  });

  testWidgets('fetch failure offers retry', (tester) async {
    final client = _StubClient();
    client.listError = const HttpException('backend down');
    await _pumpCard(tester, client);

    expect(find.text('RETRY'), findsOneWidget);

    client.listError = null;
    await tester.tap(find.text('RETRY'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text("Marvin's Phone"), findsOneWidget);
  });
}
