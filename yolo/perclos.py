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


class PerclosTracker:
    """Fraction of samples in a rolling window where the eyes were closed.

    `eyes_closed` is decided by the caller (YOLO confidence and/or EAR).
    """

    def __init__(self, window_seconds: float = 60.0, sample_rate: float = 30.0):
        self._samples = collections.deque(
            maxlen=max(1, int(window_seconds * sample_rate)))

    def update(self, eyes_closed: bool) -> float:
        self._samples.append(1.0 if eyes_closed else 0.0)
        return sum(self._samples) / len(self._samples)
