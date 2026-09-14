import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_monitor/screens/live_monitor_screen.dart';

void main() {
  group('StartupCountdownOverlay', () {
    testWidgets('shows the ceiling digit and get-ready label',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StartupCountdownOverlay(countdown: 2.4),
        ),
      ));

      expect(find.text('GET READY'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('shows 1 for a fraction under one second', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StartupCountdownOverlay(countdown: 0.2),
        ),
      ));

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('digit animates when the countdown ticks down',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StartupCountdownOverlay(countdown: 3.0),
        ),
      ));
      expect(find.text('3'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StartupCountdownOverlay(countdown: 2.0),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
    });
  });
}