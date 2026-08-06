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


def RunCalibration(get_pose, duration: float = 4.0, on_prompt=None):
    """Average valid pose samples over `duration` seconds.

    Args:
        get_pose: callable returning dict with keys pitch/yaw/roll/valid.
        on_prompt: optional callback(str) for HUD/console messages.

    Returns:
        CalibrationProfile
    Raises:
        RuntimeError: no valid pose samples were captured.
    """
    samples = []
    start = time.monotonic()
    while time.monotonic() - start < duration:
        pose = get_pose()
        if pose and pose.get("valid"):
            samples.append(pose)
        time.sleep(0.03)
    if not samples:
        raise RuntimeError("No valid pose samples during calibration.")
    n = len(samples)
    return CalibrationProfile(
        neutral_pitch=sum(s["pitch"] for s in samples) / n,
        neutral_yaw=sum(s["yaw"] for s in samples) / n,
        neutral_roll=sum(s["roll"] for s in samples) / n,
        created=time.strftime("%Y-%m-%d %H:%M:%S"),
    )
