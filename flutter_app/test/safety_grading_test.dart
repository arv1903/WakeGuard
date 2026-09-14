import 'package:flutter_test/flutter_test.dart';
import 'package:driver_monitor/utils/safety_grading.dart';

void main() {
  group('gradeSafetyScore', () {
    test('scores of 80 and above are good', () {
      expect(gradeSafetyScore(80).band, SafetyBand.good);
      expect(gradeSafetyScore(100).band, SafetyBand.good);
      expect(gradeSafetyScore(80).label, 'Good');
    });

    test('scores of 60 to 79 are fair', () {
      expect(gradeSafetyScore(60).band, SafetyBand.fair);
      expect(gradeSafetyScore(79.9).band, SafetyBand.fair);
      expect(gradeSafetyScore(60).label, 'Fair');
    });

    test('scores below 60 are poor', () {
      expect(gradeSafetyScore(59.9).band, SafetyBand.poor);
      expect(gradeSafetyScore(0).band, SafetyBand.poor);
      expect(gradeSafetyScore(0).label, 'Poor');
    });

    test('boundaries match backend cut points in yolo/score.py', () {
      // 80 exactly -> good; 79.99 -> fair; 60 exactly -> fair; 59.99 -> poor.
      expect(gradeSafetyScore(80.0).band, SafetyBand.good);
      expect(gradeSafetyScore(79.99).band, SafetyBand.fair);
      expect(gradeSafetyScore(60.0).band, SafetyBand.fair);
      expect(gradeSafetyScore(59.99).band, SafetyBand.poor);
    });

    test('out-of-range values are clamped into 0-100', () {
      expect(gradeSafetyScore(105).band, SafetyBand.good);
      expect(gradeSafetyScore(-5).band, SafetyBand.poor);
      expect(gradeSafetyScore(-5).score, 0.0);
      expect(gradeSafetyScore(105).score, 100.0);
    });

    test('bands use the shared semantic colors', () {
      // Colors themselves come from the theme; just assert they differ so a
      // theme change cannot silently collapse the bands into one color.
      final good = gradeSafetyScore(90).color;
      final fair = gradeSafetyScore(70).color;
      final poor = gradeSafetyScore(30).color;
      expect(good, isNot(fair));
      expect(fair, isNot(poor));
    });
  });

  group('safetyScoreFrom', () {
    test('returns the score when present as a number', () {
      expect(safetyScoreFrom({'safety_score': 87}), 87.0);
      expect(safetyScoreFrom({'safety_score': 87.5}), 87.5);
    });

    test('returns null when absent or malformed', () {
      expect(safetyScoreFrom({}), isNull);
      expect(safetyScoreFrom({'safety_score': null}), isNull);
      expect(safetyScoreFrom({'safety_score': '87'}), isNull);
    });
  });
}
