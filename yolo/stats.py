"""Rolling per-stage performance timings for the pipeline."""
import time
from collections import deque


class PerfStats:
    """Averages stage durations over a rolling window.

    Not re-entrant: use one instance per thread.
    """

    def __init__(self, window_frames: int = 60):
        self._window = window_frames
        self._stages = {}
        self._start = 0.0

    def tick(self) -> None:
        self._start = time.perf_counter()

    def tock(self, stage: str) -> float:
        dt = time.perf_counter() - self._start
        self._stages.setdefault(stage, deque(maxlen=self._window)).append(dt)
        return dt

    def mean(self, stage: str) -> float:
        dq = self._stages.get(stage)
        return 1000.0 * (sum(dq) / len(dq)) if dq else 0.0

    def snapshot(self) -> dict:
        return {stage: self.mean(stage) for stage in self._stages}
