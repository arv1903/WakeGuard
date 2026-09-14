"""PERCLOS (percentage of eyelid closure) and drowsiness EMA tracking."""

import collections


class DrowsyEMA:
    """Exponential moving average of YOLO drowsy confidence."""

    def __init__(self, alpha: float = 0.9):
        self._alpha = alpha
        self._value = 0.0

    def update(self, drowsy_conf: float) -> float:
        self._value = self._alpha * self._value + (1.0 - self._alpha) * drowsy_conf
        return self._value

    def reset(self) -> None:
        """Forget past history (called when a new session/trip starts)."""
        self._value = 0.0


class PerclosTracker:
    """Fraction of samples in a rolling window where the eyes were closed.

    `eyes_closed` is decided by the caller (YOLO confidence and/or EAR).
    Uses a running sum to avoid O(N) sum() on every frame (was 54k ops/s at
    30 Hz with 60 s window).
    """

    def __init__(self, window_seconds: float = 60.0, sample_rate: float = 30.0):
        self._samples = collections.deque(
            maxlen=max(1, int(window_seconds * sample_rate)))
        self._running_sum = 0.0

    def update(self, eyes_closed: bool) -> float:
        v = 1.0 if eyes_closed else 0.0
        if len(self._samples) == self._samples.maxlen:
            # Deque will drop oldest on append; subtract it first.
            oldest = self._samples[0]
            self._running_sum -= oldest
        self._samples.append(v)
        self._running_sum += v
        return self._running_sum / len(self._samples) if self._samples else 0.0

    def reset(self) -> None:
        """Drop the rolling window (prevents stale samples from a previous
        session instantly pushing PERCLOS over the alert threshold)."""
        self._samples.clear()
        self._running_sum = 0.0
