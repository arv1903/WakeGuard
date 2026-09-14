import 'package:flutter_test/flutter_test.dart';
import 'package:driver_monitor/screens/mobile/post_trip_data.dart';

void main() {
  group('parseTelemetry', () {
    test('parses backend telemetry rows into points sorted by time', () {
      final points = parseTelemetry([
        {'ts': 2.0, 'attention': 80.0, 'perclos': 0.1},
        {'ts': 0.0, 'attention': 90.0, 'perclos': 0.0},
        {'ts': 1.0, 'attention': 85.0, 'perclos': 0.05},
      ]);
      expect(points.length, 3);
      expect(points.map((p) => p.t).toList(), [0.0, 1.0, 2.0]);
      expect(points.map((p) => p.attention).toList(), [90.0, 85.0, 80.0]);
    });

    test('drops rows without numeric attention values', () {
      final points = parseTelemetry([
        {'ts': 0.0, 'attention': 90.0},
        {'ts': 1.0, 'attention': null},
        {'ts': 2.0},
      ]);
      expect(points.length, 1);
    });

    test('returns empty list for empty or null input', () {
      expect(parseTelemetry([]), isEmpty);
      expect(parseTelemetry([{}, {}]), isEmpty);
    });
  });

  group('downsample', () {
    test('keeps all points when under the cap', () {
      final points = List.generate(
          50, (i) => TripPoint(t: i.toDouble(), attention: 80.0 + i));
      final out = downsample(points, 60);
      expect(out.length, 50);
    });

    test('reduces to the cap and keeps first and last points', () {
      final points = List.generate(
          300, (i) => TripPoint(t: i.toDouble(), attention: 80.0));
      final out = downsample(points, 60);
      expect(out.length, 60);
      expect(out.last.t, 299); // final state must survive downsampling
      expect(out.first.t, 0); // so must the first
    });

    test('empty input stays empty', () {
      expect(downsample([], 60), isEmpty);
    });
  });

  group('formatElapsed', () {
    test('formats minutes and seconds under an hour', () {
      expect(formatElapsed(0), '0:00');
      expect(formatElapsed(59.4), '0:59');
      expect(formatElapsed(862), '14:22');
      expect(formatElapsed(3599), '59:59');
    });

    test('formats hours once past one hour', () {
      expect(formatElapsed(3600), '1:00:00');
      expect(formatElapsed(5405), '1:30:05');
    });

    test('negative and non-finite values clamp to zero', () {
      expect(formatElapsed(-5), '0:00');
      expect(formatElapsed(double.nan), '0:00');
    });
  });

  group('summarizeIncidents', () {
    // Backend alert labels come from yolo/config.py AlertMessages; the
    // classification below must follow the real strings, not invented ones.
    test('classifies real backend alert labels into buckets', () {
      final result = summarizeIncidents({
        'alerts_by_type': {
          'DROWSINESS DETECTED!': 3,
          'DISTRACTED - WATCH ROAD!': 1,
        },
        'alert_times': [14.0, 22.0, 305.0, 901.0],
      });
      expect(result.incidents.length, 2);
      expect(result.incidents[0].type, 'Drowsiness');
      expect(result.incidents[0].count, 3);
      expect(result.incidents[0].description, 'DROWSINESS DETECTED!');
      expect(result.incidents[1].type, 'Distraction');
      expect(result.incidents[1].count, 1);
      expect(result.firstAlertAt, 14.0);
    });

    test('groups related labels into the same bucket', () {
      final result = summarizeIncidents({
        'alerts_by_type': {
          'MICROSLEEP - EYES CLOSED! WAKE UP!': 1,
          'FATIGUE DETECTED - SUSTAINED EYE CLOSURE!': 2,
          'FACE LOST — POSSIBLE MICROSLEEP!': 1,
          'LOW BLINK RATE - TAKE A BREAK!': 4,
        },
      });
      final drowsy = result.incidents
          .where((i) => i.type == 'Drowsiness')
          .fold<int>(0, (sum, i) => sum + i.count);
      final distraction = result.incidents
          .where((i) => i.type == 'Distraction')
          .fold<int>(0, (sum, i) => sum + i.count);
      final fatigue = result.incidents
          .where((i) => i.type == 'Fatigue')
          .fold<int>(0, (sum, i) => sum + i.count);
      expect(drowsy, 1); // MICROSLEEP
      expect(distraction, 1); // FACE LOST
      expect(fatigue, 6); // FATIGUE 2 + LOW BLINK RATE 4
    });

    test('firstAlertAt omitted when alert_times absent or empty', () {
      expect(summarizeIncidents({
        'alerts_by_type': {'DROWSINESS DETECTED!': 2},
      }).firstAlertAt, isNull);
      expect(summarizeIncidents({
        'alerts_by_type': {'DROWSINESS DETECTED!': 2},
        'alert_times': <double>[],
      }).firstAlertAt, isNull);
    });

    test('no alerts yields empty result', () {
      final result = summarizeIncidents({});
      expect(result.incidents, isEmpty);
      expect(result.firstAlertAt, isNull);
    });

    test('unknown label falls back to generic Alert bucket', () {
      final result = summarizeIncidents({
        'alerts_by_type': {'MYSTERY ALERT': 1},
      });
      expect(result.incidents.single.type, 'Alert');
    });
  });
}
