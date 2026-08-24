"""Eye-closure metrics (EAR, blinks, microsleep) from MediaPipe landmarks."""

import collections
import math

LEFT_EYE = [33, 160, 158, 133, 153, 144]
RIGHT_EYE = [362, 385, 387, 263, 373, 380]


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def ComputeEAR(landmarks, frame_w: int, frame_h: int) -> float | None:
    """Average Eye Aspect Ratio across both eyes.

    Args:
        landmarks: First face's landmarks as a plain list (normalize both the
            MediaPipe <1.0 ``NormalizedLandmarkList`` wrapper and the 1.0+
            plain list via ``pipeline._normalized_landmarks``). Returns None if
            fewer than 468 landmarks are present (treated as eyes open, not
            closed — prevents spurious microsleep when face is half-occluded).

    Returns:
        float | None: EAR in (0, ~0.6) or None when unavailable.
    """
    if landmarks is None or len(landmarks) < 468:
        return None
    pts = [(lm.x * frame_w, lm.y * frame_h) for lm in landmarks]

    def ear(indices):
        p = [pts[i] for i in indices]
        return (_dist(p[1], p[5]) + _dist(p[2], p[4])) / (2.0 * _dist(p[0], p[3]) + 1e-6)

    return (ear(LEFT_EYE) + ear(RIGHT_EYE)) / 2.0


class BlinkMonitor:
    """Tracks blinks per minute, sustained closure, and microsleep."""

    def __init__(self, closed_threshold=0.20, min_blink_seconds=0.10,
                 microsleep_seconds=1.5, rate_window_seconds=60.0):
        self._closed_threshold = closed_threshold
        self._min_blink_seconds = min_blink_seconds
        self._microsleep_seconds = microsleep_seconds
        self._rate_window_seconds = rate_window_seconds
        self._closed = False
        self._closed_at = 0.0
        self._blink_ends = collections.deque()
        self._observed_seconds = 0.0
        self._last_valid_at: float | None = None

    def configure(self, closed_threshold: float | None = None,
                  min_blink_seconds: float | None = None,
                  microsleep_seconds: float | None = None) -> None:
        """Validated bulk update of thresholds (used by /api/v1/settings).

        Raises ValueError on non-numeric or out-of-range values.
        """
        if closed_threshold is not None:
            v = float(closed_threshold)
            if not 0.05 <= v <= 0.5:
                raise ValueError(f"ear_threshold {v} out of range [0.05, 0.5]")
            self._closed_threshold = v
        if min_blink_seconds is not None:
            v = float(min_blink_seconds)
            if not 0.01 <= v <= 1.0:
                raise ValueError(f"min_blink_seconds {v} out of range")
            self._min_blink_seconds = v
        if microsleep_seconds is not None:
            v = float(microsleep_seconds)
            if not 0.3 <= v <= 5.0:
                raise ValueError(f"microsleep_duration {v} out of range [0.3, 5.0]")
            self._microsleep_seconds = v

    def reset(self) -> None:
        self._closed = False
        self._closed_at = 0.0
        self._blink_ends.clear()
        self._observed_seconds = 0.0
        self._last_valid_at = None

    def update(self, ear: float | None, now: float) -> dict:
        """Feed one EAR sample. Returns a state dict (see below).

        None (unavailable EAR, e.g. face half-occluded) is treated as
        eyes open — prevents spurious microsleep when pose_valid is False.
        """
        if ear is None:
            # Unavailable measurement: reset closed state, treat as open.
            if self._closed:
                # Close any pending microsleep without counting a blink.
                self._closed = False
            # Pause observation time across gaps; do not count or discard it.
            self._last_valid_at = None
            return {
                "closed": False,
                "closed_seconds": 0.0,
                "microsleep": False,
                "blinks_per_min": len(self._blink_ends),
                "rate_ready": self._rate_ready(),
            }
        if self._last_valid_at is not None and now >= self._last_valid_at:
            self._observed_seconds += now - self._last_valid_at
        self._last_valid_at = now
        self._expire_blinks(now)
        closed = ear < self._closed_threshold
        if closed and not self._closed:
            self._closed = True
            self._closed_at = now
        elif not closed and self._closed:
            duration = now - self._closed_at
            self._closed = False
            # A microsleep is not also a blink.
            if self._min_blink_seconds <= duration < self._microsleep_seconds:
                self._blink_ends.append(now)
        closed_seconds = (now - self._closed_at) if self._closed else 0.0
        return {
            "closed": self._closed,
            "closed_seconds": closed_seconds,
            "microsleep": self._closed and closed_seconds >= self._microsleep_seconds,
            "blinks_per_min": len(self._blink_ends),
            "rate_ready": self._rate_ready(),
        }

    def _rate_ready(self) -> bool:
        return self._observed_seconds >= self._rate_window_seconds

    def _expire_blinks(self, now: float) -> None:
        cutoff = now - self._rate_window_seconds
        while self._blink_ends and self._blink_ends[0] < cutoff:
            self._blink_ends.popleft()
