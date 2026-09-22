"""Unified safety scoring calculation across backend and client interfaces."""

from .config import SafetyScorePenaltyPerAlert


def compute_safety_score(avg_attention: float, alert_count: int) -> float:
    """Compute 0-100 safety score.

    Formula: clamp(0, 100, avg_attention - alert_count * penalty)
    where penalty is SafetyScorePenaltyPerAlert (default 3.0).

    The penalty is deliberately linear and small — each alert costs 3 points,
    so a perfect 100 with 5 alerts yields 85. This is tunable without
    code changes via settings JSON.
    """
    raw = avg_attention - alert_count * SafetyScorePenaltyPerAlert
    return max(0.0, min(100.0, raw))


def safety_color(score: float) -> str:
    """Return severity bucket for UI (mirrors Flutter AppColors logic)."""
    if score >= 80:
        return "good"
    if score >= 60:
        return "warning"
    return "critical"
