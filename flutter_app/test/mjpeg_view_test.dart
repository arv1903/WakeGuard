import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/services/monitoring_client.dart';
import 'package:driver_monitor/widgets/mjpeg_view.dart';

/// Test client whose frame bytes can be published directly.
class _StubClient extends MonitoringClient {
  _StubClient() : super(baseUrl: 'http://localhost:8765');

  final ValueNotifier<Uint8List?> frames = ValueNotifier<Uint8List?>(null);

  @override
  ValueListenable<Uint8List?> get latestFrameBytes => frames;
}

/// A valid 1x1 PNG. [ui.Image.toByteData] with PNG encoding never completes
/// in the flutter_tester environment, so tests publish pre-encoded bytes.
const String _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Uint8List _png1x1() => base64Decode(_png1x1Base64);

void main() {
  testWidgets('shows the connecting placeholder before the first frame',
      (tester) async {
    final client = _StubClient();
    addTearDown(client.dispose);

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MjpegView(client: client))));
    await tester.pump();

    expect(find.text('Connecting to camera...'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('renders the latest published frame', (tester) async {
    final client = _StubClient();
    addTearDown(client.dispose);

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MjpegView(client: client))));
    await tester.pump();

    // Image decoding is real engine async work: give it actual time via
    // runAsync (the idle placeholder animates forever, so pumpAndSettle
    // would hang).
    await tester.runAsync(() async {
      client.frames.value = _png1x1();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Connecting to camera...'), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('returns to the placeholder state cleanly across clients',
      (tester) async {
    final first = _StubClient();
    addTearDown(first.dispose);

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MjpegView(client: first))));
    await tester.pump();
    await tester.runAsync(() async {
      first.frames.value = _png1x1();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(RawImage), findsOneWidget);

    // A different client with no frames yet → placeholder again.
    final second = _StubClient();
    addTearDown(second.dispose);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MjpegView(client: second))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Connecting to camera...'), findsOneWidget);
  });
}
