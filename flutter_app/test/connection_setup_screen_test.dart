import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:driver_monitor/screens/mobile/connection_setup_screen.dart';
import 'package:driver_monitor/services/auth_service.dart';
import 'package:driver_monitor/services/connection_service.dart';
import 'package:driver_monitor/services/discovery_client.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

class _StubDiscovery extends DiscoveryClient {
  _StubDiscovery(this.results);
  final List<DiscoveredBackend> results;

  @override
  Future<List<DiscoveredBackend>> discover() async => results;
}

DiscoveredBackend _backend() => DiscoveredBackend(
      host: '192.168.1.50',
      port: 8765,
      deviceName: 'DESKTOP-AB12',
      platform: 'windows',
    );

Future<void> _pumpSetup(WidgetTester tester, DiscoveryClient discovery) async {
  SharedPreferences.setMockInitialValues({});
  final client = MonitoringClient(baseUrl: 'http://127.0.0.1:8765');
  final cs = ConnectionService(client: client);
  await cs.load();
  await tester.pumpWidget(MaterialApp(
    home: ConnectionSetupScreen(
      connectionService: cs,
      authService: AuthService(),
      discoveryClient: discovery,
    ),
  ));
}

void main() {
  testWidgets('auto-probes on open and shows the found desktop',
      (tester) async {
    await _pumpSetup(tester, _StubDiscovery([_backend()]));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('FOUND ON THIS WI-FI'), findsOneWidget);
    expect(find.text('DESKTOP-AB12'), findsOneWidget);
    expect(find.text('http://192.168.1.50:8765'), findsOneWidget);
    // The manual IP field stays out of the way when discovery succeeded.
    expect(find.text('BACKEND SERVER'), findsNothing);
  });

  testWidgets('shows searching state before the probe completes',
      (tester) async {
    await _pumpSetup(tester, _StubDiscovery([_backend()]));
    // First pump builds; probe result hasn't landed yet.
    expect(find.text('SEARCHING FOR DESKTOP'), findsOneWidget);
    expect(find.text('BACKEND SERVER'), findsNothing);

    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('SEARCHING FOR DESKTOP'), findsNothing);
    expect(find.text('FOUND ON THIS WI-FI'), findsOneWidget);
  });

  testWidgets('falls back to manual entry when nothing is found',
      (tester) async {
    await _pumpSetup(tester, _StubDiscovery(const []));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('BACKEND SERVER'), findsOneWidget);
    expect(find.text('FOUND ON THIS WI-FI'), findsNothing);
    // Honest hint about why nothing was found.
    expect(find.textContaining('not found automatically'), findsOneWidget);
  });

  testWidgets('adopting the found desktop fills the backend URL',
      (tester) async {
    await _pumpSetup(tester, _StubDiscovery([_backend()]));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('DESKTOP-AB12'));
    await tester.pump(const Duration(milliseconds: 50));

    // Reveal the manual entry — the adopted URL must be in the field.
    await tester.ensureVisible(find.text('Manual Configuration Link'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Manual Configuration Link'));
    await tester.pump(const Duration(milliseconds: 50));

    // Some TextField on screen must now carry the adopted URL (the backend
    // URL field — the same controller _login reads).
    final field = tester.widget<TextField>(find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == 'http://192.168.1.50:8765',
    ));
    expect(field, isNotNull);
  });

  testWidgets('probe errors degrade to manual entry, never a crash',
      (tester) async {
    await _pumpSetup(tester, _ThrowingDiscovery());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('BACKEND SERVER'), findsOneWidget);
    expect(find.text('FOUND ON THIS WI-FI'), findsNothing);
  });
}

class _ThrowingDiscovery extends DiscoveryClient {
  @override
  Future<List<DiscoveredBackend>> discover() async {
    throw const SocketException('network unreachable');
  }
}
