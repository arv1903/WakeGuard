import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:driver_monitor/utils/gauge_math.dart';

void main() {
  group('gaugeSweepRadians', () {
    test('zero progress draws nothing (no negative sweep)', () {
      expect(gaugeSweepRadians(0.0), 0.0);
    });

    test('quarter progress draws exactly a quarter turn', () {
      expect(gaugeSweepRadians(0.25), closeTo(math.pi / 2, 1e-9));
    });

    test('full progress draws a full circle', () {
      expect(gaugeSweepRadians(1.0), closeTo(2 * math.pi, 1e-9));
    });

    test('values outside 0-1 are clamped', () {
      expect(gaugeSweepRadians(-0.5), 0.0);
      expect(gaugeSweepRadians(1.5), closeTo(2 * math.pi, 1e-9));
    });

    test('sweep starts from 12 oclock', () {
      expect(gaugeStartAngle, closeTo(-math.pi / 2, 1e-9));
    });
  });
}
