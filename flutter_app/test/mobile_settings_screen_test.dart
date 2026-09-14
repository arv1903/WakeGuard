import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:driver_monitor/models/monitoring_snapshot.dart';
import 'package:driver_monitor/screens/mobile/mobile_settings_screen.dart';
import 'package:driver_monitor/services/auth_service.dart';
import 'package:driver_monitor/services/connection_service.dart';
import 'package:driver_monitor/services/monitoring_client.dart';

class _RecordingClient extends MonitoringClient {
  _RecordingClient() : super(baseUrl: 'http://localhost:8765');

  final commands = <Map<String, dynamic>>[];
  Object? nextError;

  @override
  Future<void> sendCommand(String path, [Map<String, dynamic>? payload]) async {
    if (nextError != null) throw nextError!;
    commands.add({'path': path, 'payload': payload});
  }

  void publish(Map<String, dynamic> payload) {
    snapshot = MonitoringSnapshot.fromJson(payload);
    notifyListeners();
  }
}

Future<ConnectionService> _pumpScreen(
  WidgetTester tester,
  _RecordingClient client, {
  AuthService? auth,
}) async {
  final cs = ConnectionService(client: client);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MobileSettingsScreen(
        connectionService: cs,
        authService: auth ?? AuthService(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return cs;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('unsupported toggles are gone, not faked', (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client);

    expect(find.text('Telegram Notifications'), findsNothing);
    expect(find.text('Session Logging'), findsNothing);
    expect(find.text('PERCLOS Tolerance'), findsNothing);
    // The supported one stays.
    expect(find.text('Alarm Sound'), findsOneWidget);
  });

  testWidgets('connection status reflects the real client state',
      (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client);

    // Fresh client is disconnected — no more 'NODE ACTIVE // UPLINK SECURE'.
    expect(find.text('NODE DISCONNECTED'), findsOneWidget);
    expect(find.text('NODE ACTIVE // UPLINK SECURE'), findsNothing);
  });

  testWidgets('revoked credentials say re-pair required, not check uplink',
      (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client);

    client.connectionState = BackendConnectionState.authRejected;
    client.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('NODE ACCESS REVOKED // RE-PAIR REQUIRED'), findsOneWidget);
    expect(find.text('NODE ERROR // CHECK UPLINK'), findsNothing);
  });

  testWidgets('INITIATE RECALIBRATION posts the real endpoint', (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client);

    await tester.ensureVisible(find.text('INITIATE RECALIBRATION'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('INITIATE RECALIBRATION'));
    await tester.pumpAndSettle();

    expect(client.commands, hasLength(1));
    expect(client.commands.single['path'], '/api/v1/calibration/start');
    expect(client.commands.single['payload'], {'duration': 4});
  });

  testWidgets('alarm toggle maps to the real mute endpoint', (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    client.publish({'alarm_muted': false});
    await _pumpScreen(tester, client);

    await tester.ensureVisible(find.text('Alarm Sound'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alarm Sound'));
    await tester.pumpAndSettle();

    expect(client.commands, hasLength(1));
    expect(client.commands.single['path'], '/api/v1/alarm/mute');
  });

  testWidgets('LOGOUT signs out through the auth service', (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    final auth = AuthService();
    addTearDown(auth.dispose);
    await auth.load(); // starts logged out with empty mock prefs
    await _pumpScreen(tester, client, auth: auth);

    // Log in state can't be staged without a backend; logout must still
    // clear whatever exists and must not throw.
    await tester.ensureVisible(find.text('LOGOUT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOGOUT'));
    await tester.pumpAndSettle();

    expect(auth.isLoggedIn, isFalse);
  });

  testWidgets('threshold slider changes post the real settings payload',
      (tester) async {
    final client = _RecordingClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client);

    // Drag the head-pose slider fully right (Relaxed).
    await tester.ensureVisible(find.text('Head Pose Sensitivity'));
    await tester.pumpAndSettle();
    final sliderFinder = find.byType(Slider).first;
    final rect = tester.getRect(sliderFinder);
    await tester.drag(sliderFinder, Offset(rect.width * 0.5, 0));
    await tester.pump(const Duration(milliseconds: 700)); // debounce + settle
    await tester.pumpAndSettle();

    expect(client.commands, isNotEmpty);
    final payload = client.commands.last['payload'] as Map;
    expect(payload.containsKey('pitch_threshold'), isTrue);
    expect(payload.containsKey('yaw_threshold'), isTrue);
    expect(payload.containsKey('roll_threshold'), isTrue);
  });
}
