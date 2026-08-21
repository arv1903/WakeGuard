"""Startup pose calibration: records neutral head pose and persists a profile."""

import json
import os
import time
from dataclasses import asdict, dataclass


@dataclass
class CalibrationProfile:
    neutral_pitch: float = 0.0
    neutral_yaw: float = 0.0
    neutral_roll: float = 0.0
    created: str = ""

    @classmethod
    def load(cls, path: str):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return cls(**json.load(f))
        except (FileNotFoundError, TypeError, ValueError, json.JSONDecodeError):
            return None

    def save(self, path: str) -> None:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(asdict(self), f, indent=2)


class CalibrationSession:
    """Non-blocking calibration accumulator fed sample-by-sample each frame."""

    def __init__(self, duration: float = 4.0):
        self.duration = max(1.0, float(duration))
        self.samples: list[dict] = []
        self._start_time: float | None = None
        self._completed = False
        self._progress = 0.0

    @property
    def is_active(self) -> bool:
        return self._start_time is not None and not self._completed

    @property
    def is_finished(self) -> bool:
        return self._completed

    @property
    def progress(self) -> float:
        return self._progress

    @property
    def valid_samples(self) -> int:
        return len(self.samples)

    def start(self, now: float | None = None) -> None:
        self.samples.clear()
        self._start_time = time.monotonic() if now is None else now
        self._completed = False
        self._progress = 0.0

    def update(self, pose: dict | None, now: float | None = None) -> float:
        """Feed a pose dict. Returns progress in [0.0, 1.0]."""
        if self._start_time is None or self._completed:
            return 1.0 if self._completed else 0.0
        now = time.monotonic() if now is None else now
        elapsed = now - self._start_time
        if pose and pose.get("valid"):
            self.samples.append(pose)
        progress = min(1.0, max(0.0, elapsed / self.duration))
        self._progress = progress
        if elapsed >= self.duration:
            self._completed = True
        return progress

    def finish(self) -> CalibrationProfile:
        if not self.samples:
            raise RuntimeError("No valid pose samples during calibration.")
        n = len(self.samples)
        return CalibrationProfile(
            neutral_pitch=sum(s["pitch"] for s in self.samples) / n,
            neutral_yaw=sum(s["yaw"] for s in self.samples) / n,
            neutral_roll=sum(s["roll"] for s in self.samples) / n,
            created=time.strftime("%Y-%m-%d %H:%M:%S"),
        )


def RunCalibration(get_pose, duration: float = 4.0):
    """Average valid pose samples over `duration` seconds (synchronous wrapper).

    Args:
        get_pose: callable returning dict with keys pitch/yaw/roll/valid.

    Returns:
        CalibrationProfile
    Raises:
        RuntimeError: no valid pose samples were captured.
    """
    session = CalibrationSession(duration=duration)
    session.start()
    while not session.is_finished:
        session.update(get_pose())
        time.sleep(0.03)
    return session.finish()
