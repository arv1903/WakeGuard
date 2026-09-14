/// Single source of truth for safety-score presentation across mobile and
/// desktop tiers. Cut points mirror the backend (`yolo/score.py`): green >= 80,
/// amber >= 60, red below. The backend is authoritative for the score itself —
/// clients only derive presentation from it.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Where a safety score (0–100) lands on the shared 3-band scale.
enum SafetyBand { good, fair, poor }

/// Result of grading a safety score: numeric band plus presentation data.
class SafetyGrade {
  const SafetyGrade({
    required this.score,
    required this.band,
    required this.color,
    required this.label,
  });

  final double score;
  final SafetyBand band;
  final Color color;

  /// Short human-readable status, e.g. 'Good' / 'Fair' / 'Poor'.
  final String label;

  bool get isGood => band == SafetyBand.good;
  bool get isPoor => band == SafetyBand.poor;
}

/// Grades a 0–100 safety score on the shared band scale.
SafetyGrade gradeSafetyScore(num score) {
  final s = score.toDouble().clamp(0, 100).toDouble();
  if (s >= 80) {
    return SafetyGrade(
        score: s, band: SafetyBand.good, color: Stitch.secondary, label: 'Good');
  }
  if (s >= 60) {
    return SafetyGrade(
        score: s,
        band: SafetyBand.fair,
        color: Stitch.tertiaryFixedDim,
        label: 'Fair');
  }
  return SafetyGrade(
      score: s, band: SafetyBand.poor, color: Stitch.error, label: 'Poor');
}

/// Reads `safety_score` from a backend summary/history payload, returning
/// null when absent so callers can render an explicit "no data" state instead
/// of inventing a value.
double? safetyScoreFrom(Map<String, dynamic> data) {
  final v = data['safety_score'];
  return v is num ? v.toDouble() : null;
}
