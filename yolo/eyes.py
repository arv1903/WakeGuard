"""Eye-closure metrics (EAR, blinks, microsleep) from MediaPipe landmarks."""

import collections
import math

LEFT_EYE = [33, 160, 158, 133, 153, 144]
RIGHT_EYE = [362, 385, 387, 263, 373, 380]


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def ComputeEAR(landmarks, frame_w: int, frame_h: int) -> float:
    """Average Eye Aspect Ratio across both eyes.

    Args:
        landmarks: MediaPipe NormalizedLandmarkList (result.face_landmarks[0].
            landmark). Returns 0.0 if fewer than 468 landmarks are present.
    """
    if landmarks is None or len(landmarks) < 468:
        return 0.0
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
        self._closed = False
        self._closed_at = 0.0
        self._blink_ends = collections.deque()

    def update(self, ear: float, now: float) -> dict:
        """Feed one EAR sample. Returns a state dict (see below)."""
        closed = ear < self._closed_threshold
        if closed and not self._closed:
            self._closed = True
            self._closed_at = now
        elif not closed and self._closed:
            duration = now - self._closed_at
            self._closed = False
            if self._min_blink_seconds <= duration:
                self._blink_ends.append(now)
                while self._blink_ends and self._blink_ends[0] < now - 60.0:
                    self._blink_ends.popleft()
        closed_seconds = (now - self._closed_at) if self._closed else 0.0
        return {
            "closed": self._closed,
            "closed_seconds": closed_seconds,
            "microsleep": self._closed and closed_seconds >= self._microsleep_seconds,
            "blinks_per_min": len(self._blink_ends),
        }
