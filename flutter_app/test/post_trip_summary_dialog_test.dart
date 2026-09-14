import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_monitor/screens/post_trip_summary_dialog.dart';

Future<void> _pumpDialog(
    WidgetTester tester, Map<String, dynamic> summary) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PostTripSummaryDialog(summary: summary),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the backend safety score and numeric value',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpDialog(tester, {
      'trip_duration_s': 90.0,
      'avg_attention': 92.0,
      'alert_count': 1,
      'safety_score': 85.0,
      'avg_blinks_per_min': 14.0,
    });

    expect(find.text('85'), findsOneWidget);
    expect(find.text('SCORE'), findsOneWidget);
  });

  testWidgets('missing safety score renders a placeholder, not an invented 100',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpDialog(tester, {
      'trip_duration_s': 90.0,
      'avg_attention': 92.0,
      'alert_count': 0,
      'avg_blinks_per_min': 14.0,
    });

    expect(find.text('—'), findsOneWidget);
    expect(find.text('100'), findsNothing);
  });
}
