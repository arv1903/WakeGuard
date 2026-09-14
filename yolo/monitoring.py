"""Serializable monitoring state shared by local and remote UI clients.

The detection pipeline remains the source of truth. This module deliberately
contains no OpenCV, MediaPipe, or web-server dependencies so it can be used by
both the existing display loop and the future API service.
"""

from dataclasses import asdict, dataclass
import threading
import time
from typing import Any


SNAPSHOT_SCHEMA_VERSION = 3

_ALERT_SEVERITIES = {
    "MICROSLEEP": 4,
    "HEAD NODDING": 3,
    "FATIGUE": 3,
    "FACE LOST": 3,
    "DISTRACTED": 2,
    "LOW BLINK RATE": 2,
    "DROWSINESS": 1,
}


def GetAlertSeverity(alert: str | None) -> int:
    """Return the stable 0–4 severity used by client UIs."""
    if not alert:
        return 0
    upper = alert.upper()
    for label, severity in _ALERT_SEVERITIES.items():
        if label in upper:
            return severity
    return 1


def SelectAlert(messages: dict[str, str], *, microsleep: bool = False,
                combined: bool = False, perclos: bool = False,
                face_lost: bool = False, head_away: bool = False,
                low_blink: bool = False, yolo: bool = False) -> str | None:
    """Select the highest-priority active alert."""
    for key, active in (
        ("microsleep", microsleep),
        ("combined", combined),
        ("perclos", perclos),
        ("face_lost", face_lost),
        ("head_away", head_away),
        ("low_blink", low_blink),
        ("yolo", yolo),
    ):
        if active:
            return messages[key]
    return None


@dataclass(frozen=True)
class MonitoringSnapshot:
    """A complete, JSON-safe view of one monitoring tick.

    Values are intentionally scalar/optional so this object can be serialized
    directly for Flutter clients. ``sequence`` is monotonic within one running
    backend process and lets clients discard out-of-order or stale updates.
    """

    sequence: int = 0
    timestamp: float = 0.0
    session_id: str | None = None
    trip_started_at: float | None = None
    trip_active: bool = False
    attention: float = 100.0
    perclos: float = 0.0
    ema_drowsy: float = 0.0
    ear: float | None = None
    eyes_closed: bool = False
    microsleep: bool = False
    blinks_per_min: float = 0.0
    pitch: float = 0.0
    yaw: float = 0.0
    roll: float = 0.0
    pose_valid: bool = False
    face_found: bool = False
    face_lost: bool = False
    face_lost_progress: float = 0.0
    head_down: bool = False
    looking_away: bool = False
    head_tilt: bool = False
    focused: bool = False
    unfocused: bool = False
    alert: str | None = None
    alert_severity: int = 0
    alarm_muted: bool = False
    fps: float = 0.0
    calibration_state: str = "idle"
    calibration_progress: float = 0.0
    calibration_error: str | None = None
    calibration_valid_samples: int = 0
    startup_countdown: float = 0.0  # seconds remaining before evaluation starts

    def to_dict(self) -> dict[str, Any]:
        """Return the stable wire representation used by API clients."""
        data = asdict(self)
        data["schema_version"] = SNAPSHOT_SCHEMA_VERSION
        return data


class MonitoringStore:
    """Thread-safe latest snapshot store with change notifications.

    Publishers never wait for consumers. A slow desktop/mobile client only
    observes the newest snapshot, matching the pipeline's drop-old semantics.
    """

    def __init__(self, initial: MonitoringSnapshot | None = None):
        self._condition = threading.Condition()
        self._snapshot = initial or MonitoringSnapshot(timestamp=time.time())

    def publish(self, snapshot: MonitoringSnapshot) -> None:
        """Publish a snapshot and wake clients waiting for a newer sequence."""
        with self._condition:
            self._snapshot = snapshot
            self._condition.notify_all()

    def latest(self) -> MonitoringSnapshot:
        """Return the newest snapshot currently available."""
        with self._condition:
            return self._snapshot

    def wait_for_update(self, after_sequence: int = 0,
                        timeout: float | None = None) -> MonitoringSnapshot:
        """Wait for a newer snapshot or a sequence reset after restart.

        A timeout returns the current snapshot, which lets a server send
        heartbeat data and lets callers shut down without being permanently
        blocked. A lower sequence is also returned immediately so clients can
        detect that a backend process restarted.
        """
        with self._condition:
            self._condition.wait_for(
                lambda: self._snapshot.sequence > after_sequence
                or self._snapshot.sequence < after_sequence,
                timeout=timeout,
            )
            return self._snapshot
