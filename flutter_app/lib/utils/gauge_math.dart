import 'dart:math' as math;

/// Start angle for full-circle gauges: 12 o'clock, sweeping clockwise.
const double gaugeStartAngle = -math.pi / 2;

/// Sweep for a 0–1 gauge progress: a full circle, clamped so the arc can
/// never over-draw. Replaces the old `progress * 2π − π/2` formula, which
/// shifted every value by a quarter turn (25% filled 50% of the circle and
/// 0% drew a backwards arc).
double gaugeSweepRadians(double progress) =>
    progress.clamp(0.0, 1.0) * 2 * math.pi;
