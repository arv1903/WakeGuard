"""
Driver Drowsiness & Distraction Detection — Attention & Timer Logic.

Attention scoring, generic accumulator-based timer state machine,
and short helper utils.
"""

import time

from .config import (
    AttentionYawWeight,
    AttentionPitchWeight,
    AttentionEyeWeight,
)


class StartupCountdown:
    """Wall-clock grace timer that gates evaluation at session start.

    Counts down in real time instead of accumulating per-frame deltas, so
    the 3-2-1 period always lasts exactly ``duration`` seconds regardless of
    how slowly or irregularly the display loop ticks (CPU-bound inference
    can tick at only ~2 Hz). If ticks stall, ``remaining()`` simply holds
    steady and evaluation stays suspended.

    A duration of 0 disables the grace period entirely.
    """

    def __init__(self, duration: float = 0.0):
        self._duration = 0.0
        self._end_at: float | None = None
        self.configure(duration)

    def configure(self, duration: float) -> None:
        """Set the grace length (0 disables). Safe to call at any time."""
        self._duration = max(0.0, float(duration))

    def start(self, now: float | None = None) -> None:
        """Begin the countdown (idempotent — restarts the clock)."""
        now = time.monotonic() if now is None else now
        self._end_at = now + self._duration if self._duration > 0 else None

    def reset(self) -> None:
        """Cancel the countdown (called between trips)."""
        self._end_at = None

    def remaining(self, now: float | None = None) -> float:
        """Seconds left until the grace period ends (0 when inactive)."""
        if self._end_at is None:
            return 0.0
        now = time.monotonic() if now is None else now
        return max(0.0, self._end_at - now)

    def active(self, now: float | None = None) -> bool:
        return self.remaining(now) > 0.0


class AlertLatch:
    """Once an alert fires it stays active until the condition has been
    clean for `clear_seconds`. Prevents on/off flicker."""

    def __init__(self, clear_seconds: float = 2.0):
        self._clear_seconds = clear_seconds
        self._clean_accum = 0.0
        self._active = False

    def update(self, fired: bool, dt: float) -> bool:
        if fired:
            self._active = True
            self._clean_accum = 0.0
        elif self._active:
            self._clean_accum += dt
            if self._clean_accum >= self._clear_seconds:
                self._active = False
        return self._active

    def reset(self) -> None:
        """Clear any latched state (called between trips/sessions)."""
        self._clean_accum = 0.0
        self._active = False


def ComputeAttentionScore(DrowsyConf, Pitch, Yaw):
    """Calculate a 0–100 attention score from eye-confidence and head angles.

    Args:
        DrowsyConf (float): YOLO drowsy confidence [0–1].
        Pitch (float): Head pitch angle (degrees, down = negative).
        Yaw (float): Head yaw angle (degrees).

    Returns:
        float: Attention score clamped to [0, 100].
    """
    score = 100.0

    yaw_penalty = min(abs(Yaw) / 45.0, 1.0) * AttentionYawWeight

    if Pitch < 0:
        pitch_penalty = min(abs(Pitch) / 30.0, 1.0) * AttentionPitchWeight
    else:
        pitch_penalty = 0.0

    eye_penalty = DrowsyConf * AttentionEyeWeight

    score -= yaw_penalty + pitch_penalty + eye_penalty
    return max(0.0, min(100.0, score))


def UpdateTimer(Condition, Accumulated, DeltaTime, RequiredDuration, Freeze=False):
    """Accumulator-based escalating timer with optional freeze.

    When *Freeze* is True the accumulated time is preserved unchanged,
    allowing timers to survive face-loss episodes without firing
    prematurely and without losing their progress.

    Args:
        Condition (bool): Whether the monitored condition is currently true.
        Accumulated (float): Seconds accumulated so far.
        DeltaTime (float): Wall-clock seconds since the previous frame.
        RequiredDuration (float): Seconds the condition must persist for.
        Freeze (bool): If True, pause accumulation (preserve current value).

    Returns:
        tuple: (NewAccumulated: float, Fired: bool)
    """
    if not Condition:
        return 0.0, False

    if Freeze:
        return Accumulated, False

    new_acc = Accumulated + DeltaTime
    return new_acc, new_acc >= RequiredDuration


def CapDeltaTime(DeltaTime, Max=0.25):
    """Bound one frame's time step for the accumulator timers.

    A stall (e.g. the long idle before a session's first frame) must never
    count as sustained condition time, or an alert could fire instantly when
    the condition happens to be true on the very next frame. Negative deltas
    are treated as zero.
    """
    return min(max(DeltaTime, 0.0), Max)
